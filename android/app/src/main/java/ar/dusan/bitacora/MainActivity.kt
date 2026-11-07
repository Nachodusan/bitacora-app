package ar.dusan.bitacora

import android.app.Application
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import ar.dusan.bitacora.datos.Agenda
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.datos.Outbox
import ar.dusan.bitacora.ui.Bienvenida
import ar.dusan.bitacora.ui.CalendarioPantalla
import ar.dusan.bitacora.ui.Carpeta
import ar.dusan.bitacora.ui.ChatPantalla
import ar.dusan.bitacora.ui.EvaluacionesPantalla
import ar.dusan.bitacora.ui.LocalPaleta
import ar.dusan.bitacora.ui.Tema
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.TimeZone

class BitacoraApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Datos.iniciar(this)
    }
}

class MainActivity : ComponentActivity() {
    private lateinit var conversacion: Conversacion
    private var latido: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        conversacion = Conversacion(this)
        // Una charla que quedó abierta —la app murió, sonó el teléfono— se cierra
        // y se sube ahora.
        Outbox.rescatarBorradores()
        setContent { Tema { Raiz(conversacion) } }
    }

    /**
     * Al volver a la app: preguntar por el servidor, subir lo pendiente, traer
     * las consultas (una que Bitácora propuso, un borrador de evaluación) y
     * mandar la zona horaria, por si se viajó. Y mientras está abierta, cada
     * quince segundos, reintentar lo que no subió.
     */
    override fun onResume() {
        super.onResume()
        latido = lifecycleScope.launch {
            val c = Datos.config
            if (c.configurada) Datos.cliente().guardarAjustes(c.nombre, TimeZone.getDefault().id)
            Agenda.actualizar()
            while (isActive) {
                Outbox.comprobarServidor()
                Outbox.drenar()
                delay(15_000)
            }
        }
    }

    override fun onPause() {
        latido?.cancel()
        super.onPause()
    }

    override fun onDestroy() {
        if (isFinishing) conversacion.terminar()
        conversacion.soltar()
        super.onDestroy()
    }
}

enum class Pestana { CALENDARIO, CHAT, EVALUACIONES }

@Composable
private fun Raiz(conversacion: Conversacion) {
    val p = LocalPaleta.current
    // En `Navegacion` y no acá: Mi expediente lleva al calendario o al chat desde
    // la tarjeta de la próxima consulta.
    var pestana by Navegacion::pestana
    // La primera vez, antes que nada: qué es Bitácora, cómo se usa, qué queda
    // en el teléfono, y cómo te llama (04/10/2026; antes no había bienvenida).
    var bienvenida by rememberSaveable { mutableStateOf(!Datos.config.nombrePreguntado) }
    if (bienvenida) { Bienvenida { bienvenida = false }; return }
    // El diario de antes de las cuentas (28/10/2026): elige su PIN una vez.
    var eligiendoPin by rememberSaveable {
        mutableStateOf(Datos.config.sesion == null && Datos.config.tokenFijo.isNotBlank())
    }
    if (eligiendoPin) { ar.dusan.bitacora.ui.ElegirPin { eligiendoPin = false }; return }
    BackHandler(enabled = pestana != Pestana.CHAT) { pestana = Pestana.CHAT }

    // Cada pantalla se ocupa de la barra de estado y del teclado; el Scaffold
    // sólo deja lugar para la barra de pestañas. Si no, el margen de arriba se
    // aplicaba dos veces y el encabezado bajaba.
    Scaffold(
        containerColor = p.fondo,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            // Sin la barra mientras se habla: con el calendario a un dedo de
            // distancia, la conversación sería una pestaña más.
            if (!conversacion.abierta || pestana != Pestana.CHAT) {
                NavigationBar(containerColor = p.carta) {
                    val colores = NavigationBarItemDefaults.colors(
                        selectedIconColor = p.musgo, unselectedIconColor = p.tintaSuave,
                        indicatorColor = p.globoVos,
                    )
                    // Sólo los íconos, como en el iPhone. El nombre queda para TalkBack.
                    NavigationBarItem(pestana == Pestana.CALENDARIO, { pestana = Pestana.CALENDARIO },
                        { Icon(Icons.Outlined.CalendarMonth, "Calendario") }, colors = colores)
                    NavigationBarItem(pestana == Pestana.CHAT, { pestana = Pestana.CHAT },
                        { Icon(Icons.Outlined.GraphicEq, "Hablar") }, colors = colores)
                    NavigationBarItem(pestana == Pestana.EVALUACIONES, { pestana = Pestana.EVALUACIONES },
                        { Icon(Carpeta, "Mi espacio") }, colors = colores)
                }
            }
        },
    ) { margen ->
        Box(Modifier.fillMaxSize().padding(margen).consumeWindowInsets(margen)) {
            when (pestana) {
                Pestana.CALENDARIO -> CalendarioPantalla()
                Pestana.CHAT -> ChatPantalla(conversacion)
                Pestana.EVALUACIONES -> EvaluacionesPantalla()
            }
        }
    }
}
