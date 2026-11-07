import XCTest
@testable import BitacoraCore

final class TrozosDeVozTests: XCTestCase {

    func testUnaFraseCortaNoSePartE() {
        XCTAssertEqual(TrozosDeVoz.partir("Dale, contame."), ["Dale, contame."])
    }

    func testVacioNoDaNada() {
        XCTAssertEqual(TrozosDeVoz.partir("   \n "), [])
    }

    /// Lo que importa: el PRIMER pedazo tiene que ser corto, porque es el único
    /// que se escucha como espera. Los que siguen se generan mientras suena.
    func testElPrimerPedazoEsCorto() {
        let largo = """
        Entiendo lo que decís y me parece que tiene sentido. Ahora, si mirás el \
        problema desde otro lado, capaz aparece algo distinto. Muchas veces lo \
        que traba no es lo que uno cree que traba. Podés probar por ahí y ver \
        qué pasa con eso durante unos días.
        """
        let p = TrozosDeVoz.partir(largo)
        XCTAssertGreaterThan(p.count, 1, "un texto largo tiene que partirse")
        XCTAssertLessThanOrEqual(p[0].count, 120, "el primero es el que hace esperar")
    }

    /// Nada se pierde ni se duplica: pegando los pedazos vuelve el original.
    func testNoSePierdeNiSeAgregaTexto() {
        let textos = [
            "Hola. ¿Cómo venís? Contame lo que quieras, sin apuro.",
            "Primero pensá qué te pesa. Después fijate si se puede cambiar. Si no, hablamos.",
            "Una sola oración larga sin ningún punto adentro que igual hay que decir entera",
        ]
        for t in textos {
            let junto = TrozosDeVoz.partir(t).joined(separator: " ")
            XCTAssertEqual(junto.replacingOccurrences(of: "  ", with: " "), t,
                           "los pedazos pegados tienen que dar el texto original")
        }
    }

    /// Un punto adentro de un número no termina una frase.
    func testNoCortaEnMedioDeUnNumero() {
        let t = "Te salen 3.500 pesos por mes si lo pagás de esa manera, más o menos, "
              + "contando el aumento que ya está anunciado para el mes que viene y que "
              + "todavía no se aplicó del todo en las facturas que te llegaron."
        XCTAssertEqual(TrozosDeVoz.partir(t), [t], "un punto entre dígitos no corta")
    }

    /// Ni una abreviatura.
    func testNoCortaDespuesDeUnaAbreviatura() {
        let t = "Lo atendió el Dr. pérez y le dijo que estaba todo bien, que se quedara "
              + "tranquilo y que volviera en un mes para control, así que por ese lado "
              + "podés estar tranquilo vos también con todo esto."
        XCTAssertEqual(TrozosDeVoz.partir(t).count, 1, "minúscula después del punto")
    }

    /// Una cola muy corta se pega al pedazo anterior en vez de pedirse sola:
    /// un pedido entero para decir "Dale." mete un silencio y cuesta igual.
    func testLaColaCortaSePega() {
        let t = "Pensalo con calma, que no hay ningún apuro con esto que me venís "
              + "contando hoy y que claramente te viene dando vueltas hace rato. "
              + "Tomate los días que necesites para decidirlo bien. Dale."
        let p = TrozosDeVoz.partir(t)
        XCTAssertFalse(p.contains("Dale."), "no se pide un audio para una palabra: \(p)")
    }

    /// Una respuesta corta se dice de una: partirla cuesta dos pedidos y
    /// ahorra medio segundo. La espera que molesta es la de las largas.
    func testUnaRespuestaCortaNoSeParte() {
        let t = "Eso suena pesado y se entiende que te tenga así. ¿Qué fue lo que más te costó?"
        XCTAssertEqual(TrozosDeVoz.partir(t), [t])
    }

    func testCortaConSignosDeApertura() {
        let t = "Eso suena pesado y se entiende que te tenga así, con todo lo que venís "
              + "arrastrando de estos meses en el laburo y en casa. ¿Qué fue lo que más te "
              + "costó de todo eso que me contás recién? Contame con calma, no hay apuro."
        let p = TrozosDeVoz.partir(t)
        XCTAssertGreaterThanOrEqual(p.count, 2)
        XCTAssertTrue(p.contains { $0.hasPrefix("¿") },
                      "una pregunta arranca su propio pedazo: \(p)")
    }

    /// Signos seguidos: corta una sola vez, al final.
    func testSignosSeguidosNoDuplicanElCorte() {
        let t = "No lo puedo creer, en serio, es una locura completa lo que me estás "
              + "contando de la reunión, de la respuesta que te dieron y de todo lo que "
              + "vino después con el resto del equipo!! Contame más de eso, que me quedé "
              + "pensando en cómo lo manejaste vos en el momento."
        let p = TrozosDeVoz.partir(t)
        XCTAssertGreaterThanOrEqual(p.count, 2)
        XCTAssertTrue(p[0].hasSuffix("!!"), "cortó en el último signo: \(p[0])")
    }

    /// Ningún pedazo puede pasarse del techo del proveedor.
    func testNingunPedazoEsGigante() {
        let t = String(repeating: "Esto es una oración de prueba bastante larga. ", count: 200)
        for pedazo in TrozosDeVoz.partir(t) {
            XCTAssertLessThan(pedazo.count, 4000)
        }
    }
}
