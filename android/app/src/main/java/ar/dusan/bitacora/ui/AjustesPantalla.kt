package ar.dusan.bitacora.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.rotate
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ar.dusan.bitacora.datos.Agenda
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.datos.Outbox
import ar.dusan.bitacora.nucleo.Cliente
import kotlinx.coroutines.launch
import java.util.TimeZone

/**
 * Ajustes: cómo te llama Bitácora, su voz y, cerrado al final, el servidor.
 *
 * En tres grupos desde el 04/10/2026 (`AjustesView.swift` tiene un cuarto, la
 * luz de la voz, que Android no tiene): lo tuyo primero y lo técnico al final,
 * cerrado, abierto de entrada sólo si falta configurarlo. Y SE GUARDA SIEMPRE
 * IGUAL: con «Listo», con la flecha o con el botón de atrás. Antes la cruz salía
 * sin guardar y sólo «Guardar» guardaba. Probar la conexión quedó adentro del
 * servidor, que es donde importa.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AjustesPantalla(alCerrar: () -> Unit) {
    val p = LocalPaleta.current
    val c = Datos.config
    val alcance = rememberCoroutineScope()
    var url by rememberSaveable { mutableStateOf(c.url.ifEmpty { "http://" }) }
    var token by rememberSaveable { mutableStateOf(c.token) }
    var nombre by rememberSaveable { mutableStateOf(c.nombre) }
    var timbre by rememberSaveable { mutableStateOf(c.timbre) }
    var vozNatural by rememberSaveable { mutableStateOf(c.vozNatural) }
    var resultado by rememberSaveable { mutableStateOf<String?>(null) }
    var avanzadoAbierto by rememberSaveable { mutableStateOf(!c.configurada) }

    fun guardar() {
        if (!c.servidorFijo) { c.url = url; c.token = token }
        c.nombre = nombre; c.timbre = timbre; c.vozNatural = vozNatural
    }
    fun salir() {
        guardar()
        // En el alcance de la app y no en el de la pantalla, que se va ahora.
        if (c.configurada) Datos.alcance.launch {
            Datos.cliente().guardarAjustes(c.nombre, TimeZone.getDefault().id)
            Outbox.comprobarServidor()
            Outbox.drenar()
        }
        alCerrar()
    }
    BackHandler(onBack = ::salir)

    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = ::salir) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Volver", tint = p.tintaSuave) }
            Text("Ajustes", Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            TextButton(onClick = ::salir) { Text("Listo", color = p.musgo, fontWeight = FontWeight.SemiBold) }
        }

        Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Rotulo("Tú")
            OutlinedTextField(nombre, { if (it.length <= 40) nombre = it }, label = { Text("Cómo te llama Bitácora") },
                singleLine = true, modifier = Modifier.fillMaxWidth())
            Text("Puedes dejarlo vacío. Sin nombre te habla igual, sólo que no te nombra.", color = p.tintaTenue, fontSize = 13.sp)

            Rotulo("La voz de Bitácora")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Voz natural", Modifier.weight(1f))
                Switch(vozNatural, { vozNatural = it }, colors = SwitchDefaults.colors(checkedTrackColor = p.musgo))
            }
            Text(
                if (vozNatural) "La sintetiza el servidor y suena como una persona. Si no llega, habla la voz del teléfono."
                else "Bitácora habla con la voz del teléfono. No necesita internet, pero suena a robot.",
                color = p.tintaTenue, fontSize = 13.sp,
            )

            // Con el servidor dentro de la APK (la de un cliente), nada de esto se
            // muestra: no hay nada que la persona tenga que ver ni tocar.
            if (!c.servidorFijo) {
                Rotulo("Avanzado")
                Carta(Modifier.fillMaxWidth()) {
                    Row(Modifier.fillMaxWidth().clickable { avanzadoAbierto = !avanzadoAbierto }, verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Servidor", fontSize = 16.sp)
                            Text("Sólo para conectar con otro computador", color = p.tintaTenue, fontSize = 12.sp)
                        }
                        Icon(Icons.Outlined.KeyboardArrowDown, null, tint = p.tintaTenue,
                             modifier = Modifier.rotate(if (avanzadoAbierto) 180f else 0f))
                    }
                    if (avanzadoAbierto) {
                        OutlinedTextField(url, { url = it }, label = { Text("Dirección") }, singleLine = true,
                            modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
                        Text("La IP de la Mac con el puerto, por ejemplo http://192.168.0.10:3000.", color = p.tintaTenue, fontSize = 12.sp,
                             modifier = Modifier.padding(top = 4.dp))
                        OutlinedTextField(token, { token = it }, label = { Text("Token") }, singleLine = true,
                            modifier = Modifier.fillMaxWidth().padding(top = 8.dp), visualTransformation = PasswordVisualTransformation())
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                            TextButton(onClick = {
                                guardar()
                                resultado = "Probando…"
                                alcance.launch {
                                    Outbox.comprobarServidor()
                                    resultado = when (Outbox.servidor.value) {
                                        Cliente.Estado.LISTO -> {
                                            Datos.cliente().guardarAjustes(nombre, TimeZone.getDefault().id)
                                            Outbox.drenar()
                                            Agenda.actualizar()
                                            "Conectado."
                                        }
                                        Cliente.Estado.SIN_TOKEN -> "El servidor contesta, pero el token no es el suyo."
                                        else -> "No llego al servidor con esa dirección."
                                    }
                                }
                            }) { Text("Probar la conexión", color = p.musgo) }
                            resultado?.let { Text(it, color = if (it == "Conectado.") p.verde else p.tintaSuave, fontSize = 13.sp) }
                        }
                    }
                }
            }
            Text("Tu voz no se sube nunca: se transcribe en el teléfono y sólo viaja el texto. " +
                 "Bitácora sólo habla en llamada; si escribes, contesta por escrito.", color = p.tintaTenue, fontSize = 13.sp)
        }
    }
}

@Composable
fun Rotulo(texto: String) {
    Text(texto.uppercase(), color = LocalPaleta.current.tintaTenue, fontSize = 11.sp, fontWeight = FontWeight.Bold,
         letterSpacing = 0.6.sp, modifier = Modifier.padding(top = 6.dp))
}
