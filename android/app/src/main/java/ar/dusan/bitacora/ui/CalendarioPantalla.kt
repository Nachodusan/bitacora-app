package ar.dusan.bitacora.ui

import android.content.res.Configuration
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ar.dusan.bitacora.datos.Agenda
import ar.dusan.bitacora.datos.Apunte
import ar.dusan.bitacora.Navegacion
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.datos.EntradaLocal
import ar.dusan.bitacora.nucleo.DiaLogico
import ar.dusan.bitacora.nucleo.Evento
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneOffset
import java.time.format.TextStyle
import java.util.Locale
import ar.dusan.bitacora.nucleo.Transcripcion
import ar.dusan.bitacora.nucleo.Hablante
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.activity.compose.BackHandler

private val es = Locale.forLanguageTag("es")

/**
 * El calendario: cada día con sus charlas, sus notas y sus consultas. Es
 * `CalendarioView.swift`. Desde el 04/10/2026 cada cosa es un punto bajo el
 * número —musgo si hubo charla, celeste si hubo nota, verde azulado si hay
 * consulta (hueco si es una propuesta)— y el relleno queda para el día elegido;
 * antes las charlas pintaban la celda entera. Deslizar a los lados cambia de
 * mes y tocar el nombre del mes vuelve a hoy.
 */
@Composable
fun CalendarioPantalla() {
    val p = LocalPaleta.current
    val hoy = DiaLogico.hoy()
    var mes by rememberSaveable { mutableStateOf(hoy.substring(0, 7)) }
    var seleccionado by rememberSaveable { mutableStateOf(hoy) }
    var agregando by rememberSaveable { mutableStateOf(false) }
    var notaAbierta by rememberSaveable { mutableStateOf<String?>(null) }
    var charlaAbierta by rememberSaveable { mutableStateOf<String?>(null) }

    val entradas by Datos.entradas.todo.collectAsState()
    val apuntes by Datos.apuntes.todo.collectAsState()
    val eventos by Datos.eventos.todo.collectAsState()
    LaunchedEffect(Unit) { Agenda.actualizar() }
    // Lo que pidió Mi expediente desde la tarjeta de la próxima consulta: ver el
    // día de la consulta, o abrir la hoja de consulta nueva (en hoy; ahí se
    // elige el día). Se atiende una vez y se borra.
    LaunchedEffect(Navegacion.irAlDia, Navegacion.nuevaConsulta) {
        Navegacion.irAlDia?.let { dia ->
            Navegacion.irAlDia = null
            mes = dia.substring(0, 7)
            seleccionado = dia
        }
        if (Navegacion.nuevaConsulta) {
            Navegacion.nuevaConsulta = false
            mes = hoy.substring(0, 7)
            seleccionado = hoy
            agregando = true
        }
    }

    notaAbierta?.let { ApuntesPantalla(it) { notaAbierta = null }; return }
    charlaAbierta?.let { id ->
        entradas.firstOrNull { it.clientUuid == id }?.let { CharlaGuardada(it) { charlaAbierta = null }; return }
    }
    if (agregando) HojaDeEvento(seleccionado, null) { agregando = false }

    val porDia = entradas.groupBy { it.dia }
    val notasPorDia = apuntes.filter { it.texto.isNotBlank() }.groupBy { it.dia }
    val ym = YearMonth.parse(mes)

    Column(Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 16.dp)) {
        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.size(48.dp))
            Text("Calendario", Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            // Lo que dijo para llevar a terapia ya no se abre desde acá: desde el
            // 04/10/2026 es «Mi resumen», en «Mi expediente».
            // Agregar una consulta va acá arriba, como el «+» de Consultas. Hasta
            // el 04/10/2026 era un circulito verde azulado al lado del día, sin
            // nombre; Dusan eligió esto entre tres propuestas. La hoja abre en el
            // día elegido, y ahí se puede cambiar.
            IconButton(onClick = { agregando = true }) {
                Icon(Icons.Outlined.Add, "Agregar una consulta", tint = p.tintaSuave)
            }
        }
        Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { mes = ym.minusMonths(1).toString() }) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Mes anterior", tint = p.tintaSuave)
            }
            // Tocar el mes vuelve a hoy: después de mirar meses atrás, es la
            // manera de volver sin contar flechas.
            Text("${ym.month.getDisplayName(TextStyle.FULL_STANDALONE, es)} ${ym.year}",
                 Modifier.weight(1f).clickable { mes = hoy.substring(0, 7); seleccionado = hoy },
                 textAlign = TextAlign.Center, fontWeight = FontWeight.Bold, fontSize = 20.sp)
            IconButton(onClick = { mes = ym.plusMonths(1).toString() }) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Mes siguiente", tint = p.tintaSuave)
            }
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 6.dp)) {
            for (d in listOf("L", "M", "M", "J", "V", "S", "D")) {
                Text(d, Modifier.weight(1f), textAlign = TextAlign.Center, color = p.tintaTenue, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            }
        }
        // Lunes primero, como se lee un calendario en español.
        val vacios = ym.atDay(1).dayOfWeek.value - 1
        val celdas = List(vacios) { null } + (1..ym.lengthOfMonth()).map { ym.atDay(it).toString() }
        // Deslizar a los lados cambia de mes, como pasar una hoja.
        Column(Modifier.pointerInput(mes) {
            var dx = 0f
            detectHorizontalDragGestures(
                onDragStart = { dx = 0f },
                onDragEnd = { if (dx < -80f) mes = ym.plusMonths(1).toString() else if (dx > 80f) mes = ym.minusMonths(1).toString() },
            ) { _, d -> dx += d }
        }) {
            for (semana in celdas.chunked(7)) {
                Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (i in 0 until 7) {
                        val dia = semana.getOrNull(i)
                        if (dia == null) Spacer(Modifier.weight(1f))
                        else Celda(dia, porDia[dia].orEmpty().size, notasPorDia[dia].orEmpty().size,
                                   Agenda.marca(dia, eventos), dia == hoy, dia == seleccionado, Modifier.weight(1f)) { seleccionado = dia }
                    }
                }
            }
        }

        Detalle(seleccionado, hoy, porDia[seleccionado].orEmpty(), notasPorDia[seleccionado].orEmpty(),
                Agenda.delDia(seleccionado, eventos), alAbrirNota = { notaAbierta = it }, alAbrirCharla = { charlaAbierta = it })
    }
}

@Composable
private fun Celda(dia: String, charlas: Int, notas: Int, marca: Agenda.Marca, esHoy: Boolean, elegido: Boolean,
                  modifier: Modifier, alTocar: () -> Unit) {
    val p = LocalPaleta.current
    val fondo = if (elegido) p.musgo else androidx.compose.ui.graphics.Color.Transparent
    // Sobre el musgo del día elegido, los puntos van del color del papel.
    fun punto(c: androidx.compose.ui.graphics.Color) = if (elegido) p.fondo else c
    Column(
        modifier.height(46.dp).background(fondo, RoundedCornerShape(12.dp))
            .border(1.6.dp, if (esHoy && !elegido) p.bitacora else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(12.dp))
            .clickable(onClick = alTocar),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Text(dia.takeLast(2).trimStart('0'), color = if (elegido) p.fondo else p.tinta,
             fontWeight = if (esHoy || elegido) FontWeight.Bold else FontWeight.Medium, fontSize = 15.sp)
        Row(Modifier.height(8.dp).padding(top = 3.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            if (charlas > 0) Box(Modifier.size(5.dp).background(punto(p.musgo), CircleShape))
            if (notas > 0) Box(Modifier.size(5.dp).background(punto(p.nota), CircleShape))
            when (marca) {
                Agenda.Marca.CONFIRMADO -> Box(Modifier.size(5.dp).background(punto(p.verde), CircleShape))
                Agenda.Marca.PROPUESTO -> Box(Modifier.size(5.dp).border(1.dp, punto(p.verde), CircleShape))
                Agenda.Marca.NINGUNA -> {}
            }
        }
    }
}

/** Lo que pasó un día: primero lo previsto (las consultas), después lo que pasó, por hora. */
@Composable
private fun Detalle(dia: String, hoy: String, charlas: List<EntradaLocal>, notas: List<Apunte>, eventos: List<Evento>,
                    alAbrirNota: (String) -> Unit, alAbrirCharla: (String) -> Unit) {
    val p = LocalPaleta.current
    val fecha = LocalDate.parse(dia)
    val titulo = "${fecha.dayOfMonth} de ${fecha.month.getDisplayName(TextStyle.FULL, es)}"
    Row(Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(if (dia == hoy) "Hoy · $titulo" else titulo, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
        if (charlas.isNotEmpty()) {
            Text("${charlas.size}", color = p.fondo, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                 modifier = Modifier.background(p.musgo, RoundedCornerShape(10.dp)).padding(horizontal = 9.dp, vertical = 2.dp))
        }
    }
    val cosas = (charlas.map { it.creadoLocal to it } + notas.map { DiaLogico.paredIso(
        java.time.LocalDateTime.ofInstant(java.time.Instant.ofEpochMilli(it.creadoEn), java.time.ZoneId.systemDefault())) to it })
        .sortedBy { it.first }.map { it.second }
    if (cosas.isEmpty() && eventos.isEmpty()) {
        // Sin reproche: hasta el 04/10/2026 decía «Ese día no hablaste».
        Text("Nada este día.", color = p.tintaTenue, modifier = Modifier.padding(top = 6.dp))
        return
    }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(bottom = 24.dp)) {
        items(eventos, key = { "e${it.id}" }) { TarjetaDeEvento(it) }
        items(cosas, key = { if (it is EntradaLocal) "c${it.clientUuid}" else "n${(it as Apunte).id}" }) { cosa ->
            when (cosa) {
                is EntradaLocal -> TarjetaDeCharla(cosa) { alAbrirCharla(cosa.clientUuid) }
                is Apunte -> Carta(Modifier.fillMaxWidth().clickable { alAbrirNota(cosa.id) },
                                   fondo = p.nota.copy(alpha = 0.10f), borde = p.nota.copy(alpha = 0.45f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.EditNote, null, tint = p.nota, modifier = Modifier.size(14.dp))
                        Text(" ${cuando(cosa.creadoEn).substringAfter(", ")} · Nota", color = p.nota, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    }
                    Text(cosa.texto.trim(), color = p.tinta, fontSize = 15.sp, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
    }
}

/**
 * Una charla del día, corta: la hora, cuánto duró y cómo empezó, con el mismo
 * dibujo que el chat (`Globo`). Desde el 04/10/2026; antes era la transcripción
 * entera con «Vos:» y «Bitácora:» delante. La duración como la diría una persona
 * y el estado de la subida sólo si algo falló.
 */
@Composable
private fun TarjetaDeCharla(e: EntradaLocal, alAbrir: () -> Unit) {
    val p = LocalPaleta.current
    val turnos = Transcripcion.turnos(e.transcripcion)
    Carta(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).clickable(onClick = alAbrir)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(e.creadoLocal.substring(11, 16), color = p.musgo, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            if (e.duracionSeg > 0) Text(" · ${Transcripcion.duracion(e.duracionSeg)}", color = p.tintaTenue, fontSize = 12.sp)
            if (e.estado == "rechazada") Text("  No se pudo subir", color = p.rojo, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        }
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            turnos.firstOrNull { it.de == Hablante.VOS }?.let { Globo(it, lineas = 3) }
            turnos.firstOrNull { it.de == Hablante.BITACORA }?.let { Globo(it, lineas = 3) }
        }
        Text("Ver la charla entera ›", color = p.musgo, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
             modifier = Modifier.padding(top = 8.dp))
    }
}

/** Una charla guardada, entera, como se vio en el chat. Se abre desde su tarjeta. */
@Composable
private fun CharlaGuardada(e: EntradaLocal, alVolver: () -> Unit) {
    val p = LocalPaleta.current
    val alcance = rememberCoroutineScope()
    // Borrar la charla (28/10/2026): del servidor, con lo que la ficha sacó de
    // ella, y después del teléfono. Si nunca llegó al servidor, sólo de acá.
    var borrando by remember { mutableStateOf(false) }
    var noSeBorro by remember { mutableStateOf(false) }
    BackHandler(onBack = alVolver)
    val fecha = LocalDate.parse(e.dia)
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = alVolver) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver", tint = p.tintaSuave) }
            Text("${fecha.dayOfMonth} de ${fecha.month.getDisplayName(TextStyle.FULL, es)}", Modifier.weight(1f),
                 textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            IconButton(onClick = { borrando = true }) { Icon(Icons.Outlined.Delete, "Borrar esta charla", tint = p.tintaSuave) }
        }
        if (borrando) AlertDialog(
            onDismissRequest = { borrando = false },
            title = { Text("¿Borrar esta charla?") },
            text = { Text("Se borra de este teléfono y del servidor, con lo que Bitácora anotó de ella. No se puede deshacer.") },
            confirmButton = { TextButton({
                borrando = false
                alcance.launch {
                    val ok = e.servidorId == null && e.estado == "borrador" || Datos.cliente().borrarConversacion(e.clientUuid)
                    if (ok) { Datos.entradas.cambiar { l -> l.filter { it.clientUuid != e.clientUuid } }; alVolver() }
                    else noSeBorro = true
                }
            }) { Text("Borrar", color = p.rojo) } },
            dismissButton = { TextButton({ borrando = false }) { Text("Cancelar") } },
        )
        if (noSeBorro) AlertDialog(
            onDismissRequest = { noSeBorro = false },
            title = { Text("No se pudo borrar") },
            text = { Text("Hace falta conexión para borrarla también del servidor. Prueba de nuevo en un rato.") },
            confirmButton = { TextButton({ noSeBorro = false }) { Text("Bueno") } },
        )
        val hora = e.creadoLocal.substring(11, 16)
        Text(if (e.duracionSeg > 0) "$hora · ${Transcripcion.duracion(e.duracionSeg)}" else hora,
             color = p.tintaTenue, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            items(Transcripcion.turnos(e.transcripcion)) { Globo(it) }
        }
    }
}

/**
 * Una consulta, u otra cosa del calendario. Si es una PROPUESTA —Bitácora la
 * sacó de algo que la persona dijo—, lo dice y pregunta si se agrega: hasta
 * que diga que sí, no cuenta para nada.
 */
@Composable
private fun TarjetaDeEvento(e: Evento) {
    val p = LocalPaleta.current
    val alcance = rememberCoroutineScope()
    var trabajando by remember { mutableStateOf(false) }
    var fallo by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var cambiandoHora by remember { mutableStateOf(false) }
    var confirmarBorrado by remember { mutableStateOf(false) }
    var paraLlevarAbierto by remember { mutableStateOf(false) }

    fun hacer(accion: suspend () -> Boolean) {
        trabajando = true; fallo = false
        alcance.launch { fallo = !accion(); trabajando = false }
    }

    val borde = p.verde.copy(alpha = 0.45f)
    Column(
        Modifier.fillMaxWidth()
            .background(p.verde.copy(alpha = if (e.esPropuesta) 0.05f else 0.10f), RoundedCornerShape(22.dp))
            .drawBehind {
                drawRoundRect(borde, cornerRadius = CornerRadius(22.dp.toPx()),
                    style = Stroke(1.dp.toPx(), pathEffect = if (e.esPropuesta) PathEffect.dashPathEffect(floatArrayOf(12f, 9f)) else null))
            }
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // El sillón, el mismo de Consultas en «Mi expediente».
            Icon(if (e.esConsulta) Sillon else Icons.Outlined.Event, null, tint = p.verde, modifier = Modifier.size(16.dp))
            Text("  ${if (e.esConsulta) "Consulta" else e.titulo ?: "Evento"}  ", color = p.verde, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            Text(e.hora ?: "Sin hora", color = p.verde, fontSize = 13.sp, modifier = Modifier.weight(1f))
            if (!e.esPropuesta) Box {
                IconButton(onClick = { menu = true }, modifier = Modifier.size(28.dp)) {
                    Icon(Icons.Outlined.MoreHoriz, "Opciones", tint = p.verde)
                }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Cambiar la hora") }, { menu = false; cambiandoHora = true })
                    DropdownMenuItem({ Text("Eliminar", color = p.rojo) }, { menu = false; confirmarBorrado = true })
                }
            }
        }
        if (e.esPropuesta) {
            Text("La anotó Bitácora por algo que dijiste en una charla. ¿La agrego a tu calendario?",
                 color = p.tinta, fontSize = 15.sp, modifier = Modifier.padding(vertical = 8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Button({ hacer { Agenda.confirmar(e) } }, enabled = !trabajando,
                       colors = ButtonDefaults.buttonColors(containerColor = p.verde, contentColor = p.fondo)) { Text("Agregar") }
                OutlinedButton({ hacer { Agenda.descartar(e) } }, enabled = !trabajando) { Text("No", color = p.tinta) }
            }
        }
        // Lo que eligió llevar, resumido: se abre al tocarlo (04/10/2026).
        if (e.paraLlevar.isNotEmpty()) {
            Row(Modifier.clickable { paraLlevarAbierto = !paraLlevarAbierto }.padding(top = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text("Para llevar: ${e.paraLlevar.size} ${if (e.paraLlevar.size == 1) "cosa" else "cosas"}", color = p.tintaSuave, fontSize = 15.sp)
                Icon(Icons.Outlined.KeyboardArrowDown, null, tint = p.tintaTenue,
                     modifier = Modifier.size(18.dp).rotate(if (paraLlevarAbierto) 180f else 0f))
            }
        }
        if (e.paraLlevar.isNotEmpty() && paraLlevarAbierto) {
            for (cosa in e.paraLlevar) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 3.dp)) {
                    Box(Modifier.size(4.dp).background(p.verde, CircleShape))
                    Text("  $cosa", color = p.tinta, fontSize = 15.sp)
                }
            }
        }
        if (fallo) Text("No llego al servidor. Prueba de nuevo en un rato.", color = p.rojo, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
    }

    if (cambiandoHora) HojaDeEvento(e.dia, e) { cambiandoHora = false }
    if (confirmarBorrado) AlertDialog(
        onDismissRequest = { confirmarBorrado = false },
        title = { Text("¿Eliminar esta ${if (e.esConsulta) "consulta" else "cosa"} del calendario?") },
        confirmButton = { TextButton({ confirmarBorrado = false; hacer { Agenda.borrar(e) } }) { Text("Eliminar", color = p.rojo) } },
        dismissButton = { TextButton({ confirmarBorrado = false }) { Text("Cancelar") } },
    )
}

/**
 * Cargar una consulta en un día, o cambiarle la hora a una que ya está. Son
 * dos datos y uno es optativo. El día viene elegido, el que se estaba mirando;
 * desde el 04/10/2026 el botón está arriba y no al lado del día, así que al
 * agregar también se puede cambiar acá.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HojaDeEvento(dia: String, cambiando: Evento?, alCerrar: () -> Unit) {
    val p = LocalPaleta.current
    val alcance = rememberCoroutineScope()
    var esConsulta by remember { mutableStateOf(cambiando?.esConsulta ?: true) }
    var titulo by remember { mutableStateOf("") }
    var conHora by remember { mutableStateOf(cambiando == null || cambiando.hora != null) }
    val (h, m) = cambiando?.hora?.split(":")?.map { it.toInt() } ?: listOf(17, 0)
    val reloj = rememberTimePickerState(h, m, is24Hour = true)
    var guardando by remember { mutableStateOf(false) }
    var fallo by remember { mutableStateOf(false) }
    var diaElegido by remember { mutableStateOf(dia) }
    var eligiendoDia by remember { mutableStateOf(false) }
    fun escrito(d: String) = LocalDate.parse(d).let {
        "${it.dayOfWeek.getDisplayName(TextStyle.FULL, es).replaceFirstChar { c -> c.uppercase() }}, " +
            "${it.dayOfMonth} de ${it.month.getDisplayName(TextStyle.FULL, es)}"
    }

    // Lunes primero y en castellano, como el calendario de la app, aunque el
    // teléfono esté en otro idioma: el selector toma las dos cosas del idioma
    // de la pantalla, y esta versión no deja pasárselo directo. Va ADENTRO del
    // diálogo: su ventana arma su propia configuración y tapa la de afuera.
    val config = LocalConfiguration.current
    val enCastellano = remember(config) { Configuration(config).apply { setLocale(Locale.forLanguageTag("es-ES")) } }
    if (eligiendoDia) {
        val estado = rememberDatePickerState(LocalDate.parse(diaElegido).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { eligiendoDia = false },
            confirmButton = {
                TextButton({
                    estado.selectedDateMillis?.let { diaElegido = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString() }
                    eligiendoDia = false
                }) { Text("Listo", color = p.verde) }
            },
            dismissButton = { TextButton({ eligiendoDia = false }) { Text("Cancelar") } },
        ) {
            CompositionLocalProvider(LocalConfiguration provides enCastellano) {
                DatePicker(estado, title = null, headline = null, showModeToggle = false)
            }
        }
    }

    AlertDialog(
        onDismissRequest = alCerrar,
        title = { Text(if (cambiando == null) "Agregar" else "Cambiar la hora") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (cambiando == null) Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Día", Modifier.weight(1f))
                    TextButton({ eligiendoDia = true }) { Text(escrito(diaElegido), color = p.verde) }
                } else Text(escrito(dia), color = p.tintaSuave)
                if (cambiando == null) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        SegmentedButton(esConsulta, { esConsulta = true }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("Consulta") }
                        SegmentedButton(!esConsulta, { esConsulta = false }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("Otra cosa") }
                    }
                    if (esConsulta) Text("Con tu terapeuta. El día anterior, Bitácora te ayuda a elegir qué llevar; después, te pregunta cómo te fue.",
                                         color = p.tintaTenue, fontSize = 13.sp)
                    else OutlinedTextField(titulo, { if (it.length <= 80) titulo = it }, label = { Text("Qué es") }, singleLine = true)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("A una hora", Modifier.weight(1f))
                    Switch(conHora, { conHora = it }, colors = SwitchDefaults.colors(checkedTrackColor = p.verde))
                }
                if (conHora) TimePicker(reloj)
                if (fallo) Text("No llego al servidor: no se guardó.", color = p.rojo, fontSize = 13.sp)
            }
        },
        confirmButton = {
            TextButton(enabled = !guardando && (esConsulta || titulo.isNotBlank()), onClick = {
                guardando = true; fallo = false
                val hora = if (conHora) "%02d:%02d".format(reloj.hour, reloj.minute) else null
                alcance.launch {
                    val ok = if (cambiando != null) Agenda.cambiarHora(cambiando, hora)
                             else Agenda.agregar(if (esConsulta) "consulta" else "otro", diaElegido, hora, titulo.trim().ifEmpty { null })
                    guardando = false
                    if (ok) alCerrar() else fallo = true
                }
            }) { Text("Guardar", color = p.verde) }
        },
        dismissButton = { TextButton(onClick = alCerrar) { Text("Cancelar") } },
    )
}
