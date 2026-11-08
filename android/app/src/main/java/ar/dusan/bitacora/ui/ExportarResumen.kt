package ar.dusan.bitacora.ui

import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import java.time.YearMonth
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.nucleo.NotaDelDia
import ar.dusan.bitacora.nucleo.Resumen
import ar.dusan.bitacora.nucleo.SeccionDeLaFicha
import ar.dusan.bitacora.nucleo.Transcripcion
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate

/**
 * El PDF de «Mi resumen», para mandarle al psicólogo. Es `ExportarResumen.swift`.
 *
 * Android no tiene el motor de impresión de HTML de iOS a mano, así que acá se
 * dibuja directo: bloques de texto medidos y repartidos en hojas A4. Una frase
 * no queda partida entre dos hojas, ni la fecha de un día separada de lo que
 * sigue. El archivo queda en la caché de la app y sale del teléfono sólo si la
 * persona lo manda: nada se sube a ningún lado.
 */
object PdfDeResumen {
    private const val ANCHO = 595
    private const val ALTO = 842
    private const val MX = 52f
    private const val MY = 46f
    private const val PIE = 22f
    private val util = (ANCHO - 2 * MX).toInt()

    private const val TINTA = 0xFF1F1E1B.toInt()
    private const val SUAVE = 0xFF63605A.toInt()
    private const val TENUE = 0xFF96928A.toInt()
    private const val MUSGO = 0xFF4F6029.toInt()
    private const val BARRA = 0xFFA8B98A.toInt()
    private const val AVISO = 0xFFEFF1E4.toInt()
    private const val LINEA = 0xFFD9D9CC.toInt()

    private fun pintura(tam: Float, color: Int, tipo: Typeface = Typeface.DEFAULT) =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = tam; this.color = color; typeface = tipo }

    /** Un pedazo que no se parte: uno o más textos, uno abajo del otro. */
    private class Bloque(
        val textos: List<StaticLayout>,
        val sangria: Float = 0f,
        val barra: Int? = null,
        val fondo: Int? = null,
        val linea: Boolean = false,
        val antes: Float = 0f,
        val despues: Float = 0f,
        val conElSiguiente: Boolean = false,
    ) {
        val relleno = if (fondo != null) 8f else 0f
        val alto = antes + textos.sumOf { it.height }.toFloat() + 2 * relleno + (if (linea) 4f else 0f) + despues

        fun dibujar(c: Canvas, y0: Float) {
            var y = y0 + antes
            val cuerpo = textos.sumOf { it.height }.toFloat() + 2 * relleno
            fondo?.let { c.drawRect(MX, y, MX + util, y + cuerpo, Paint().apply { color = it }) }
            barra?.let { c.drawRect(MX, y, MX + (if (fondo != null) 3f else 2f), y + cuerpo, Paint().apply { color = it }) }
            y += relleno
            for (t in textos) {
                c.save(); c.translate(MX + sangria, y); t.draw(c); c.restore()
                y += t.height
            }
            if (linea) c.drawRect(MX, y + 3f, MX + util, y + 3.5f, Paint().apply { color = LINEA })
        }
    }

    /** `margen`: lo que se le resta al ancho del lado derecho, para los recuadros. */
    private fun texto(t: CharSequence, p: TextPaint, sangria: Float = 0f, margen: Float = 0f, interlineado: Float = 1.25f) =
        StaticLayout.Builder.obtain(t, 0, t.length, p, (util - sangria - margen).toInt())
            .setAlignment(Layout.Alignment.ALIGN_NORMAL).setLineSpacing(0f, interlineado).build()

    private fun conRotulo(rotulo: String, resto: String): CharSequence =
        SpannableStringBuilder(rotulo).apply {
            setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            append(resto)
        }

    /** Los títulos de la ficha para el psicólogo: en tercera persona, como en iOS. */
    private val titulosDeLaFicha = mapOf(
        "problematica" to "Lo que le pasa", "desencadenante" to "Lo que lo activa", "le_sirve" to "Lo que le sirve",
        "no_le_sirve" to "Lo que no le sirve", "meta" to "Lo que quiere", "persona" to "Su gente",
        "como_hablarle" to "Cómo prefiere que le hablen", "dato" to "Quién es",
    )

    private fun bloques(notas: List<NotaDelDia>, charlas: List<Resumen.CharlaSinFrases>, tramo: String,
                        nombre: String?, generado: String, ficha: List<SeccionDeLaFicha>): List<Bloque> {
        val serif = Typeface.SERIF
        val l = mutableListOf(
            Bloque(listOf(texto("Mi resumen", pintura(22f, TINTA, serif))), despues = 2f),
            Bloque(listOf(texto(Resumen.encabezado(nombre, tramo, generado), pintura(10f, SUAVE))), despues = 14f),
            Bloque(listOf(texto(Resumen.aviso(nombre), pintura(9.5f, 0xFF3E3C37.toInt()), sangria = 13f, margen = 10f)),
                   sangria = 13f, barra = MUSGO, fondo = AVISO, despues = 18f),
        )
        // Lo que eligió de su ficha para su psicólogo, arriba de los días (27/10/2026).
        val compartido = ficha.filter { it.datos.isNotEmpty() }
        if (compartido.isNotEmpty()) {
            l += Bloque(listOf(texto("Lo que eligió compartir", pintura(11.5f, TINTA, Typeface.DEFAULT_BOLD))),
                        linea = true, despues = 6f, conElSiguiente = true)
            l += Bloque(listOf(texto("Lo arma la app a partir de sus charlas; ${if (nombre == null) "la persona" else nombre} eligió qué mostrar.",
                                     pintura(9f, SUAVE))), despues = 6f, conElSiguiente = true)
            for (s in compartido) {
                l += Bloque(listOf(texto(conRotulo(titulosDeLaFicha[s.tipo] ?: s.titulo, ""), pintura(9.5f, SUAVE))),
                            antes = 4f, conElSiguiente = true)
                for (d in s.datos) {
                    val partes = mutableListOf(texto(d.nombre, pintura(11.5f, TINTA, Typeface.SERIF), sangria = 9f))
                    d.citas.firstOrNull()?.let {
                        partes += texto("«${it.cita}» · ${if (d.veces == 1) "una vez" else "${d.veces} veces"}, la última el ${Resumen.fechaConDia(d.ultima)}",
                                        pintura(8.5f, TENUE), sangria = 9f)
                    }
                    l += Bloque(partes, sangria = 9f, barra = BARRA, despues = 7f)
                }
            }
            l += Bloque(emptyList(), despues = 16f)
        }
        if (notas.isEmpty() && charlas.isEmpty()) l += Bloque(listOf(texto("No hay nada guardado en estos días.", pintura(11f, SUAVE))))
        fun titulo(dia: String, hora: String): Bloque {
            val t = SpannableStringBuilder(Resumen.fechaConDia(dia)).apply {
                setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                val i = length
                append("   $hora")
                setSpan(ForegroundColorSpan(TENUE), i, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                setSpan(AbsoluteSizeSpan(9), i, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            return Bloque(listOf(texto(t, pintura(11.5f, TINTA))), linea = true, despues = 6f, conElSiguiente = true)
        }
        fun cita(texto: String, sobre: String = ""): Bloque {
            val partes = mutableListOf(texto("«$texto»", pintura(11.5f, TINTA, serif), sangria = 9f))
            if (sobre.isNotBlank()) partes += texto(sobre, pintura(8.5f, TENUE), sangria = 9f)
            return Bloque(partes, sangria = 9f, barra = BARRA, despues = 7f)
        }
        // Las notas y las charlas sin frases, juntas y por fecha y hora.
        val dias = notas.map { Triple(it.dia, it.hora, it as Any) } + charlas.map { Triple(it.dia, it.hora, it as Any) }
        for ((_, _, d) in dias.sortedWith(compareBy({ it.first }, { it.second }))) {
            when (d) {
                is NotaDelDia -> {
                    l += titulo(d.dia, d.hora)
                    for (c in d.citas) l += cita(c.texto, c.sobre)
                    if (d.temas.isNotEmpty()) l += Bloque(listOf(texto(conRotulo("Temas", " (los escribe la app): ${d.temas.joinToString(" · ")}"),
                                                                        pintura(9f, SUAVE))), antes = 2f)
                    d.contexto?.takeIf { it.isNotBlank() }?.let {
                        l += Bloque(listOf(texto(conRotulo("Contexto", " (lo escribe la app): $it"), pintura(9f, SUAVE))), antes = 4f)
                    }
                    // El registro: sólo existe en este documento, nunca en pantalla.
                    val registro = Resumen.registroOrdenado(d.registro)
                    if (registro.isNotEmpty()) {
                        l += Bloque(listOf(texto(conRotulo("Registro", " (lo arma la app con sus frases):"), pintura(9f, SUAVE))),
                                    antes = 6f, conElSiguiente = true)
                        for ((tipo, r) in registro)
                            l += Bloque(listOf(texto(conRotulo("$tipo · ${r.que}", ":  «${r.cita}»"), pintura(9.5f, TINTA))), antes = 2f)
                    }
                }
                is Resumen.CharlaSinFrases -> {
                    l += titulo(d.dia, d.hora)
                    l += Bloque(listOf(texto("Ese día no se separaron frases: va lo que dijo en la charla, textual.", pintura(9f, SUAVE))),
                                despues = 6f, conElSiguiente = true)
                    for (t in d.dicho) l += cita(t)
                }
            }
            l += Bloque(emptyList(), despues = 16f)
        }
        return l
    }

    /** Arma el PDF en la caché y devuelve el archivo y cuántas hojas tiene. */
    fun crear(contexto: Context, notas: List<NotaDelDia>, charlas: List<Resumen.CharlaSinFrases>, tramo: String,
              nombre: String?, generado: String, archivo: String, pie: String,
              ficha: List<SeccionDeLaFicha> = emptyList()): Pair<File, Int> {
        // Primero se reparte en hojas, para saber cuántas son antes de numerarlas.
        val todos = bloques(notas, charlas, tramo, nombre, generado, ficha)
        val limite = ALTO - MY - PIE
        val hojas = mutableListOf(mutableListOf<Pair<Bloque, Float>>())
        var y = MY
        for ((i, b) in todos.withIndex()) {
            // Lo que va pegado a lo que sigue (la fecha, el aviso de un día sin
            // frases) no queda solo al pie: se mide junto con lo siguiente.
            var junto = b.alto
            var k = i
            while (todos[k].conElSiguiente && k + 1 < todos.size) { k++; junto += todos[k].alto }
            if (y + junto > limite && hojas.last().isNotEmpty()) {
                hojas += mutableListOf<Pair<Bloque, Float>>()
                y = MY
            }
            hojas.last() += b to y
            y += b.alto
        }

        val doc = PdfDocument()
        val pintaPie = pintura(8f, 0xFF8C8C8C.toInt()).apply { textAlign = Paint.Align.CENTER }
        hojas.forEachIndexed { n, hoja ->
            val pagina = doc.startPage(PdfDocument.PageInfo.Builder(ANCHO, ALTO, n + 1).create())
            for ((b, yb) in hoja) b.dibujar(pagina.canvas, yb)
            pagina.canvas.drawText("$pie · página ${n + 1} de ${hojas.size}", ANCHO / 2f, ALTO - MY + 6f, pintaPie)
            doc.finishPage(pagina)
        }
        val carpeta = File(contexto.cacheDir, "resumen").apply { mkdirs() }
        val f = File(carpeta, "${archivo.replace('/', '-').replace(':', '-')}.pdf")
        f.outputStream().use { doc.writeTo(it) }
        doc.close()
        return f to hojas.size
    }

    /** La hoja de compartir del sistema: correo, WhatsApp, Drive, lo que tenga. */
    fun compartir(contexto: Context, f: File) {
        val uri = FileProvider.getUriForFile(contexto, "${contexto.packageName}.archivos", f)
        val envio = Intent(Intent.ACTION_SEND).setType("application/pdf")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_SUBJECT, f.nameWithoutExtension)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        contexto.startActivity(Intent.createChooser(envio, "Enviar o guardar"))
    }
}

private sealed interface Exportado {
    data object Armando : Exportado
    data class Listo(val archivo: File, val paginas: Int, val dias: Int) : Exportado
    data object Fallo : Exportado
}

/**
 * Exportar a PDF: un calendario del mes con los días que tienen algo, para
 * elegirlos uno por uno. Es `HojaDeExportar` de iOS.
 *
 * Al abrir vienen marcados todos los del mes; se tocan para sacarlos o volver
 * a ponerlos, y no tienen que ser seguidos. Así lo pidió Dusan el 04/10/2026,
 * después de probar un «desde / hasta»: si pasó algo puntual que se habló en
 * dos días, que se pueda mandar sólo eso. Un día con charla pero sin frases
 * separadas se marca igual (también lo pidió): va lo que dijo en la charla,
 * textual. Todos los días con algo se ven iguales; qué es cada cosa lo explica
 * el botón de información, no la pantalla. Las frases se piden de a un mes,
 * al mirarlo, y el PDF se arma con esas.
 */
@Composable
fun ExportarPantalla(mes: String, alCerrar: () -> Unit) {
    val p = LocalPaleta.current
    val contexto = LocalContext.current
    val alcance = rememberCoroutineScope()
    var visto by rememberSaveable { mutableStateOf(mes) }
    val porDia = remember { mutableStateMapOf<String, List<NotaDelDia>>() }
    val traidos = remember { mutableStateListOf<String>() }
    var elegidos by remember { mutableStateOf(setOf<String>()) }
    // Si la persona ya eligió algo a mano. Hasta entonces, el mes que se mira
    // llega con todos sus días marcados.
    var tocado by remember { mutableStateOf(false) }
    var cargando by remember { mutableStateOf(false) }
    var sinServidor by remember { mutableStateOf(false) }
    var resultado by remember { mutableStateOf<Exportado?>(null) }
    var explicando by remember { mutableStateOf(false) }
    BackHandler(onBack = alCerrar)

    // Los días con charla salen del teléfono, como en el calendario.
    val entradas by Datos.entradas.todo.collectAsState()
    val conCharla = entradas.map { it.dia }.toSet()
    // Los días de un mes que se pueden mandar: con frases o con charla. Sólo si
    // ese mes ya se trajo: sin las frases, un día que sí las tiene se mandaría
    // como si no.
    fun conAlgo(m: String): Set<String> =
        if (m !in traidos) emptySet() else (porDia.keys + conCharla).filter { it.startsWith(m) }.toSet()
    // Los elegidos son justo todos los días con algo de un mes: el documento
    // dice «septiembre de 2026» y no la lista.
    val esElMes = elegidos.map { it.take(7) }.toSet().singleOrNull()?.let { elegidos == conAlgo(it) } ?: false

    // Trae las frases del mes que se mira, una vez. Mientras la persona no haya
    // elegido nada a mano, el mes llega con todos sus días marcados: por defecto
    // va el mes entero, también si abrió la hoja en un mes vacío y pasó a otro.
    LaunchedEffect(visto) {
        sinServidor = false
        if (visto in traidos) return@LaunchedEffect
        cargando = true
        val (desde, hasta) = Resumen.mes(visto)
        val notas = if (Datos.config.configurada) Datos.cliente().notas(desde, hasta) else emptyList()
        cargando = false
        if (notas == null) { sinServidor = true; return@LaunchedEffect }
        notas.groupBy { it.dia }.forEach { (d, ns) -> porDia[d] = Resumen.enOrden(ns) }
        traidos += visto
        if (!tocado && elegidos.isEmpty()) elegidos = conAlgo(visto)
    }
    // Cambiar los días deja viejo el PDF que ya estaba armado.
    LaunchedEffect(elegidos) { resultado = null }

    fun armar() {
        val dias = elegidos.sorted()
        val notas = dias.flatMap { porDia[it].orEmpty() }
        // De los días sin frases, lo que dijo en cada charla de ese día.
        val charlas = dias.filter { it !in porDia }.flatMap { d ->
            entradas.filter { it.dia == d }.sortedBy { it.creadoLocal }
                .map { Resumen.CharlaSinFrases(d, it.creadoLocal.substring(11, 16), Transcripcion.loQueDijo(it.transcripcion)) }
                .filter { it.dicho.isNotEmpty() }
        }
        if (notas.isEmpty() && charlas.isEmpty()) return
        val nombre = Datos.config.nombre.trim().takeIf { it.isNotEmpty() }
        val tramo = Resumen.escrito(dias, esElMes)
        resultado = Exportado.Armando
        alcance.launch {
            resultado = runCatching {
                val (f, hojas) = withContext(Dispatchers.Default) {
                    // La fecha del calendario y no el día de la bitácora: a la una de la
                    // mañana, el documento es de hoy, no de ayer.
                    PdfDeResumen.crear(contexto, notas, charlas, tramo, nombre, LocalDate.now().toString(),
                        archivo = if (nombre == null) "Mi resumen - $tramo" else "Mi resumen de $nombre - $tramo",
                        pie = if (nombre == null) "Mi resumen · $tramo" else "Mi resumen de $nombre · $tramo",
                        ficha = Datos.cliente().fichaCompartida().orEmpty())
                }
                Exportado.Listo(f, hojas, dias.size)
            }.getOrElse { Exportado.Fallo }
        }
    }

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = alCerrar) { Icon(Icons.Outlined.Close, "Cerrar", tint = p.tintaSuave) }
            Text("Exportar a PDF", Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            // La explicación, sólo si la pide: en la pantalla ocupaba lugar cada
            // vez, para algo que se entiende solo después de la primera.
            IconButton(onClick = { explicando = true }) { Icon(Icons.Outlined.Info, "Qué es esto", tint = p.tintaSuave) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp),
               verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Carta(Modifier.fillMaxWidth()) {
                Calendario(visto, conAlgo(visto), elegidos, cargando, alCambiarMes = { visto = it }) { d ->
                    tocado = true
                    elegidos = if (d in elegidos) elegidos - d else elegidos + d
                }
                when {
                    sinServidor -> Text("No se pudo conectar con el servidor para ver este mes.", color = p.tintaSuave,
                                        fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
                    !cargando && conAlgo(visto).isEmpty() ->
                        Text("En ${Resumen.meses[YearMonth.parse(visto).monthValue - 1]} no hay nada guardado.",
                             color = p.tintaSuave, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
                }
            }
            Text(if (elegidos.isEmpty()) "Elige al menos un día" else Resumen.escrito(elegidos, esElMes), fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val delMes = conAlgo(visto)
                TextButton({ tocado = true; elegidos = elegidos + delMes }, enabled = delMes.isNotEmpty()) { Text("Todo el mes", color = p.musgo) }
                TextButton({ tocado = true; elegidos = elegidos - delMes }, enabled = delMes.isNotEmpty()) { Text("Ninguno", color = p.musgo) }
            }
            when (val r = resultado) {
                null -> Button(::armar, enabled = elegidos.isNotEmpty(),
                               colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo)) { Text("Crear PDF") }
                Exportado.Armando -> Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(18.dp), color = p.tintaSuave, strokeWidth = 2.dp)
                    Text("  Armando el documento…", color = p.tintaSuave)
                }
                is Exportado.Listo -> {
                    Text("Listo: ${if (r.dias == 1) "un día" else "${r.dias} días"}, ${if (r.paginas == 1) "una página" else "${r.paginas} páginas"}.")
                    Button({ PdfDeResumen.compartir(contexto, r.archivo) },
                           colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo)) {
                        Icon(Icons.Outlined.Share, null, Modifier.size(18.dp))
                        Text("  Enviar o guardar")
                    }
                }
                Exportado.Fallo -> {
                    Text("No se pudo armar el PDF. Prueba de nuevo.", color = p.tintaSuave)
                    TextButton(::armar) { Text("Probar de nuevo", color = p.musgo) }
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }
    if (explicando) AlertDialog(
        onDismissRequest = { explicando = false },
        text = { Text("Arma un PDF con lo que dijiste, para mandarle a tu psicólogo. Vienen marcados todos los días del mes " +
                      "en que hablaste; toca un día para sacarlo o volver a ponerlo. Van tus frases tal como las dijiste, y de " +
                      "los días en que no se separaron frases, lo que dijiste en la charla. El PDF lo mandas tú desde el " +
                      "teléfono; no se sube a ningún lado.") },
        confirmButton = { TextButton({ explicando = false }) { Text("Entendido", color = p.musgo) } },
    )
}

/** El mes en grilla, lunes primero. Los días con algo se marcan y desmarcan; los demás, apagados. */
@Composable
private fun Calendario(mes: String, conAlgo: Set<String>, elegidos: Set<String>, cargando: Boolean,
                       alCambiarMes: (String) -> Unit, alTocar: (String) -> Unit) {
    val p = LocalPaleta.current
    val ym = YearMonth.parse(mes)
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { alCambiarMes(ym.minusMonths(1).toString()) }) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Mes anterior", tint = p.tintaSuave)
        }
        Text("${Resumen.meses[ym.monthValue - 1]} ${ym.year}", Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold)
        IconButton(onClick = { alCambiarMes(ym.plusMonths(1).toString()) }) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Mes siguiente", tint = p.tintaSuave)
        }
    }
    Row(Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
        for (d in listOf("L", "M", "M", "J", "V", "S", "D")) {
            Text(d, Modifier.weight(1f), textAlign = TextAlign.Center, color = p.tintaTenue, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }
    }
    val vacios = ym.atDay(1).dayOfWeek.value - 1
    val celdas = List(vacios) { null } + (1..ym.lengthOfMonth()).map { ym.atDay(it).toString() }
    Box(contentAlignment = Alignment.Center) {
        Column(Modifier.alpha(if (cargando) 0.35f else 1f)) {
            for (semana in celdas.chunked(7)) {
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    for (i in 0 until 7) {
                        val dia = semana.getOrNull(i)
                        if (dia == null) { Spacer(Modifier.weight(1f)); continue }
                        val tiene = dia in conAlgo
                        val elegido = dia in elegidos
                        Box(
                            Modifier.weight(1f).height(40.dp)
                                .background(if (elegido) p.musgo else Color.Transparent, RoundedCornerShape(11.dp))
                                .border(1.2.dp, if (tiene && !elegido) p.musgo.copy(alpha = 0.6f) else Color.Transparent, RoundedCornerShape(11.dp))
                                .clickable(enabled = tiene) { alTocar(dia) },
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(dia.takeLast(2).trimStart('0'), fontSize = 15.sp,
                                 fontWeight = if (elegido) FontWeight.Bold else FontWeight.Medium,
                                 color = when { elegido -> p.fondo; tiene -> p.tinta; else -> p.tintaTenue.copy(alpha = 0.6f) })
                        }
                    }
                }
            }
        }
        if (cargando) CircularProgressIndicator(Modifier.size(22.dp), color = p.tintaSuave, strokeWidth = 2.dp)
    }
}
