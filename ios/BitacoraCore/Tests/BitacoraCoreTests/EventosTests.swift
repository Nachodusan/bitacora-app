import XCTest
@testable import BitacoraCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Los eventos del calendario, contra el contrato de `api/src/consultas.ts`.
final class EventosTests: XCTestCase {

    let config = ConfigServidor(baseURL: URL(string: "http://localhost:3000")!, token: "secreto")

    func cliente(_ codigo: Int, _ cuerpo: String,
                 mirar: (@Sendable (URLRequest) -> Void)? = nil) -> SyncClient {
        SyncClient(config: config) { req in
            mirar?(req)
            let resp = HTTPURLResponse(url: req.url!, statusCode: codigo, httpVersion: nil, headerFields: nil)!
            return (Data(cuerpo.utf8), resp)
        }
    }

    /// Una consulta tal como la manda el servidor, con borrador y lo que eligió llevar.
    let consulta = #"""
    {"eventos":[{"id":7,"client_uuid":null,"tipo":"consulta","dia":"2026-10-09","hora":"17:00",
      "titulo":null,"origen":"bitacora","estado":"propuesto","para_llevar":["lo de mi hermana"],
      "borrador":{"entendi":"Entendí algo.","aporte":"","sentir":"Tranquila.","temas":["límites"],"avance":""},
      "evaluada":false}]}
    """#

    func testLeeLosEventosDelServidor() async {
        let e = await cliente(200, consulta).eventos()
        XCTAssertEqual(e, [Evento(id: 7, tipo: "consulta", dia: "2026-10-09", hora: "17:00",
                                  origen: "bitacora", estado: "propuesto",
                                  paraLlevar: ["lo de mi hermana"],
                                  borrador: BorradorDeEvaluacion(entendi: "Entendí algo.", sentir: "Tranquila.",
                                                                 temas: ["límites"]))])
        XCTAssertEqual(e?.first?.esPropuesta, true)
    }

    /// Sin servidor, `nil` y no una lista vacía: con `nil` el teléfono se queda
    /// con su copia en vez de borrar el calendario.
    func testSinServidorNoEsLoMismoQueSinEventos() async {
        let sinRed = SyncClient(config: config) { _ in throw URLError(.notConnectedToInternet) }
        let nada = await sinRed.eventos()
        XCTAssertNil(nada)
        let vacio = await cliente(200, #"{"eventos":[]}"#).eventos()
        XCTAssertEqual(vacio, [])
    }

    /// Un borrador a medias no puede hacer que no se lea ningún evento.
    func testUnBorradorIncompletoSeLeeIgual() throws {
        let b = try JSONDecoder().decode(BorradorDeEvaluacion.self, from: Data(#"{"entendi":"algo"}"#.utf8))
        XCTAssertEqual(b, BorradorDeEvaluacion(entendi: "algo"))
    }

    /// Los tres casos de la hora: no tocarla, sacarla y ponerla.
    func testElCambioMandaSoloLoQueCambia() throws {
        func json(_ c: CambioDeEvento) throws -> String {
            let e = JSONEncoder()
            e.outputFormatting = .sortedKeys
            return String(decoding: try e.encode(c), as: UTF8.self)
        }
        XCTAssertEqual(try json(CambioDeEvento(estado: "confirmado")), #"{"estado":"confirmado"}"#)
        XCTAssertEqual(try json(CambioDeEvento(hora: .some(nil))), #"{"hora":null}"#)
        XCTAssertEqual(try json(CambioDeEvento(hora: "09:30")), #"{"hora":"09:30"}"#)
        XCTAssertEqual(try json(CambioDeEvento(evaluada: true)), #"{"evaluada":true}"#)
    }

    func testCrearMandaElCuerpoDelContrato() async throws {
        let visto = Visto()
        let r = await cliente(201, #"{"evento":{"id":3,"client_uuid":"u","tipo":"consulta","dia":"2026-10-09","hora":null,"titulo":null,"origen":"persona","estado":"confirmado","para_llevar":[],"borrador":null,"evaluada":false}}"#,
                              mirar: { visto.req = $0 })
            .crearEvento(clientUuid: "u", tipo: "consulta", dia: "2026-10-09", hora: nil, titulo: nil)
        XCTAssertEqual(r?.id, 3)
        XCTAssertEqual(visto.req?.httpMethod, "POST")
        XCTAssertEqual(visto.req?.url?.path, "/eventos")
        let cuerpo = try JSONSerialization.jsonObject(with: visto.req!.httpBody!) as! [String: Any]
        XCTAssertEqual(Set(cuerpo.keys), ["client_uuid", "tipo", "dia", "hora", "titulo"])
    }

    func testBorrarAceptaQueYaNoEste() async {
        let borrado = await cliente(204, "").borrarEvento(id: 3)
        XCTAssertTrue(borrado)
        let yaNoEstaba = await cliente(404, "").borrarEvento(id: 3)
        XCTAssertTrue(yaNoEstaba)
        let fallo = await cliente(500, "").borrarEvento(id: 3)
        XCTAssertFalse(fallo)
    }

    // MARK: - La próxima consulta

    func testLaProximaConsultaEsLaConfirmadaQueNoPaso() {
        let eventos = [
            Evento(id: 1, tipo: "consulta", dia: "2026-10-02", hora: "19:00"),
            Evento(id: 2, tipo: "consulta", dia: "2026-10-16", hora: "19:00"),
            Evento(id: 3, tipo: "consulta", dia: "2026-10-09", hora: "19:00"),
            Evento(id: 4, tipo: "otro", dia: "2026-10-07", hora: "10:00"),
            Evento(id: 5, tipo: "consulta", dia: "2026-10-08", origen: "bitacora", estado: "propuesto"),
        ]
        XCTAssertEqual(Evento.proximaConsulta(en: eventos, ahora: "2026-10-06 10:00")?.id, 3)
        // Una hora después de empezar ya pasó: sigue la de la semana siguiente.
        XCTAssertEqual(Evento.proximaConsulta(en: eventos, ahora: "2026-10-09 20:00")?.id, 2)
        XCTAssertNil(Evento.proximaConsulta(en: eventos, ahora: "2026-10-17 08:00"))
    }

    func testLasConsultasDelMesSumanLasDeLosProximosTreintaDias() {
        let eventos = [
            Evento(id: 1, tipo: "consulta", dia: "2026-10-05", hora: "17:00"),
            Evento(id: 2, tipo: "consulta", dia: "2026-11-02", hora: "17:00"),
            Evento(id: 3, tipo: "consulta", dia: "2026-12-07", hora: "17:00"),
            Evento(id: 4, tipo: "otro", dia: "2026-10-28", hora: "10:00"),
            Evento(id: 5, tipo: "consulta", dia: "2026-10-30", origen: "bitacora", estado: "propuesto"),
            Evento(id: 6, tipo: "consulta", dia: "2026-09-28", hora: "17:00"),
        ]
        // La del 5 ya pasó pero es de este mes; la del 2 de noviembre está a
        // ocho días; la de diciembre, lejos. Ni el «otro» ni la propuesta.
        XCTAssertEqual(Evento.consultasDelMes(en: eventos, ahora: "2026-10-25 03:00").map(\.id), [1, 2])
        XCTAssertEqual(Evento.consultasDelMes(en: [], ahora: "2026-10-25 03:00").count, 0)
    }

    func testSinHoraCuentaElMediodiaComoElServidor() {
        let e = [Evento(id: 1, tipo: "consulta", dia: "2026-10-09")]
        XCTAssertEqual(Evento.proximaConsulta(en: e, ahora: "2026-10-09 11:59")?.id, 1)
        XCTAssertNil(Evento.proximaConsulta(en: e, ahora: "2026-10-09 12:00"))
    }

    func testCuantoFalta() {
        XCTAssertEqual(Evento.cuantoFalta(hasta: "2026-10-06", desde: "2026-10-06"), "hoy")
        XCTAssertEqual(Evento.cuantoFalta(hasta: "2026-10-07", desde: "2026-10-06"), "mañana")
        XCTAssertEqual(Evento.cuantoFalta(hasta: "2026-10-09", desde: "2026-10-06"), "en 3 días")
        // Cruzando de mes.
        XCTAssertEqual(Evento.cuantoFalta(hasta: "2026-11-02", desde: "2026-10-30"), "en 3 días")
    }
}

/// Para mirar el pedido desde un closure `@Sendable` sin capturar un `var`.
private final class Visto: @unchecked Sendable {
    var req: URLRequest?
}
