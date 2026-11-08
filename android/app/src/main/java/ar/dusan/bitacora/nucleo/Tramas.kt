package ar.dusan.bitacora.nucleo

import kotlinx.serialization.Serializable
import okio.BufferedSource

/**
 * Lo que llega por un turno en vivo (`POST /charla/vivo`).
 *
 * El servidor deja la conexión abierta y manda tramas mientras Bitácora
 * escribe y la voz se sintetiza: un byte que dice qué es, cuatro con el largo
 * (big-endian) y el contenido. Es `TramasDeCharla.swift`.
 */
sealed interface Trama {
    /** El texto hasta ahora, entero. Reemplaza al anterior. */
    data class Texto(val texto: String) : Trama
    /** La frecuencia del audio. Llega una vez, antes del primer audio. */
    data class Frecuencia(val hz: Int) : Trama
    /** Muestras de 16 bits, mono, little-endian. */
    class Audio(val pcm: ByteArray) : Trama
    /**
     * El final. `ok` en falso es que el servidor no pudo generar el turno y
     * `texto` es la despedida fija. `faltaDecir` es lo que la voz del servidor
     * no llegó a decir: lo dice la del teléfono.
     */
    data class Fin(val ok: Boolean, val texto: String, val faltaDecir: String) : Trama
    /** El corte de riesgo del servidor: `texto` es el mensaje fijo, y la charla se cierra. */
    data class Cuidado(val texto: String) : Trama
}

@Serializable
private data class FinCrudo(val ok: Boolean, val texto: String, val hablado: Int? = null, val cuidado: Boolean? = null)

object Tramas {
    /**
     * Lee UNA trama. `null` si la conexión terminó. Una trama de un tipo que no
     * se conoce se saltea y se lee la siguiente: así el servidor puede agregar
     * una nueva sin romper a un teléfono viejo.
     */
    fun leer(fuente: BufferedSource): Trama? {
        while (true) {
            if (fuente.exhausted()) return null
            val tipo = fuente.readByte().toInt().toChar()
            val largo = fuente.readInt()
            val cuerpo = fuente.readByteArray(largo.toLong())
            decodificar(tipo, cuerpo)?.let { return it }
        }
    }

    fun decodificar(tipo: Char, cuerpo: ByteArray): Trama? = when (tipo) {
        'T' -> Trama.Texto(cuerpo.toString(Charsets.UTF_8))
        'H' -> cuerpo.toString(Charsets.UTF_8).toIntOrNull()?.let { Trama.Frecuencia(it) }
        'A' -> Trama.Audio(cuerpo)
        'F' -> runCatching { json.decodeFromString<FinCrudo>(cuerpo.toString(Charsets.UTF_8)) }.getOrNull()?.let {
            if (it.cuidado == true) Trama.Cuidado(it.texto)
            else Trama.Fin(it.ok, it.texto, desde(it.hablado ?: 0, it.texto))
        }
        else -> null
    }

    /**
     * Lo que queda del texto a partir de `n`. El servidor cuenta en unidades
     * UTF-16, igual que Kotlin, así que acá no hay que convertir nada.
     */
    fun desde(n: Int, texto: String): String = when {
        n <= 0 -> texto.trim()
        n >= texto.length -> ""
        else -> texto.substring(n).trim()
    }
}
