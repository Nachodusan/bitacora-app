package ar.dusan.bitacora.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FormatQuote
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.nucleo.DatoDeLaFicha
import ar.dusan.bitacora.nucleo.Ficha
import ar.dusan.bitacora.nucleo.Resumen
import kotlinx.coroutines.launch

/**
 * «Lo que Bitácora sabe de ti», en Mi espacio. Es `MiFichaView.swift`.
 *
 * La primera vez se ve el aviso: qué se guarda y qué se arma. Hasta que lo
 * lee, el servidor no arma la ficha ni la usa en la charla. Después, la ficha
 * con la frase suya de donde salió cada dato: lo marca para su psicólogo o lo
 * quita. Al final, borrar la cuenta (treinta días en la papelera).
 */
@Composable
fun FichaPantalla(alVolver: () -> Unit) {
    val p = LocalPaleta.current
    val alcance = rememberCoroutineScope()
    var ficha by remember { mutableStateOf<Ficha?>(null) }
    var sinServidor by remember { mutableStateOf(false) }
    var abierto by remember { mutableStateOf<Int?>(null) }
    var quitando by remember { mutableStateOf<DatoDeLaFicha?>(null) }
    var borrandoCuenta by remember { mutableStateOf(false) }

    suspend fun cargar() {
        val f = Datos.cliente().ficha()
        if (f != null) ficha = f else sinServidor = true
    }
    fun cambiarDato(id: Int, f: (DatoDeLaFicha) -> DatoDeLaFicha?) {
        ficha = ficha?.let { fi ->
            fi.copy(secciones = fi.secciones.map { s -> s.copy(datos = s.datos.mapNotNull { if (it.id == id) f(it) else it }) }
                .filter { it.datos.isNotEmpty() })
        }
    }
    LaunchedEffect(Unit) { cargar() }
    BackHandler(onBack = alVolver)

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = alVolver) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver a Mi espacio", tint = p.tintaSuave) }
            Text("Lo que Bitácora sabe de ti", Modifier.weight(1f), textAlign = TextAlign.Center,
                 fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Spacer(Modifier.size(48.dp))
        }
        val f = ficha
        when {
            f == null && sinServidor -> Text("No se pudo traer tu ficha. Revisa la conexión y vuelve a entrar.",
                color = p.tintaSuave, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(32.dp))
            f == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = p.musgo) }
            !f.avisada -> Aviso { alcance.launch { if (Datos.cliente().leyoElAviso()) cargar() } }
            else -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
                f.cuentaSeBorraEl?.let { dia ->
                    Papelera(dia) { alcance.launch { if (Datos.cliente().recuperarCuenta()) cargar() } }
                }
                Text("Sale de lo que contaste en tus charlas, con tus palabras. Toca un dato para ver de dónde salió, " +
                     "mandárselo a tu psicólogo o quitarlo.", color = p.tintaSuave, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
                if (f.secciones.isEmpty()) {
                    Text("Todavía no hay nada. Se va armando con tus charlas, al cerrar cada día.",
                         color = p.tintaTenue, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp))
                }
                f.secciones.forEach { s ->
                    Rotulo(s.titulo)
                    Carta(Modifier.fillMaxWidth().padding(top = 6.dp), radio = 18.dp) {
                        s.datos.forEachIndexed { i, d ->
                            if (i > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(p.cartaBorde))
                            Fila(d, abierto == d.id,
                                alTocar = { abierto = if (abierto == d.id) null else d.id },
                                alCompartir = { si -> alcance.launch { if (Datos.cliente().compartir(d.id, si)) cambiarDato(d.id) { it.copy(compartir = si) } } },
                                alQuitar = { quitando = d })
                        }
                    }
                    Spacer(Modifier.height(8.dp))
                }
                if (f.cuentaSeBorraEl == null) {
                    TextButton(onClick = { borrandoCuenta = true }, modifier = Modifier.fillMaxWidth().padding(top = 16.dp)) {
                        Text("Borrar mi cuenta", color = p.tintaTenue, fontWeight = FontWeight.SemiBold)
                    }
                }
                Text("Para borrar una charla, ábrela desde el calendario y toca el basurero.", color = p.tintaTenue,
                     fontSize = 12.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                Spacer(Modifier.height(100.dp))
            }
        }
    }

    quitando?.let { d ->
        AlertDialog(
            onDismissRequest = { quitando = null },
            title = { Text("¿Quitar «${d.nombre}» de tu ficha?") },
            text = { Text("Bitácora deja de usarlo y no vuelve a anotarlo. Tus conversaciones no se tocan.") },
            confirmButton = { TextButton({
                quitando = null
                alcance.launch { if (Datos.cliente().quitar(d.id)) cambiarDato(d.id) { null } }
            }) { Text("Quitar", color = p.rojo) } },
            dismissButton = { TextButton({ quitando = null }) { Text("Cancelar") } },
        )
    }
    if (borrandoCuenta) {
        AlertDialog(
            onDismissRequest = { borrandoCuenta = false },
            title = { Text("¿Borrar tu cuenta?") },
            text = { Text("Todo lo tuyo va a la papelera por 30 días: tus conversaciones, tu ficha y tus resúmenes. " +
                          "En ese tiempo puedes recuperarla; después se borra para siempre.") },
            confirmButton = { TextButton({
                borrandoCuenta = false
                alcance.launch { if (Datos.cliente().borrarCuenta() != null) cargar() }
            }) { Text("Borrar mi cuenta", color = p.rojo) } },
            dismissButton = { TextButton({ borrandoCuenta = false }) { Text("Cancelar") } },
        )
    }
}

@Composable
private fun Fila(d: DatoDeLaFicha, abierta: Boolean, alTocar: () -> Unit, alCompartir: (Boolean) -> Unit, alQuitar: () -> Unit) {
    val p = LocalPaleta.current
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable(onClick = alTocar).padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(d.nombre, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                Text((if (d.veces == 1) "Lo contaste una vez" else "Lo contaste ${d.veces} veces") + ", la última el ${fecha(d.ultima)}",
                     color = p.tintaTenue, fontSize = 12.sp)
                d.cuandoYParaQue?.let { Text(it, color = p.musgo, fontSize = 12.sp, fontWeight = FontWeight.Medium) }
                if (d.apodos.isNotEmpty()) Text("También le dices: " + d.apodos.joinToString(", "), color = p.tintaTenue, fontSize = 12.sp)
            }
            if (d.compartir) Icon(Icons.Outlined.People, "Para tu psicólogo", tint = p.musgo, modifier = Modifier.size(16.dp))
            Icon(if (abierta) Icons.Outlined.KeyboardArrowUp else Icons.Outlined.KeyboardArrowDown, null, tint = p.tintaTenue)
        }
        if (abierta) {
            d.citas.forEach { c ->
                Row(Modifier.padding(vertical = 4.dp)) {
                    Box(Modifier.width(2.dp).height(36.dp).background(p.musgo.copy(alpha = 0.6f)))
                    Column(Modifier.padding(start = 10.dp)) {
                        Text("«${c.cita}»", fontFamily = FontFamily.Serif, fontSize = 15.sp)
                        Text(fecha(c.dia), color = p.tintaTenue, fontSize = 11.sp)
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Para mi psicólogo", Modifier.weight(1f), fontSize = 15.sp)
                Switch(d.compartir, alCompartir, colors = SwitchDefaults.colors(checkedTrackColor = p.musgo))
            }
            TextButton(onClick = alQuitar, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) {
                Text("Quitar de mi ficha", color = p.rojo, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun Papelera(dia: String, alRecuperar: () -> Unit) {
    val p = LocalPaleta.current
    Carta(Modifier.fillMaxWidth().padding(vertical = 8.dp), fondo = p.musgo, borde = p.musgo) {
        Text("Tu cuenta se borra el ${fecha(dia)}", color = p.fondo, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
        Text("Mientras tanto Bitácora no arma nada nuevo. Si te arrepientes, la recuperas entera.",
             color = p.fondo.copy(alpha = 0.8f), fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
        Button(alRecuperar, Modifier.fillMaxWidth().padding(top = 10.dp),
               colors = ButtonDefaults.buttonColors(containerColor = p.fondo, contentColor = p.musgo)) {
            Text("Recuperar mi cuenta", fontWeight = FontWeight.SemiBold)
        }
    }
}

/** El aviso, antes de ver la ficha por primera vez. */
@Composable
private fun Aviso(alEntender: () -> Unit) {
    val p = LocalPaleta.current
    val puntos: List<Pair<ImageVector, String>> = listOf(
        Icons.Outlined.FormatQuote to "Tus charlas se guardan tal como las dijiste. Nadie las cambia.",
        Icons.Outlined.Description to "Con ellas, Bitácora arma una ficha: lo que te pasa, lo que te sirve, tu gente, lo que quieres. Cada dato lleva la frase tuya de donde salió.",
        Icons.Outlined.Info to "No hace diagnósticos. Anota sólo lo que contaste, con tus palabras.",
        Icons.Outlined.ChatBubbleOutline to "La usa para hablarte a ti y no a cualquiera. A tu psicólogo le llega sólo lo que elijas.",
        Icons.Outlined.Delete to "Puedes quitar cualquier dato, borrar una conversación o tu cuenta entera.",
        Icons.Outlined.Phone to "Si alguna vez estás en peligro, Bitácora te da el *4141 al momento. Eso no pasa por la ficha.",
    )
    var enviando by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
           verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Antes de verla", fontFamily = FontFamily.Serif, fontSize = 26.sp)
        puntos.forEach { (icono, texto) ->
            Row {
                Icon(icono, null, tint = p.musgo, modifier = Modifier.size(22.dp))
                Text(texto, color = p.tintaSuave, fontSize = 15.sp, modifier = Modifier.padding(start = 12.dp))
            }
        }
        Button({ enviando = true; alEntender() }, Modifier.fillMaxWidth().padding(top = 8.dp), enabled = !enviando,
               colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo)) {
            Text(if (enviando) "Un momento…" else "Entendido, ver mi ficha", fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(80.dp))
    }
}

private fun fecha(dia: String): String {
    val d = dia.substring(8, 10).toInt()
    val m = dia.substring(5, 7).toInt()
    return "$d de ${Resumen.meses[m - 1]}"
}
