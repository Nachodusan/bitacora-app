package ar.dusan.bitacora.nucleo

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.coroutineContext

/**
 * El cliente del servidor de la bitácora. Es `SyncClient.swift`.
 *
 * Todo con el mismo token, y nada que dependa de una sesión: el servidor no
 * guarda estado entre pedidos.
 */
class Cliente(baseUrl: String, private val token: String) {

    /** En qué estado está el servidor, visto desde el teléfono. */
    enum class Estado {
        /** Contestó y aceptó la llave. */
        LISTO,
        /** Contestó 401 o 403: está vivo, pero el token no le cierra. */
        SIN_TOKEN,
        /** No contestó: apagado, dirección equivocada, o sin señal. */
        INALCANZABLE,
    }

    sealed interface Subida {
        data class Aceptada(val id: Int) : Subida
        /** Red, timeout, 5xx, o cualquier cosa que no dependa de la entrada. */
        data object Reintentable : Subida
        /** Un 401: queda pendiente hasta que el token esté bien. */
        data object SinCredencial : Subida
        /** El contenido no se acepta: reintentar no sirve. */
        data class Rechazada(val motivo: String) : Subida
    }

    private val base: HttpUrl? = baseUrl.trim().trimEnd('/').toHttpUrlOrNull()

    private fun url(ruta: String): HttpUrl? = base?.newBuilder()?.addPathSegments(ruta)?.build()

    private fun pedido(ruta: String): Request.Builder? =
        url(ruta)?.let { Request.Builder().url(it).header("Authorization", "Bearer $token") }

    private suspend fun <T> ejecutar(cliente: OkHttpClient, req: Request?, leer: (Response) -> T): T? =
        withContext(Dispatchers.IO) {
            if (req == null) return@withContext null
            runCatching { cliente.newCall(req).execute().use(leer) }.getOrNull()
        }

    /**
     * Pregunta contra una ruta que SÍ pide credencial: `/health` contesta sin
     * token, así que un "está vivo" de ahí no dice si la app va a poder trabajar.
     */
    suspend fun comprobar(): Estado =
        ejecutar(sondeo, pedido("ajustes")?.get()?.build()) {
            when (it.code) {
                200 -> Estado.LISTO
                401, 403 -> Estado.SIN_TOKEN
                else -> Estado.INALCANZABLE
            }
        } ?: Estado.INALCANZABLE

    /** `POST /entradas`. Idempotente por `client_uuid`: reintentar es seguro. */
    suspend fun subir(e: EntradaNueva): Subida =
        ejecutar(normal, pedido("entradas")?.post(cuerpo(json.encodeToString(e)))?.build()) { r ->
            val texto = r.body?.string().orEmpty()
            when (r.code) {
                200, 201 -> runCatching { json.decodeFromString<RespuestaEntrada>(texto) }
                    .getOrNull()?.let { Subida.Aceptada(it.id) } ?: Subida.Reintentable
                401, 403 -> Subida.SinCredencial
                400, 413, 415, 422 -> Subida.Rechazada(texto.ifEmpty { "rechazada" })
                else -> Subida.Reintentable
            }
        } ?: Subida.Reintentable

    /**
     * `POST /charla/vivo`. Va entregando las tramas a medida que llegan.
     *
     * Tira si no se pudo abrir o si se cortó. Cancelar la corrutina cierra la
     * conexión, y eso es lo que le avisa al servidor que corte lo que estaba
     * generando (y pagando).
     */
    suspend fun charlaEnVivo(p: PedidoDeCharla, alRecibir: suspend (Trama) -> Unit) {
        val req = pedido("charla/vivo")?.post(cuerpo(json.encodeToString(p)))?.build()
            ?: throw IOException("dirección del servidor inválida")
        withContext(Dispatchers.IO) {
            val llamada = enVivo.newCall(req)
            val atado = coroutineContext[kotlinx.coroutines.Job]?.invokeOnCompletion { llamada.cancel() }
            try {
                llamada.execute().use { r ->
                    if (r.code != 200) throw IOException("HTTP ${r.code}")
                    val fuente = r.body?.source() ?: throw IOException("sin cuerpo")
                    while (true) {
                        coroutineContext.ensureActive()
                        val t = Tramas.leer(fuente) ?: break
                        alRecibir(t)
                    }
                }
            } finally {
                atado?.dispose()
            }
        }
    }

    /** `GET /eventos`. `null` si no se pudo preguntar, que no es lo mismo que no tener ninguno. */
    suspend fun eventos(): List<Evento>? =
        ejecutar(normal, pedido("eventos")?.get()?.build()) { r ->
            if (r.code != 200) null
            else runCatching { json.decodeFromString<RespuestaEventos>(r.body!!.string()).eventos }.getOrNull()
        }

    /** `POST /eventos`. Idempotente por `clientUuid`. */
    suspend fun crearEvento(clientUuid: String, tipo: String, dia: String, hora: String?, titulo: String?): Evento? {
        val c = buildJsonObject {
            put("client_uuid", clientUuid)
            put("tipo", tipo)
            put("dia", dia)
            hora?.let { put("hora", it) }
            titulo?.let { put("titulo", it) }
        }
        return ejecutar(normal, pedido("eventos")?.post(cuerpo(c.toString()))?.build(), ::leerEvento)
    }

    /** `PATCH /eventos/:id`, con sólo lo que cambia. */
    suspend fun cambiarEvento(id: Int, cambio: JsonObject): Evento? =
        ejecutar(normal, pedido("eventos/$id")?.patch(cuerpo(cambio.toString()))?.build(), ::leerEvento)

    /** `DELETE /eventos/:id`. Un 404 también es que ya no está. */
    suspend fun borrarEvento(id: Int): Boolean =
        ejecutar(normal, pedido("eventos/$id")?.delete()?.build()) { it.code == 204 || it.code == 404 } ?: false

    private fun leerEvento(r: Response): Evento? =
        if (r.code != 200 && r.code != 201) null
        else runCatching { json.decodeFromString<RespuestaEvento>(r.body!!.string()).evento }.getOrNull()

    /** `PUT /ajustes`: el nombre y la zona horaria del teléfono. */
    suspend fun guardarAjustes(nombre: String?, zona: String): Boolean {
        val limpio = nombre?.trim()?.take(40)?.ifEmpty { null }
        val c = buildJsonObject {
            put("zona", zona)
            put("nombre", limpio)
        }
        return ejecutar(normal, pedido("ajustes")?.put(cuerpo(c.toString()))?.build()) { it.code == 200 } ?: false
    }

    /** `GET /notas`: lo que dijo, en sus palabras, para llevar a terapia. */
    /**
     * `GET /notas` entre dos días (los dos incluidos). `null` si no se pudo
     * preguntar, que no es lo mismo que no tener nada: un PDF vacío porque se
     * cortó la red se mandaría igual al psicólogo.
     */
    suspend fun notas(desde: String, hasta: String): List<NotaDelDia>? {
        val u = url("notas")?.newBuilder()?.addQueryParameter("desde", desde)?.addQueryParameter("hasta", hasta)?.build()
        val req = u?.let { Request.Builder().url(it).header("Authorization", "Bearer $token").get().build() }
        return ejecutar(normal, req) { r ->
            if (r.code != 200) null
            else runCatching { json.decodeFromString<RespuestaNotas>(r.body!!.string()).notas }.getOrNull()
        }
    }

    /** `GET /ficha`: la ficha entera, para Mi espacio. `null` si no se pudo preguntar. */
    suspend fun ficha(): Ficha? =
        ejecutar(normal, pedido("ficha")?.get()?.build()) { r ->
            if (r.code != 200) null else runCatching { json.decodeFromString<Ficha>(r.body!!.string()) }.getOrNull()
        }

    /** `GET /ficha/compartida`: lo que eligió para su psicólogo, para el PDF. */
    suspend fun fichaCompartida(): List<SeccionDeLaFicha>? =
        ejecutar(normal, pedido("ficha/compartida")?.get()?.build()) { r ->
            if (r.code != 200) null
            else runCatching { json.decodeFromString<RespuestaFichaCompartida>(r.body!!.string()).secciones }.getOrNull()
        }

    /** `POST /ficha/aviso`: leyó el aviso. Hasta entonces la ficha no se arma. */
    suspend fun leyoElAviso(): Boolean = ok(pedido("ficha/aviso")?.post(cuerpo("{}"))?.build())

    suspend fun compartir(dato: Int, si: Boolean): Boolean =
        ok(pedido("ficha/$dato")?.patch(cuerpo("""{"compartir":$si}"""))?.build())

    suspend fun quitar(dato: Int): Boolean = ok(pedido("ficha/$dato")?.delete()?.build())

    /** Borra una conversación en el servidor, con lo que salió de ella. */
    suspend fun borrarConversacion(uuid: String): Boolean = ok(pedido("entradas/$uuid")?.delete()?.build())

    /** La cuenta va a la papelera por treinta días. Devuelve el día en que se borra. */
    suspend fun borrarCuenta(): String? =
        ejecutar(normal, pedido("cuenta/borrar")?.post(cuerpo("{}"))?.build()) { r ->
            if (r.code != 200) null
            else runCatching { json.decodeFromString<RespuestaBorrarCuenta>(r.body!!.string()).seBorraEl }.getOrNull()
        }

    suspend fun recuperarCuenta(): Boolean = ok(pedido("cuenta/recuperar")?.post(cuerpo("{}"))?.build())

    // ---- Cuentas (28/10/2026): un ID que da el servidor y un PIN de seis dígitos.

    private fun perfilJson(pf: PerfilDeCuenta, extra: Map<String, String> = emptyMap()) = buildJsonObject {
        extra.forEach { (k, v) -> put(k, v) }
        put("nombre", pf.nombre); put("fecha_nacimiento", pf.fechaNacimiento)
        put("pais", pf.pais); put("ciudad", pf.ciudad); put("con_quien", pf.conQuien)
    }.toString()

    private fun leerCuenta(r: Response): ResultadoDeCuenta {
        val d = runCatching { json.decodeFromString<RespuestaDeCuenta>(r.body!!.string()) }.getOrNull()
        return when (r.code) {
            200, 201 -> d?.token?.let { ResultadoDeCuenta.Lista(d.id, it) } ?: ResultadoDeCuenta.SinServidor
            401 -> ResultadoDeCuenta.Incorrecto
            423 -> ResultadoDeCuenta.Trabada
            else -> ResultadoDeCuenta.SinServidor
        }
    }

    private fun sinToken(ruta: String, c: String): Request? = url(ruta)?.let { Request.Builder().url(it).post(cuerpo(c)).build() }

    suspend fun crearCuenta(pin: String, pf: PerfilDeCuenta, zona: String): ResultadoDeCuenta =
        ejecutar(normal, sinToken("cuentas", perfilJson(pf, mapOf("pin" to pin, "zona" to zona))), ::leerCuenta)
            ?: ResultadoDeCuenta.SinServidor

    suspend fun entrar(id: String, pin: String): ResultadoDeCuenta =
        ejecutar(normal, sinToken("cuentas/entrar", buildJsonObject { put("id", id); put("pin", pin) }.toString()), ::leerCuenta)
            ?: ResultadoDeCuenta.SinServidor

    /** El diario de antes de las cuentas elige su PIN (con el token fijo). */
    suspend fun elegirPin(pin: String): ResultadoDeCuenta =
        ejecutar(normal, pedido("cuenta/pin")?.post(cuerpo(buildJsonObject { put("pin", pin) }.toString()))?.build(), ::leerCuenta)
            ?: ResultadoDeCuenta.SinServidor

    suspend fun perfil(): PerfilDeCuenta? =
        ejecutar(normal, pedido("perfil")?.get()?.build()) { r ->
            if (r.code != 200) null else runCatching { json.decodeFromString<PerfilDeCuenta>(r.body!!.string()) }.getOrNull()
        }

    suspend fun guardarPerfil(pf: PerfilDeCuenta): Boolean = ok(pedido("perfil")?.put(cuerpo(perfilJson(pf)))?.build())

    private suspend fun ok(req: Request?): Boolean = ejecutar(normal, req) { it.code in 200..299 } ?: false

    private fun cuerpo(texto: String) = texto.toRequestBody("application/json".toMediaType())

    companion object {
        /** Para preguntar si el servidor está. Corto: en una red local, cuatro segundos es no estar. */
        private val sondeo = OkHttpClient.Builder().callTimeout(4, TimeUnit.SECONDS).build()

        /** Para todo lo demás. Holgado: perder una entrada por impaciencia es peor que esperar. */
        private val normal = OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build()

        /**
         * Para el turno en vivo: sin techo total —el turno dura lo que dure—, pero
         * con uno entre trama y trama, por si el servidor se cuelga a la mitad.
         */
        private val enVivo = OkHttpClient.Builder()
            .connectTimeout(6, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .build()
    }
}
