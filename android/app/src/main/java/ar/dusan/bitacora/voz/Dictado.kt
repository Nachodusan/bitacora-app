package ar.dusan.bitacora.voz

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.Locale

/**
 * El dictado, en el teléfono y sólo en el teléfono (regla 1).
 *
 * Se usa `createOnDeviceSpeechRecognizer`, que existe desde Android 12 y no
 * manda el audio a ningún lado. Si el teléfono no lo tiene —o no tiene el
 * español descargado—, NO se cae al reconocedor común, que puede transcribir
 * por internet: se dice que no se puede y se ofrece escribir. Es la misma regla
 * que en el iPhone: se transcribe ahí o falla a la vista.
 *
 * Cada `escuchar` es una sola frase: el reconocedor corta solo cuando hay
 * silencio. Qué hacer con ese corte —si la frase quedó colgada, seguir— lo
 * decide `Conversacion` con `FinDeTurno`.
 */
class Dictado(private val context: Context) {
    private var reconocedor: SpeechRecognizer? = null

    val disponible: Boolean
        get() = SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    /** El nivel de la voz, de 0 a 1, para la luz de la pantalla. */
    var alNivel: ((Float) -> Unit)? = null

    fun escuchar(alParcial: (String) -> Unit, alTerminar: (String) -> Unit, alFallar: (String) -> Unit) {
        frenar()
        if (!disponible) {
            alFallar(SIN_RECONOCEDOR)
            return
        }
        val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        reconocedor = r
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {
                alNivel?.invoke(((rmsdB + 2f) / 12f).coerceIn(0f, 1f))
            }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {
                primero(partialResults)?.let(alParcial)
            }
            override fun onResults(results: Bundle?) {
                alTerminar(primero(results).orEmpty())
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onError(error: Int) {
                when (error) {
                    // No dijo nada, o nada que se entendiera: es un turno vacío, no un error.
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> alTerminar("")
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> alFallar("Falta el permiso del micrófono.")
                    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED, SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
                        alFallar(FALTA_IDIOMA)
                    SpeechRecognizer.ERROR_CLIENT, SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> alTerminar("")
                    else -> alFallar("El dictado se detuvo. Toca para seguir, o escribe.")
                }
            }
        })
        r.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, idioma())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            // Pistas para esperar un poco más antes de cortar. El reconocedor
            // puede no hacerles caso; lo que sí se cumple es lo de `FinDeTurno`.
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2200L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1300L)
        })
    }

    /** Desde Android 13 se le puede pedir al sistema que baje el español. */
    val puedeDescargar: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    /**
     * Le pide al sistema que descargue el modelo de español para dictar en el
     * teléfono. Lo baja el sistema, como cualquier idioma; el audio de la
     * persona sigue sin salir del teléfono. Pregunta el sistema, no la app.
     */
    fun descargarIdioma() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        r.triggerModelDownload(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, idioma())
        })
        Handler(Looper.getMainLooper()).postDelayed({ r.destroy() }, 10_000)
    }

    fun frenar() {
        reconocedor?.let {
            it.cancel()
            it.destroy()
        }
        reconocedor = null
        alNivel?.invoke(0f)
    }

    private fun primero(b: Bundle?): String? =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()?.ifEmpty { null }

    /** El español del teléfono si está en español; si no, el de Estados Unidos, que es el que más se descarga. */
    private fun idioma(): String {
        val l = Locale.getDefault()
        return if (l.language == "es") l.toLanguageTag() else "es-US"
    }

    companion object {
        const val FALTA_IDIOMA =
            "Falta el español para dictar sin internet. Mientras tanto puedes escribir."
        const val SIN_RECONOCEDOR =
            "Este teléfono no tiene dictado que funcione sin internet. Puedes escribir: la voz nunca sale del teléfono."
    }
}
