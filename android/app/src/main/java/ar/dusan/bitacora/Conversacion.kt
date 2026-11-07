package ar.dusan.bitacora

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.datos.Outbox
import ar.dusan.bitacora.nucleo.DiaLogico
import ar.dusan.bitacora.nucleo.FinDeTurno
import ar.dusan.bitacora.nucleo.Hablante
import ar.dusan.bitacora.nucleo.PedidoDeCharla
import ar.dusan.bitacora.nucleo.Riesgo
import ar.dusan.bitacora.nucleo.Trama
import ar.dusan.bitacora.nucleo.Transcripcion
import ar.dusan.bitacora.nucleo.Turno
import ar.dusan.bitacora.nucleo.TurnoDeCharla
import ar.dusan.bitacora.voz.Altavoz
import ar.dusan.bitacora.voz.Dictado
import ar.dusan.bitacora.voz.VozDelTelefono
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Coordina la conversación: quién habla, cuándo se escucha, cuándo se guarda.
 * Es `Conversacion.swift`, con lo que en Android se puede hacer igual.
 *
 * Lo que gobierna todo, igual que allá:
 *
 *   · LA CHARLA LA TERMINA LA PERSONA. No hay tope de turnos ni cierre
 *     automático, y la conversación se escribe a disco mientras pasa.
 *   · EL CORTE DE RIESGO VA ANTES QUE EL SERVIDOR, con un mensaje fijo que dice
 *     la voz del teléfono. El servidor tiene el mismo corte por si acá no
 *     disparó.
 *   · BITÁCORA SÓLO HABLA EN LLAMADA. Si la persona escribe, contesta por
 *     escrito y en silencio.
 *
 * Lo que todavía NO hace, a diferencia del iPhone: escuchar mientras Bitácora
 * habla. Acá la llamada es por turnos: mientras habla, el micrófono está
 * cerrado, y para cortarla se toca la pantalla. En el iPhone eso necesitó
 * cancelación de eco y un umbral calibrado a mano; en Android hay que probarlo
 * en un teléfono de verdad antes de prometerlo.
 */
class Conversacion(context: Context) {

    enum class Fase { INACTIVA, ESCUCHANDO, PENSANDO, HABLANDO, ESPERANDO, CERRADA, CUIDADO }
    enum class Modo { LLAMADA, ESCRITA }

    var fase by mutableStateOf(Fase.INACTIVA)
        private set
    var modo by mutableStateOf(Modo.ESCRITA)
        private set
    val turnos = mutableStateListOf<Turno>()
    /** Lo que se ve mientras habla, antes de que el turno se cierre. */
    var parcial by mutableStateOf("")
        private set
    /** Un aviso para mostrar: el dictado no está, el servidor no llegó. */
    var aviso by mutableStateOf<String?>(null)
        private set
    /** De 0 a 1: la luz de la voz. */
    var nivel by mutableFloatStateOf(0f)
        private set

    /** Cuánto suena la voz de Bitácora en este instante, de 0 a 1 (para los anillos). */
    fun nivelDeLaVoz(): Float = altavoz.nivel

    val activa get() = fase in setOf(Fase.ESCUCHANDO, Fase.PENSANDO, Fase.HABLANDO, Fase.ESPERANDO)
    val enLlamada get() = modo == Modo.LLAMADA && activa
    /** Grabando un mensaje suelto: el micrófono abierto, sin llamada. */
    val grabando get() = modo == Modo.ESCRITA && fase == Fase.ESCUCHANDO

    /**
     * Si la pantalla de la conversación está abierta, como en el iPhone: se
     * entra tocando el portal, y recién adentro están el campo para escribir,
     * el micrófono y la llamada. Entrar cuesta un gesto a propósito: hablar de
     * lo que te pasó no es revisar el correo.
     */
    var abierta by mutableStateOf(false)
        private set

    fun abrirPantalla() {
        abierta = true
    }

    /** Salir al portal: si había una charla, se cierra y se guarda. */
    fun cerrarPantalla() {
        // Preparar es para esta visita al chat: la próxima vez se entra normal.
        Navegacion.preparando = null
        if (activa) terminar()
        volverAEmpezar()
        abierta = false
    }

    private val alcance: CoroutineScope = MainScope()
    private val dictado = Dictado(context)
    private val altavoz = Altavoz()
    private val voz = VozDelTelefono(context)

    private var borrador: String? = null
    private var comienzo = 0L
    private var turnoEnCurso: Job? = null
    /** Lo que venía diciendo en un turno que quedó colgado. */
    private var colgado: String? = null
    /** Cambia en cada turno pedido: lo que llegue de uno viejo se descarta. */
    private var pedido = 0

    init {
        dictado.alNivel = { nivel = it }
    }

    val puedeDictar get() = dictado.disponible

    /** Si el aviso es que falta el español, y el teléfono puede bajarlo. */
    val puedeBajarElIdioma get() = aviso == Dictado.FALTA_IDIOMA && dictado.puedeDescargar

    fun bajarElIdioma() {
        dictado.descargarIdioma()
        aviso = null
    }

    // MARK: - Entrar

    /** Abre la llamada: escucha, contesta con voz, y vuelve a escuchar. */
    fun arrancarLlamada() {
        aviso = null
        if (!dictado.disponible) {
            aviso = Dictado.SIN_RECONOCEDOR
            return
        }
        if (!activa) abrir()
        modo = Modo.LLAMADA
        escuchar()
    }

    /** Manda algo escrito. Si ya venía en llamada, la llamada sigue. */
    fun enviarTexto(texto: String) {
        val limpio = texto.trim()
        if (limpio.isEmpty()) return
        aviso = null
        if (!activa) {
            abrir()
            modo = Modo.ESCRITA
        }
        if (fase == Fase.ESCUCHANDO) dictado.frenar()
        procesar(limpio)
    }

    private fun abrir() {
        if (fase == Fase.CERRADA || fase == Fase.CUIDADO) turnos.clear()
        if (borrador == null) {
            turnos.clear()
            borrador = Outbox.abrirBorrador()
            comienzo = System.currentTimeMillis()
        }
        colgado = null
        parcial = ""
    }

    /**
     * Graba UN mensaje: escucha, transcribe, lo manda y suelta el micrófono.
     * Es la diferencia con la llamada: sirve para dejar algo dicho sin abrir
     * una conversación de voz, y la respuesta llega por escrito. Tocar de nuevo
     * mientras graba manda lo que haya.
     */
    fun grabarUnMensaje() {
        aviso = null
        if (grabando) {
            val dicho = FinDeTurno.unir(colgado, parcial)
            dictado.frenar()
            colgado = null
            parcial = ""
            if (dicho.isNotEmpty()) procesar(dicho)
            else fase = if (turnos.isEmpty()) Fase.INACTIVA else Fase.ESPERANDO
            return
        }
        if (!dictado.disponible) {
            aviso = Dictado.SIN_RECONOCEDOR
            return
        }
        if (enLlamada || fase == Fase.PENSANDO || fase == Fase.HABLANDO) return
        if (!activa) abrir()
        modo = Modo.ESCRITA
        escuchar()
    }

    // MARK: - Escuchar

    private fun escuchar() {
        fase = Fase.ESCUCHANDO
        dictado.escuchar(
            alParcial = { parcial = FinDeTurno.unir(colgado, it) },
            alTerminar = { recibirTurno(it) },
            alFallar = {
                aviso = it
                fase = if (turnos.isEmpty()) Fase.INACTIVA else Fase.ESPERANDO
                modo = Modo.ESCRITA
            },
        )
    }

    /**
     * El reconocedor cortó. Si la frase quedó colgada —«y», «porque», una
     * coma—, se sigue escuchando y lo que diga se suma: la persona tiene
     * prioridad al hablar. Si no dijo nada, se vuelve a escuchar: el silencio
     * no cierra la llamada.
     */
    private fun recibirTurno(texto: String) {
        if (fase != Fase.ESCUCHANDO) return
        val todo = FinDeTurno.unir(colgado, texto)
        if (todo.isEmpty()) {
            // En llamada, el silencio no la cierra: se vuelve a escuchar. En un
            // mensaje suelto, no hubo mensaje: se suelta el micrófono.
            if (modo == Modo.LLAMADA) escuchar()
            else fase = if (turnos.isEmpty()) Fase.INACTIVA else Fase.ESPERANDO
            return
        }
        if (texto.isNotEmpty() && FinDeTurno.quedoColgado(todo)) {
            colgado = todo
            escuchar()
            return
        }
        colgado = null
        parcial = ""
        procesar(todo)
    }

    // MARK: - El turno

    private fun procesar(texto: String) {
        turnos.add(Turno(Hablante.VOS, texto))
        anotar()

        // REGLA 6, ANTES QUE EL SERVIDOR. A un modelo se lo convence; a una
        // función no. Mira todo lo que dijo en esta charla, no sólo lo último.
        if (Riesgo.haySenal(Transcripcion.soloVos(turnos))) {
            cerrarCon(Riesgo.mensaje, Fase.CUIDADO)
            return
        }
        fase = Fase.PENSANDO
        pedirTurno()
    }

    private fun pedirTurno() {
        val este = ++pedido
        val hablada = modo == Modo.LLAMADA
        val conVozDelServidor = hablada && Datos.config.vozNatural
        val p = PedidoDeCharla(
            turnos = turnos.map { TurnoDeCharla(it.de.rol, it.texto) },
            dia = DiaLogico.hoy(),
            timbre = if (conVozDelServidor) Datos.config.timbre else null,
            preparar = Navegacion.preparandoVigente?.id,
        )
        var lugar: Int? = null
        var hz = 24_000

        fun escribir(t: String) {
            val i = lugar
            if (i != null && i < turnos.size) turnos[i] = Turno(Hablante.BITACORA, t)
            else {
                turnos.add(Turno(Hablante.BITACORA, t))
                lugar = turnos.size - 1
                if (hablada) fase = Fase.HABLANDO
            }
        }

        turnoEnCurso = alcance.launch {
            try {
                Datos.cliente().charlaEnVivo(p) { trama ->
                    withContext(Dispatchers.Main) {
                        if (este != pedido) return@withContext
                        when (trama) {
                            is Trama.Frecuencia -> hz = trama.hz
                            is Trama.Texto -> if (trama.texto.isNotEmpty()) escribir(trama.texto)
                            is Trama.Audio -> if (conVozDelServidor && lugar != null) {
                                if (!altavoz.sono) altavoz.empezar(hz)
                                altavoz.sonar(trama.pcm)
                            }
                            is Trama.Cuidado -> {
                                lugar?.let { if (it < turnos.size) turnos.removeAt(it) }
                                altavoz.callar()
                                cerrarCon(trama.texto, Fase.CUIDADO)
                            }
                            is Trama.Fin -> {
                                if (!trama.ok) {
                                    lugar?.let { if (it < turnos.size) turnos.removeAt(it) }
                                    altavoz.callar()
                                    cerrarCon(trama.texto, Fase.CERRADA)
                                } else {
                                    escribir(trama.texto)
                                    anotar()
                                    if (hablada) hablarLoQueFalta(este, trama.faltaDecir, conVozDelServidor)
                                    else fase = Fase.ESPERANDO
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                if (este != pedido || e is kotlinx.coroutines.CancellationException) return@launch
                // No llegó nada: se avisa y lo dicho queda guardado.
                altavoz.callar()
                lugar?.let { if (it < turnos.size) turnos.removeAt(it) }
                cerrarCon(MENSAJE_DE_CORTE, Fase.CERRADA)
            }
        }
    }

    /**
     * Termina de sonar el audio del servidor; lo que la voz del servidor no
     * llegó a decir —o todo, si estaba apagada— lo dice la del teléfono. Y en
     * llamada, vuelve a escuchar.
     */
    private fun hablarLoQueFalta(este: Int, faltaDecir: String, huboServidor: Boolean) {
        fun seguir() {
            if (este != pedido || fase != Fase.HABLANDO) return
            if (faltaDecir.isNotBlank()) voz.decir(faltaDecir) { if (este == pedido && fase == Fase.HABLANDO) escuchar() }
            else escuchar()
        }
        if (huboServidor && altavoz.sono) altavoz.alTerminar { alcance.launch { seguir() } } else seguir()
    }

    /**
     * Cortarla mientras habla: se calla y escucha. No cierra la charla. Lo que
     * ya dijo queda escrito.
     */
    fun interrumpir() {
        if (fase != Fase.HABLANDO) return
        pedido++
        turnoEnCurso?.cancel()
        altavoz.callar()
        voz.callar()
        if (modo == Modo.LLAMADA) escuchar() else fase = Fase.ESPERANDO
    }

    /** Colgar la llamada sin cerrar la charla: se puede seguir escribiendo. */
    fun colgar() {
        if (modo != Modo.LLAMADA) return
        pedido++
        turnoEnCurso?.cancel()
        dictado.frenar()
        altavoz.callar()
        voz.callar()
        colgado?.let { turnos.add(Turno(Hablante.VOS, it)) }
        colgado = null
        parcial = ""
        modo = Modo.ESCRITA
        anotar()
        fase = if (turnos.isEmpty()) Fase.INACTIVA else Fase.ESPERANDO
    }

    /** Termina la charla: lo que quedó a medio decir entra, se guarda, y se cierra. */
    fun terminar() {
        if (fase == Fase.CUIDADO) return
        pedido++
        turnoEnCurso?.cancel()
        dictado.frenar()
        altavoz.callar()
        voz.callar()
        FinDeTurno.unir(colgado, parcial).takeIf { it.isNotEmpty() && fase == Fase.ESCUCHANDO }
            ?.let { turnos.add(Turno(Hablante.VOS, it)) }
        colgado = null
        parcial = ""
        guardar()
        fase = if (turnos.isEmpty()) Fase.INACTIVA else Fase.CERRADA
    }

    /** Después de cerrar: limpiar la pantalla para otra charla. */
    fun volverAEmpezar() {
        turnos.clear()
        aviso = null
        fase = Fase.INACTIVA
        modo = Modo.ESCRITA
    }

    /**
     * Cierra diciendo algo fijo: el mensaje de cuidado o la despedida de un
     * corte. SIEMPRE con la voz del teléfono —nunca se manda a sintetizar
     * afuera— y sólo en llamada; escribiendo, se muestra.
     */
    private fun cerrarCon(mensaje: String, final: Fase) {
        dictado.frenar()
        turnos.add(Turno(Hablante.BITACORA, mensaje))
        anotar()
        val hablada = modo == Modo.LLAMADA
        guardar()
        fase = final
        if (hablada) voz.decir(mensaje) {}
    }

    // MARK: - Guardado

    private fun anotar() {
        val id = borrador ?: return
        val todos = colgado?.let { turnos + Turno(Hablante.VOS, it) } ?: turnos.toList()
        Outbox.anotar(id, Transcripcion.de(todos), (System.currentTimeMillis() - comienzo) / 1000.0)
    }

    private fun guardar() {
        anotar()
        borrador?.let { Outbox.cerrar(it) }
        borrador = null
    }

    /** Si la app se va del todo, lo hablado queda pendiente para subir. */
    fun soltar() {
        dictado.frenar()
        altavoz.callar()
        voz.cerrar()
        alcance.cancel()
    }

    companion object {
        /** La misma que la del servidor y la del iPhone. Si no se llega, no hay de dónde traerla. */
        const val MENSAJE_DE_CORTE =
            "Se me cortó aquí, discúlpame. Lo que me contaste quedó guardado. Si quieres, seguimos en un rato."
    }
}
