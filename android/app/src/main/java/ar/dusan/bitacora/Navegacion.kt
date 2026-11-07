package ar.dusan.bitacora

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import ar.dusan.bitacora.nucleo.Evento
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/**
 * Lo que una pestaña le pide a otra. Es `Navegacion.swift`.
 *
 * Nació el 06/10/2026 con la tarjeta de la próxima consulta, arriba de Mi
 * expediente: «Agendar consulta» lleva al calendario con la hoja de consulta
 * nueva abierta, tocar la tarjeta lleva a ese día, y «Preparar» abre el chat
 * para prepararla. Los pedidos los atiende la pestaña que corresponde, y los
 * borra al atenderlos.
 */
object Navegacion {
    var pestana by mutableStateOf(Pestana.CHAT)

    /** El calendario abre la hoja de consulta nueva, en el día de hoy. */
    var nuevaConsulta by mutableStateOf(false)

    /** El calendario muestra este día ("YYYY-MM-DD"). */
    var irAlDia by mutableStateOf<String?>(null)

    /**
     * La consulta que se está preparando en el chat, desde «Preparar». Mientras
     * esté, cada turno se lo dice al servidor (`preparar`), que pone a Bitácora en
     * el modo de antes de la consulta aunque falten días. Se borra al salir de
     * la conversación, con la cruz del aviso, o cuando la consulta pasa.
     */
    var preparando by mutableStateOf<Evento?>(null)

    val preparandoVigente: Evento? get() = preparando?.takeIf { it.momento > ahora() }

    fun agendarConsulta() {
        nuevaConsulta = true
        pestana = Pestana.CALENDARIO
    }

    fun verEnElCalendario(dia: String) {
        irAlDia = dia
        pestana = Pestana.CALENDARIO
    }

    fun preparar(consulta: Evento) {
        preparando = consulta
        pestana = Pestana.CHAT
    }

    /** La hora de pared, "YYYY-MM-DD HH:MM", para compararla con `Evento.momento`. */
    fun ahora(): String = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm"))

    /** «Jueves 8 · 17:00»: la tarjeta de la próxima consulta y el aviso del chat. */
    fun cuando(e: Evento): String {
        val f = LocalDate.parse(e.dia)
        val dia = f.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.forLanguageTag("es"))
            .replaceFirstChar { it.uppercase() } + " ${f.dayOfMonth}"
        return e.hora?.let { "$dia · $it" } ?: dia
    }
}
