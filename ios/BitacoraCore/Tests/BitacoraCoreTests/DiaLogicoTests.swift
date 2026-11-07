import XCTest
@testable import BitacoraCore

/// Estos casos son los mismos que corrí contra Postgres. Si alguno cambia acá,
/// tiene que cambiar también la columna generada `entradas.dia`.
final class DiaLogicoTests: XCTestCase {

    func testMadrugadaPerteneceAlDiaAnterior() {
        // Regla 2: "lo que hablo a la 1am pertenece al día anterior".
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2026, mes: 8, dia: 10, hora: 1, minuto: 30)),
                       "2026-08-09")
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2026, mes: 8, dia: 10, hora: 0, minuto: 0)),
                       "2026-08-09")
    }

    func testElCorteEsALas4EnPunto() {
        // 03:59:59 es todavía ayer; 04:00:00 ya es hoy.
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2026, mes: 8, dia: 10, hora: 3, minuto: 59, segundo: 59)),
                       "2026-08-09")
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2026, mes: 8, dia: 10, hora: 4, minuto: 0, segundo: 0)),
                       "2026-08-10")
    }

    func testTardeYNochePertenecenAlMismoDia() {
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2026, mes: 8, dia: 10, hora: 9, minuto: 0)),
                       "2026-08-10")
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2026, mes: 8, dia: 10, hora: 23, minuto: 50)),
                       "2026-08-10")
    }

    func testCruceDeMesYDeAnio() {
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2026, mes: 9, dia: 1, hora: 2, minuto: 0)),
                       "2026-08-31")
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2027, mes: 1, dia: 1, hora: 3, minuto: 0)),
                       "2026-12-31")
    }

    func testAnioBisiesto() {
        XCTAssertEqual(DiaLogico.dia(de: .init(anio: 2028, mes: 3, dia: 1, hora: 2, minuto: 0)),
                       "2028-02-29")
    }

    /// El corte no puede depender del horario de verano ni de la zona: se calcula
    /// sobre hora de pared. Dos teléfonos en zonas distintas que marcan la misma
    /// hora tienen que dar el mismo día lógico.
    func testElDiaLogicoNoDependeDeLaZona() {
        let paredBuenosAires = HoraDePared(
            instante: Date(timeIntervalSince1970: 1_786_000_000),
            zona: TimeZone(identifier: "America/Argentina/Buenos_Aires")!)
        let paredTokio = HoraDePared(
            instante: Date(timeIntervalSince1970: 1_786_000_000),
            zona: TimeZone(identifier: "Asia/Tokyo")!)
        // Son horas de pared distintas (el instante es el mismo), y cada una se
        // resuelve con su propia hora local: eso es lo que queremos.
        XCTAssertNotEqual(paredBuenosAires.hora, paredTokio.hora)

        // Pero la misma hora de pared da siempre el mismo día, venga de donde venga.
        let a = HoraDePared(anio: 2026, mes: 8, dia: 10, hora: 2, minuto: 0)
        XCTAssertEqual(DiaLogico.dia(de: a), "2026-08-09")
    }

    func testFormatoDeCreadoLocal() {
        let p = HoraDePared(anio: 2026, mes: 8, dia: 3, hora: 9, minuto: 5, segundo: 7)
        // Sin "Z" y sin offset: si llevara zona, Postgres lo interpretaría y el
        // corte de las 4am dejaría de ser sobre hora de pared.
        XCTAssertEqual(p.iso8601SinZona, "2026-08-03T09:05:07")
        XCTAssertFalse(p.iso8601SinZona.contains("Z"))
        XCTAssertFalse(p.iso8601SinZona.contains("+"))
    }
}
