package ar.dusan.bitacora.nucleo

import java.time.LocalDateTime
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/**
 * El día de la bitácora no es el del reloj: corta a las 4 de la mañana.
 *
 * Lo que alguien habla a la una de la mañana pertenece al día que todavía no
 * terminó para esa persona. Es la misma fórmula que `DiaLogico.swift`, la
 * columna generada `entradas.dia` y `leerReloj()` del servidor: si cambia,
 * cambia en todos lados o el sistema se parte.
 */
object DiaLogico {
    const val HORA_DE_CORTE = 4L

    private val pared = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss")

    /** "YYYY-MM-DD" del día lógico de una hora de pared. */
    fun dia(horaDePared: LocalDateTime): String =
        horaDePared.minusHours(HORA_DE_CORTE).toLocalDate().toString()

    fun hoy(): String = dia(LocalDateTime.now())

    /**
     * La hora de pared SIN zona, como la pide `creado_local`. Con segundos
     * siempre: el servidor rechaza "10:15" sin ellos.
     */
    fun paredIso(horaDePared: LocalDateTime): String =
        horaDePared.truncatedTo(ChronoUnit.SECONDS).format(pared)

    /** El instante CON su desfase, como lo pide `creado_en`. */
    fun instanteIso(ahora: ZonedDateTime): String =
        ahora.truncatedTo(ChronoUnit.SECONDS).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
}
