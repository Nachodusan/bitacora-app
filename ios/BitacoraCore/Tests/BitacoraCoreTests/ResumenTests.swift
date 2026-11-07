import XCTest
@testable import BitacoraCore

final class ResumenTests: XCTestCase {

    func testElMes() {
        XCTAssertEqual(Resumen.mes(anio: 2026, mes: 9).desde, "2026-09-01")
        XCTAssertEqual(Resumen.mes(anio: 2026, mes: 9).hasta, "2026-09-30")
        XCTAssertEqual(Resumen.mes(anio: 2028, mes: 2).hasta, "2028-02-29")
        XCTAssertEqual(Resumen.mes(anio: 2026, mes: 2).hasta, "2026-02-28")
        XCTAssertEqual(Resumen.mes(anio: 2026, mes: 12).hasta, "2026-12-31")
    }

    func testElTramoEscrito() {
        XCTAssertEqual(Resumen.escrito(desde: "2026-09-01", hasta: "2026-09-30"), "septiembre de 2026")
        XCTAssertEqual(Resumen.escrito(desde: "2026-09-15", hasta: "2026-09-15"), "15 de septiembre de 2026")
        XCTAssertEqual(Resumen.escrito(desde: "2026-09-15", hasta: "2026-09-16"), "del 15 al 16 de septiembre de 2026")
        XCTAssertEqual(Resumen.escrito(desde: "2026-09-28", hasta: "2026-10-03"),
                       "del 28 de septiembre al 3 de octubre de 2026")
        XCTAssertEqual(Resumen.escrito(desde: "2026-12-28", hasta: "2027-01-03"),
                       "del 28 de diciembre de 2026 al 3 de enero de 2027")
        XCTAssertEqual(Resumen.escrito(desde: "2026-09-01", hasta: "2026-09-29"), "del 1 al 29 de septiembre de 2026",
                       "un mes al que le falta un día no es el mes")
    }

    func testLosDiasSueltos() {
        XCTAssertEqual(Resumen.escrito(dias: ["2026-09-16", "2026-09-15"], esElMes: false), "15 y 16 de septiembre de 2026")
        XCTAssertEqual(Resumen.escrito(dias: ["2026-09-15"], esElMes: false), "15 de septiembre de 2026")
        XCTAssertEqual(Resumen.escrito(dias: ["2026-09-03", "2026-09-24", "2026-09-10"], esElMes: false),
                       "3, 10 y 24 de septiembre de 2026")
        XCTAssertEqual(Resumen.escrito(dias: ["2026-09-28", "2026-09-30", "2026-10-02"], esElMes: false),
                       "28 y 30 de septiembre y 2 de octubre de 2026")
        XCTAssertEqual(Resumen.escrito(dias: ["2026-12-30", "2027-01-02"], esElMes: false),
                       "30 de diciembre de 2026 y 2 de enero de 2027")
        let ocho = ["03", "05", "07", "10", "12", "15", "20", "24"].map { "2026-09-\($0)" }
        XCTAssertEqual(Resumen.escrito(dias: ocho, esElMes: false), "8 días, del 3 al 24 de septiembre de 2026")
        XCTAssertEqual(Resumen.escrito(dias: ocho, esElMes: true), "septiembre de 2026")
        XCTAssertEqual(Resumen.escrito(dias: [], esElMes: false), "ningún día")
    }

    private func nota(_ dia: String, _ hora: String, _ texto: String, contexto: String? = nil,
                      temas: [String] = []) -> NotaDelDia {
        NotaDelDia(dia: dia, hora: hora, temas: temas, contexto: contexto,
                   citas: [.init(texto: texto, sobre: "algo")])
    }

    func testElDocumentoVaDelMasViejoAlMasNuevo() {
        let html = Resumen.html(notas: [nota("2026-09-16", "21:00", "SEGUNDA"), nota("2026-09-15", "23:30", "PRIMERA")],
                                tramo: "15 y 16 de septiembre de 2026", nombre: "Tomás", generado: "2026-10-04")
        let a = html.range(of: "PRIMERA")!.lowerBound
        let b = html.range(of: "SEGUNDA")!.lowerBound
        XCTAssertLessThan(a, b)
        XCTAssertTrue(html.contains("Martes 15 de septiembre"))
        XCTAssertTrue(html.contains("De Tomás · 15 y 16 de septiembre de 2026 ·"))
        XCTAssertTrue(html.contains("Son frases de Tomás"))
        XCTAssertTrue(html.contains("preparado con Bitácora el 4 de octubre de 2026"))
    }

    /// El registro va en el PDF, por tipo y en orden, cada uno con su frase.
    func testElRegistroVaEnElDocumento() {
        let n = NotaDelDia(dia: "2026-09-15", hora: "21:00", temas: [], contexto: nil,
                           citas: [.init(texto: "me dio mucha bronca", sobre: "el jefe")],
                           registro: [.init(tipo: "habito", que: "comer de noche", cita: "como todas las noches"),
                                      .init(tipo: "emocion", que: "bronca", cita: "me dio mucha bronca")])
        let html = Resumen.html(notas: [n], tramo: "x", nombre: nil, generado: "2026-10-04")
        let e = html.range(of: "Emoción")!.lowerBound
        let h = html.range(of: "Hábito")!.lowerBound
        XCTAssertLessThan(e, h)
        XCTAssertTrue(html.contains("«como todas las noches»"))
        XCTAssertTrue(html.contains("la persona no lo ve en la app"))
    }

    func testSinRegistroNoHayTabla() {
        let html = Resumen.html(notas: [nota("2026-09-15", "21:00", "algo")], tramo: "x", nombre: nil, generado: "2026-10-04")
        XCTAssertFalse(html.contains("<table class=\"registro\">"))
    }

    /// Un servidor viejo manda la nota sin registro.
    func testLaNotaSinRegistroSeLeeIgual() throws {
        let json = #"{"dia":"2026-09-15","hora":"21:00","temas":[],"contexto":null,"citas":[{"texto":"a","sobre":"b"}]}"#
        let n = try JSONDecoder().decode(NotaDelDia.self, from: Data(json.utf8))
        XCTAssertEqual(n.registro, [])
    }

    /// Lo que dijo la persona no puede romper el documento ni meterle nada.
    func testLoQueDijoSeEscapa() {
        let html = Resumen.html(notas: [nota("2026-09-15", "21:00", "a <b>mí</b> & \"nadie\"")],
                                tramo: "15 de septiembre de 2026", nombre: "<script>", generado: "2026-10-04")
        XCTAssertTrue(html.contains("«a &lt;b&gt;mí&lt;/b&gt; &amp; &quot;nadie&quot;»"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("De &lt;script&gt;"))
    }

    /// Lo que escribe el modelo va marcado como de la app; las frases, no.
    func testLoDeLaAppVaMarcado() {
        let html = Resumen.html(notas: [nota("2026-09-15", "21:00", "no sirvo", contexto: "Tuvo un mal día.",
                                             temas: ["trabajo", "familia"])],
                                tramo: "15 de septiembre de 2026", nombre: nil, generado: "2026-10-04")
        XCTAssertTrue(html.contains("<b>Contexto</b> (lo escribe la app): Tuvo un mal día."))
        XCTAssertTrue(html.contains("<b>Temas</b> (los escribe la app): trabajo · familia"))
        XCTAssertTrue(html.contains("No es un informe clínico ni un diagnóstico"))
        XCTAssertTrue(html.contains("Son frases de la persona"), "sin nombre cargado")
    }

    func testSinFrasesLoDice() {
        let html = Resumen.html(notas: [], tramo: "septiembre de 2026", nombre: "Tomás", generado: "2026-10-04")
        XCTAssertTrue(html.contains("No hay nada guardado en estos días."))
    }

    /// Lo que dijo la persona, turno por turno; lo de Bitácora no va.
    func testLoQueDijoEnLaCharla() {
        let t = "Vos: Hola.\nBitácora: Hola, ¿cómo estás?\nSegundo párrafo de Bitácora.\n"
            + "Vos: Me ofrecieron otra pega.\nY no sé qué hacer.\nLaya: Una línea vieja.\nVos:   \n"
        XCTAssertEqual(Transcripcion.loQueDijo(t), ["Hola.", "Me ofrecieron otra pega.\nY no sé qué hacer."])
        XCTAssertEqual(Transcripcion.loQueDijo(""), [])
    }

    /// Un día con charla y sin frases también va, en su lugar, y dice qué es.
    func testUnDiaSinFrasesVaConLoQueDijo() {
        let html = Resumen.html(
            notas: [nota("2026-09-29", "22:00", "DESPUÉS"), nota("2026-09-26", "20:30", "ANTES")],
            charlas: [Resumen.CharlaSinFrases(dia: "2026-09-28", hora: "21:30",
                                              dicho: ["me ofrecieron <otra> pega", "dos\nlíneas"])],
            tramo: "26, 28 y 29 de septiembre de 2026", nombre: "Tomás", generado: "2026-10-04")
        let antes = html.range(of: "ANTES")!.lowerBound
        let charla = html.range(of: "Lunes 28 de septiembre")!.lowerBound
        let despues = html.range(of: "DESPUÉS")!.lowerBound
        XCTAssertLessThan(antes, charla)
        XCTAssertLessThan(charla, despues)
        XCTAssertTrue(html.contains("Ese día no se separaron frases: va lo que dijo en la charla, textual."))
        XCTAssertTrue(html.contains("<blockquote>«me ofrecieron &lt;otra&gt; pega»</blockquote>"))
        XCTAssertTrue(html.contains("«dos<br>líneas»"))
    }

    func testLasNotasPidenElTramo() async {
        final class Buzon: @unchecked Sendable { var url: URL? }
        let buzon = Buzon()
        let cliente = SyncClient(config: ConfigServidor(baseURL: URL(string: "http://localhost:3000")!, token: "t")) { req in
            buzon.url = req.url
            let cuerpo = #"{"desde":"2026-09-15","hasta":"2026-09-16","notas":[]}"#
            return (Data(cuerpo.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let r = await cliente.notas(desde: "2026-09-15", hasta: "2026-09-16")
        XCTAssertEqual(r?.count, 0)
        XCTAssertEqual(buzon.url?.absoluteString, "http://localhost:3000/notas?desde=2026-09-15&hasta=2026-09-16")
    }

    /// Sin servidor no es «no hay nada»: un PDF vacío se mandaría igual.
    func testSinServidorEsNil() async {
        let cliente = SyncClient(config: ConfigServidor(baseURL: URL(string: "http://localhost:3000")!, token: "t")) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let r = await cliente.notas(desde: "2026-09-01", hasta: "2026-09-30")
        XCTAssertNil(r)
    }
}
