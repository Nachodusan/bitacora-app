package ar.dusan.bitacora.nucleo

import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.util.Locale

/**
 * «Mi resumen»: las frases para llevar a terapia, de a un mes, y lo que dice
 * el documento que se le manda al psicólogo. Es `Resumen.swift`; el PDF lo
 * dibuja `ui/ExportarResumen.kt`.
 */
object Resumen {
    private val es = Locale.forLanguageTag("es")

    val meses = listOf("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                       "agosto", "septiembre", "octubre", "noviembre", "diciembre")

    /** El primer y el último día de un mes ("YYYY-MM"). */
    fun mes(ym: String): Pair<String, String> {
        val m = YearMonth.parse(ym)
        return m.atDay(1).toString() to m.atEndOfMonth().toString()
    }

    /**
     * El tramo como lo diría una persona: «septiembre de 2026» si es el mes
     * entero, «15 de septiembre de 2026» si es un día, «del 15 al 16 de
     * septiembre de 2026», o con los dos meses si cruza.
     */
    fun escrito(desde: String, hasta: String): String {
        val a = LocalDate.parse(desde)
        val b = LocalDate.parse(hasta)
        fun m(d: LocalDate) = meses[d.monthValue - 1]
        return when {
            a.year == b.year && a.month == b.month && a.dayOfMonth == 1 && b.dayOfMonth == b.lengthOfMonth() -> "${m(a)} de ${a.year}"
            a == b -> "${a.dayOfMonth} de ${m(a)} de ${a.year}"
            a.year == b.year && a.month == b.month -> "del ${a.dayOfMonth} al ${b.dayOfMonth} de ${m(b)} de ${b.year}"
            a.year == b.year -> "del ${a.dayOfMonth} de ${m(a)} al ${b.dayOfMonth} de ${m(b)} de ${b.year}"
            else -> "del ${a.dayOfMonth} de ${m(a)} de ${a.year} al ${b.dayOfMonth} de ${m(b)} de ${b.year}"
        }
    }

    /**
     * Días sueltos, elegidos uno por uno en el calendario. Con `esElMes` (son
     * todos los del mes que tenían algo): «septiembre de 2026». Si no: «15 y 16
     * de septiembre de 2026», «3, 10 y 24 de septiembre de 2026», «28 y 30 de
     * septiembre y 2 de octubre de 2026». Con más de cinco: «8 días, del 3 al
     * 24 de septiembre de 2026».
     */
    fun escrito(dias: Collection<String>, esElMes: Boolean): String {
        val orden = dias.toSortedSet().map(LocalDate::parse)
        if (orden.isEmpty()) return "ningún día"
        val a = orden.first()
        val b = orden.last()
        if (esElMes && a.year == b.year && a.month == b.month) return "${meses[a.monthValue - 1]} de ${a.year}"
        if (orden.size > 5) return "${orden.size} días, ${escrito(a.toString(), b.toString())}"
        val unAnio = a.year == b.year
        val grupos = orden.groupBy { YearMonth.from(it) }.map { (ym, ds) ->
            "${enLista(ds.map { it.dayOfMonth.toString() })} de ${meses[ym.monthValue - 1]}" + (if (unAnio) "" else " de ${ym.year}")
        }
        return enLista(grupos) + (if (unAnio) " de ${a.year}" else "")
    }

    /** «a», «a y b», «a, b y c». */
    fun enLista(cosas: List<String>): String =
        if (cosas.size <= 1) cosas.firstOrNull().orEmpty() else cosas.dropLast(1).joinToString(", ") + " y " + cosas.last()

    /** «Martes 15 de septiembre». */
    fun fechaConDia(dia: String): String {
        val d = LocalDate.parse(dia)
        return "${d.dayOfWeek.getDisplayName(TextStyle.FULL, es).replaceFirstChar { it.uppercase() }} ${d.dayOfMonth} de ${meses[d.monthValue - 1]}"
    }

    /** «4 de octubre de 2026». */
    fun fechaConAnio(dia: String): String {
        val d = LocalDate.parse(dia)
        return "${d.dayOfMonth} de ${meses[d.monthValue - 1]} de ${d.year}"
    }

    /**
     * Un día con charla pero sin frases separadas: va lo que dijo, textual
     * (`Transcripcion.loQueDijo`). Lo pidió Dusan: un día así también se le
     * tiene que poder mandar al psicólogo.
     */
    data class CharlaSinFrases(val dia: String, val hora: String, val dicho: List<String>)

    /** Del más viejo al más nuevo, como se lee un diario. El servidor las manda al revés. */
    fun enOrden(notas: List<NotaDelDia>): List<NotaDelDia> = notas.sortedWith(compareBy({ it.dia }, { it.hora }))

    /**
     * Lo primero que lee el psicólogo: qué es y qué no es. Escrito PARA ÉL, en
     * tercera persona. Un texto de un modelo que llega a un profesional con
     * forma de informe carga una autoridad que no se ganó.
     */
    fun aviso(nombre: String?): String {
        val quien = nombre?.trim()?.takeIf { it.isNotEmpty() }?.let { "de $it" } ?: "de la persona"
        return "Son frases $quien, tal como las dijo en su diario hablado, verificadas contra lo que quedó transcrito. " +
            "No es un informe clínico ni un diagnóstico: es material para trabajar en sesión. Los temas, el contexto " +
            "y el registro de cada día los arma la app y están marcados así; pueden equivocarse. El registro (emociones, " +
            "impulsos, conductas y hábitos que contó) lleva siempre su frase textual y la persona no lo ve en la app."
    }

    /** Los cuatro tipos del registro, en este orden y con su nombre para el psicólogo. */
    val TIPOS_DE_REGISTRO = listOf("emocion" to "Emoción", "impulso" to "Impulso", "conducta" to "Conducta", "habito" to "Hábito")

    /** El registro ordenado por tipo, con el nombre del tipo. Lo que traiga un tipo desconocido no va. */
    fun registroOrdenado(r: List<NotaDelDia.Registro>): List<Pair<String, NotaDelDia.Registro>> =
        TIPOS_DE_REGISTRO.flatMap { (clave, nombre) -> r.filter { it.tipo == clave }.map { nombre to it } }

    /** `tramo`: qué días son, ya escrito. */
    fun encabezado(nombre: String?, tramo: String, generado: String): String {
        val quien = nombre?.trim()?.takeIf { it.isNotEmpty() } ?: "la persona"
        return "De $quien · $tramo · preparado con Bitácora el ${fechaConAnio(generado)}"
    }
}
