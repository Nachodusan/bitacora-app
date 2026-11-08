package ar.dusan.bitacora.nucleo

import java.text.Normalizer

/** Quién habla en un turno. `rol` es como viaja al servidor. */
enum class Hablante(val rol: String) { VOS("vos"), BITACORA("bitacora") }

data class Turno(val de: Hablante, val texto: String)

/**
 * Cómo se escribe el diálogo en `entradas.transcripcion`.
 *
 * Con las dos voces, porque sin la pregunta muchas respuestas no significan
 * nada. Lo que cita del lado del servidor —las notas de terapia— filtra primero
 * las líneas que arrancan con "Vos:", así que ese rótulo es formato de datos y
 * no se traduce.
 */
object Transcripcion {
    fun de(turnos: List<Turno>): String =
        turnos.joinToString("\n") { "${if (it.de == Hablante.VOS) "Vos" else "Bitácora"}: ${it.texto}" }

    /** Sólo lo que dijo la persona: una pregunta de Bitácora no puede disparar el corte. */
    fun soloVos(turnos: List<Turno>): String =
        turnos.filter { it.de == Hablante.VOS }.joinToString(" ") { it.texto }

    /**
     * Lo que dijo la persona en una charla guardada, turno por turno y textual:
     * cada línea `Vos:` con las que la siguen hasta el próximo rótulo. Lo de
     * Bitácora (o de Laya, su nombre viejo) no va. Es lo que lleva el PDF de
     * «Mi resumen» de un día que no dejó frases separadas.
     */
    fun loQueDijo(transcripcion: String): List<String> {
        val turnos = mutableListOf<String>()
        var actual: StringBuilder? = null
        fun cerrar() { actual?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let(turnos::add); actual = null }
        for (linea in transcripcion.split('\n')) {
            when {
                linea.startsWith("Vos:") -> { cerrar(); actual = StringBuilder(linea.removePrefix("Vos:")) }
                linea.startsWith("Bitácora:") || linea.startsWith("Laya:") -> cerrar()
                else -> actual?.append('\n')?.append(linea)
            }
        }
        cerrar()
        return turnos
    }

    /**
     * La charla guardada, de nuevo en turnos: las dos voces, en orden. Es la
     * vuelta de `de`, para mostrar en el calendario una charla igual que en el
     * chat y no como un bloque con «Vos:» y «Bitácora:» delante (04/10/2026).
     * Las líneas sin rótulo se suman al turno anterior; lo que viene antes de
     * cualquier rótulo es de la persona. Es `Transcripcion.turnos` del iPhone.
     */
    fun turnos(transcripcion: String): List<Turno> {
        val turnos = mutableListOf<Turno>()
        var quien = Hablante.VOS
        var texto: StringBuilder? = null
        fun cerrar() { texto?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { turnos += Turno(quien, it) }; texto = null }
        for (linea in transcripcion.split('\n')) {
            when {
                linea.startsWith("Vos:") -> { cerrar(); quien = Hablante.VOS; texto = StringBuilder(linea.removePrefix("Vos:")) }
                linea.startsWith("Bitácora:") -> { cerrar(); quien = Hablante.BITACORA; texto = StringBuilder(linea.removePrefix("Bitácora:")) }
                linea.startsWith("Laya:") -> { cerrar(); quien = Hablante.BITACORA; texto = StringBuilder(linea.removePrefix("Laya:")) }
                else -> texto = (texto?.append('\n') ?: StringBuilder()).append(linea)
            }
        }
        cerrar()
        return turnos
    }

    /** Cuánto duró una charla, como lo diría una persona: «7 min», no «420s». */
    fun duracion(segundos: Double): String =
        if (segundos < 60) "menos de 1 min" else "${Math.round(segundos / 60)} min"
}

/**
 * Cuándo se da por terminado el turno de la persona.
 *
 * Es `FinDeTurno.swift`, adaptado: en Android el reconocedor corta solo cuando
 * hay silencio, así que lo que se decide acá es si ese corte fue a tiempo. Si
 * la frase quedó colgada —en una coma, en puntos suspensivos o en una palabra
 * con la que nadie termina («y», «porque», «o sea»)—, se sigue escuchando y lo
 * que diga después se suma. La persona tiene prioridad al hablar.
 */
object FinDeTurno {
    private val colgantes = setOf(
        "y", "e", "o", "u", "pero", "porque", "que", "aunque", "si", "ni", "sino",
        "como", "cuando", "donde", "mientras", "entonces", "pues", "osea",
        "de", "del", "a", "al", "en", "con", "sin", "para", "por", "sobre", "entre",
        "hasta", "desde", "hacia", "el", "la", "los", "las", "un", "una", "unos",
        "unas", "mi", "mis", "tu", "tus", "su", "sus", "lo", "le", "me", "te", "se",
        "es", "era", "fue", "son", "estoy", "esta", "estaba", "tengo", "tiene",
        "hay", "muy", "mas", "tan", "eh", "em", "este", "bueno", "igual", "tipo",
    )

    private fun plano(s: String) =
        Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase()

    /** Si lo dicho quedó a mitad de idea. */
    fun quedoColgado(dicho: String): Boolean {
        val texto = dicho.trim()
        if (texto.isEmpty()) return false
        if (texto.endsWith("...") || texto.endsWith("…") || texto.endsWith(",")) return true
        val palabras = plano(texto).split(Regex("[^\\p{L} ]+|\\s+")).filter { it.isNotEmpty() }
        val ultima = palabras.lastOrNull() ?: return false
        val dos = palabras.takeLast(2).joinToString("")
        return ultima in colgantes || dos in colgantes
    }

    /** Junta lo que venía diciendo con lo que agregó después. */
    fun unir(antes: String?, despues: String): String {
        val a = antes.orEmpty().trim()
        val d = despues.trim()
        return when {
            a.isEmpty() -> d
            d.isEmpty() -> a
            else -> "$a $d"
        }
    }
}
