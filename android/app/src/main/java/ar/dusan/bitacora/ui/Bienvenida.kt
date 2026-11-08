package ar.dusan.bitacora.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ar.dusan.bitacora.datos.Datos
import kotlinx.coroutines.launch
import java.util.TimeZone

/**
 * Lo primero, antes que nada: qué es Bitácora, cómo se usa, qué queda en el
 * teléfono, y cómo te llama. Es `Bienvenida.swift`.
 *
 * Desde el 04/10/2026. Hasta ese día Android abría directo en el chat, sin
 * contar qué era la app ni preguntar el nombre (había que ir a Ajustes). Dusan
 * eligió estas tres pantallas en la maqueta. Se pasa con «Siguiente» o
 * deslizando. Los permisos del micrófono se piden la primera vez que se graba o
 * se llama, no acá.
 */
@Composable
fun Bienvenida(alTerminar: () -> Unit) {
    val p = LocalPaleta.current
    val paginas = rememberPagerState { 4 }
    val alcance = rememberCoroutineScope()
    fun siguiente() = alcance.launch { paginas.animateScrollToPage(paginas.currentPage + 1) }

    Box(Modifier.fillMaxSize().background(p.fondo).statusBarsPadding().navigationBarsPadding()) {
        HorizontalPager(paginas, Modifier.fillMaxSize()) { pagina ->
            when (pagina) {
                0 -> Pagina({ VozViva(Modifier.size(40.dp), p.musgo) }, "Un diario que te escucha", { siguiente() }) {
                    Parrafo("Le cuentas tu día a Bitácora, hablando o escribiendo, y queda guardado en tu calendario.")
                    Parrafo("No es terapia ni la reemplaza: te ayuda a ordenar lo que pasa para llevarlo a tu terapeuta.")
                }
                1 -> Pagina({ Icon(Icons.Outlined.ChatBubbleOutline, null, tint = p.musgo, modifier = Modifier.size(36.dp)) },
                            "Tres maneras de contar algo", { siguiente() }) {
                    Manera({ Icon(Icons.Outlined.Keyboard, null, tint = p.musgo, modifier = Modifier.size(20.dp)) },
                           "Escribe", "Te contesta por escrito.")
                    Manera({ Microfono(Modifier.size(20.dp), p.musgo) }, "Graba un mensaje", "Se transcribe en el teléfono.")
                    Manera({ VozViva(Modifier.size(22.dp), p.musgo) }, "Llama", "Una conversación hablada. La terminas tú.")
                }
                2 -> Pagina({ Icon(Icons.Outlined.Lock, null, tint = p.musgo, modifier = Modifier.size(36.dp)) },
                            "Lo tuyo se queda contigo", { siguiente() }) {
                    Parrafo("Tu voz se transcribe en el teléfono y nunca se sube.")
                    Parrafo("Tus sesiones y tus notas quedan sólo aquí.")
                    Parrafo("Si estás pasando un momento muy difícil, llama al *4141 (en Chile): es gratis y atiende a toda hora.")
                }
                else -> Registro { perfil ->
                    // Al terminar el registro, o al entrar a una cuenta que ya existía.
                    val c = Datos.config
                    c.nombre = perfil.nombre.orEmpty()
                    c.nombrePreguntado = true
                    alcance.launch { Datos.cliente().guardarAjustes(c.nombre, TimeZone.getDefault().id) }
                    alTerminar()
                }
            }
        }
        if (paginas.currentPage < 3) {
            Row(Modifier.align(Alignment.TopCenter).padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (i in 0 until 3) {
                    Box(Modifier.width(if (i == paginas.currentPage) 22.dp else 8.dp).height(8.dp)
                        .background(if (i == paginas.currentPage) p.musgo else p.cartaBorde, RoundedCornerShape(4.dp)))
                }
            }
        }
    }
}

@Composable
private fun Pagina(icono: @Composable () -> Unit, titulo: String, alSeguir: () -> Unit, contenido: @Composable ColumnScope.() -> Unit) {
    val p = LocalPaleta.current
    Column(Modifier.fillMaxSize().padding(horizontal = 28.dp).padding(bottom = 24.dp)) {
        Box(Modifier.padding(top = 90.dp).size(84.dp).background(p.musgo.copy(alpha = 0.14f), CircleShape),
            contentAlignment = Alignment.Center) { icono() }
        Text(titulo, color = p.tinta, fontSize = 30.sp, lineHeight = 36.sp, fontWeight = FontWeight.Bold,
             modifier = Modifier.padding(top = 28.dp))
        Column(Modifier.padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = contenido)
        Spacer(Modifier.weight(1f))
        Boton("Siguiente", onClick = alSeguir)
    }
}

@Composable
private fun Parrafo(texto: String) {
    Text(texto, color = LocalPaleta.current.tintaSuave, fontSize = 17.sp, lineHeight = 25.sp)
}

@Composable
private fun Manera(icono: @Composable () -> Unit, nombre: String, detalle: String) {
    val p = LocalPaleta.current
    Row(verticalAlignment = Alignment.Top) {
        Box(Modifier.size(44.dp).background(p.carta, CircleShape).border(1.dp, p.cartaBorde, CircleShape),
            contentAlignment = Alignment.Center) { icono() }
        Column(Modifier.padding(start = 14.dp)) {
            Text(nombre, color = p.tinta, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(detalle, color = p.tintaSuave, fontSize = 15.sp)
        }
    }
}

@Composable
private fun Boton(texto: String, habilitado: Boolean = true, onClick: () -> Unit) {
    val p = LocalPaleta.current
    Button(onClick, enabled = habilitado, modifier = Modifier.fillMaxWidth().height(52.dp),
           colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo,
                                                disabledContainerColor = p.tintaSuave.copy(alpha = 0.18f),
                                                disabledContentColor = p.tintaSuave)) {
        Text(texto, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}
