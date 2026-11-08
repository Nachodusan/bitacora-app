import XCTest
@testable import BitacoraCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SyncClientTests: XCTestCase {

    let config = ConfigServidor(baseURL: URL(string: "http://localhost:3000")!, token: "secreto")

    func clienteQueResponde(_ codigo: Int, _ cuerpo: String) -> SyncClient {
        SyncClient(config: config) { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: codigo,
                                       httpVersion: nil, headerFields: nil)!
            return (Data(cuerpo.utf8), resp)
        }
    }

    func entradaDePrueba() -> EntradaNueva {
        EntradaNueva.desde(instante: Date(timeIntervalSince1970: 1_786_000_000),
                           zona: TimeZone(identifier: "America/Argentina/Buenos_Aires")!,
                           transcripcion: "dormí como seis horas",
                           duracionSeg: 4.2,
                           clientUuid: "11111111-1111-1111-1111-111111111111")
    }

    func testMandaElBearerToken() async {
        var visto: URLRequest?
        let c = SyncClient(config: config) { req in
            visto = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: nil, headerFields: nil)!
            return (Data(#"{"id":1}"#.utf8), resp)
        }
        _ = await c.subir(entradaDePrueba())
        XCTAssertEqual(visto?.value(forHTTPHeaderField: "Authorization"), "Bearer secreto")
        XCTAssertEqual(visto?.url?.path, "/entradas")
        XCTAssertEqual(visto?.httpMethod, "POST")
    }

    func testElCuerpoUsaLasClavesDelContrato() throws {
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(entradaDePrueba())) as! [String: Any]
        // Si alguna de estas claves cambia, el insert del backend rompe.
        XCTAssertEqual(Set(json.keys),
                       ["client_uuid", "creado_en", "creado_local", "fuente",
                        "transcripcion", "duracion_seg"])
        XCTAssertEqual(json["fuente"] as? String, "dictado_ios")
        // creado_en lleva offset, creado_local no. Los dos, siempre.
        XCTAssertTrue((json["creado_en"] as! String).contains("-03:00"))
        XCTAssertFalse((json["creado_local"] as! String).contains("-03:00"))
    }

    func testAceptadaCon201() async {
        let r = await clienteQueResponde(201, #"{"id":42,"dia":"2026-08-05"}"#).subir(entradaDePrueba())
        XCTAssertEqual(r, .aceptada(RespuestaEntrada(id: 42, dia: "2026-08-05")))
    }

    /// Idempotencia: reenviar una entrada ya subida devuelve 200 con el id que
    /// ya tenía. Para la cola es un éxito, no un error.
    func testReenvioDevuelveElMismoId() async {
        let r = await clienteQueResponde(200, #"{"id":42}"#).subir(entradaDePrueba())
        XCTAssertEqual(r, .aceptada(RespuestaEntrada(id: 42, dia: nil)))
    }

    func testErrorDeServidorSeReintenta() async {
        guard case .reintentable = await clienteQueResponde(500, "boom").subir(entradaDePrueba()) else {
            return XCTFail("un 500 tiene que ser reintentable")
        }
    }

    func testErrorDeClienteNoSeReintenta() async {
        guard case .rechazada(let codigo, _) = await clienteQueResponde(422, "transcripcion vacía")
            .subir(entradaDePrueba()) else {
            return XCTFail("un 422 no se reintenta nunca")
        }
        XCTAssertEqual(codigo, 422)
    }

    /// El 401 va por su propio camino y NO cae en `rechazada`.
    ///
    /// El resto de los 4xx son culpa del contenido: el servidor va a contestar
    /// lo mismo mil veces. Este depende del token, que es config del teléfono y
    /// se arregla en Ajustes. Cuando estaba metido en la misma bolsa, todo lo
    /// dictado antes de cargar el token quedaba muerto para siempre: el texto
    /// seguía en disco pero no había ningún camino de vuelta a `pendiente`.
    func testFaltaElTokenNoQuemaLaEntrada() async {
        for codigo in [401, 403] {
            let r = await clienteQueResponde(codigo, #"{"error":"no autorizado"}"#)
                .subir(entradaDePrueba())
            guard case .sinCredencial(let c) = r else {
                return XCTFail("un \(codigo) tiene que ser sinCredencial y no rechazada: "
                               + "el token se arregla y la entrada se sube después")
            }
            XCTAssertEqual(c, codigo)
        }
    }

    /// Los tres estados que decide `comprobar()`, que es lo que habilita o traba
    /// el orbe. No pueden colapsarse en un booleano: cada uno pide una acción
    /// distinta —cargar el token, prender la máquina, esperar— y la pantalla
    /// tiene que poder decir cuál.
    func testLosTresEstadosDelServidor() async {
        var r = await clienteQueResponde(200, "{}").comprobar()
        XCTAssertEqual(r, .listo)

        r = await clienteQueResponde(401, "{}").comprobar()
        XCTAssertEqual(r, .sinToken, "el servidor está vivo, la llave no le cierra")

        r = await SyncClient(config: config) { _ in throw URLError(.cannotConnectToHost) }
            .comprobar()
        XCTAssertEqual(r, .inalcanzable, "no contestó: no es lo mismo que rechazar")
    }

    func testSinRedSeReintenta() async {
        let c = SyncClient(config: config) { _ in
            throw URLError(.notConnectedToInternet)
        }
        guard case .reintentable = await c.subir(entradaDePrueba()) else {
            return XCTFail("sin red tiene que ser reintentable — es el caso del modo avión")
        }
    }

    // ── La voz ──────────────────────────────────────────────────────────
    //
    // Todo lo que puede salir mal tiene que devolver `nil`, no un error: el
    // teléfono traduce `nil` a "habla la voz de iOS" y la charla sigue. Un
    // error acá sería una excepción que hay que atrapar en cada llamador, y el
    // día que alguno se olvide, Bitácora se queda muda en vez de sonar peor.

    func testLaVozDevuelveElAudio() async {
        let mp3 = Data([0xff, 0xfb, 0x90, 0x44])
        let cliente = SyncClient(config: config) { req in
            (mp3, HTTPURLResponse(url: req.url!, statusCode: 200,
                                  httpVersion: nil, headerFields: nil)!)
        }
        let r = await cliente.voz(texto: "hola", timbre: "mujer")
        XCTAssertEqual(r, mp3)
    }

    func testLaVozMandaTextoYTimbre() async throws {
        // Una clase y no un `var` capturado: el closure es `@Sendable` y mutar
        // una variable capturada desde ahí es un error en Swift 6.
        final class Buzon: @unchecked Sendable { var cuerpo: Data? }
        let buzon = Buzon()
        let cliente = SyncClient(config: config) { req in
            buzon.cuerpo = req.httpBody
            return (Data([0xff]), HTTPURLResponse(url: req.url!, statusCode: 200,
                                                  httpVersion: nil, headerFields: nil)!)
        }
        _ = await cliente.voz(texto: "contame", timbre: "hombre")
        let json = try XCTUnwrap(buzon.cuerpo.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: String] })
        XCTAssertEqual(json["texto"], "contame")
        XCTAssertEqual(json["timbre"], "hombre")
    }

    /// Cada motivo por el que el servidor puede no dar audio termina igual.
    func testTodoLoQueFallaEnLaVozDaNil() async {
        for codigo in [401, 403, 404, 429, 500, 503] {
            let r = await clienteQueResponde(codigo, #"{"ok":false}"#)
                .voz(texto: "hola", timbre: "mujer")
            XCTAssertNil(r, "un \(codigo) tiene que caer a la voz de iOS")
        }
    }

    /// Un 200 con el cuerpo vacío es un audio que no se puede reproducir.
    /// Pasarlo igual sería un turno mudo que encima consume el vigía entero.
    func testLaVozVaciaEsNil() async {
        let r = await clienteQueResponde(200, "").voz(texto: "hola", timbre: "mujer")
        XCTAssertNil(r)
    }

    func testSinRedLaVozEsNil() async {
        let cliente = SyncClient(config: config) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let r = await cliente.voz(texto: "hola", timbre: "mujer")
        XCTAssertNil(r)
    }

    func testBackoffCreceYSeFrena() {
        XCTAssertEqual(Backoff.espera(intento: 1, jitter: 0), 2)
        XCTAssertEqual(Backoff.espera(intento: 2, jitter: 0), 4)
        XCTAssertEqual(Backoff.espera(intento: 3, jitter: 0), 8)
        XCTAssertEqual(Backoff.espera(intento: 10, jitter: 0), Backoff.techoSeg)
        // Un intento absurdo no puede dar infinito ni NaN: la cola se colgaría.
        XCTAssertEqual(Backoff.espera(intento: 9999, jitter: 0), Backoff.techoSeg)
        XCTAssertTrue(Backoff.espera(intento: 9999, jitter: 0.9).isFinite)
    }

    func testElJitterSoloRestaNuncaSuma() {
        for intento in 1...12 {
            let sinJitter = Backoff.espera(intento: intento, jitter: 0)
            let conJitter = Backoff.espera(intento: intento, jitter: 0.99)
            XCTAssertLessThanOrEqual(conJitter, sinJitter)
            XCTAssertGreaterThan(conJitter, 0)
        }
    }
}
