package ar.dusan.bitacora.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/*
 * Los dos íconos del compositor, dibujados acá y no tomados del catálogo, como
 * en el iPhone (`Iconos.swift`): el de la llamada no existe en ningún catálogo
 * —hay teléfonos y formas de onda, y ninguna dice "estoy hablando con alguien
 * que me contesta"—, y si uno es propio y el otro no, no pesan igual.
 *
 * Están pensados en una grilla de 24, con dos o tres formas cada uno: a tamaño
 * chico, más trazos se leen como un borrón.
 */

/**
 * La llamada: una voz que irradia. Un núcleo lleno con dos arcos alrededor.
 * No es un teléfono —nadie llama por teléfono a una app— ni un ecualizador.
 * Con `viva`, los arcos respiran.
 */
@Composable
fun VozViva(modifier: Modifier, color: Color, viva: Boolean = false) {
    val respiro = rememberInfiniteTransition(label = "voz")
    val pulso by respiro.animateFloat(
        initialValue = if (viva) 0.82f else 1f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1000), RepeatMode.Reverse), label = "pulso",
    )
    Canvas(modifier) {
        val u = size.minDimension / 24f
        val centro = Offset(size.width / 2, size.height / 2)
        // El núcleo chico y los arcos bien afuera: pegados se leían como un ojo.
        drawCircle(color, radius = 2.8f * u, center = centro)
        val r = 8.5f * u * (if (viva) pulso else 1f)
        val trazo = Stroke(width = 2f * u, cap = StrokeCap.Round)
        val esquina = Offset(centro.x - r, centro.y - r)
        drawArc(color, startAngle = 145f, sweepAngle = 70f, useCenter = false, topLeft = esquina, size = Size(2 * r, 2 * r), style = trazo)
        drawArc(color, startAngle = -35f, sweepAngle = 70f, useCenter = false, topLeft = esquina, size = Size(2 * r, 2 * r), style = trazo)
    }
}

/** Grabar un mensaje y transcribirlo: un micrófono macizo, la forma que se reconoce de un vistazo. */
@Composable
fun Microfono(modifier: Modifier, color: Color) {
    Canvas(modifier) {
        val u = size.minDimension / 24f
        val x0 = (size.width - 24f * u) / 2
        val y0 = (size.height - 24f * u) / 2
        fun p(x: Float, y: Float) = Offset(x0 + x * u, y0 + y * u)
        // La cápsula.
        drawRoundRect(color, topLeft = p(9.1f, 2.4f), size = Size(5.8f * u, 10.8f * u), cornerRadius = CornerRadius(2.9f * u))
        // El arco que la sostiene, abierto hacia arriba.
        drawArc(color, startAngle = 0f, sweepAngle = 180f, useCenter = false,
                topLeft = p(6.2f, 4.9f), size = Size(11.6f * u, 11.6f * u),
                style = Stroke(width = 2.1f * u, cap = StrokeCap.Round))
        // El pie.
        drawRoundRect(color, topLeft = p(10.95f, 16.7f), size = Size(2.1f * u, 3.4f * u), cornerRadius = CornerRadius(1.05f * u))
        drawRoundRect(color, topLeft = p(8.2f, 19.35f), size = Size(7.6f * u, 2.1f * u), cornerRadius = CornerRadius(1.05f * u))
    }
}

/*
 * Los dos de la portada de «Mi expediente», elegidos por Dusan el 04/10/2026 entre
 * seis cada uno: el sillón de la consulta para Consultas, y un libro para Mi
 * resumen. Son `armchair` y `book-2` de Tabler Icons (licencia MIT), con sus
 * trazos tal cual; en el iPhone están dibujados igual (`Iconos.swift`). Como
 * `ImageVector`, se pintan con el `tint` de `Icon`.
 */

/** Consultas: el sillón. Se reconoce como terapia sin parecerse a nada más de la app. */
val Sillon: ImageVector by lazy {
    deLineas(
        "Sillón",
        "M5 11a2 2 0 0 1 2 2v2h10v-2a2 2 0 1 1 4 0v4a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2",
        "M5 11v-5a3 3 0 0 1 3 -3h8a3 3 0 0 1 3 3v5",
        "M6 19v2",
        "M18 19v2",
    )
}

/** Mi resumen: un libro, lo que se escribe y se relee. */
val Libro: ImageVector by lazy {
    deLineas(
        "Libro",
        "M19 4v16h-12a2 2 0 0 1 -2 -2v-12a2 2 0 0 1 2 -2h12",
        "M19 16h-12a2 2 0 0 0 -2 2",
        "M9 8h6",
    )
}

/**
 * La pestaña «Mi expediente»: una carpeta, el `folder` de Tabler Icons. Desde la
 * noche del 04/10/2026, cuando la pestaña dejó de llamarse «Mi proceso» y Dusan
 * pidió otro ícono que el sillón de Consultas. El mismo dibujo está en `Iconos.swift`.
 */
val Carpeta: ImageVector by lazy {
    deLineas(
        "Carpeta",
        "M5 4h4l3 3h7a2 2 0 0 1 2 2v8a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2v-11a2 2 0 0 1 2 -2",
    )
}

/**
 * Las notas sueltas: una libreta, el `notebook` de Tabler Icons. Reemplazó el
 * 04/10/2026 al ícono de lápiz, que en Claude o ChatGPT se lee como «charla
 * nueva»; va con la palabra «Notas» al lado. El mismo dibujo está en `Iconos.swift`.
 */
val Libreta: ImageVector by lazy {
    deLineas(
        "Libreta",
        "M6 4h11a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-11a1 1 0 0 1 -1 -1v-14a1 1 0 0 1 1 -1",
        "M9 4v16",
        "M13 8h2",
        "M13 12h2",
    )
}

/** Un dibujo de líneas en la grilla de 24: trazo de 2, puntas y codos redondos. */
private fun deLineas(nombre: String, vararg trazos: String): ImageVector =
    ImageVector.Builder(nombre, 24.dp, 24.dp, 24f, 24f).apply {
        trazos.forEach {
            addPath(
                pathData = addPathNodes(it),
                stroke = SolidColor(Color.Black),
                strokeLineWidth = 2f,
                strokeLineCap = StrokeCap.Round,
                strokeLineJoin = StrokeJoin.Round,
            )
        }
    }.build()
