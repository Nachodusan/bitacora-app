package ar.dusan.bitacora.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.compose.ui.semantics.clearAndSetSemantics
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin

/**
 * La marca de Bitácora: un punto durazno con anillos ondulados alrededor, como
 * curvas de nivel. Es `Anillos.swift`, con la misma fórmula y los mismos
 * colores: la marca tiene que ser la misma en los dos teléfonos (docs/arquitectura.md, «La
 * marca: los anillos»).
 *
 * Sin `activa` (el inicio) los anillos van parejos y respiran despacio. Con
 * `activa` (la llamada) se desordenan y se cruzan, giran lento, y hablan con la
 * voz: `nivel()` se lee en cada cuadro —el micrófono escuchando, el parlante
 * hablando— y empuja los anillos hacia afuera en ondas, cada uno un poco después
 * que el de adentro. El punto late con la voz.
 */
@Composable
fun Anillos(
    modifier: Modifier = Modifier,
    tamano: Dp = 96.dp,
    activa: Boolean = false,
    nivel: () -> Float = { 0f },
) {
    // El reloj y los seguidores viven en el estado del composable y avanzan en
    // cada cuadro; el Canvas sólo lee.
    var t by remember { mutableFloatStateOf(0f) }
    var cuadro by remember { mutableLongStateOf(0L) }
    val estado = remember { EstadoDeAnillos() }
    val activaAhora by rememberUpdatedState(activa)
    val nivelAhora by rememberUpdatedState(nivel)

    LaunchedEffect(Unit) {
        var antes = 0L
        while (true) {
            withFrameNanos { ahora ->
                val dt = if (antes == 0L) 0f else min(0.1f, (ahora - antes) / 1e9f)
                antes = ahora
                t += dt
                estado.avanzar(dt, activaAhora, nivelAhora())
                cuadro = ahora
            }
        }
    }

    val pxPorDp = LocalDensity.current.density
    // En modo claro el crema no se ve: las líneas pasan a oliva oscuro.
    val linea = if (isSystemInDarkTheme()) CREMA else OLIVA
    Canvas(modifier.size(tamano).clearAndSetSemantics { }) {
        @Suppress("UNUSED_EXPRESSION") cuadro // leer el cuadro hace que se redibuje
        val c = Offset(size.width / 2, size.height / 2)
        val d = estado.desorden
        val radioMax = min(size.width, size.height) / 2 * (0.86f - 0.10f * d)
        val radioMin = radioMax * 0.26f
        val cantidad = 7
        val respiro = 1 + 0.025f * sin(t * 0.9f)
        for (i in 0 until cantidad) {
            val f = i / (cantidad - 1f)
            val pi = estado.pulsoHace(i * 0.055f)
            val r = (radioMin + (radioMax - radioMin) * f) * respiro * (1 + 0.10f * pi * (1 - 0.4f * f))
            val lado = if (i % 2 == 0) 1f else -1f
            val camino = Path()
            val pasos = 120
            for (k in 0..pasos) {
                val a = k / pasos.toFloat() * 2 * Math.PI.toFloat()
                val calma = sin(3 * a + t * 0.18f + i * 0.5f) * 0.045f + sin(2 * a - t * 0.11f + 1.3f) * 0.03f
                val fase = estado.fase
                val caos = sin(4 * a + lado * fase + i * 1.7f) * 0.07f +
                    sin(5 * a - fase * 0.74f + i * 2.3f) * 0.05f +
                    sin(7 * a + fase * 1.22f + i * 0.9f) * 0.025f
                val onda = calma * (1 - d) + caos * d * (0.45f + 0.9f * pi)
                val rr = r * (1 + onda * (0.75f + 0.35f * f))
                val x = c.x + rr * cos(a)
                val y = c.y + rr * sin(a)
                if (k == 0) camino.moveTo(x, y) else camino.lineTo(x, y)
            }
            camino.close()
            val opacidad = min(1f, (0.85f - 0.25f * f) * (0.8f + 0.45f * pi))
            drawPath(camino, linea.copy(alpha = opacidad), style = Stroke(width = pxPorDp))
        }
        val p0 = estado.pulsoHace(0f)
        val pr = radioMin * 0.55f * (1 + 0.05f * sin(t * 0.9f + 0.6f) + 0.35f * p0)
        drawCircle(DURAZNO, radius = pr, center = c)
    }
}

private val DURAZNO = Color(0xFFEDA680)
private val CREMA = Color(0xFFDBD4B3)
private val OLIVA = Color(0xFF54523D)

/** Lo que avanza cuadro a cuadro: el desorden, el pulso con su historia y el giro. */
private class EstadoDeAnillos {
    var desorden = 0f
        private set
    var fase = 0f
        private set
    private var pulso = 0f
    private val historia = ArrayDeque<Pair<Float, Float>>() // (tiempo, pulso)
    private var reloj = 0f

    fun avanzar(dt: Float, activa: Boolean, nivelCrudo: Float) {
        reloj += dt
        desorden = seguir(desorden, if (activa) 1f else 0f, dt, sube = 0.6f, baja = 0.8f)
        // El mismo recorte que en el iPhone: el piso del medidor no es voz.
        val voz = if (activa) ((nivelCrudo - 0.15f) / 0.75f).coerceIn(0f, 1f) else 0f
        pulso = seguir(pulso, voz, dt, sube = 0.04f, baja = 0.12f)
        historia.addLast(reloj to pulso)
        while (historia.isNotEmpty() && reloj - historia.first().first > 0.6f) historia.removeFirst()
        // La fase se acumula: multiplicar el reloj por una velocidad que cambia
        // la hace saltar (lo que en el iPhone hacía girar las líneas a tirones).
        fase += dt * (0.35f + 0.15f * desorden + 0.15f * pulso)
    }

    fun pulsoHace(segundos: Float): Float {
        val objetivo = reloj - segundos
        return historia.lastOrNull { it.first <= objetivo }?.second ?: historia.firstOrNull()?.second ?: 0f
    }

    private fun seguir(actual: Float, objetivo: Float, dt: Float, sube: Float, baja: Float): Float {
        val tau = if (objetivo > actual) sube else baja
        return objetivo + (actual - objetivo) * exp(-dt / tau)
    }
}
