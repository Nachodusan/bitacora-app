package ar.dusan.bitacora.nucleo

import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.ZonedDateTime

class DiaLogicoTest {
    @Test fun laMadrugadaEsDelDiaAnterior() {
        assertEquals("2026-10-02", DiaLogico.dia(LocalDateTime.of(2026, 10, 3, 1, 30)))
        assertEquals("2026-10-03", DiaLogico.dia(LocalDateTime.of(2026, 10, 3, 4, 0)))
    }

    @Test fun lasHorasVanComoLasPideElServidor() {
        assertEquals("2026-10-03T10:15:00", DiaLogico.paredIso(LocalDateTime.of(2026, 10, 3, 10, 15)))
        val instante = ZonedDateTime.of(2026, 10, 3, 10, 15, 7, 123, ZoneOffset.ofHours(-3))
        assertEquals("2026-10-03T10:15:07-03:00", DiaLogico.instanteIso(instante))
    }
}

class RiesgoTest {
    @Test fun lasSenalesDisparan() {
        for (f in listOf("no quiero seguir viviendo", "pensé en quitarme la vida", "Me quiero matar.",
                         "quiero desaparecer", "¡NO QUIERO VIVIR!", "tengo ganas de hacerme daño"))
            assertTrue(f, Riesgo.haySenal(f))
    }

    /** Las dos que se sacaron el 03/10/2026, y el falso positivo de siempre. */
    @Test fun loDeTodosLosDiasNoCorta() {
        for (f in listOf("me quiero morir de la vergüenza", "no aguanto más el calor",
                         "quiero recortarme el pelo", "hoy dormí mal y estoy cansado"))
            assertFalse(f, Riesgo.haySenal(f))
    }

    @Test fun elMensajeTraeEl4141YSeDiceComoSeMarca() {
        assertTrue(Riesgo.mensaje.contains("*4141"))
        assertFalse(Riesgo.mensaje.contains("?"))
        assertEquals("Llama al asterisco cuatro uno cuatro uno.", Riesgo.paraDecir("Llama al *4141."))
        assertEquals("son 41410 pesos", Riesgo.paraDecir("son 41410 pesos"))
    }
}

class CharlaTest {
    @Test fun laTranscripcionLlevaLosRotulos() {
        val t = listOf(Turno(Hablante.VOS, "hola"), Turno(Hablante.BITACORA, "¿Cómo estás?"))
        assertEquals("Vos: hola\nBitácora: ¿Cómo estás?", Transcripcion.de(t))
        assertEquals("hola", Transcripcion.soloVos(t))
    }

    @Test fun losTurnosVuelvenComoSeGuardaron() {
        val turnos = listOf(Turno(Hablante.VOS, "hola"), Turno(Hablante.BITACORA, "¿Cómo estás?"), Turno(Hablante.VOS, "bien"))
        assertEquals(turnos, Transcripcion.turnos(Transcripcion.de(turnos)))
        assertEquals(listOf(Turno(Hablante.VOS, "primero\nsegundo"), Turno(Hablante.BITACORA, "Te escucho.")),
                     Transcripcion.turnos("Vos: primero\nsegundo\nLaya: Te escucho."))
        assertEquals(listOf(Turno(Hablante.VOS, "hoy dormí poco")), Transcripcion.turnos("hoy dormí poco"))
    }

    @Test fun laDuracionSeEscribeEnMinutos() {
        assertEquals("menos de 1 min", Transcripcion.duracion(3.0))
        assertEquals("7 min", Transcripcion.duracion(420.0))
        assertEquals("2 min", Transcripcion.duracion(95.0))
    }

    @Test fun unaFraseColgadaSigueAbierta() {
        for (f in listOf("Hoy fui al trabajo y", "Lo que pasa es que,", "No sé, o sea", "Estaba pensando…", "porque."))
            assertTrue(f, FinDeTurno.quedoColgado(f))
        for (f in listOf("Hoy fui al trabajo.", "¿Qué me recomiendas?", "estoy bien"))
            assertFalse(f, FinDeTurno.quedoColgado(f))
        assertEquals("hoy fui y me cansé", FinDeTurno.unir("hoy fui y", " me cansé"))
    }
}

class TramasTest {
    private fun trama(tipo: Char, cuerpo: ByteArray) = Buffer().apply {
        writeByte(tipo.code); writeInt(cuerpo.size); write(cuerpo)
    }

    @Test fun leeCadaTipoYSalteaLoQueNoConoce() {
        val b = Buffer()
        b.writeAll(trama('T', "Hola.".toByteArray()))
        b.writeAll(trama('Z', "algo nuevo".toByteArray()))
        b.writeAll(trama('H', "24000".toByteArray()))
        b.writeAll(trama('F', """{"ok":true,"texto":"Hola. ¿Qué tal?","hablado":5}""".toByteArray()))
        assertEquals(Trama.Texto("Hola."), Tramas.leer(b))
        assertEquals(Trama.Frecuencia(24000), Tramas.leer(b))
        assertEquals(Trama.Fin(true, "Hola. ¿Qué tal?", "¿Qué tal?"), Tramas.leer(b))
        assertNull(Tramas.leer(b))
    }

    @Test fun elCorteDeRiesgoDelServidorLlegaComoCuidado() {
        val f = Tramas.decodificar('F', """{"ok":true,"texto":"Gracias por decirlo aquí.","hablado":0,"cuidado":true}""".toByteArray())
        assertEquals(Trama.Cuidado("Gracias por decirlo aquí."), f)
    }
}

class ResumenTest {
    @Test fun elMes() {
        assertEquals("2026-09-01" to "2026-09-30", Resumen.mes("2026-09"))
        assertEquals("2028-02-01" to "2028-02-29", Resumen.mes("2028-02"))
    }

    @Test fun elTramoEscrito() {
        assertEquals("septiembre de 2026", Resumen.escrito("2026-09-01", "2026-09-30"))
        assertEquals("15 de septiembre de 2026", Resumen.escrito("2026-09-15", "2026-09-15"))
        assertEquals("del 15 al 16 de septiembre de 2026", Resumen.escrito("2026-09-15", "2026-09-16"))
        assertEquals("del 28 de septiembre al 3 de octubre de 2026", Resumen.escrito("2026-09-28", "2026-10-03"))
        assertEquals("del 28 de diciembre de 2026 al 3 de enero de 2027", Resumen.escrito("2026-12-28", "2027-01-03"))
        assertEquals("del 1 al 29 de septiembre de 2026", Resumen.escrito("2026-09-01", "2026-09-29"))
    }

    @Test fun lasFechasYElOrden() {
        assertEquals("Martes 15 de septiembre", Resumen.fechaConDia("2026-09-15"))
        val notas = listOf(NotaDelDia("2026-09-16", "21:00"), NotaDelDia("2026-09-15", "23:30"))
        assertEquals(listOf("2026-09-15", "2026-09-16"), Resumen.enOrden(notas).map { it.dia })
    }

    /** Lo primero que lee el psicólogo dice qué es y qué no es, con o sin nombre. */
    @Test fun elAviso() {
        assertTrue(Resumen.aviso("Tomás").startsWith("Son frases de Tomás,"))
        assertTrue(Resumen.aviso(" ").startsWith("Son frases de la persona,"))
        assertTrue(Resumen.aviso(null).contains("No es un informe clínico ni un diagnóstico"))
        assertEquals("De Tomás · 15 y 16 de septiembre de 2026 · preparado con Bitácora el 4 de octubre de 2026",
                     Resumen.encabezado("Tomás", "15 y 16 de septiembre de 2026", "2026-10-04"))
    }

    /** Lo que dijo la persona, turno por turno; lo de Bitácora no va. */
    @Test fun loQueDijoEnLaCharla() {
        val t = "Vos: Hola.\nBitácora: Hola, ¿cómo estás?\nSegundo párrafo de Bitácora.\n" +
            "Vos: Me ofrecieron otra pega.\nY no sé qué hacer.\nLaya: Una línea vieja.\nVos:   \n"
        assertEquals(listOf("Hola.", "Me ofrecieron otra pega.\nY no sé qué hacer."), Transcripcion.loQueDijo(t))
        assertEquals(emptyList<String>(), Transcripcion.loQueDijo(""))
    }

    @Test fun losDiasSueltos() {
        assertEquals("15 y 16 de septiembre de 2026", Resumen.escrito(listOf("2026-09-16", "2026-09-15"), false))
        assertEquals("15 de septiembre de 2026", Resumen.escrito(listOf("2026-09-15"), false))
        assertEquals("3, 10 y 24 de septiembre de 2026", Resumen.escrito(listOf("2026-09-03", "2026-09-24", "2026-09-10"), false))
        assertEquals("28 y 30 de septiembre y 2 de octubre de 2026", Resumen.escrito(listOf("2026-09-28", "2026-09-30", "2026-10-02"), false))
        assertEquals("30 de diciembre de 2026 y 2 de enero de 2027", Resumen.escrito(listOf("2026-12-30", "2027-01-02"), false))
        val ocho = listOf("03", "05", "07", "10", "12", "15", "20", "24").map { "2026-09-$it" }
        assertEquals("8 días, del 3 al 24 de septiembre de 2026", Resumen.escrito(ocho, false))
        assertEquals("septiembre de 2026", Resumen.escrito(ocho, true))
        assertEquals("ningún día", Resumen.escrito(emptyList(), false))
    }
}

class ProximaConsultaTest {
    @Test fun esLaConfirmadaQueNoPaso() {
        val eventos = listOf(
            Evento(1, tipo = "consulta", dia = "2026-10-02", hora = "19:00"),
            Evento(2, tipo = "consulta", dia = "2026-10-16", hora = "19:00"),
            Evento(3, tipo = "consulta", dia = "2026-10-09", hora = "19:00"),
            Evento(4, tipo = "otro", dia = "2026-10-07", hora = "10:00"),
            Evento(5, tipo = "consulta", dia = "2026-10-08", origen = "bitacora", estado = "propuesto"),
        )
        assertEquals(3, Evento.proximaConsulta(eventos, "2026-10-06 10:00")?.id)
        // Una hora después de empezar ya pasó: sigue la de la semana siguiente.
        assertEquals(2, Evento.proximaConsulta(eventos, "2026-10-09 20:00")?.id)
        assertNull(Evento.proximaConsulta(eventos, "2026-10-17 08:00"))
    }

    @Test fun sinHoraCuentaElMediodiaComoElServidor() {
        val e = listOf(Evento(1, tipo = "consulta", dia = "2026-10-09"))
        assertEquals(1, Evento.proximaConsulta(e, "2026-10-09 11:59")?.id)
        assertNull(Evento.proximaConsulta(e, "2026-10-09 12:00"))
    }

    @Test fun cuantoFalta() {
        assertEquals("hoy", Evento.cuantoFalta("2026-10-06", "2026-10-06"))
        assertEquals("mañana", Evento.cuantoFalta("2026-10-07", "2026-10-06"))
        assertEquals("en 3 días", Evento.cuantoFalta("2026-10-09", "2026-10-06"))
        assertEquals("en 3 días", Evento.cuantoFalta("2026-11-02", "2026-10-30"))
    }

    @Test fun preparaSoloSiVieneLaConsulta() {
        val sin = json.encodeToString(PedidoDeCharla.serializer(), PedidoDeCharla(emptyList(), "2026-10-06"))
        assertFalse(sin.contains("preparar"))
        val con = json.encodeToString(PedidoDeCharla.serializer(), PedidoDeCharla(emptyList(), "2026-10-06", preparar = 7))
        assertTrue(con.contains("\"preparar\":7"))
    }

    @Test
    fun elRegistroSeOrdenaPorTipoYSeLeeSinElCampo() {
        val r = listOf(NotaDelDia.Registro("habito", "comer de noche", "como todas las noches"),
                       NotaDelDia.Registro("raro", "x", "y"),
                       NotaDelDia.Registro("emocion", "bronca", "me dio bronca"))
        assertEquals(listOf("Emoción", "Hábito"), Resumen.registroOrdenado(r).map { it.first })
        val vieja = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
            .decodeFromString(NotaDelDia.serializer(), """{"dia":"2026-09-15","hora":"21:00","citas":[]}""")
        assertEquals(emptyList<NotaDelDia.Registro>(), vieja.registro)
    }
}
