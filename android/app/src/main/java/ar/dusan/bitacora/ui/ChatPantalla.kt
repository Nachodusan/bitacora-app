package ar.dusan.bitacora.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import ar.dusan.bitacora.Conversacion
import ar.dusan.bitacora.Conversacion.Fase
import ar.dusan.bitacora.Navegacion
import ar.dusan.bitacora.nucleo.Evento
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.datos.Outbox
import ar.dusan.bitacora.nucleo.Cliente
import ar.dusan.bitacora.nucleo.Hablante
import ar.dusan.bitacora.nucleo.Turno
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow

/**
 * El chat, como en el iPhone (`ConversacionView.swift`).
 *
 * CERRADO es el portal: una luz con ondas, y nada más. Tocarla abre la
 * conversación, se va la barra de pestañas, y recién ahí está el campo, con
 * las tres maneras de decir algo: escribir, grabar un mensaje que se
 * transcribe, o abrir la llamada. Arriba a la izquierda, cerrado, las notas
 * sueltas; abierto, la cruz para salir. A la derecha, Ajustes.
 */
@Composable
fun ChatPantalla(charla: Conversacion) {
    val context = LocalContext.current
    var enAjustes by rememberSaveable { mutableStateOf(false) }
    var enNotas by rememberSaveable { mutableStateOf(false) }
    val servidor by Outbox.servidor.collectAsState()

    // El micrófono se pide la primera vez que hace falta, para lo que se tocó.
    var despuesDelPermiso by remember { mutableStateOf<(() -> Unit)?>(null) }
    val pedirMicrofono = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) despuesDelPermiso?.invoke()
        despuesDelPermiso = null
    }
    fun conMicrofono(accion: () -> Unit) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) accion()
        else {
            despuesDelPermiso = accion
            pedirMicrofono.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    // «Preparar» entra directo a la conversación, sin pasar por el portal: se
    // vino a hablar de la consulta.
    LaunchedEffect(Navegacion.preparando?.id) {
        if (Navegacion.preparando != null && !charla.abierta) charla.abrirPantalla()
    }

    if (enAjustes) {
        AjustesPantalla(alCerrar = { enAjustes = false })
        return
    }
    if (enNotas) {
        ApuntesPantalla(alCerrar = { enNotas = false })
        return
    }

    // Con el servidor dentro de la APK no hay nada que revisar en Ajustes:
    // los avisos dicen qué pasa y no llevan a ningún lado.
    val fijo = Datos.config.servidorFijo
    val sinServidor = when {
        !Datos.config.configurada -> "Falta decirle a la app dónde está tu servidor y con qué llave."
        servidor == Cliente.Estado.SIN_TOKEN && fijo -> "El servidor no reconoce la app. Hay que volver a instalarla."
        servidor == Cliente.Estado.SIN_TOKEN -> "El servidor está andando pero no me reconoce. Revisa el token en Ajustes."
        servidor == Cliente.Estado.INALCANZABLE && fijo -> "No llego al servidor. Revisa tu conexión a internet y vuelve a probar."
        servidor == Cliente.Estado.INALCANZABLE -> "No llego al servidor. Puede estar apagado, o la dirección puede estar mal."
        else -> null
    }

    if (!charla.abierta) {
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            Arriba(abierta = false, alIzquierda = { enNotas = true }, alAjustes = { enAjustes = true })
            sinServidor?.let { Aviso(it, if (fijo) null else "Abrir Ajustes") { enAjustes = true } }
            Portal(alAbrir = { charla.abrirPantalla() })
        }
        return
    }

    BackHandler { charla.cerrarPantalla() }
    // Sin la barra de pestañas, el borde de abajo es el de la pantalla: hay que
    // dejar lugar para la barra de gestos.
    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()) {
        Arriba(abierta = true, alIzquierda = { charla.cerrarPantalla() }, alAjustes = { enAjustes = true })
        Navegacion.preparandoVigente?.let { AvisoDePreparar(it) }
        if (sinServidor != null && !charla.activa) Aviso(sinServidor, if (fijo) null else "Abrir Ajustes") { enAjustes = true }
        charla.aviso?.let { a ->
            if (charla.puedeBajarElIdioma) Aviso(a, "Descargar el español") { charla.bajarElIdioma() }
            else Aviso(a, null, null)
        }

        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (charla.fase == Fase.CUIDADO) Cuidado(charla) else Turnos(charla)
        }

        if (charla.fase != Fase.CUIDADO) {
            if (charla.enLlamada) EnLlamada(charla)
            else Compositor(
                charla,
                alGrabar = { conMicrofono { charla.grabarUnMensaje() } },
                alLlamar = { conMicrofono { charla.arrancarLlamada() } },
            )
        }
    }
}

@Composable
private fun Arriba(abierta: Boolean, alIzquierda: () -> Unit, alAjustes: () -> Unit) {
    val p = LocalPaleta.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        // Las notas, con su nombre desde el 04/10/2026: una libreta y la palabra.
        // El lápiz que había se lee como «charla nueva» en Claude o ChatGPT.
        if (abierta) IconButton(onClick = alIzquierda) { Icon(Icons.Outlined.Close, "Salir de la conversación", tint = p.tintaSuave) }
        else Row(
            Modifier.clip(RoundedCornerShape(20.dp)).border(1.dp, p.cartaBorde, RoundedCornerShape(20.dp))
                .background(p.carta).clickable(onClick = alIzquierda).padding(horizontal = 14.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Libreta, null, tint = p.tintaSuave, modifier = Modifier.size(18.dp))
            Text("  Notas", color = p.tintaSuave, fontSize = 15.sp)
        }
        Text("Chat", Modifier.weight(1f), textAlign = TextAlign.Center, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
        // Del mismo ancho que las notas, para que el título quede centrado.
        if (!abierta) Spacer(Modifier.width(54.dp))
        IconButton(onClick = alAjustes) { Icon(Icons.Outlined.Settings, "Ajustes", tint = p.tintaSuave) }
    }
}

/**
 * Arriba de la charla, mientras se prepara una consulta: cuál es, y la cruz para
 * dejar de prepararla. Como la tarjeta de Mi expediente: el rótulo, cuándo, y
 * qué hacer.
 */
@Composable
private fun AvisoDePreparar(consulta: Evento) {
    val p = LocalPaleta.current
    Carta(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), radio = 16.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Sillon, null, tint = p.musgo, modifier = Modifier.size(22.dp))
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text("Preparando tu consulta", color = p.tintaTenue, fontSize = 12.sp)
                Text(Navegacion.cuando(consulta), fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                Text("Cuéntale qué quieres llevarle, escribiendo o en llamada.", color = p.tintaSuave, fontSize = 12.sp,
                     modifier = Modifier.padding(top = 2.dp))
            }
            IconButton(onClick = { Navegacion.preparando = null }) {
                Icon(Icons.Outlined.Close, "Dejar de preparar la consulta", tint = p.tintaSuave, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun Aviso(texto: String, boton: String?, accion: (() -> Unit)?) {
    val p = LocalPaleta.current
    Carta(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        Text(texto, color = p.tintaSuave, fontSize = 14.sp)
        if (boton != null && accion != null) {
            OutlinedButton(onClick = accion, modifier = Modifier.padding(top = 8.dp)) { Text(boton, color = p.musgo) }
        }
    }
}

/**
 * La puerta de entrada a la charla. Las ondas nacen del núcleo y se van, lento,
 * cada dos segundos y medio: alguien está del otro lado esperando. Al tocarla,
 * el portal crece y se apaga, y recién cuando terminó de irse se abre la
 * conversación: si no, las dos cosas se pisan en pantalla.
 */
@Composable
private fun Portal(alAbrir: () -> Unit) {
    val p = LocalPaleta.current
    val alcance = rememberCoroutineScope()
    val salida = remember { Animatable(0f) }

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(190.dp)
                .scale(1f + 0.9f * salida.value).alpha(1f - salida.value)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    if (salida.value > 0f) return@clickable
                    alcance.launch {
                        launch { salida.animateTo(1f, tween(420)) }
                        delay(380)
                        alAbrir()
                        salida.snapTo(0f)
                    }
                }
                .semantics { contentDescription = "Abrir la conversación" },
            contentAlignment = Alignment.Center,
        ) {
            // La marca, tranquila (26/10/2026). Reemplaza a las ondas musgo y
            // al botón con la voz que irradia.
            Anillos(tamano = 170.dp)
        }
        Text("Toca para abrir", color = p.tintaTenue, fontSize = 15.sp, modifier = Modifier.padding(top = 26.dp).alpha(1f - salida.value))
        Spacer(Modifier.height(120.dp))
    }
}

@Composable
private fun Turnos(charla: Conversacion) {
    val p = LocalPaleta.current
    val lista = rememberLazyListState()
    LaunchedEffect(charla.turnos.size, charla.turnos.lastOrNull()?.texto?.length, charla.parcial) {
        val total = charla.turnos.size + (if (charla.parcial.isNotEmpty()) 1 else 0) + 1
        lista.animateScrollToItem(total - 1)
    }
    LazyColumn(
        // Mientras Bitácora habla, tocar la conversación la corta: no cierra la charla.
        Modifier.fillMaxSize().clickable(
            enabled = charla.fase == Fase.HABLANDO,
            interactionSource = remember { MutableInteractionSource() }, indication = null,
        ) { charla.interrumpir() },
        state = lista, contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        items(charla.turnos) { Globo(it) }
        if (charla.parcial.isNotEmpty()) item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Text(charla.parcial, color = p.tintaTenue, fontStyle = FontStyle.Italic,
                     modifier = Modifier.widthIn(max = 300.dp).background(p.globoVos.copy(alpha = 0.6f), RoundedCornerShape(18.dp)).padding(12.dp))
            }
        }
        item { Estado(charla) }
    }
}

/**
 * La persona en un globo, a la derecha; Bitácora suelta, con otra letra. Lo usa
 * también el calendario para las charlas guardadas (04/10/2026): la misma charla
 * se ve igual en los dos lados. `lineas` corta el adelanto de la tarjeta.
 */
@Composable
fun Globo(t: Turno, lineas: Int = Int.MAX_VALUE) {
    val p = LocalPaleta.current
    if (t.de == Hablante.VOS) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            Text(t.texto, color = p.tinta, fontSize = 16.sp, maxLines = lineas, overflow = TextOverflow.Ellipsis,
                 modifier = Modifier.widthIn(max = 300.dp).background(p.globoVos, RoundedCornerShape(18.dp)).padding(12.dp))
        }
    } else {
        Text(t.texto, color = p.tinta, fontFamily = FontFamily.Serif, fontSize = 18.sp, lineHeight = 26.sp,
             maxLines = lineas, overflow = TextOverflow.Ellipsis,
             modifier = Modifier.fillMaxWidth().padding(end = 24.dp))
    }
}

/** Debajo de la charla: qué está pasando, cuando hay algo que decir. */
@Composable
private fun Estado(charla: Conversacion) {
    val p = LocalPaleta.current
    val texto = when (charla.fase) {
        Fase.ESCUCHANDO -> if (charla.grabando) "Grabando… toca el micrófono para mandarlo" else null
        Fase.CERRADA -> "Guardado"
        else -> null
    } ?: return
    Text(texto, color = p.tintaTenue, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 4.dp))
}

/**
 * Un campo grande con todo adentro, como en Claude o ChatGPT: el campo es el
 * centro de gravedad de la pantalla. Una sola fila; los botones abajo, donde se
 * dejaron, aunque el texto crezca.
 */
@Composable
private fun Compositor(charla: Conversacion, alGrabar: () -> Unit, alLlamar: () -> Unit) {
    val p = LocalPaleta.current
    var texto by rememberSaveable { mutableStateOf("") }
    fun mandar() {
        if (texto.isBlank()) return
        charla.enviarTexto(texto)
        texto = ""
    }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp)
            .shadow(6.dp, RoundedCornerShape(24.dp), ambientColor = Color.Black.copy(alpha = 0.05f), spotColor = Color.Black.copy(alpha = 0.05f))
            .background(p.carta, RoundedCornerShape(24.dp)).border(1.dp, p.cartaBorde, RoundedCornerShape(24.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Box(Modifier.weight(1f).padding(vertical = 9.dp, horizontal = 4.dp)) {
            if (texto.isEmpty()) Text("Escribe lo que quieras contarle…", color = p.tintaTenue, fontSize = 16.sp)
            BasicTextField(
                value = texto, onValueChange = { texto = it }, maxLines = 5,
                textStyle = TextStyle(color = p.tinta, fontSize = 16.sp), cursorBrush = SolidColor(p.musgo),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Escribe lo que quieras contarle" },
            )
        }
        Spacer(Modifier.size(6.dp))
        when {
            charla.fase == Fase.PENSANDO -> Pensando(Modifier.padding(bottom = 14.dp, end = 6.dp))
            texto.isNotBlank() -> Boton("Enviar", acentuado = true, accion = ::mandar) {
                Icon(Icons.Filled.ArrowUpward, null, tint = p.fondo, modifier = Modifier.size(20.dp))
            }
            else -> {
                Boton("Grabar un mensaje", grabando = charla.grabando, accion = alGrabar) {
                    Microfono(Modifier.size(20.dp), if (charla.grabando) p.musgo else p.tintaSuave)
                }
                Spacer(Modifier.size(8.dp))
                Boton("Abrir la llamada", acentuado = true, accion = alLlamar) {
                    VozViva(Modifier.size(20.dp), p.fondo)
                }
            }
        }
    }
}

/** Un botón del compositor. Todos del mismo tamaño y forma: sólo cambia si lleva el acento. */
@Composable
private fun Boton(nombre: String, acentuado: Boolean = false, grabando: Boolean = false, accion: () -> Unit, icono: @Composable () -> Unit) {
    val p = LocalPaleta.current
    val fondo = when {
        acentuado -> p.musgo
        grabando -> p.musgo.copy(alpha = 0.18f)
        else -> p.globoVos
    }
    Box(Modifier.size(40.dp).background(fondo, CircleShape).clickable(onClick = accion).semantics { contentDescription = nombre },
        contentAlignment = Alignment.Center) { icono() }
}

/** Tres puntos que laten: Bitácora está pensando. */
@Composable
private fun Pensando(modifier: Modifier = Modifier) {
    val p = LocalPaleta.current
    val t by rememberInfiniteTransition(label = "pensando").animateFloat(0f, 1f, infiniteRepeatable(tween(1200, easing = LinearEasing)), label = "t")
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        for (i in 0 until 3) {
            val f = ((t - i * 0.18f) % 1f + 1f) % 1f
            Box(Modifier.size(7.dp).alpha(0.3f + 0.7f * (if (f < 0.5f) f * 2 else (1 - f) * 2)).background(p.musgo, CircleShape))
        }
    }
}

/**
 * Con la llamada abierta: la voz, qué está pasando, y la cruz para cortarla. La
 * conversación sigue a la vista arriba: si algo no se escuchó bien, se lee.
 */
@Composable
private fun EnLlamada(charla: Conversacion) {
    val p = LocalPaleta.current
    val etiqueta = when (charla.fase) {
        Fase.ESCUCHANDO -> if (charla.parcial.isEmpty()) "Te escucho" else "Sigue…"
        Fase.HABLANDO -> "Bitácora… toca para cortarla"
        Fase.PENSANDO, Fase.ESPERANDO -> "Pensando…"
        else -> ""
    }
    Column(Modifier.fillMaxWidth().padding(bottom = 18.dp, top = 6.dp), horizontalAlignment = Alignment.CenterHorizontally,
           verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Los anillos, desordenados y hablando con la voz: el micrófono mientras
        // escucha, el parlante mientras habla Bitácora (26/10/2026).
        Anillos(tamano = 150.dp, activa = true, nivel = {
            when (charla.fase) {
                Fase.ESCUCHANDO -> charla.nivel
                Fase.HABLANDO -> charla.nivelDeLaVoz()
                else -> 0f
            }
        })
        if (etiqueta.isNotEmpty()) Text(etiqueta, color = p.tinta, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        Box(Modifier.size(50.dp).background(p.carta.copy(alpha = 0.7f), CircleShape).border(1.dp, p.cartaBorde, CircleShape)
                .clickable { charla.terminar() }.semantics { contentDescription = "Cortar la llamada" },
            contentAlignment = Alignment.Center) {
            Icon(Icons.Outlined.Close, null, tint = p.tintaSuave)
        }
    }
}

/** El mensaje de cuidado queda solo en la pantalla, con su panel. */
@Composable
private fun Cuidado(charla: Conversacion) {
    val p = LocalPaleta.current
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.SpaceBetween) {
        Text(charla.turnos.lastOrNull()?.texto.orEmpty(), fontFamily = FontFamily.Serif, fontSize = 19.sp,
             lineHeight = 28.sp, color = p.tinta, modifier = Modifier.padding(top = 12.dp))
        Carta(Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Outlined.FavoriteBorder, null, tint = p.bitacora)
                Text("Conversación pausada", color = p.tintaSuave, modifier = Modifier.padding(vertical = 8.dp))
                OutlinedButton(onClick = { charla.cerrarPantalla() }) { Text("Cerrar", color = p.tinta) }
            }
        }
    }
}
