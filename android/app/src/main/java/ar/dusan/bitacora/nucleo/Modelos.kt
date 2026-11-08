package ar.dusan.bitacora.nucleo

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** El JSON de toda la app: tolerante a campos nuevos, y sin mandar nulos. */
val json = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}

@Serializable
data class TurnoDeCharla(val de: String, val texto: String)

/**
 * El cuerpo de `POST /charla/vivo`. Sin `timbre` llega sólo el texto. `preparar`
 * es la consulta que se prepara desde «Preparar» en Mi expediente; en `null` no
 * se escribe (`explicitNulls = false`), y un servidor viejo no la ve.
 */
@Serializable
data class PedidoDeCharla(val turnos: List<TurnoDeCharla>, val dia: String, val timbre: String? = null,
                          val preparar: Int? = null)

/** El cuerpo de `POST /entradas`. */
@Serializable
data class EntradaNueva(
    @SerialName("client_uuid") val clientUuid: String,
    @SerialName("creado_en") val creadoEn: String,
    @SerialName("creado_local") val creadoLocal: String,
    val fuente: String,
    val transcripcion: String,
    @SerialName("duracion_seg") val duracionSeg: Double,
)

@Serializable
data class RespuestaEntrada(val id: Int, val dia: String? = null)

/** Un evento del calendario, casi siempre una consulta (`api/src/consultas.ts`). */
@Serializable
data class Evento(
    val id: Int,
    @SerialName("client_uuid") val clientUuid: String? = null,
    val tipo: String,
    val dia: String,
    val hora: String? = null,
    val titulo: String? = null,
    val origen: String = "persona",
    val estado: String = "confirmado",
    @SerialName("para_llevar") val paraLlevar: List<String> = emptyList(),
    val borrador: Borrador? = null,
    val evaluada: Boolean = false,
) {
    val esConsulta get() = tipo == "consulta"
    val esPropuesta get() = estado == "propuesto"

    /**
     * Cuándo es, para compararlo con la hora de pared: "YYYY-MM-DD HH:MM". Sin
     * hora cuenta el mediodía, igual que el servidor (`MOMENTO`, en `consultas.ts`).
     */
    val momento get() = "$dia ${hora ?: "12:00"}"

    companion object {
        /**
         * La próxima consulta confirmada que todavía no pasó: la de la tarjeta de
         * arriba de Mi expediente (desde el 06/10/2026). Una propuesta de
         * Bitácora no cuenta hasta que la persona la confirma. `ahora` es la hora
         * de pared, "YYYY-MM-DD HH:MM". Es `Evento.proximaConsulta` del iPhone.
         */
        fun proximaConsulta(eventos: List<Evento>, ahora: String): Evento? =
            eventos.filter { it.esConsulta && !it.esPropuesta && it.momento > ahora }.minByOrNull { it.momento }

        /** «hoy», «mañana» o «en 3 días», contando desde el día lógico. */
        fun cuantoFalta(dia: String, hoy: String): String {
            val dias = java.time.temporal.ChronoUnit.DAYS.between(
                java.time.LocalDate.parse(hoy), java.time.LocalDate.parse(dia))
            return when {
                dias < 1 -> "hoy"
                dias == 1L -> "mañana"
                else -> "en $dias días"
            }
        }
    }
}

/** Lo que el servidor sacó de las charlas de después de una consulta. */
@Serializable
data class Borrador(
    val entendi: String = "",
    val aporte: String = "",
    val sentir: String = "",
    val temas: List<String> = emptyList(),
    val avance: String = "",
)

@Serializable
data class RespuestaEventos(val eventos: List<Evento>)

@Serializable
data class RespuestaEvento(val evento: Evento)

/** Lo que dijo un día, en sus palabras, para llevar a terapia (`GET /notas`). */
@Serializable
data class NotaDelDia(
    val dia: String,
    val hora: String,
    val temas: List<String> = emptyList(),
    val contexto: String? = null,
    val citas: List<Cita> = emptyList(),
    /**
     * Emociones, impulsos, conductas y hábitos que contó, cada uno con su frase.
     * SÓLO para el PDF del psicólogo: ninguna pantalla se lo muestra a la
     * persona, para que no se autodiagnostique. Un servidor anterior al 14 de
     * octubre no lo manda y llega vacío.
     */
    val registro: List<Registro> = emptyList(),
) {
    @Serializable
    data class Cita(val texto: String, val sobre: String = "")

    /** `tipo`: "emocion", "impulso", "conducta" o "habito". */
    @Serializable
    data class Registro(val tipo: String, val que: String, val cita: String)
}

@Serializable
data class RespuestaNotas(val notas: List<NotaDelDia>)

/** La ficha viva, como la ve la persona en Mi espacio (`api/src/ficha.ts`). */
@Serializable
data class Ficha(
    val activa: Boolean,
    val avisada: Boolean,
    @SerialName("cuenta_se_borra_el") val cuentaSeBorraEl: String? = null,
    val secciones: List<SeccionDeLaFicha> = emptyList(),
)

@Serializable
data class SeccionDeLaFicha(val tipo: String, val titulo: String, val datos: List<DatoDeLaFicha>)

@Serializable
data class DatoDeLaFicha(
    val id: Int,
    val nombre: String,
    val descripcion: String? = null,
    val veces: Int,
    val primera: String,
    val ultima: String,
    val compartir: Boolean,
    val citas: List<CitaDeLaFicha> = emptyList(),
    /** Cómo más le dice («el viejo» por «su papá»). */
    val apodos: List<String> = emptyList(),
    /** Cuándo le sirve (lo más seguido primero) y para qué. Sólo en «Qué le sirve». */
    val momentos: List<String> = emptyList(),
    val para: List<String> = emptyList(),
) {
    /** «En la noche · para: le cuesta dormir», o null. */
    val cuandoYParaQue: String?
        get() = listOf(momentos.take(2).joinToString(" y ").replaceFirstChar { it.uppercase() },
                       if (para.isEmpty()) "" else "para: " + para.take(3).joinToString(", "))
            .filter { it.isNotEmpty() }.joinToString(" · ").ifEmpty { null }
}

@Serializable
data class CitaDeLaFicha(val dia: String, val cita: String)

@Serializable
data class RespuestaBorrarCuenta(@SerialName("se_borra_el") val seBorraEl: String)

@Serializable
data class RespuestaFichaCompartida(val secciones: List<SeccionDeLaFicha>)

/** Lo que la persona da al registrarse (28/10/2026). Todo opcional. */
@Serializable
data class PerfilDeCuenta(
    val id: String? = null,
    val nombre: String? = null,
    @SerialName("fecha_nacimiento") val fechaNacimiento: String? = null,
    val pais: String? = null,
    val ciudad: String? = null,
    @SerialName("con_quien") val conQuien: String? = null,
)

@Serializable
data class RespuestaDeCuenta(val id: String? = null, val token: String? = null,
                             @SerialName("trabada_hasta") val trabadaHasta: String? = null)

sealed interface ResultadoDeCuenta {
    data class Lista(val id: String?, val token: String) : ResultadoDeCuenta
    data object Incorrecto : ResultadoDeCuenta
    data object Trabada : ResultadoDeCuenta
    data object SinServidor : ResultadoDeCuenta
}
