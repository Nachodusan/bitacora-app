import XCTest
@testable import BitacoraCore

final class FinDeTurnoTests: XCTestCase {

    func testAMitadDeFraseEsperaMasQueCuandoCerro() {
        XCTAssertEqual(FinDeTurno.silencio(tras: "Hoy me fue mal en el trabajo"), FinDeTurno.silencioAMitad)
        XCTAssertEqual(FinDeTurno.silencio(tras: "Hoy me fue mal en el trabajo."), FinDeTurno.silencioSiCerro)
        XCTAssertEqual(FinDeTurno.silencio(tras: "¿Tú qué opinas?"), FinDeTurno.silencioSiCerro)
        XCTAssertGreaterThan(FinDeTurno.silencioAMitad, FinDeTurno.silencioSiCerro)
    }

    /// Nadie termina de hablar en «y» ni en «porque». Ahí se espera lo más largo.
    func testUnaPalabraQuePideQueSigaAlgoEsperaLoMasLargo() {
        for frase in ["Fui a ver a mi hermana y", "No sé si renunciar porque",
                      "Lo que pasa es que", "Estaba pensando en", "Me dijo que, o sea",
                      "Creo que no es de mis capacidades, sino de"] {
            XCTAssertEqual(FinDeTurno.silencio(tras: frase), FinDeTurno.silencioSiQuedoColgado, frase)
        }
    }

    /// El dictado pone puntos en casi cualquier pausa. Un punto detrás de una
    /// palabra colgante no la convierte en oración.
    func testUnPuntoDetrasDeUnaPalabraColganteNoCierra() {
        XCTAssertEqual(FinDeTurno.silencio(tras: "Fui a ver a mi hermana y."), FinDeTurno.silencioSiQuedoColgado)
        XCTAssertEqual(FinDeTurno.silencio(tras: "No sé si renunciar, porque."), FinDeTurno.silencioSiQuedoColgado)
    }

    func testLaComaYLosPuntosSuspensivosNoCierran() {
        XCTAssertEqual(FinDeTurno.silencio(tras: "Hoy estuve pensando,"), FinDeTurno.silencioSiQuedoColgado)
        XCTAssertEqual(FinDeTurno.silencio(tras: "No sé..."), FinDeTurno.silencioSiQuedoColgado)
        XCTAssertEqual(FinDeTurno.silencio(tras: "No sé…"), FinDeTurno.silencioSiQuedoColgado)
    }

    func testLosAcentosYLasMayusculasNoCambianNada() {
        XCTAssertEqual(FinDeTurno.silencio(tras: "Y eso es lo que más"), FinDeTurno.silencioSiQuedoColgado)
        XCTAssertEqual(FinDeTurno.silencio(tras: "No sé qué hacer, ESTÁ"), FinDeTurno.silencioSiQuedoColgado)
    }

    func testVacioNoRompe() {
        XCTAssertEqual(FinDeTurno.silencio(tras: "   "), FinDeTurno.silencioAMitad)
    }

    func testUnirJuntaLasDosPartesComoUnaSolaCosaDicha() {
        XCTAssertEqual(FinDeTurno.unir("Creo que no es por mí", "sino por la carrera."),
                       "Creo que no es por mí sino por la carrera.")
        XCTAssertEqual(FinDeTurno.unir(nil, " hola "), "hola")
        XCTAssertEqual(FinDeTurno.unir("hola", ""), "hola")
        XCTAssertEqual(FinDeTurno.unir("", ""), "")
    }
}
