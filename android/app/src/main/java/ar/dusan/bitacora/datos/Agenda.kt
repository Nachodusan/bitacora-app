package ar.dusan.bitacora.datos

import ar.dusan.bitacora.nucleo.Evento
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate
import java.util.UUID

/**
 * Las consultas y otros eventos del calendario. Es `Agenda.swift`.
 *
 * El servidor es el dueño (`api/src/consultas.ts`): Bitácora las ve para
 * ayudar a preparar una sesión y para preguntar cómo le fue, y propone las que
 * se mencionan en una charla. Acá vive una copia para mostrarlas sin red.
 * Cargar, confirmar o borrar sí necesita servidor; si no llega, se dice.
 *
 * Y es el puente con Evaluaciones: crea la sesión «para revisar» cuando una
 * consulta trae borrador, y le avisa al servidor cuando una ya tiene su
 * evaluación. Lo único que viaja es eso: que está evaluada.
 */
object Agenda {
    enum class Marca { NINGUNA, PROPUESTO, CONFIRMADO }

    fun delDia(dia: String, eventos: List<Evento>): List<Evento> =
        eventos.filter { it.dia == dia }.sortedBy { it.hora.orEmpty() }

    fun marca(dia: String, eventos: List<Evento>): Marca {
        val delDia = eventos.filter { it.dia == dia }
        return when {
            delDia.any { !it.esPropuesta } -> Marca.CONFIRMADO
            delDia.isNotEmpty() -> Marca.PROPUESTO
            else -> Marca.NINGUNA
        }
    }

    /** Trae los eventos del servidor. Sin servidor, se queda con la copia. */
    suspend fun actualizar() {
        if (!Datos.config.configurada) return
        val nuevos = Datos.cliente().eventos() ?: return
        Datos.eventos.cambiar { nuevos }
        traerBorradores()
        avisarEvaluadas()
    }

    suspend fun agregar(tipo: String, dia: String, hora: String?, titulo: String?): Boolean {
        val e = Datos.cliente().crearEvento(UUID.randomUUID().toString(), tipo, dia, hora, titulo) ?: return false
        Datos.eventos.cambiar { l -> l.filter { it.id != e.id } + e }
        return true
    }

    suspend fun confirmar(e: Evento) = cambiar(e, buildJsonObject { put("estado", "confirmado") })

    /** Una propuesta que la persona dijo que no: en el servidor queda descartada, para no volver a proponerla. */
    suspend fun descartar(e: Evento): Boolean {
        Datos.cliente().cambiarEvento(e.id, buildJsonObject { put("estado", "descartado") }) ?: return false
        Datos.eventos.cambiar { l -> l.filter { it.id != e.id } }
        return true
    }

    suspend fun cambiarHora(e: Evento, hora: String?) =
        cambiar(e, buildJsonObject { put("hora", hora?.let { JsonPrimitive(it) } ?: JsonNull) })

    suspend fun borrar(e: Evento): Boolean {
        if (!Datos.cliente().borrarEvento(e.id)) return false
        Datos.eventos.cambiar { l -> l.filter { it.id != e.id } }
        return true
    }

    /** La evaluación de esta consulta quedó guardada acá. Si no llega, se reintenta al actualizar. */
    suspend fun evaluada(eventoId: Int) {
        val e = Datos.eventos.valor.firstOrNull { it.id == eventoId } ?: return
        if (!e.evaluada) cambiar(e, buildJsonObject { put("evaluada", true) })
    }

    private suspend fun cambiar(e: Evento, cambio: kotlinx.serialization.json.JsonObject): Boolean {
        val nuevo = Datos.cliente().cambiarEvento(e.id, cambio) ?: return false
        Datos.eventos.cambiar { l -> l.map { if (it.id == nuevo.id) nuevo else it } }
        return true
    }

    /**
     * Crea la sesión para revisar de cada consulta que trae borrador y todavía
     * no tiene una. Una sola vez por consulta: lo que la persona edite no se pisa.
     */
    private fun traerBorradores() {
        Datos.sesiones.cambiar { sesiones ->
            var todas = sesiones
            for (e in Datos.eventos.valor) {
                val b = e.borrador ?: continue
                if (!e.esConsulta || e.esPropuesta || e.evaluada || todas.any { it.eventoId == e.id }) continue
                todas = todas + SesionDeTerapia(
                    id = UUID.randomUUID().toString(),
                    numero = (todas.maxOfOrNull { it.numero } ?: 0) + 1,
                    fecha = e.dia,
                    entendi = b.entendi, aporte = b.aporte, sentir = b.sentir,
                    temas = b.temas, avance = b.avance,
                    eventoId = e.id, revisada = false,
                )
            }
            todas
        }
    }

    /**
     * Le avisa al servidor qué consultas ya tienen su evaluación: la que nació
     * del borrador y ya se revisó, o una anotada a mano el mismo día.
     */
    private suspend fun avisarEvaluadas() {
        val hoy = LocalDate.now().toString()
        for (e in Datos.eventos.valor) {
            if (!e.esConsulta || e.esPropuesta || e.evaluada || e.dia > hoy) continue
            val todas = Datos.sesiones.valor
            val suya = todas.firstOrNull { it.eventoId == e.id }
                ?: todas.firstOrNull { it.eventoId == null && it.fecha == e.dia }
                ?: continue
            if (!suya.revisada) continue
            if (suya.eventoId == null) {
                Datos.sesiones.cambiar { l -> l.map { if (it.id == suya.id) it.copy(eventoId = e.id) else it } }
            }
            evaluada(e.id)
        }
    }
}
