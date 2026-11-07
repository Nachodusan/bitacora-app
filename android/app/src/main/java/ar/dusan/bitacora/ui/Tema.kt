package ar.dusan.bitacora.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.BorderStroke

/**
 * La paleta de la app, la misma de `Estilo.swift`: papel, musgo, y el dorado
 * de Bitácora. Las notas en celeste y las consultas en verde azulado, para que
 * se distingan de lejos en el calendario.
 */
data class Paleta(
    val fondo: Color,
    val tinta: Color,
    val tintaSuave: Color,
    val tintaTenue: Color,
    val globoVos: Color,
    val musgo: Color,
    val musgoSuave: Color,
    val bitacora: Color,
    val carta: Color,
    val cartaBorde: Color,
    val verde: Color,
    val rojo: Color,
    val nota: Color,
)

private val clara = Paleta(
    fondo = Color(0xFFF4F4ED), tinta = Color(0xFF1F1E1B), tintaSuave = Color(0xFF63605A),
    tintaTenue = Color(0xFF96928A), globoVos = Color(0xFFE8E9DE), musgo = Color(0xFF4F6029),
    musgoSuave = Color(0xFF6B7F3C), bitacora = Color(0xFF8A6A1E), carta = Color(0xFFFFFFFF),
    cartaBorde = Color(0xFFE2E3D8), verde = Color(0xFF0F7A70), rojo = Color(0xFFA93226),
    nota = Color(0xFF2B6F9E),
)

private val oscura = Paleta(
    fondo = Color(0xFF16180F), tinta = Color(0xFFEDEBE4), tintaSuave = Color(0xFFA29D92),
    tintaTenue = Color(0xFF6F6B62), globoVos = Color(0xFF23261C), musgo = Color(0xFFA8C070),
    musgoSuave = Color(0xFF8DA55C), bitacora = Color(0xFFC9A340), carta = Color(0xFF1D2016),
    cartaBorde = Color(0xFF2A2E20), verde = Color(0xFF2FA294), rojo = Color(0xFFCE6152),
    nota = Color(0xFF7EC3EA),
)

val LocalPaleta = staticCompositionLocalOf { oscura }

@Composable
fun Tema(contenido: @Composable () -> Unit) {
    val p = if (isSystemInDarkTheme()) oscura else clara
    val esquema = (if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()).copy(
        primary = p.musgo, onPrimary = p.fondo, secondary = p.bitacora, background = p.fondo,
        surface = p.fondo, onSurface = p.tinta, onBackground = p.tinta, surfaceVariant = p.carta,
        onSurfaceVariant = p.tintaSuave, outline = p.cartaBorde, error = p.rojo,
        surfaceContainer = p.carta, surfaceContainerHigh = p.carta, surfaceContainerLow = p.fondo,
        secondaryContainer = p.globoVos, onSecondaryContainer = p.musgo,
    )
    CompositionLocalProvider(LocalPaleta provides p) {
        MaterialTheme(colorScheme = esquema) {
            Surface(color = p.fondo, contentColor = p.tinta) { contenido() }
        }
    }
}

/** Una tarjeta: el papel un poco más claro, con un borde fino. */
@Composable
fun Carta(
    modifier: Modifier = Modifier,
    radio: Dp = 22.dp,
    fondo: Color? = null,
    borde: Color? = null,
    contenido: @Composable ColumnScope.() -> Unit,
) {
    val p = LocalPaleta.current
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(radio),
        color = fondo ?: p.carta,
        contentColor = p.tinta,
        border = BorderStroke(1.dp, borde ?: p.cartaBorde),
    ) {
        Column(Modifier.padding(14.dp), content = contenido)
    }
}
