package ar.dusan.bitacora.datos

import android.content.Context
import android.content.SharedPreferences
import ar.dusan.bitacora.BuildConfig
import ar.dusan.bitacora.nucleo.Cliente
import ar.dusan.bitacora.nucleo.Evento
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.serialization.Serializable
import java.io.File

/** Una conversación tal como vive en el teléfono. Es `EntradaLocal.swift`. */
@Serializable
data class EntradaLocal(
    val clientUuid: String,
    /** El instante, con desfase: `creado_en`. */
    val creadoEn: String,
    /** La hora de pared, sin zona: `creado_local`. */
    val creadoLocal: String,
    /** El día lógico (corte a las 4am). */
    val dia: String,
    val transcripcion: String,
    val duracionSeg: Double,
    /** borrador, pendiente, subida o rechazada. */
    val estado: String,
    val servidorId: Int? = null,
)

/** Lo que la persona se lleva de una sesión con su terapeuta. Es `SesionDeTerapia.swift`. */
@Serializable
data class SesionDeTerapia(
    val id: String,
    val numero: Int,
    /** "YYYY-MM-DD", el día de la sesión y no el día en que se anotó. */
    val fecha: String,
    val entendi: String = "",
    val aporte: String = "",
    val sentir: String = "",
    val temas: List<String> = emptyList(),
    val avance: String = "",
    /** La consulta del calendario a la que corresponde, si se sabe. */
    val eventoId: Int? = null,
    /** Falso mientras sea un borrador que la persona todavía no miró. */
    val revisada: Boolean = true,
    val creadoEn: Long = System.currentTimeMillis(),
) {
    val hayAlgoEscrito get() = temas.isNotEmpty() || listOf(entendi, aporte, sentir, avance).any { it.isNotBlank() }
}

/** Una nota suelta: algo escrito sin hablar con nadie. Es `Apunte` en el iPhone. */
@Serializable
data class Apunte(
    val id: String,
    val creadoEn: Long,
    /** El día lógico en que se escribió. */
    val dia: String,
    val texto: String,
)

/**
 * La configuración: dónde está el servidor, con qué llave, cómo llamarla.
 *
 * El servidor puede venir dentro de la app (`servidorFijo`, desde el
 * 06/10/2026): así va la APK de un cliente, que no tiene por qué ver ni
 * tocar una dirección o un token. Si no, la dirección y el token se escriben
 * en Ajustes, como se prueba en el emulador.
 */
class Config(private val prefs: SharedPreferences) {
    /** Si la APK trae el servidor adentro (`servidor.properties` al compilar). */
    val servidorFijo = BuildConfig.SERVIDOR_URL.isNotBlank() && BuildConfig.SERVIDOR_TOKEN.isNotBlank()

    var url: String
        get() = if (servidorFijo) BuildConfig.SERVIDOR_URL else prefs.getString("url", "").orEmpty()
        set(v) = prefs.edit().putString("url", v.trim()).apply()
    /** El token fijo de antes de las cuentas. Sólo sirve para que el diario que ya existía elija su PIN. */
    val tokenFijo: String
        get() = if (servidorFijo) BuildConfig.SERVIDOR_TOKEN else prefs.getString("token", "").orEmpty()

    /** La sesión de la cuenta (28/10/2026). Con ella, todo va a la base de esa cuenta. */
    var sesion: String?
        get() = prefs.getString("sesion", null)
        set(v) = prefs.edit().putString("sesion", v).apply()

    /** El ID de la cuenta, para mostrarlo y anotarlo. */
    var cuentaId: String?
        get() = prefs.getString("cuentaId", null)
        set(v) = prefs.edit().putString("cuentaId", v).apply()

    /** Con la sesión si hay; si no, el token fijo (sólo el diario de antes). */
    var token: String
        get() = sesion ?: tokenFijo
        set(v) = prefs.edit().putString("token", v.trim()).apply()
    var nombre: String
        get() = prefs.getString("nombre", "").orEmpty()
        set(v) = prefs.edit().putString("nombre", v.trim()).apply()
    /** Una sola voz desde el 26/10/2026, Lupita: un «hombre» guardado de antes se ignora. */
    var timbre: String
        get() = "mujer"
        set(@Suppress("UNUSED_PARAMETER") v) {}
    /** La voz del servidor. Apagada, en llamada habla la del teléfono. */
    var vozNatural: Boolean
        get() = prefs.getBoolean("vozNatural", true)
        set(v) = prefs.edit().putBoolean("vozNatural", v).apply()

    /**
     * Si ya pasó por la bienvenida. Lo que había antes de que existiera
     * (04/10/2026) cuenta como visto si ya tenía nombre.
     */
    var nombrePreguntado: Boolean
        get() = prefs.getBoolean("nombrePreguntado", nombre.isNotBlank())
        set(v) = prefs.edit().putBoolean("nombrePreguntado", v).apply()

    val configurada get() = url.isNotBlank() && token.isNotBlank()
}

/** Todo lo que se guarda, en un solo lugar. Se arma una vez, al abrir la app. */
object Datos {
    lateinit var config: Config
        private set
    lateinit var entradas: Almacen<EntradaLocal>
        private set
    lateinit var sesiones: Almacen<SesionDeTerapia>
        private set
    lateinit var apuntes: Almacen<Apunte>
        private set
    /** La copia de los eventos del servidor, para mostrarlos sin red. */
    lateinit var eventos: Almacen<Evento>
        private set

    /** Para lo que tiene que seguir aunque se cierre una pantalla: subir, avisar. */
    val alcance = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    fun iniciar(context: Context) {
        if (::config.isInitialized) return
        config = Config(context.getSharedPreferences("bitacora", Context.MODE_PRIVATE))
        val carpeta = context.filesDir
        entradas = Almacen(File(carpeta, "entradas.json"), EntradaLocal.serializer())
        sesiones = Almacen(File(carpeta, "sesiones.json"), SesionDeTerapia.serializer())
        apuntes = Almacen(File(carpeta, "apuntes.json"), Apunte.serializer())
        eventos = Almacen(File(carpeta, "eventos.json"), Evento.serializer())
    }

    fun cliente() = Cliente(config.url, config.token)
}
