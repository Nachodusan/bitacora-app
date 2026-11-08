package ar.dusan.bitacora.voz

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.concurrent.Executors

/**
 * El reproductor del audio en vivo: muestras de 16 bits, mono, que llegan del
 * servidor mientras se sintetizan. Es `Altavoz.swift`.
 *
 * Se escribe en un hilo aparte: `AudioTrack.write` bloquea cuando el buffer
 * está lleno, y el que lee las tramas tiene que seguir mostrando el texto
 * mientras se escribe.
 */
class Altavoz {
    private val hilo = Executors.newSingleThreadExecutor()
    private var pista: AudioTrack? = null
    @Volatile private var escritas = 0L
    @Volatile private var hz = 24_000
    /** El volumen de cada tramo de 40 ms escrito: dónde empieza y cuánto suena. */
    private val volumenes = java.util.concurrent.ConcurrentLinkedDeque<Pair<Long, Float>>()

    /** Si ya salió audio en este turno. */
    val sono: Boolean get() = escritas > 0

    fun empezar(frecuencia: Int) {
        callar()
        hz = frecuencia
        escritas = 0
        volumenes.clear()
        val minimo = AudioTrack.getMinBufferSize(hz, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        pista = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(hz)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build(),
            )
            .setBufferSizeInBytes(minimo * 4)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
            .also { it.play() }
    }

    fun sonar(pcm: ByteArray) {
        val p = pista ?: return
        hilo.execute {
            if (pista !== p) return@execute
            medir(pcm, escritas)
            p.write(pcm, 0, pcm.size)
            escritas += pcm.size / 2
        }
    }

    /**
     * Espera a que suene todo lo escrito y avisa. Si se calla antes, no avisa:
     * quien calla ya sabe qué sigue.
     */
    fun alTerminar(listo: () -> Unit) {
        val p = pista
        hilo.execute {
            if (p == null || pista !== p) {
                listo()
                return@execute
            }
            val total = escritas
            val limite = System.currentTimeMillis() + total * 1000 / hz + 3_000
            while (pista === p && p.playbackHeadPosition < total && System.currentTimeMillis() < limite) {
                Thread.sleep(40)
            }
            if (pista === p) listo()
        }
    }

    /**
     * Cuánto suena AHORA, de 0 a 1, con la escala de `Altavoz.swift`: -45 dB es
     * el piso y 0 dB el techo. Es lo que está saliendo por el parlante, no lo
     * último que se escribió: el buffer va adelantado, y los anillos tienen que
     * moverse con lo que se oye.
     */
    val nivel: Float
        get() {
            val p = pista ?: return 0f
            val cabeza = runCatching { p.playbackHeadPosition.toLong() }.getOrDefault(0L)
            while (volumenes.size > 1 && (volumenes.elementAtOrNull(1)?.first ?: Long.MAX_VALUE) <= cabeza) volumenes.pollFirst()
            val actual = volumenes.peekFirst() ?: return 0f
            return if (actual.first <= cabeza && cabeza < escritas) actual.second else 0f
        }

    private fun medir(pcm: ByteArray, desde: Long) {
        val tramo = hz / 25 // 40 ms
        val muestras = pcm.size / 2
        var i = 0
        while (i < muestras) {
            val fin = minOf(muestras, i + tramo)
            var suma = 0.0
            for (k in i until fin) {
                val v = ((pcm[2 * k + 1].toInt() shl 8) or (pcm[2 * k].toInt() and 0xFF)).toShort() / 32768.0
                suma += v * v
            }
            val rms = kotlin.math.sqrt(suma / (fin - i)).coerceAtLeast(1e-7)
            val db = 20 * kotlin.math.log10(rms)
            volumenes.addLast(desde + i to ((db + 45) / 45).toFloat().coerceIn(0f, 1f))
            i = fin
        }
    }

    fun callar() {
        val p = pista ?: return
        pista = null
        volumenes.clear()
        runCatching { p.pause(); p.flush(); p.release() }
    }
}
