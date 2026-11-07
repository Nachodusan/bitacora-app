import XCTest
@testable import BitacoraCore

/// El formato en que la conversación llega a `entradas.transcripcion`.
final class TranscripcionTests: XCTestCase {

    /// Desde el 02/10/2026 la compañera se llama Bitácora, y así se rotula.
    /// `Vos:` no se toca: de ese rótulo depende la verificación de las citas.
    func testCadaLineaVaConSuRotulo() {
        let t = Transcripcion.de([Turno(de: .vos, texto: "hola"),
                                  Turno(de: .bitacora, texto: "¿Cómo estás?")])
        XCTAssertEqual(t, "Vos: hola\nBitácora: ¿Cómo estás?")
    }

    /// Las conversaciones de antes del cambio de nombre: sólo el rótulo, al
    /// principio de la línea. Lo que la persona dijo queda como estaba.
    func testElRotuloViejoSeRenombraSinTocarLoDicho() {
        let vieja = "Vos: hola, Laya\nLaya: Hola. ¿Cómo estás?\nVos: bien\nLaya: Me alegra."
        XCTAssertEqual(Transcripcion.conRotuloNuevo(vieja),
                       "Vos: hola, Laya\nBitácora: Hola. ¿Cómo estás?\nVos: bien\nBitácora: Me alegra.")
        let nueva = Transcripcion.conRotuloNuevo(vieja)
        XCTAssertEqual(Transcripcion.conRotuloNuevo(nueva), nueva, "correrlo de nuevo no cambia nada")
    }

    /// La vuelta de `de(_:)`: lo que se guardó se lee en los mismos turnos.
    func testLosTurnosVuelvenComoSeGuardaron() {
        let turnos = [Turno(de: .vos, texto: "hola"), Turno(de: .bitacora, texto: "¿Cómo estás?"),
                      Turno(de: .vos, texto: "bien")]
        XCTAssertEqual(Transcripcion.turnos(Transcripcion.de(turnos)), turnos)
    }

    /// Un turno de varios párrafos sigue siendo uno, y el rótulo viejo se lee
    /// como Bitácora.
    func testLosParrafosQuedanEnSuTurno() {
        let t = Transcripcion.turnos("Vos: primero\nsegundo\nLaya: Te escucho.")
        XCTAssertEqual(t, [Turno(de: .vos, texto: "primero\nsegundo"), Turno(de: .bitacora, texto: "Te escucho.")])
    }

    /// Una entrada sin rótulos, de antes de la charla, es toda de la persona.
    func testSinRotulosEsDeLaPersona() {
        XCTAssertEqual(Transcripcion.turnos("hoy dormí poco"), [Turno(de: .vos, texto: "hoy dormí poco")])
        XCTAssertEqual(Transcripcion.turnos(""), [])
    }

    func testLaDuracionSeEscribeEnMinutos() {
        XCTAssertEqual(Transcripcion.duracion(segundos: 3), "menos de 1 min")
        XCTAssertEqual(Transcripcion.duracion(segundos: 420), "7 min")
        XCTAssertEqual(Transcripcion.duracion(segundos: 95), "2 min")
    }

    func testSoloVosNoTraeLoQueDijoBitacora() {
        let s = Transcripcion.soloVos([Turno(de: .bitacora, texto: "¿Quieres desaparecer?"),
                                       Turno(de: .vos, texto: "no")])
        XCTAssertEqual(s, "no")
    }
}
