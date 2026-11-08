import XCTest
@testable import BitacoraCore

/// Qué hace el teléfono con cada código HTTP. Lo que decide si una charla se
/// reintenta o queda muerta en disco.
final class RespuestasDelServidorTests: XCTestCase {

    private func cliente(_ status: Int, cuerpo: String = "{}") -> SyncClient {
        SyncClient(config: ConfigServidor(baseURL: URL(string: "http://x")!, token: "t")) { req in
            (Data(cuerpo.utf8),
             HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private var entrada: EntradaNueva {
        EntradaNueva(clientUuid: UUID().uuidString, creadoEn: "2026-09-05T21:00:00-03:00",
                     creadoLocal: "2026-09-05T21:00:00", fuente: .dictadoIos,
                     transcripcion: "Vos: hola", duracionSeg: 3)
    }

    /// Un 404 —una URL con un path de más, un proxy que no rutea— no es culpa de
    /// la entrada. Marcarla rechazada la dejaba en disco para siempre: corregir
    /// la URL después no la rescataba.
    func testUn404NoMataLaEntrada() async {
        let r = await cliente(404).subir(entrada)
        guard case .reintentable = r else { return XCTFail("404 tiene que reintentarse, dio \(r)") }
    }

    func testUn429TampocoLaMata() async {
        let r = await cliente(429).subir(entrada)
        guard case .reintentable = r else { return XCTFail("429 tiene que reintentarse, dio \(r)") }
    }

    /// Los que sí son del contenido: el servidor va a contestar lo mismo siempre.
    func testUn400SigueSiendoRechazada() async {
        let r = await cliente(400, cuerpo: "{\"error\":\"mal\"}").subir(entrada)
        guard case .rechazada(let codigo, _) = r, codigo == 400 else { return XCTFail("\(r)") }
    }

    func testUn401EsSinCredencial() async {
        let r = await cliente(401).subir(entrada)
        guard case .sinCredencial(let c) = r, c == 401 else { return XCTFail("\(r)") }
    }

    /// `comprobar()` decidía «listo» ante cualquier cosa que no fuera 401/403.
    /// Un 404 habilitaba el orbe, y la charla moría en el primer turno.
    func testComprobarSoloDaListoCon200() async {
        let listo = await cliente(200).comprobar()
        XCTAssertEqual(listo, .listo)
        let sinToken = await cliente(401).comprobar()
        XCTAssertEqual(sinToken, .sinToken)
        for status in [404, 500, 502, 503] {
            let e = await cliente(status).comprobar()
            XCTAssertEqual(e, .inalcanzable, "con \(status) no está listo")
        }
    }
}
