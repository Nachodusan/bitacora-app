package ar.dusan.bitacora.datos

import ar.dusan.bitacora.nucleo.Cliente
import ar.dusan.bitacora.nucleo.DiaLogico
import ar.dusan.bitacora.nucleo.EntradaNueva
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDateTime
import java.time.ZonedDateTime
import java.util.UUID

/**
 * La cola de salida de las conversaciones. Es `Outbox.swift`.
 *
 * La charla se escribe a disco MIENTRAS PASA, como borrador, después de cada
 * turno: la conversación la termina la persona, y un desahogo largo que termina
 * con la app cerrada por el sistema no se puede perder. Al cerrarla queda
 * pendiente, y la cola la sube en orden. La fila local no se borra nunca: el
 * teléfono es la primera copia.
 */
object Outbox {
    private val candado = Mutex()

    private val _servidor = MutableStateFlow<Cliente.Estado?>(null)
    /** Cómo está el servidor, para avisarlo en el chat. `null` si todavía no se preguntó. */
    val servidor: StateFlow<Cliente.Estado?> = _servidor

    /** Abre el borrador de una charla que empieza. Devuelve su id. */
    fun abrirBorrador(): String {
        val pared = LocalDateTime.now()
        val e = EntradaLocal(
            clientUuid = UUID.randomUUID().toString(),
            creadoEn = DiaLogico.instanteIso(ZonedDateTime.now()),
            creadoLocal = DiaLogico.paredIso(pared),
            dia = DiaLogico.dia(pared),
            transcripcion = "",
            duracionSeg = 0.0,
            estado = "borrador",
        )
        Datos.entradas.cambiar { it + e }
        return e.clientUuid
    }

    /** Reescribe el borrador con lo que va de charla. Después de cada turno. */
    fun anotar(id: String, transcripcion: String, duracionSeg: Double) {
        Datos.entradas.cambiar { l ->
            l.map { if (it.clientUuid == id) it.copy(transcripcion = transcripcion, duracionSeg = maxOf(0.0, duracionSeg)) else it }
        }
    }

    /**
     * Cierra el borrador. Si la persona no dijo nada —abrió y cortó—, no hay
     * bitácora que guardar y se borra. Si dijo algo, queda pendiente y se sube.
     */
    fun cerrar(id: String) {
        Datos.entradas.cambiar { l ->
            l.mapNotNull {
                when {
                    it.clientUuid != id -> it
                    !it.transcripcion.contains("Vos:") -> null
                    else -> it.copy(estado = "pendiente")
                }
            }
        }
        Datos.alcance.launch { drenar() }
    }

    /**
     * Una charla que quedó abierta —la app murió, sonó el teléfono— se cierra
     * al volver a abrir la app. Si no, el borrador sólo serviría para el caso
     * en que la persona se acuerda de cerrarla.
     */
    fun rescatarBorradores(salvo: String? = null) {
        Datos.entradas.valor.filter { it.estado == "borrador" && it.clientUuid != salvo }
            .forEach { cerrar(it.clientUuid) }
    }

    suspend fun comprobarServidor() {
        _servidor.value = if (Datos.config.configurada) Datos.cliente().comprobar() else Cliente.Estado.INALCANZABLE
    }

    /**
     * Sube las pendientes, de a una y en orden. Para en el primer fallo que no
     * sea de la entrada: si no hay red, la siguiente tampoco va a pasar.
     */
    suspend fun drenar() = candado.withLock {
        if (!Datos.config.configurada) return@withLock
        val cliente = Datos.cliente()
        for (e in Datos.entradas.valor.filter { it.estado == "pendiente" }.sortedBy { it.creadoEn }) {
            val nueva = EntradaNueva(e.clientUuid, e.creadoEn, e.creadoLocal, "dictado_android",
                                     e.transcripcion, e.duracionSeg)
            when (val r = cliente.subir(nueva)) {
                is Cliente.Subida.Aceptada -> marcar(e.clientUuid, "subida", r.id)
                is Cliente.Subida.Rechazada -> marcar(e.clientUuid, "rechazada", null)
                Cliente.Subida.SinCredencial, Cliente.Subida.Reintentable -> return@withLock
            }
        }
    }

    private fun marcar(id: String, estado: String, servidorId: Int?) {
        Datos.entradas.cambiar { l ->
            l.map { if (it.clientUuid == id) it.copy(estado = estado, servidorId = servidorId ?: it.servidorId) else it }
        }
    }
}
