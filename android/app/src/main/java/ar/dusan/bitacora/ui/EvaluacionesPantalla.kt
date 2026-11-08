package ar.dusan.bitacora.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ar.dusan.bitacora.datos.Agenda
import ar.dusan.bitacora.Navegacion
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.datos.SesionDeTerapia
import ar.dusan.bitacora.nucleo.Ficha
import ar.dusan.bitacora.nucleo.DiaLogico
import ar.dusan.bitacora.nucleo.NotaDelDia
import ar.dusan.bitacora.nucleo.Resumen
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneOffset
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID
import androidx.compose.foundation.layout.width
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.LocalOffer
import androidx.compose.material.icons.automirrored.outlined.TrendingUp
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Spa
import androidx.compose.material.icons.outlined.Lightbulb
import ar.dusan.bitacora.nucleo.Transcripcion
import ar.dusan.bitacora.datos.EntradaLocal
import androidx.compose.material.icons.filled.Add
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.draw.drawBehind
import ar.dusan.bitacora.nucleo.Evento

private val es = Locale.forLanguageTag("es")

private fun fechaEscrita(dia: String): String {
    val f = LocalDate.parse(dia)
    return "${f.dayOfWeek.getDisplayName(TextStyle.FULL, es).replaceFirstChar { it.uppercase() }}, " +
        "${f.dayOfMonth} de ${f.month.getDisplayName(TextStyle.FULL, es)} de ${f.year}"
}

/**
 * La pestaña «Mi expediente» («Mi proceso» hasta la noche del 04/10/2026), con
 * dos partes, como `EvaluacionesView.swift`.
 * CONSULTAS: lo que la persona se lleva de cada sesión con su terapeuta (la
 * lista, una sesión para releer, y la anotación paso por paso, una pregunta por
 * pantalla). Viven sólo en el teléfono; si la sesión es una consulta del
 * calendario y la persona habló de ella con Bitácora, llega armada, «para
 * revisar». MI RESUMEN: lo que dijo en sus palabras, para llevar a terapia;
 * hasta el 04/10/2026 se abría desde el calendario.
 *
 * Abre en una portada con dos tarjetas, una por parte, y se entra a cada una
 * como a una pantalla aparte. Hasta el 04/10/2026 eran dos botones pegados
 * arriba de la lista, y Dusan sintió que la gente se iba a perder. Eligió esta
 * forma («como los íconos de la pantalla de inicio») y el sillón y el libro.
 */
@Composable
fun EvaluacionesPantalla() {
    val sesiones by Datos.sesiones.todo.collectAsState()
    // null es la portada; "consultas" o "resumen", lo de adentro.
    var parte by rememberSaveable { mutableStateOf<String?>(null) }
    var mesResumen by rememberSaveable { mutableStateOf(DiaLogico.hoy().substring(0, 7)) }
    var exportando by rememberSaveable { mutableStateOf(false) }
    var abierta by rememberSaveable { mutableStateOf<String?>(null) }
    var anotando by rememberSaveable { mutableStateOf<String?>(null) }
    var modo by rememberSaveable { mutableStateOf("nueva") }
    var paso by rememberSaveable { mutableStateOf(0) }
    // Un día de «Mi resumen», abierto desde el índice del mes.
    var diaDelResumen by remember { mutableStateOf<NotaDelDia?>(null) }
    var diaSinFrases by remember { mutableStateOf<DiaSinFrases?>(null) }
    LaunchedEffect(Unit) { Agenda.actualizar() }

    if (exportando) { ExportarPantalla(mesResumen) { exportando = false }; return }
    val enEdicion = anotando?.let { id -> sesiones.firstOrNull { it.id == id } }
    if (enEdicion != null) {
        AnotarSesion(enEdicion, modo, paso) { descartar ->
            if (descartar) Datos.sesiones.cambiar { l -> l.filter { it.id != enEdicion.id } }
            else if (modo == "repaso") darPorRevisada(enEdicion.id)
            anotando = null
        }
        return
    }
    val leyendo = abierta?.let { id -> sesiones.firstOrNull { it.id == id } }
    if (leyendo != null) {
        SesionPantalla(leyendo, alVolver = { abierta = null }, alEditar = { m, p -> modo = m; paso = p; anotando = leyendo.id })
        return
    }
    diaDelResumen?.let { DiaDelResumen(it) { diaDelResumen = null }; return }
    diaSinFrases?.let { DiaSinFrasesPantalla(it) { diaSinFrases = null }; return }
    val adentro = parte
    if (adentro == "ficha") { FichaPantalla { parte = null }; return }
    if (adentro == null) {
        Portada(sesiones) {
            // «Mi resumen» abre siempre en el mes de hoy, que es el que dice la tarjeta.
            if (it == "resumen") mesResumen = DiaLogico.hoy().substring(0, 7)
            parte = it
        }
        return
    }
    Lista(sesiones, adentro, mesResumen, alVolver = { parte = null }, alCambiarMes = { mesResumen = it },
          alExportar = { exportando = true }, alAbrir = { abierta = it }, alNueva = {
        val nueva = SesionDeTerapia(UUID.randomUUID().toString(), (sesiones.maxOfOrNull { it.numero } ?: 0) + 1, LocalDate.now().toString())
        Datos.sesiones.cambiar { it + nueva }
        modo = "nueva"; paso = 0; anotando = nueva.id
    }, alAbrirDia = { diaDelResumen = it }, alAbrirSinFrases = { diaSinFrases = it })
}

/** Queda como suya. Si es de una consulta, el servidor se entera: deja de preguntar y borra el borrador. */
private fun darPorRevisada(id: String) {
    val s = Datos.sesiones.valor.firstOrNull { it.id == id } ?: return
    Datos.sesiones.cambiar { l -> l.map { if (it.id == id) it.copy(revisada = true) else it } }
    s.eventoId?.let { Datos.alcance.launch { Agenda.evaluada(it) } }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Lista(sesiones: List<SesionDeTerapia>, parte: String, mesResumen: String, alVolver: () -> Unit,
                  alCambiarMes: (String) -> Unit, alExportar: () -> Unit, alAbrir: (String) -> Unit, alNueva: () -> Unit,
                  alAbrirDia: (NotaDelDia) -> Unit, alAbrirSinFrases: (DiaSinFrases) -> Unit) {
    val p = LocalPaleta.current
    BackHandler(onBack = alVolver)
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = alVolver) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver a Mi espacio", tint = p.tintaSuave) }
            Text(if (parte == "consultas") "Consultas" else "Mi resumen", Modifier.weight(1f), textAlign = TextAlign.Center,
                 fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            // El «+» es de las consultas. En «Mi resumen» el PDF tiene su botón
            // ancho abajo (04/10/2026), en vez del ícono de compartir de acá.
            if (parte == "consultas") IconButton(onClick = alNueva) { Icon(Icons.Outlined.Add, "Anotar una sesión nueva", tint = p.tintaSuave) }
            else Spacer(Modifier.size(48.dp))
        }
        if (parte == "resumen") { MiResumen(mesResumen, alCambiarMes, alExportar, alAbrirDia, alAbrirSinFrases); return@Column }
        if (sesiones.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Lo que te llevas de cada sesión", fontWeight = FontWeight.SemiBold, fontSize = 19.sp, textAlign = TextAlign.Center)
                Text("Después de una sesión con tu terapeuta, anota qué entendiste, qué aprendiste, cómo te sentiste, " +
                     "los temas que se trataron y en qué sentiste que avanzaste. Si hablas de la sesión con Bitácora, te la deja armada para revisar.",
                     color = p.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.padding(vertical = 12.dp))
                Button(alNueva, colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo)) { Text("Anotar mi primera sesión") }
            }
            return@Column
        }
        // ORDENADA desde la noche del 04/10/2026 (la propuesta A que eligió
        // Dusan): arriba lo que está para revisar, con de dónde salió; abajo las
        // demás por mes, un renglón cada una. Antes, tarjetas altas e iguales.
        val ordenadas = sesiones.sortedWith(compareByDescending<SesionDeTerapia> { it.fecha }.thenByDescending { it.numero })
        val porMes = ordenadas.filter { it.revisada }.groupBy { it.fecha.substring(0, 7) }
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(ordenadas.filter { !it.revisada }, key = { "r" + it.id }) { s -> ParaRevisar(s) { alAbrir(s.id) } }
            porMes.forEach { (mes, lista) ->
                item(key = "m$mes") { Rotulo(tituloDelMes(mes)) }
                item(key = "g$mes") {
                    Carta(Modifier.fillMaxWidth(), radio = 18.dp) {
                        lista.forEachIndexed { i, s ->
                            if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(p.cartaBorde))
                            FilaDeSesion(s) { alAbrir(s.id) }
                        }
                    }
                }
            }
        }
    }
}

/**
 * La portada: las dos partes lado a lado, como `Portada` en `EvaluacionesView.swift`.
 * Cada tarjeta dice lo justo para saber qué hay adentro: cuántas sesiones hay, y
 * de qué mes es el resumen. Las que llegaron armadas y faltan revisar se cuentan
 * en un círculo dorado sobre el sillón: es lo único que pide algo de la persona.
 */
@Composable
private fun Portada(sesiones: List<SesionDeTerapia>, alElegir: (String) -> Unit) {
    val cuantas = when (sesiones.size) {
        0 -> "Ninguna todavía"
        1 -> "1 sesión"
        else -> "${sesiones.size} sesiones"
    }
    val mes = Resumen.meses[DiaLogico.hoy().substring(5, 7).toInt() - 1].replaceFirstChar { it.uppercase() }
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.size(48.dp))
            Text("Mi espacio", Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Spacer(Modifier.size(48.dp))
        }
        ProximaConsulta()
        // Las dos del mismo alto aunque una tenga una línea más.
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Entrada(Sillon, "Consultas", cuantas, sesiones.count { !it.revisada }, Modifier.weight(1f).fillMaxHeight()) { alElegir("consultas") }
            Entrada(Libro, "Mi resumen", mes, 0, Modifier.weight(1f).fillMaxHeight()) { alElegir("resumen") }
        }
        // La ficha viva (27/10/2026), sólo en los diarios que la tienen. El
        // círculo pide leer el aviso, que es lo único que espera algo.
        val ficha = fichaDeLaPortada()
        if (ficha?.activa == true) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)) {
                Entrada(Icons.Outlined.FormatQuote, "Lo que Bitácora sabe de ti",
                        if (ficha.avisada) "Con tus palabras" else "Léelo antes de que se arme",
                        if (ficha.avisada) 0 else 1, Modifier.fillMaxWidth()) { alElegir("ficha") }
            }
        }
        // El ID de la cuenta, para anotarlo (28/10/2026).
        Datos.config.cuentaId?.let {
            Text("Tu ID: $it", color = LocalPaleta.current.tintaTenue, fontSize = 13.sp,
                 fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                 textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 14.dp))
        }
    }
}

/**
 * Arriba de todo en Mi expediente: la próxima consulta, o cómo agendarla. Es
 * `ProximaConsulta` de `EvaluacionesView.swift`.
 *
 * Desde el 06/10/2026: Dusan eligió la propuesta B («la próxima consulta
 * arriba») y de ella sólo estos dos estados. Sin consulta, un botón que lleva al
 * calendario con la hoja de consulta nueva abierta; con consulta, cuándo es y
 * «Preparar», que abre el chat con Bitácora en el modo de antes de la consulta.
 * Tocar la tarjeta lleva a ese día del calendario. Cuenta sólo una consulta
 * confirmada: una que propuso Bitácora se confirma en el calendario.
 */
@Composable
private fun ProximaConsulta() {
    val p = LocalPaleta.current
    val eventos by Datos.eventos.todo.collectAsState()
    val proxima = Evento.proximaConsulta(eventos, Navegacion.ahora())
    val boton = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo)
    if (proxima != null) {
        Carta(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
            .clip(RoundedCornerShape(22.dp)).clickable { Navegacion.verEnElCalendario(proxima.dia) }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Sillon, null, tint = p.musgo, modifier = Modifier.size(26.dp))
                Column(Modifier.weight(1f).padding(horizontal = 14.dp)) {
                    Text("Próxima consulta", color = p.tintaTenue, fontSize = 12.sp)
                    Text(Navegacion.cuando(proxima), fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    Text(Evento.cuantoFalta(proxima.dia, DiaLogico.hoy()), color = p.tintaSuave, fontSize = 12.sp)
                }
                Button(onClick = { Navegacion.preparar(proxima) }, colors = boton) {
                    Text("Preparar", fontWeight = FontWeight.SemiBold)
                }
            }
        }
    } else {
        // Con el borde punteado: es un lugar que espera algo, no una tarjeta llena.
        val borde = p.cartaBorde
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)
                .drawBehind {
                    drawRoundRect(borde, cornerRadius = CornerRadius(22.dp.toPx()),
                        style = Stroke(1.2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))))
                }
                .padding(vertical = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(Sillon, null, tint = p.musgo, modifier = Modifier.size(28.dp))
            Text("Sin consulta agendada", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.padding(top = 8.dp))
            Text("Cuando tengas una, anótala aquí", color = p.tintaSuave, fontSize = 13.sp, modifier = Modifier.padding(top = 2.dp))
            Button(onClick = { Navegacion.agendarConsulta() }, colors = boton, modifier = Modifier.padding(top = 12.dp)) {
                Icon(Icons.Default.Add, null, modifier = Modifier.size(18.dp))
                Text("  Agendar consulta", fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun Entrada(dibujo: ImageVector, titulo: String, detalle: String, aviso: Int, modifier: Modifier, alTocar: () -> Unit) {
    val p = LocalPaleta.current
    Carta(modifier.clip(RoundedCornerShape(22.dp)).clickable(onClick = alTocar)) {
        Column(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box {
                Box(Modifier.size(60.dp).background(p.musgo.copy(alpha = 0.14f), CircleShape), contentAlignment = Alignment.Center) {
                    Icon(dibujo, null, tint = p.musgo, modifier = Modifier.size(30.dp))
                }
                if (aviso > 0) Box(
                    Modifier.align(Alignment.TopEnd).offset(x = 5.dp, y = (-3).dp).height(20.dp).widthIn(min = 20.dp)
                        .background(p.bitacora, RoundedCornerShape(10.dp)).padding(horizontal = 5.dp)
                        .semantics { contentDescription = "$aviso para revisar" },
                    contentAlignment = Alignment.Center,
                ) { Text("$aviso", color = p.fondo, fontSize = 11.sp, fontWeight = FontWeight.Bold) }
            }
            Text(titulo, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.padding(top = 12.dp))
            Text(detalle, color = p.tintaTenue, fontSize = 12.sp, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

@Composable
private fun fichaDeLaPortada(): Ficha? {
    var f by remember { mutableStateOf<Ficha?>(null) }
    LaunchedEffect(Unit) { f = Datos.cliente().ficha() }
    return f
}

/** «septiembre», o «septiembre de 2025» si no es de este año. */
private fun tituloDelMes(mes: String): String {
    val ym = YearMonth.parse(mes)
    val nombre = Resumen.meses[ym.monthValue - 1]
    return if (ym.year == LocalDate.now().year) nombre else "$nombre de ${ym.year}"
}

/** «jueves 8 de octubre». */
private fun diaLargo(dia: String): String {
    val f = LocalDate.parse(dia)
    return "${f.dayOfWeek.getDisplayName(TextStyle.FULL, es)} ${f.dayOfMonth} de ${f.month.getDisplayName(TextStyle.FULL, es)}"
}

/** «jue 24 sep». */
private fun diaCorto(dia: String): String {
    val f = LocalDate.parse(dia)
    return "${f.dayOfWeek.getDisplayName(TextStyle.FULL, es).take(3)} ${f.dayOfMonth} ${f.month.getDisplayName(TextStyle.FULL, es).take(3)}"
}

/** Una sesión que armó Bitácora y falta mirar: qué es, de dónde salió y qué hacer. */
@Composable
private fun ParaRevisar(s: SesionDeTerapia, alTocar: () -> Unit) {
    val p = LocalPaleta.current
    Carta(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).clickable(onClick = alTocar), radio = 20.dp,
          fondo = p.bitacora.copy(alpha = 0.10f), borde = p.bitacora.copy(alpha = 0.4f)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Sesión ${s.numero} · ${diaLargo(s.fecha)}", fontWeight = FontWeight.SemiBold, fontSize = 16.sp, modifier = Modifier.weight(1f))
            Text("Para revisar", color = p.bitacora, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }
        Text("Bitácora la armó con lo que le contaste después de la consulta. Mírala y cámbiala si hace falta.",
             color = p.tintaSuave, fontSize = 14.sp, modifier = Modifier.padding(vertical = 8.dp))
        Text("Revisar", color = p.fondo, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
             modifier = Modifier.background(p.bitacora, RoundedCornerShape(16.dp)).padding(horizontal = 16.dp, vertical = 6.dp))
    }
}

/** Un renglón: el número, el día y lo primero que se escribió, con su rótulo. */
@Composable
private fun FilaDeSesion(s: SesionDeTerapia, alTocar: () -> Unit) {
    val p = LocalPaleta.current
    val adelanto = listOf("Entendí" to s.entendi, "Me aportó" to s.aporte, "Me sentí" to s.sentir, "Avancé" to s.avance)
        .firstOrNull { it.second.isNotBlank() }
    Row(Modifier.fillMaxWidth().clickable(onClick = alTocar).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text("Sesión ${s.numero}", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                Text("  ${diaCorto(s.fecha)}", color = p.tintaTenue, fontSize = 12.sp, modifier = Modifier.padding(bottom = 2.dp))
            }
            adelanto?.let {
                Text("${it.first}: ${it.second.trim()}", color = p.tintaSuave, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = p.tintaTenue)
    }
}

@Composable
private fun Etiqueta(t: String) {
    val p = LocalPaleta.current
    Text(t, color = p.musgo, fontSize = 13.sp, fontWeight = FontWeight.Medium,
         modifier = Modifier.background(p.musgo.copy(alpha = 0.14f), RoundedCornerShape(14.dp)).padding(horizontal = 10.dp, vertical = 5.dp))
}

/** Los pasos, en el orden de Dusan, con «cómo te sentiste» desde el 03/10/2026. */
private enum class Paso(val pregunta: String, val ayuda: String, val rotulo: String) {
    NUMERO("¿Qué sesión fue?", "El número de la sesión con tu terapeuta.", "Sesión"),
    FECHA("¿Qué día fue?", "La fecha de la sesión, no la de hoy si la anotas después.", "Fecha"),
    ENTENDI("¿Qué entendiste de la sesión?", "Lo que te quedó claro, con tus palabras.", "Qué entendí de la sesión"),
    APORTE("¿Qué te aportó o qué aprendiste?", "Algo que no sabías, o que ahora ves distinto.", "Qué me aportó o qué aprendí"),
    SENTIR("¿Cómo te sentiste?", "En la sesión, o al salir de ella.", "Cómo me sentí"),
    TEMAS("¿Qué temas se trataron?", "Los puntos clave, de a uno. Puedes escribir varios separados por coma.", "Temas que se trataron"),
    AVANCE("¿En qué sentiste que avanzaste?", "Aunque sea un paso chico.", "En qué sentí que avancé"),
}

/** Una sesión ya anotada se lee como una nota, no como un formulario. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SesionPantalla(s: SesionDeTerapia, alVolver: () -> Unit, alEditar: (String, Int) -> Unit) {
    val p = LocalPaleta.current
    var borrar by remember { mutableStateOf(false) }
    BackHandler(onBack = alVolver)
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = alVolver) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver", tint = p.tintaSuave) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 40.dp)) {
            Text("Sesión ${s.numero}", fontSize = 32.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { alEditar("solo", Paso.NUMERO.ordinal) })
            Text(fechaEscrita(s.fecha), color = p.musgoSuave, modifier = Modifier.clickable { alEditar("solo", Paso.FECHA.ordinal) }.padding(bottom = 10.dp))
            if (!s.revisada) Carta(Modifier.fillMaxWidth().padding(bottom = 10.dp), fondo = p.bitacora.copy(alpha = 0.10f), borde = p.bitacora.copy(alpha = 0.4f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.AutoAwesome, null, tint = p.bitacora, modifier = Modifier.size(14.dp))
                    Text("  Para revisar", color = p.bitacora, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                }
                Text("La armó Bitácora con lo que contaste después de la consulta. Corrige lo que no esté bien y completa lo que falte.",
                     modifier = Modifier.padding(vertical = 8.dp))
                Button({ darPorRevisada(s.id) }, colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo)) { Text("Está bien así") }
            }
            // Cada parte con su ícono y su pregunta, y los dos botones con su
            // nombre (04/10/2026, la propuesta A): antes, rótulos en mayúsculas
            // iguales y un lápiz y una papelera arriba, sin decir qué hacían.
            Parte(Icons.Outlined.Lightbulb, "¿Qué entendiste?", s.entendi) { alEditar("solo", Paso.ENTENDI.ordinal) }
            Parte(Icons.Outlined.Spa, "¿Qué te aportó o qué aprendiste?", s.aporte) { alEditar("solo", Paso.APORTE.ordinal) }
            Parte(Icons.Outlined.FavoriteBorder, "¿Cómo te sentiste?", s.sentir) { alEditar("solo", Paso.SENTIR.ordinal) }
            Parte(Icons.AutoMirrored.Outlined.TrendingUp, "¿En qué avanzaste?", s.avance) { alEditar("solo", Paso.AVANCE.ordinal) }
            Column(Modifier.fillMaxWidth().clickable { alEditar("solo", Paso.TEMAS.ordinal) }.padding(vertical = 10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Circulo(Icons.Outlined.LocalOffer)
                    Text("¿Qué temas se trataron?", color = p.tintaTenue, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                         modifier = Modifier.padding(start = 12.dp))
                }
                if (s.temas.isEmpty()) Text("+ Anotar", color = p.musgoSuave, modifier = Modifier.padding(start = 44.dp, top = 6.dp))
                else FlowRow(Modifier.padding(start = 44.dp, top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    s.temas.forEach { Etiqueta(it) }
                }
            }
            Row(Modifier.padding(top = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton({ alEditar("repaso", 0) }) {
                    Icon(Icons.Outlined.Edit, null, tint = p.tinta, modifier = Modifier.size(18.dp))
                    Text("  Repasar todo", color = p.tinta)
                }
                OutlinedButton({ borrar = true }) {
                    Icon(Icons.Outlined.Delete, null, tint = p.rojo, modifier = Modifier.size(18.dp))
                    Text("  Eliminar", color = p.rojo)
                }
            }
        }
    }
    if (borrar) AlertDialog(
        onDismissRequest = { borrar = false },
        title = { Text("¿Eliminar la sesión ${s.numero}?") },
        text = { Text("Se borra lo que anotaste de esta sesión. No se puede deshacer.") },
        confirmButton = { TextButton({ borrar = false; Datos.sesiones.cambiar { l -> l.filter { it.id != s.id } }; alVolver() }) { Text("Eliminar", color = p.rojo) } },
        dismissButton = { TextButton({ borrar = false }) { Text("Cancelar") } },
    )
}

@Composable
private fun Parte(icono: ImageVector, pregunta: String, texto: String, alTocar: () -> Unit) {
    val p = LocalPaleta.current
    Row(Modifier.fillMaxWidth().clickable(onClick = alTocar).padding(vertical = 10.dp), verticalAlignment = Alignment.Top) {
        Circulo(icono)
        Column(Modifier.padding(start = 12.dp)) {
            Text(pregunta, color = p.tintaTenue, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            if (texto.isBlank()) Text("+ Anotar", color = p.musgoSuave, modifier = Modifier.padding(top = 4.dp))
            else Text(texto.trim(), fontSize = 17.sp, lineHeight = 24.sp, modifier = Modifier.padding(top = 4.dp))
        }
    }
}

@Composable
private fun Circulo(icono: ImageVector) {
    val p = LocalPaleta.current
    Box(Modifier.size(32.dp).background(p.musgo.copy(alpha = 0.14f), CircleShape), contentAlignment = Alignment.Center) {
        Icon(icono, null, tint = p.musgo, modifier = Modifier.size(17.dp))
    }
}

/**
 * Anotar una sesión de a una cosa por vez: la pregunta grande arriba y debajo
 * lo único que hay que hacer. Ningún paso es obligatorio, y lo escrito queda
 * guardado mientras se escribe. `modo`: nueva, repaso, o solo (un paso).
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun AnotarSesion(s: SesionDeTerapia, modo: String, desde: Int, alCerrar: (descartar: Boolean) -> Unit) {
    val p = LocalPaleta.current
    var paso by rememberSaveable { mutableStateOf(desde) }
    var confirmarDescarte by remember { mutableStateOf(false) }
    var temaNuevo by rememberSaveable { mutableStateOf("") }
    val actual = Paso.entries[paso]
    val soloUno = modo == "solo"

    fun guardar(f: (SesionDeTerapia) -> SesionDeTerapia) = Datos.sesiones.cambiar { l -> l.map { if (it.id == s.id) f(it) else it } }
    fun agregarTemas() {
        val nuevos = temaNuevo.split(',', ';', '\n').map { it.trim() }.filter { it.isNotEmpty() }
        if (nuevos.isNotEmpty()) guardar { x -> x.copy(temas = x.temas + nuevos.filter { n -> x.temas.none { it.equals(n, true) } }) }
        temaNuevo = ""
    }
    fun salir() {
        agregarTemas()
        val ahora = Datos.sesiones.valor.firstOrNull { it.id == s.id }
        if (modo == "nueva" && ahora?.hayAlgoEscrito == true) confirmarDescarte = true
        else alCerrar(modo == "nueva")
    }
    BackHandler(onBack = ::salir)

    Column(Modifier.fillMaxSize().statusBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = ::salir) { Icon(Icons.Outlined.Close, if (modo == "nueva") "Salir sin guardar" else "Cerrar", tint = p.tintaSuave) }
            if (!soloUno) Text("Paso ${paso + 1} de ${Paso.entries.size}", Modifier.weight(1f), textAlign = TextAlign.Center, color = p.tintaTenue, fontSize = 13.sp)
            Spacer(Modifier.size(48.dp))
        }
        if (!soloUno) Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Paso.entries.forEach { Box(Modifier.weight(1f).height(4.dp).background(if (it.ordinal <= paso) p.musgo else p.cartaBorde, RoundedCornerShape(2.dp))) }
        }
        Column(Modifier.weight(1f).padding(horizontal = 24.dp).padding(top = 28.dp)) {
            Text(actual.pregunta, fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
            Text(actual.ayuda, color = p.tintaSuave, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp))
            val ahora = Datos.sesiones.todo.collectAsState().value.firstOrNull { it.id == s.id } ?: s
            when (actual) {
                Paso.NUMERO -> Row(Modifier.fillMaxWidth().padding(top = 30.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    OutlinedButton({ guardar { it.copy(numero = maxOf(1, it.numero - 1)) } }) { Text("−", fontSize = 22.sp) }
                    Text("${ahora.numero}", fontSize = 72.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 28.dp))
                    OutlinedButton({ guardar { it.copy(numero = minOf(999, it.numero + 1)) } }) { Text("+", fontSize = 22.sp) }
                }
                Paso.FECHA -> {
                    val estado = rememberDatePickerState(LocalDate.parse(ahora.fecha).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli())
                    LaunchedEffect(estado.selectedDateMillis) {
                        estado.selectedDateMillis?.let { ms ->
                            val d = Instant.ofEpochMilli(ms).atZone(ZoneOffset.UTC).toLocalDate().toString()
                            if (d != ahora.fecha) guardar { it.copy(fecha = d) }
                        }
                    }
                    DatePicker(estado, title = null, headline = null, showModeToggle = false)
                }
                Paso.TEMAS -> Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CampoLargo(temaNuevo, "Un tema", Modifier.weight(1f), lineas = 1) { temaNuevo = it }
                        IconButton(::agregarTemas) { Icon(Icons.Outlined.Add, "Agregar el tema", tint = p.musgo) }
                    }
                    FlowRow(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ahora.temas.forEach { t ->
                            Text("$t  ×", color = p.musgo, fontSize = 14.sp,
                                 modifier = Modifier.background(p.musgo.copy(alpha = 0.14f), RoundedCornerShape(16.dp))
                                     .clickable { guardar { x -> x.copy(temas = x.temas - t) } }.padding(horizontal = 12.dp, vertical = 8.dp))
                        }
                    }
                }
                else -> {
                    val valor = when (actual) { Paso.ENTENDI -> ahora.entendi; Paso.APORTE -> ahora.aporte; Paso.SENTIR -> ahora.sentir; else -> ahora.avance }
                    CampoLargo(valor, "Escribe todo lo que quieras…", Modifier.fillMaxWidth().weight(1f).padding(bottom = 12.dp)) { v ->
                        guardar {
                            when (actual) {
                                Paso.ENTENDI -> it.copy(entendi = v); Paso.APORTE -> it.copy(aporte = v)
                                Paso.SENTIR -> it.copy(sentir = v); else -> it.copy(avance = v)
                            }
                        }
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            if (!soloUno && paso > 0) OutlinedButton({ agregarTemas(); paso-- }) { Text("Atrás", color = p.tinta) }
            Spacer(Modifier.weight(1f))
            val ultimo = paso == Paso.entries.lastIndex
            Button({
                agregarTemas()
                if (soloUno || ultimo) alCerrar(false) else paso++
            }, colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo)) {
                Text(if (soloUno) "Listo" else if (ultimo) "Guardar" else "Siguiente")
            }
        }
    }
    if (confirmarDescarte) AlertDialog(
        onDismissRequest = { confirmarDescarte = false },
        title = { Text("¿Salir sin guardar esta sesión?") },
        text = { Text("Se pierde lo que anotaste hasta acá.") },
        confirmButton = { TextButton({ confirmarDescarte = false; alCerrar(true) }) { Text("Descartar la sesión", color = p.rojo) } },
        dismissButton = { TextButton({ confirmarDescarte = false }) { Text("Seguir anotando") } },
    )
}

@Composable
private fun CampoLargo(valor: String, marca: String, modifier: Modifier, lineas: Int = Int.MAX_VALUE, alCambiar: (String) -> Unit) {
    val p = LocalPaleta.current
    TextField(
        value = valor, onValueChange = alCambiar, modifier = modifier,
        placeholder = { Text(marca, color = p.tintaTenue) }, maxLines = lineas, singleLine = lineas == 1,
        shape = RoundedCornerShape(20.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = p.carta, unfocusedContainerColor = p.carta,
            focusedIndicatorColor = p.carta, unfocusedIndicatorColor = p.carta, cursorColor = p.musgo,
        ),
    )
}

/**
 * «Mi resumen»: lo que dijo, en sus palabras, para llevar a terapia (`GET /notas`).
 * Es `NotasView.swift`. Va de a un mes, del día 1 al último.
 *
 * Desde la noche del 04/10/2026 es un ÍNDICE: arriba cuántos días y frases tuvo
 * el mes, abajo una fila por día con el comienzo de lo que pasó, y al tocarla el
 * día solo (`DiaDelResumen`). Antes eran tarjetas largas con todo mezclado, y
 * Dusan sintió que quien la abriera se iba a perder. La aclaración (no es un
 * informe ni un diagnóstico) quedó en una línea, con el texto entero detrás de ⓘ.
 */
@Composable
private fun MiResumen(mes: String, alCambiarMes: (String) -> Unit, alExportar: () -> Unit, alAbrirDia: (NotaDelDia) -> Unit,
                      alAbrirSinFrases: (DiaSinFrases) -> Unit) {
    val p = LocalPaleta.current
    val entradas by Datos.entradas.todo.collectAsState()
    val ym = YearMonth.parse(mes)
    var notas by remember(mes) { mutableStateOf<List<NotaDelDia>?>(null) }
    var sinServidor by remember(mes) { mutableStateOf(false) }
    var intento by remember { mutableStateOf(0) }
    var verAclaracion by remember { mutableStateOf(false) }
    LaunchedEffect(mes, intento) {
        val (desde, hasta) = Resumen.mes(mes)
        val r = if (Datos.config.configurada) Datos.cliente().notas(desde, hasta) else emptyList()
        sinServidor = r == null
        notas = r?.let(Resumen::enOrden)
    }
    val nombreDelMes = Resumen.meses[ym.monthValue - 1].replaceFirstChar { it.uppercase() }
    Column(Modifier.fillMaxSize()) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { alCambiarMes(ym.minusMonths(1).toString()) }) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Mes anterior", tint = p.tintaSuave)
        }
        Text("$nombreDelMes ${ym.year}", Modifier.weight(1f), textAlign = TextAlign.Center,
             fontWeight = FontWeight.Bold, fontSize = 20.sp)
        IconButton(onClick = { alCambiarMes(ym.plusMonths(1).toString()) }) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Mes siguiente", tint = p.tintaSuave)
        }
    }
    Row(Modifier.fillMaxWidth().clickable { verAclaracion = true }.padding(bottom = 6.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        Text("Tus frases, tal como las dijiste · no es un informe  ", color = p.tintaTenue, fontSize = 12.sp)
        Icon(Icons.Outlined.Info, "Qué es Mi resumen", tint = p.tintaSuave, modifier = Modifier.size(16.dp))
    }
    val lista = notas
    Box(Modifier.weight(1f).fillMaxWidth()) { when {
        sinServidor -> Column(Modifier.padding(24.dp)) {
            Text("No se pudo conectar con el servidor. Lo que dijiste sigue guardado; prueba de nuevo en un rato.", color = p.tintaSuave)
            TextButton({ intento++ }) { Text("Probar de nuevo", color = p.musgo) }
        }
        lista == null -> Text("Buscando…", color = p.tintaTenue, modifier = Modifier.padding(24.dp))
        diasSinFrases(entradas, mes, lista).let { sin -> lista.isEmpty() && sin.isEmpty() } ->
            Text("Nada en ${Resumen.meses[ym.monthValue - 1]}. Las notas se escriben solas al terminar cada día.",
                 color = p.tintaSuave, modifier = Modifier.padding(24.dp))
        else -> LazyColumn(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val sin = diasSinFrases(entradas, mes, lista)
            // Del 1 al último: las notas y los días con charla sin frases, juntos.
            val renglones: List<Any> = (lista.map { it.dia to it.hora to (it as Any) } +
                sin.map { it.dia to (it.charlas.firstOrNull()?.hora ?: "") to (it as Any) })
                .sortedWith(compareBy({ it.first.first }, { it.first.second })).map { it.second }
            item {
                val dias = (lista.map { it.dia } + sin.map { it.dia }).toSet().size
                val frases = lista.sumOf { it.citas.size }
                Carta(Modifier.fillMaxWidth(), radio = 18.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(nombreDelMes, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                            Text("$dias ${if (dias == 1) "día" else "días"}" +
                                 (if (frases > 0) " · $frases ${if (frases == 1) "frase" else "frases"}" else ""),
                                 color = p.tintaSuave, fontSize = 13.sp)
                        }
                        Icon(Libro, null, tint = p.musgo, modifier = Modifier.size(24.dp))
                    }
                }
            }
            item {
                Carta(Modifier.fillMaxWidth(), radio = 18.dp) {
                    renglones.forEachIndexed { i, r ->
                        if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(p.cartaBorde))
                        when (r) {
                            is NotaDelDia -> FilaDelDia(r) { alAbrirDia(r) }
                            is DiaSinFrases -> FilaSinFrases(r) { alAbrirSinFrases(r) }
                        }
                    }
                }
            }
        }
    } }
    // El PDF, a la vista y con su nombre (04/10/2026): antes era el ícono de
    // compartir arriba, que no decía qué hacía.
    Button(alExportar, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp).height(52.dp),
           colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo)) {
        Icon(Icons.Outlined.Description, null, modifier = Modifier.size(20.dp))
        Text("  Armar el PDF para tu psicólogo", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    }
    }
    if (verAclaracion) AlertDialog(
        onDismissRequest = { verAclaracion = false },
        confirmButton = { TextButton({ verAclaracion = false }) { Text("Entendido", color = p.musgo) } },
        text = {
            Text("Esto son tus propias frases, tal como las dijiste, y un resumen corto de cada día que escribe Bitácora. " +
                 "No es un informe ni un diagnóstico: es material para que lo lleves y lo trabajen ustedes.", color = p.tinta)
        },
    )
}

/** Una charla de un día sin frases: su hora y lo que dijo la persona, turno por turno. */
data class CharlaDelDia(val hora: String, val dicho: List<String>)

/** Un día con charla pero sin frases separadas (hoy, que no se cerró, o uno del que no salieron). */
data class DiaSinFrases(val dia: String, val charlas: List<CharlaDelDia>)

/**
 * Los días del mes con charla en el teléfono y sin frases del servidor. Desde la
 * noche del 04/10/2026 Mi resumen los muestra igual (lo pidió Dusan): el
 * psicólogo tiene una idea del mes entero, y qué días van al PDF lo elige la
 * persona. Es lo mismo que lleva el PDF de un día así.
 */
private fun diasSinFrases(entradas: List<EntradaLocal>, mes: String, notas: List<NotaDelDia>): List<DiaSinFrases> {
    val conFrases = notas.map { it.dia }.toSet()
    return entradas.filter { it.dia.startsWith(mes) && it.dia !in conFrases }
        .groupBy { it.dia }
        .mapNotNull { (dia, del) ->
            val charlas = del.sortedBy { it.creadoLocal }
                .map { CharlaDelDia(it.creadoLocal.substring(11, 16), Transcripcion.loQueDijo(it.transcripcion)) }
                .filter { it.dicho.isNotEmpty() }
            if (charlas.isEmpty()) null else DiaSinFrases(dia, charlas)
        }
}

/** Un día con charla y sin frases: lo primero que dijo y por qué todavía no hay frases. */
@Composable
private fun FilaSinFrases(d: DiaSinFrases, alTocar: () -> Unit) {
    val p = LocalPaleta.current
    val porQue = if (d.dia == DiaLogico.hoy()) "las frases llegan al cerrar el día" else "sin frases separadas"
    Row(Modifier.fillMaxWidth().clickable(onClick = alTocar).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.width(40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(d.dia.takeLast(2).trimStart('0'), fontWeight = FontWeight.SemiBold, fontSize = 19.sp)
            Text(Resumen.fechaConDia(d.dia).take(3).lowercase(), color = p.tintaTenue, fontSize = 11.sp)
        }
        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
            Text("«${d.charlas.firstOrNull()?.dicho?.firstOrNull().orEmpty()}»", maxLines = 2, overflow = TextOverflow.Ellipsis,
                 fontSize = 15.sp, lineHeight = 20.sp)
            Text("${d.charlas.size} ${if (d.charlas.size == 1) "charla" else "charlas"} · $porQue", color = p.tintaTenue, fontSize = 12.sp)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = p.tintaTenue)
    }
}

/** Un día sin frases, abierto: lo que dijo la persona en la charla, textual, con la barra de las citas. */
@Composable
private fun DiaSinFrasesPantalla(d: DiaSinFrases, alVolver: () -> Unit) {
    val p = LocalPaleta.current
    BackHandler(onBack = alVolver)
    val esHoy = d.dia == DiaLogico.hoy()
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = alVolver) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver al mes", tint = p.tintaSuave) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 32.dp)) {
            Text(Resumen.fechaConDia(d.dia), fontSize = 26.sp, lineHeight = 32.sp, fontWeight = FontWeight.Bold)
            Carta(Modifier.fillMaxWidth().padding(top = 14.dp), fondo = p.musgo.copy(alpha = 0.10f)) {
                Text(if (esHoy) "Este día todavía no terminó: el resumen y las frases se arman al cerrarse, a las 4 de la mañana. Mientras tanto, esto es lo que dijiste."
                     else "Ese día no se separaron frases. Esto es lo que dijiste en la charla, textual.",
                     color = p.tintaSuave, fontSize = 13.sp)
            }
            Row(Modifier.padding(top = 22.dp, bottom = 8.dp)) {
                Text("EN TUS PALABRAS", color = p.tintaTenue, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp)
                Text(" · de la charla, textual", color = p.tintaTenue, fontSize = 11.sp)
            }
            d.charlas.forEach { c ->
                if (d.charlas.size > 1) Text(c.hora, color = p.musgo, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                                             modifier = Modifier.padding(vertical = 6.dp))
                c.dicho.forEach { texto ->
                    Row(Modifier.padding(bottom = 12.dp).height(IntrinsicSize.Min)) {
                        Box(Modifier.width(3.dp).fillMaxHeight().background(p.musgo.copy(alpha = 0.5f)))
                        Text("«$texto»", fontSize = 16.sp, lineHeight = 22.sp, modifier = Modifier.padding(start = 10.dp))
                    }
                }
            }
        }
    }
}

/** Un día en el índice: el número, el día de la semana, el comienzo de lo que pasó y cuántas frases tiene. */
@Composable
private fun FilaDelDia(n: NotaDelDia, alTocar: () -> Unit) {
    val p = LocalPaleta.current
    val adelanto = n.contexto?.takeIf { it.isNotBlank() } ?: n.citas.firstOrNull()?.let { "«${it.texto}»" }.orEmpty()
    Row(Modifier.fillMaxWidth().clickable(onClick = alTocar).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.width(40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(n.dia.takeLast(2).trimStart('0'), fontWeight = FontWeight.SemiBold, fontSize = 19.sp)
            Text(Resumen.fechaConDia(n.dia).take(3).lowercase(), color = p.tintaTenue, fontSize = 11.sp)
        }
        Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
            Text(adelanto, maxLines = 2, overflow = TextOverflow.Ellipsis, fontSize = 15.sp, lineHeight = 20.sp)
            Text("${n.hora} · ${n.citas.size} ${if (n.citas.size == 1) "frase" else "frases"}", color = p.tintaTenue, fontSize = 12.sp)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = p.tintaTenue)
    }
}

/**
 * Un día de «Mi resumen», solo: lo que pasó, tus palabras y los temas, en ese
 * orden y con un título cada parte. El contexto va primero porque así lo pidió
 * Dusan, con su autor a la vista: lo escribe Bitácora; las frases son tuyas y
 * textuales, con la barra al costado. Es `DiaDelResumenView` del iPhone.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DiaDelResumen(n: NotaDelDia, alVolver: () -> Unit) {
    val p = LocalPaleta.current
    BackHandler(onBack = alVolver)
    @Composable fun Titulo(texto: String, detalle: String? = null) {
        Row(Modifier.padding(top = 22.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(texto.uppercase(), color = p.tintaTenue, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp)
            if (detalle != null) Text(" · $detalle", color = p.tintaTenue, fontSize = 11.sp)
        }
    }
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = alVolver) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver al mes", tint = p.tintaSuave) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 32.dp)) {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(Resumen.fechaConDia(n.dia), fontSize = 26.sp, lineHeight = 32.sp, fontWeight = FontWeight.Bold,
                     modifier = Modifier.weight(1f, fill = false))
                Text("  ${n.hora}", color = p.tintaTenue, fontSize = 13.sp, modifier = Modifier.padding(bottom = 4.dp))
            }
            n.contexto?.takeIf { it.isNotBlank() }?.let {
                Titulo("Lo que pasó", "resumido por Bitácora")
                Text(it, fontSize = 17.sp, lineHeight = 25.sp)
            }
            if (n.citas.isNotEmpty()) {
                Titulo("En tus palabras")
                n.citas.forEach { c ->
                    Row(Modifier.padding(bottom = 12.dp).height(IntrinsicSize.Min)) {
                        Box(Modifier.width(3.dp).fillMaxHeight().background(p.musgo.copy(alpha = 0.5f)))
                        Column(Modifier.padding(start = 10.dp)) {
                            Text("«${c.texto}»", fontSize = 16.sp, lineHeight = 22.sp)
                            if (c.sobre.isNotBlank()) Text(c.sobre, color = p.tintaTenue, fontSize = 12.sp)
                        }
                    }
                }
            }
            if (n.temas.isNotEmpty()) {
                Titulo("Temas")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    n.temas.forEach { Etiqueta(it) }
                }
            }
        }
    }
}
