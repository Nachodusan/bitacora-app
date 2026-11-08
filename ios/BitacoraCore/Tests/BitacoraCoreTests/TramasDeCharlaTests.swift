import XCTest
@testable import BitacoraCore

final class TramasDeCharlaTests: XCTestCase {

    private func trama(_ tipo: Character, _ cuerpo: Data) -> Data {
        var d = Data([tipo.asciiValue!])
        let n = UInt32(cuerpo.count)
        d.append(contentsOf: [UInt8(n >> 24), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)])
        d.append(cuerpo)
        return d
    }
    private func trama(_ tipo: Character, _ texto: String) -> Data { trama(tipo, Data(texto.utf8)) }

    func testLeeCadaTipoDeTrama() {
        var l = LectorDeTramas()
        let fin = #"{"ok":true,"texto":"Hola. ¿Qué tal?","hablado":15}"#
        let todo = trama("T", "Hola.") + trama("H", "24000") + trama("A", Data([1, 2, 3, 4])) + trama("F", fin)
        XCTAssertEqual(l.recibir(todo), [
            .texto("Hola."),
            .frecuencia(24000),
            .audio(Data([1, 2, 3, 4])),
            .fin(ok: true, texto: "Hola. ¿Qué tal?", faltaDecir: ""),
        ])
    }

    /// Los pedazos de red cortan donde quieren. Byte por byte es el peor caso.
    func testDaLoMismoLlegueComoLleguePartido() {
        let todo = trama("T", "Qué duro.") + trama("A", Data(repeating: 7, count: 300)) + trama("T", "Qué duro. ¿Y después?")
        for tamano in [1, 2, 5, 6, 64, 1000] {
            var l = LectorDeTramas()
            var r: [TramaDeCharla] = []
            var i = 0
            while i < todo.count {
                r += l.recibir(todo.subdata(in: i..<min(i + tamano, todo.count)))
                i += tamano
            }
            XCTAssertEqual(r, [.texto("Qué duro."), .audio(Data(repeating: 7, count: 300)),
                               .texto("Qué duro. ¿Y después?")], "partido de a \(tamano)")
        }
    }

    func testDiceCuantoFaltaParaLaTramaEnCurso() {
        var l = LectorDeTramas()
        XCTAssertEqual(l.faltan, 5)
        let t = trama("A", Data(repeating: 0, count: 10))
        _ = l.recibir(t.prefix(3))
        XCTAssertEqual(l.faltan, 2)
        _ = l.recibir(t.subdata(in: 3..<5))
        XCTAssertEqual(l.faltan, 10)
        XCTAssertEqual(l.recibir(t.suffix(10)).count, 1)
        XCTAssertEqual(l.faltan, 5)
    }

    /// Si la voz del servidor se cortó a mitad de camino, lo que falta lo dice
    /// la voz de iOS. Ni se repite ni se saltea nada.
    func testLoQueFaltaDecirArrancaDondeTerminoLaVoz() {
        var l = LectorDeTramas()
        let texto = "Qué duro lo de tu jefe. ¿Qué pasó después?"
        let hablado = "Qué duro lo de tu jefe.".utf16.count
        let r = l.recibir(trama("F", #"{"ok":true,"texto":"\#(texto)","hablado":\#(hablado)}"#))
        XCTAssertEqual(r, [.fin(ok: true, texto: texto, faltaDecir: "¿Qué pasó después?")])
    }

    /// El servidor cuenta en UTF-16 y Swift en caracteres: con un emoji antes
    /// del corte, las dos cuentas no coinciden.
    func testElCorteCuentaComoCuentaElServidor() {
        let texto = "Bien 😀 dicho. Sigue así."
        let n = "Bien 😀 dicho.".utf16.count
        XCTAssertEqual(LectorDeTramas.desde(n, en: texto), "Sigue así.")
        XCTAssertEqual(LectorDeTramas.desde(0, en: texto), texto)
        XCTAssertEqual(LectorDeTramas.desde(texto.utf16.count, en: texto), "")
        XCTAssertEqual(LectorDeTramas.desde(9999, en: texto), "")
    }

    func testSinVozFaltaDecirTodo() {
        var l = LectorDeTramas()
        let r = l.recibir(trama("F", #"{"ok":true,"texto":"Hola, aquí estoy.","hablado":0}"#))
        XCTAssertEqual(r, [.fin(ok: true, texto: "Hola, aquí estoy.", faltaDecir: "Hola, aquí estoy.")])
    }

    func testElCorteDelServidorLlegaComoFinSinOk() {
        var l = LectorDeTramas()
        let r = l.recibir(trama("F", #"{"ok":false,"texto":"Se me cortó aquí.","hablado":0}"#))
        XCTAssertEqual(r, [.fin(ok: false, texto: "Se me cortó aquí.", faltaDecir: "Se me cortó aquí.")])
    }

    /// El corte de riesgo del servidor: llega como su propio caso, no como un
    /// final común, para que nadie lo trate como un turno más.
    func testElCorteDeRiesgoDelServidorLlegaComoCuidado() {
        var l = LectorDeTramas()
        let r = l.recibir(trama("F", #"{"ok":true,"texto":"Gracias por decirlo aquí.","hablado":0,"cuidado":true}"#))
        XCTAssertEqual(r, [.cuidado(texto: "Gracias por decirlo aquí.")])
    }

    /// Un tipo de trama que este teléfono no conoce se saltea sin romper nada.
    func testUnaTramaDesconocidaSeSaltea() {
        var l = LectorDeTramas()
        XCTAssertEqual(l.recibir(trama("Z", "algo nuevo") + trama("T", "Hola")), [.texto("Hola")])
    }
}
