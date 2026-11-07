package ar.dusan.bitacora.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import ar.dusan.bitacora.datos.Datos
import ar.dusan.bitacora.nucleo.PerfilDeCuenta
import ar.dusan.bitacora.nucleo.ResultadoDeCuenta
import kotlinx.coroutines.launch
import java.text.Collator
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.TimeZone

/**
 * Las cuentas (28/10/2026). Es `Registro.swift`. Al final de la bienvenida:
 * crear una cuenta o entrar a una con el ID y el PIN.
 *
 * CREAR pide lo que no sale de las charlas: cómo te llamo, cuándo naciste, el
 * país y la ciudad, y con quién vives. Todo se puede dejar en blanco. Después
 * un PIN de seis dígitos dos veces, y el servidor da el ID. Si se olvida el
 * PIN no hay cómo recuperarlo todavía: se crea otra cuenta.
 */
@Composable
fun Registro(alTerminar: (PerfilDeCuenta) -> Unit) {
    val alcance = rememberCoroutineScope()
    var paso by rememberSaveable { mutableStateOf("elegir") }
    var perfil by remember { mutableStateOf(PerfilDeCuenta()) }
    var pin by rememberSaveable { mutableStateOf("") }
    var pin2 by rememberSaveable { mutableStateOf("") }
    var id by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var esperando by remember { mutableStateOf(false) }
    val c = Datos.config

    fun crear() {
        if (pin != pin2) { error = "No coinciden. Elige el PIN otra vez."; pin = ""; pin2 = ""; paso = "pin"; return }
        esperando = true
        alcance.launch {
            when (val r = Datos.cliente().crearCuenta(pin, perfil, TimeZone.getDefault().id)) {
                is ResultadoDeCuenta.Lista -> { c.sesion = r.token; c.cuentaId = r.id; error = null; paso = "id" }
                else -> error = "No se pudo crear la cuenta. Revisa la conexión y prueba de nuevo."
            }
            esperando = false
        }
    }
    fun entrar() {
        esperando = true
        alcance.launch {
            when (val r = Datos.cliente().entrar(id, pin)) {
                is ResultadoDeCuenta.Lista -> {
                    c.sesion = r.token
                    val pf = Datos.cliente().perfil()
                    c.cuentaId = pf?.id
                    alTerminar(pf ?: PerfilDeCuenta())
                }
                ResultadoDeCuenta.Incorrecto -> { error = "El ID o el PIN no son correctos."; pin = "" }
                ResultadoDeCuenta.Trabada -> { error = "Hubo muchos intentos. Espera unos minutos y vuelve a probar."; pin = "" }
                ResultadoDeCuenta.SinServidor -> error = "No se pudo conectar. Revisa la conexión."
            }
            esperando = false
        }
    }

    Column(Modifier.fillMaxSize().imePadding().padding(horizontal = 30.dp).padding(bottom = 24.dp)) {
        when (paso) {
            "elegir" -> {
                Spacer(Modifier.weight(1f))
                Titulo("Tu cuenta")
                Explicacion("Lo que hables con Bitácora queda en tu cuenta, separado de cualquier otra persona.")
                Spacer(Modifier.weight(1f))
                Ancho("Crear mi cuenta") { paso = "datos" }
                TextButton({ error = null; paso = "entrar" }, Modifier.fillMaxWidth().padding(top = 8.dp)) {
                    Text("Ya tengo una cuenta", color = LocalPaleta.current.musgo, fontWeight = FontWeight.SemiBold)
                }
            }
            "datos" -> DatosDelRegistro(perfil, { perfil = it }) { paso = "pin" }
            "pin" -> PedirPin("Elige un PIN\nde 6 dígitos", error ?: "Con él y tu ID vuelves a entrar si cambias de teléfono o reinstalas la app.",
                              pin, { pin = it }, esperando) { error = null; paso = "repetir" }
            "repetir" -> PedirPin("Repítelo", error ?: "Para estar seguros de que es el que quieres.", pin2, { pin2 = it }, esperando) { crear() }
            "id" -> MostrarId(c.cuentaId.orEmpty()) { alTerminar(perfil) }
            else -> {
                BackHandler { error = null; pin = ""; paso = "elegir" }
                Spacer(Modifier.weight(1f))
                Titulo("Entrar")
                Etiqueta("Tu ID")
                Campo(id, { id = it.uppercase().take(8) }, "ABC-123", mono = true)
                Etiqueta("Tu PIN")
                CampoDePin(pin, { pin = it }, enfocar = false)
                error?.let { Text(it, color = LocalPaleta.current.rojo, fontSize = 15.sp, modifier = Modifier.padding(top = 14.dp)) }
                Spacer(Modifier.weight(1f))
                Ancho(if (esperando) "Un momento…" else "Entrar", pin.length == 6 && id.length >= 6 && !esperando) { entrar() }
                TextButton({ error = null; pin = ""; paso = "elegir" }, Modifier.fillMaxWidth().padding(top = 6.dp)) {
                    Text("Volver", color = LocalPaleta.current.tintaSuave)
                }
            }
        }
    }
}

/**
 * Para el diario que ya existía antes de las cuentas: elige su PIN una vez,
 * recibe su ID y de paso completa lo del registro. Es `ElegirPinView` de iOS.
 */
@Composable
fun ElegirPin(alTerminar: () -> Unit) {
    val p = LocalPaleta.current
    val alcance = rememberCoroutineScope()
    var paso by rememberSaveable { mutableStateOf(0) }
    var perfil by remember { mutableStateOf(PerfilDeCuenta(nombre = Datos.config.nombre.ifBlank { null })) }
    var pin by rememberSaveable { mutableStateOf("") }
    var pin2 by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    fun guardar() {
        if (pin != pin2) { error = "No coinciden. Elige el PIN otra vez."; pin = ""; pin2 = ""; paso = 2; return }
        alcance.launch {
            when (val r = Datos.cliente().elegirPin(pin)) {
                is ResultadoDeCuenta.Lista -> {
                    Datos.config.sesion = r.token
                    Datos.config.cuentaId = r.id
                    Datos.cliente().guardarPerfil(perfil)
                    perfil.nombre?.let { Datos.config.nombre = it }
                    error = null; paso = 4
                }
                else -> { error = "No se pudo guardar. Revisa la conexión."; pin = ""; pin2 = ""; paso = 2 }
            }
        }
    }

    Box(Modifier.fillMaxSize().background(p.fondo)) {
        Column(Modifier.fillMaxSize().imePadding().padding(horizontal = 30.dp).padding(bottom = 24.dp, top = 40.dp)) {
            when (paso) {
                0 -> {
                    Spacer(Modifier.weight(1f))
                    Titulo("Bitácora ahora\ntiene cuentas")
                    Explicacion("Tu diario sigue igual. Solo falta que elijas un PIN: con él y tu ID entras si cambias de teléfono. " +
                                "Antes, unos datos que no salen de las charlas.")
                    Spacer(Modifier.weight(1f))
                    Ancho("Seguir") { paso = 1 }
                }
                1 -> DatosDelRegistro(perfil, { perfil = it }) { paso = 2 }
                2 -> PedirPin("Elige un PIN\nde 6 dígitos", error ?: "Con él y tu ID vuelves a entrar si cambias de teléfono.",
                              pin, { pin = it }, false) { error = null; paso = 3 }
                3 -> PedirPin("Repítelo", error ?: "Para estar seguros de que es el que quieres.", pin2, { pin2 = it }, false) { guardar() }
                else -> MostrarId(Datos.config.cuentaId.orEmpty(), alTerminar)
            }
        }
    }
}

/** Los datos del registro, en una sola pantalla. Todos se pueden dejar en blanco. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DatosDelRegistro(perfil: PerfilDeCuenta, cambiar: (PerfilDeCuenta) -> Unit, listo: () -> Unit) {
    val p = LocalPaleta.current
    var eligiendoFecha by remember { mutableStateOf(false) }
    var eligiendoPais by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Titulo("Para conocerte", Modifier.padding(top = 50.dp))
        Explicacion("Lo que no quieras contar, déjalo en blanco.")
        Etiqueta("¿Cómo quieres que te llame?")
        Campo(perfil.nombre.orEmpty(), { cambiar(perfil.copy(nombre = it.take(40).ifBlank { null })) })

        // La fecha y no la edad: así la edad se mantiene al día sola.
        Etiqueta("¿Cuándo naciste?")
        Elegible(perfil.fechaNacimiento?.let { fechaLarga(it) }, "Elegir la fecha", quitar = perfil.fechaNacimiento?.let {
            { cambiar(perfil.copy(fechaNacimiento = null)) } }) { eligiendoFecha = true }

        // Primero el país, después la ciudad (28/10/2026).
        Etiqueta("¿Dónde vives?")
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Box(Modifier.weight(1f)) { Elegible(perfil.pais, "País") { eligiendoPais = true } }
            Box(Modifier.weight(1f)) {
                if (perfil.pais == null) Elegible(null, "Ciudad", habilitado = false) {}
                else Campo(perfil.ciudad.orEmpty(), { cambiar(perfil.copy(ciudad = it.take(60).ifBlank { null })) }, "Ciudad")
            }
        }

        Etiqueta("¿Con quién vives? (opcional)")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (o in listOf("Solo/a", "Familia", "Pareja", "Amigos")) {
                val elegido = perfil.conQuien == o
                Text(o, color = if (elegido) p.fondo else p.tinta, fontSize = 15.sp,
                     fontWeight = if (elegido) FontWeight.SemiBold else FontWeight.Normal,
                     modifier = Modifier.clickable { cambiar(perfil.copy(conQuien = if (elegido) null else o)) }
                         .background(if (elegido) p.musgo else p.carta, RoundedCornerShape(50))
                         .border(1.dp, if (elegido) p.musgo else p.cartaBorde, RoundedCornerShape(50))
                         .padding(horizontal = 12.dp, vertical = 8.dp))
            }
        }
        Spacer(Modifier.height(28.dp))
        Ancho("Seguir", onClick = listo)
        Spacer(Modifier.height(20.dp))
    }

    if (eligiendoFecha) {
        val inicial = perfil.fechaNacimiento?.let { LocalDate.parse(it) } ?: LocalDate.of(2000, 1, 1)
        val estado = rememberDatePickerState(
            initialSelectedDateMillis = inicial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            yearRange = 1900..LocalDate.now().year)
        DatePickerDialog(
            onDismissRequest = { eligiendoFecha = false },
            confirmButton = { TextButton({
                estado.selectedDateMillis?.let {
                    val d = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                    if (!d.isAfter(LocalDate.now())) cambiar(perfil.copy(fechaNacimiento = d.toString()))
                }
                eligiendoFecha = false
            }) { Text("Listo") } },
            dismissButton = { TextButton({ eligiendoFecha = false }) { Text("Cancelar") } },
        ) { DatePicker(estado, title = { Text("¿Cuándo naciste?", Modifier.padding(start = 24.dp, top = 16.dp)) }) }
    }
    if (eligiendoPais) ElegirPais({ eligiendoPais = false }) { pais ->
        cambiar(perfil.copy(pais = pais, ciudad = if (pais == perfil.pais) perfil.ciudad else null))
        eligiendoPais = false
    }
}

/** Todos los países, con su nombre en español, y un buscador. */
@Composable
private fun ElegirPais(alCerrar: () -> Unit, elegir: (String) -> Unit) {
    val p = LocalPaleta.current
    val es = Locale.forLanguageTag("es")
    val todos = remember {
        Locale.getISOCountries().map { Locale.Builder().setRegion(it).build().getDisplayCountry(es) }
            .filter { it.isNotBlank() }.sortedWith(Collator.getInstance(es))
    }
    var buscar by remember { mutableStateOf("") }
    val sinTildes = { t: String -> java.text.Normalizer.normalize(t, java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").lowercase() }
    Dialog(onDismissRequest = alCerrar) {
        Column(Modifier.fillMaxWidth().height(560.dp).background(p.fondo, RoundedCornerShape(24.dp)).padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("País", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.weight(1f))
                IconButton(alCerrar) { Icon(Icons.Outlined.Close, "Cerrar", tint = p.tintaSuave) }
            }
            Campo(buscar, { buscar = it }, "Buscar país")
            LazyColumn(Modifier.padding(top = 8.dp)) {
                items(todos.filter { buscar.isBlank() || sinTildes(it).contains(sinTildes(buscar.trim())) }) { pais ->
                    Text(pais, fontSize = 17.sp, modifier = Modifier.fillMaxWidth().clickable { elegir(pais) }.padding(vertical = 12.dp))
                }
            }
        }
    }
}

@Composable
private fun ColumnScope.PedirPin(titulo: String, detalle: String, valor: String, cambiar: (String) -> Unit, esperando: Boolean, listo: () -> Unit) {
    Spacer(Modifier.height(80.dp))
    Titulo(titulo)
    Explicacion(detalle)
    Spacer(Modifier.height(24.dp))
    CampoDePin(valor, cambiar)
    Spacer(Modifier.height(24.dp))
    Ancho(if (esperando) "Un momento…" else "Seguir", valor.length == 6 && !esperando, listo)
}

/** Seis puntos que se llenan; el teclado numérico va por detrás. */
@Composable
private fun CampoDePin(valor: String, cambiar: (String) -> Unit, enfocar: Boolean = true) {
    val p = LocalPaleta.current
    val foco = remember { FocusRequester() }
    Box(Modifier.fillMaxWidth().padding(top = 10.dp), contentAlignment = Alignment.Center) {
        androidx.compose.foundation.text.BasicTextField(
            valor, { cambiar(it.filter(Char::isDigit).take(6)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            visualTransformation = PasswordVisualTransformation(),
            textStyle = TextStyle(color = Color.Transparent),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(Color.Transparent),
            modifier = Modifier.matchParentSize().focusRequester(foco),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.clickable { foco.requestFocus() }) {
            for (i in 0 until 6) Box(Modifier.size(18.dp)
                .background(if (i < valor.length) p.musgo else Color.Transparent, CircleShape)
                .border(1.5.dp, if (i < valor.length) p.musgo else p.tintaSuave.copy(alpha = 0.4f), CircleShape))
        }
    }
    if (enfocar) LaunchedEffect(Unit) { foco.requestFocus() }
}

@Composable
private fun ColumnScope.MostrarId(id: String, alTerminar: () -> Unit) {
    val p = LocalPaleta.current
    Spacer(Modifier.height(120.dp))
    Titulo("Este es tu ID")
    Text(id, color = p.musgo, fontSize = 44.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold,
         modifier = Modifier.padding(top = 22.dp))
    Explicacion("Anótalo en un lugar seguro. Con tu ID y tu PIN vuelves a entrar si cambias de teléfono. " +
                "Si los pierdes, no hay forma de recuperarlos. También lo ves en Mi espacio.")
    Spacer(Modifier.weight(1f))
    Ancho("Lo anoté, empezar", onClick = alTerminar)
}

@Composable
private fun Titulo(t: String, modifier: Modifier = Modifier) =
    Text(t, color = LocalPaleta.current.tinta, fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold, modifier = modifier)

@Composable
private fun Explicacion(t: String) =
    Text(t, color = LocalPaleta.current.tintaSuave, fontSize = 16.sp, lineHeight = 23.sp, modifier = Modifier.padding(top = 12.dp))

@Composable
private fun Etiqueta(t: String) =
    Text(t, color = LocalPaleta.current.tintaTenue, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 22.dp))

@Composable
private fun Campo(valor: String, cambiar: (String) -> Unit, marca: String = "", mono: Boolean = false) {
    val p = LocalPaleta.current
    TextField(
        valor, cambiar, singleLine = true,
        placeholder = { if (marca.isNotEmpty()) Text(marca, color = p.tintaTenue) },
        keyboardOptions = KeyboardOptions(capitalization = if (mono) KeyboardCapitalization.Characters else KeyboardCapitalization.Words),
        textStyle = TextStyle(fontSize = 19.sp, color = p.tinta, fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = p.musgo, unfocusedIndicatorColor = p.tintaSuave.copy(alpha = 0.3f), cursorColor = p.musgo,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
}

/** Un campo que se toca para elegir. */
@Composable
private fun Elegible(valor: String?, marca: String, habilitado: Boolean = true, quitar: (() -> Unit)? = null, alTocar: () -> Unit) {
    val p = LocalPaleta.current
    Column(Modifier.fillMaxWidth().clickable(enabled = habilitado, onClick = alTocar)) {
        Row(Modifier.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(valor ?: marca, fontSize = 19.sp, modifier = Modifier.weight(1f),
                 color = if (valor == null) p.tintaTenue.copy(alpha = if (habilitado) 0.9f else 0.4f) else p.tinta)
            if (quitar != null) IconButton(quitar, Modifier.size(24.dp)) { Icon(Icons.Outlined.Close, "Quitar", tint = p.tintaTenue) }
            else Icon(Icons.Outlined.KeyboardArrowDown, null, tint = p.tintaTenue.copy(alpha = if (habilitado) 1f else 0.4f))
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(p.tintaSuave.copy(alpha = 0.3f)))
    }
}

@Composable
private fun Ancho(texto: String, habilitado: Boolean = true, onClick: () -> Unit) {
    val p = LocalPaleta.current
    Button(onClick, enabled = habilitado, modifier = Modifier.fillMaxWidth().height(52.dp),
           colors = ButtonDefaults.buttonColors(containerColor = p.musgo, contentColor = p.fondo,
                                                disabledContainerColor = p.tintaSuave.copy(alpha = 0.18f),
                                                disabledContentColor = p.tintaSuave)) {
        Text(texto, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

private fun fechaLarga(dia: String): String =
    LocalDate.parse(dia).format(DateTimeFormatter.ofPattern("d 'de' MMMM 'de' yyyy", Locale.forLanguageTag("es")))
