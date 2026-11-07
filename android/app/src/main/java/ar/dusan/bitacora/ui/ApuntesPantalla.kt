package ar.dusan.bitacora.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ar.dusan.bitacora.datos.Apunte
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.nucleo.DiaLogico
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/**
 * Las notas sueltas: para quien no quiere hablar con nadie y sólo quiere dejar
 * algo escrito. Abre directo en una hoja en blanco; sin botón de guardar, y una
 * hoja que se cierra vacía no deja rastro. Viven sólo en el teléfono, y se ven
 * en el calendario, en celeste.
 */
/**
 * Abre una hoja: la nota `id`, o una en blanco. Desde el chat siempre en
 * blanco; desde el calendario, una que ya existe, para seguir escribiendo.
 */
@Composable
fun ApuntesPantalla(id: String? = null, alCerrar: () -> Unit) {
    val hoja = rememberSaveable { id ?: nuevaNota() }
    Hoja(hoja, alCerrar)
}

private fun nuevaNota(): String = UUID.randomUUID().toString()

@Composable
private fun Hoja(id: String, alCerrar: () -> Unit) {
    val p = LocalPaleta.current
    val existente = Datos.apuntes.valor.firstOrNull { it.id == id }
    var texto by rememberSaveable(id) { mutableStateOf(existente?.texto.orEmpty()) }

    fun guardar(t: String) {
        Datos.apuntes.cambiar { l ->
            val ya = l.firstOrNull { it.id == id }
            when {
                t.isBlank() -> l.filter { it.id != id }
                ya != null -> l.map { if (it.id == id) it.copy(texto = t) else it }
                else -> l + Apunte(id, System.currentTimeMillis(), DiaLogico.hoy(), t)
            }
        }
    }
    BackHandler(onBack = alCerrar)

    Column(Modifier.fillMaxSize().statusBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = alCerrar) { Icon(Icons.Outlined.Close, "Cerrar la nota", tint = p.tintaSuave) }
            Text("Nota", Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, color = p.nota)
            IconButton(onClick = { guardar(""); alCerrar() }) { Icon(Icons.Outlined.Delete, "Eliminar la nota", tint = p.tintaSuave) }
        }
        TextField(
            value = texto,
            onValueChange = { texto = it; guardar(it) },
            placeholder = { Text("Escribe lo que quieras. Queda guardado mientras escribes.", color = p.tintaTenue) },
            modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = p.fondo, unfocusedContainerColor = p.fondo,
                focusedIndicatorColor = p.fondo, unfocusedIndicatorColor = p.fondo, cursorColor = p.nota,
            ),
            textStyle = androidx.compose.ui.text.TextStyle(fontSize = 17.sp, lineHeight = 25.sp, color = p.tinta),
        )
    }
}

fun cuando(milis: Long): String =
    DateTimeFormatter.ofPattern("d 'de' MMMM, HH:mm", Locale.forLanguageTag("es"))
        .format(Instant.ofEpochMilli(milis).atZone(ZoneId.systemDefault()))
