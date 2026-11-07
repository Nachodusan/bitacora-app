import XCTest
@testable import BitacoraCore

final class HerramientasTests: XCTestCase {
    func testElCuerpoAceleradoOfreceRespirar() {
        XCTAssertEqual(Herramienta.sugerida(para: "Siento el pecho apretado y no puedo respirar"), .calmarme)
        XCTAssertEqual(Herramienta.sugerida(para: "Tengo un ataque de pánico"), .calmarme)
        XCTAssertEqual(Herramienta.sugerida(para: "Estoy muy nerviosa por mañana"), .calmarme)
    }

    func testSinPalabrasOfrecePonerleNombre() {
        XCTAssertEqual(Herramienta.sugerida(para: "No sé cómo me siento, la verdad"), .nombrar)
        XCTAssertEqual(Herramienta.sugerida(para: "No me sale la palabra para esto"), .nombrar)
        XCTAssertEqual(Herramienta.sugerida(para: "Me siento raro desde ayer"), .nombrar)
    }

    func testLasDosALaVezRespirarPrimero() {
        XCTAssertEqual(Herramienta.sugerida(para: "No sé qué siento, pero tengo mucha ansiedad"), .calmarme)
    }

    func testUnaCharlaComunNoOfreceNada() {
        XCTAssertNil(Herramienta.sugerida(para: "Hoy almorcé con mi mamá y estuvo lindo"))
        XCTAssertNil(Herramienta.sugerida(para: "Mi jefe me gritó y tengo rabia"))
    }

    func testConRiesgoNoSeOfreceNada() {
        XCTAssertNil(Herramienta.sugerida(para: "Tengo ansiedad y ya no quiero vivir"))
    }

    func testLoQueEntraALaCharla() {
        XCTAssertEqual(Herramienta.loQueElegiste("frustración", intensidad: 8),
                       "Le puse nombre a lo que siento: frustración, 8 de 10.")
        XCTAssertEqual(Herramienta.respire(minutos: 3, mejor: true),
                       "Respiré 3 minutos con la app. Ya estoy un poco mejor.")
    }
}

extension HerramientasTests {
    /// Bitácora ofrece la respiración por su cuenta (charla del 27/10/2026, 3 a. m.):
    /// el botón tiene que aparecer aunque la persona no haya dicho nada del cuerpo.
    func testLaHerramientaOfrecidaPorBitacoraTraeElBoton() {
        XCTAssertEqual(Herramienta.ofrecida(en: "Si quieres, abajo tienes una respiración guiada; puede servir."), .calmarme)
        XCTAssertEqual(Herramienta.ofrecida(en: "Si quieres, abajo puedes ponerle nombre a lo que sientes."), .nombrar)
        XCTAssertNil(Herramienta.ofrecida(en: "Mañana lo retomas con la cabeza más fresca."))
    }
}
