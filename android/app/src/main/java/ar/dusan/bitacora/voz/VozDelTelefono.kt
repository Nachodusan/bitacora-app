package ar.dusan.bitacora.voz

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import ar.dusan.bitacora.nucleo.Riesgo
import java.util.Locale
import java.util.UUID

/**
 * La voz del teléfono: el respaldo cuando la del servidor no llega, y la ÚNICA
 * que dice los textos fijos —el mensaje de cuidado y la despedida de los
 * cortes—, que nunca se mandan a sintetizar afuera.
 *
 * Por eso se elige una voz en español que NO necesite red. El motor de voz de
 * Android puede tener voces que sintetizan por internet; si la única que hay es
 * una de ésas, no se habla: el texto queda en pantalla. Que no suene es peor
 * que que suene a robot, pero mejor que mandar afuera justo el mensaje de riesgo.
 */
class VozDelTelefono(context: Context) {
    private val principal = Handler(Looper.getMainLooper())
    private val pendientes = mutableMapOf<String, () -> Unit>()
    private var lista = false
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { estado ->
        lista = estado == TextToSpeech.SUCCESS && elegirVoz()
    }

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) {}
            override fun onDone(utteranceId: String) = terminar(utteranceId)
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String) = terminar(utteranceId)
            override fun onError(utteranceId: String, errorCode: Int) = terminar(utteranceId)
            override fun onStop(utteranceId: String, interrupted: Boolean) = terminar(utteranceId)
        })
    }

    private fun elegirVoz(): Boolean {
        val enEspanol = tts.voices.orEmpty().filter {
            it.locale.language == "es" && !it.isNetworkConnectionRequired &&
                TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED !in it.features.orEmpty()
        }
        // De México o de Estados Unidos primero: lo más cerca de un español neutro.
        val voz = enEspanol.minByOrNull { if (it.locale.country in setOf("MX", "US", "419")) 0 else 1 }
            ?: return false
        tts.voice = voz
        tts.setSpeechRate(0.96f)
        return true
    }

    /** Dice el texto y avisa al terminar. Si no hay voz sin red, avisa enseguida. */
    fun decir(texto: String, alTerminar: () -> Unit) {
        if (!lista || texto.isBlank()) {
            principal.post(alTerminar)
            return
        }
        val id = UUID.randomUUID().toString()
        pendientes[id] = alTerminar
        tts.speak(Riesgo.paraDecir(texto), TextToSpeech.QUEUE_FLUSH, null, id)
        // Perro guardián: si el motor no avisa —pasa—, la charla no se cuelga.
        principal.postDelayed({ terminar(id) }, 4_000L + texto.length * 90L)
    }

    private fun terminar(id: String) {
        principal.post { pendientes.remove(id)?.invoke() }
    }

    fun callar() {
        pendientes.clear()
        tts.stop()
    }

    fun cerrar() {
        callar()
        tts.shutdown()
    }

    val idioma: Locale? get() = tts.voice?.locale
}
