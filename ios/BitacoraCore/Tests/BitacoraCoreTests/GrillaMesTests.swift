import XCTest
@testable import BitacoraCore

final class GrillaMesTests: XCTestCase {

    func testAgosto2026ArrancaSabado() {
        // 2026-08-01 cae sábado. Con la semana empezando en lunes, quedan 5
        // celdas de relleno antes del día 1.
        let g = CalendarioMensual.grilla(anio: 2026, mes: 8)
        XCTAssertEqual(g.semanas[0], [nil, nil, nil, nil, nil, "2026-08-01", "2026-08-02"])
        XCTAssertEqual(g.dias.count, 31)
        XCTAssertEqual(g.dias.first, "2026-08-01")
        XCTAssertEqual(g.dias.last, "2026-08-31")
    }

    func testMesQueArrancaDomingoLlevaSemanaCompletaDeRelleno() {
        // 2026-02-01 es domingo: con la semana en lunes, es la última celda.
        let g = CalendarioMensual.grilla(anio: 2026, mes: 2)
        XCTAssertEqual(g.semanas[0], [nil, nil, nil, nil, nil, nil, "2026-02-01"])
        XCTAssertEqual(g.dias.count, 28)
    }

    func testFebreroBisiesto() {
        let g = CalendarioMensual.grilla(anio: 2028, mes: 2)
        XCTAssertEqual(g.dias.count, 29)
        XCTAssertEqual(g.dias.last, "2028-02-29")
        // 2028-02-01 es martes: una sola celda de relleno.
        XCTAssertEqual(g.semanas[0][0], nil)
        XCTAssertEqual(g.semanas[0][1], "2028-02-01")
    }

    func testTodasLasSemanasTienenSieteCeldas() {
        for anio in [2025, 2026, 2027, 2028] {
            for mes in 1...12 {
                let g = CalendarioMensual.grilla(anio: anio, mes: mes)
                XCTAssertTrue(g.semanas.allSatisfy { $0.count == 7 },
                              "\(anio)-\(mes) tiene una semana incompleta")
                // Sin huecos en el medio: el relleno va sólo en las puntas.
                let planas = g.semanas.flatMap { $0 }
                let primeroReal = planas.firstIndex { $0 != nil }!
                let ultimoReal = planas.lastIndex { $0 != nil }!
                XCTAssertFalse(planas[primeroReal...ultimoReal].contains(nil),
                               "\(anio)-\(mes) tiene un hueco en el medio")
            }
        }
    }

    /// Las claves de la grilla tienen que ser exactamente las que produce el
    /// corte de las 4am, o el calendario no encuentra las entradas.
    func testLasClavesCoincidenConElDiaLogico() {
        let g = CalendarioMensual.grilla(anio: 2026, mes: 8)
        // Una entrada dictada a las 2am del 10 pertenece al 9, y el 9 está en la
        // grilla con esa misma clave.
        let clave = DiaLogico.dia(de: .init(anio: 2026, mes: 8, dia: 10, hora: 2, minuto: 0))
        XCTAssertEqual(clave, "2026-08-09")
        XCTAssertTrue(g.dias.contains(clave))
    }

    func testCorridoDeMes() {
        XCTAssertEqual(CalendarioMensual.corrido(anio: 2026, mes: 8, meses: 1).mes, 9)
        // Cruce de año en las dos direcciones.
        let dic = CalendarioMensual.corrido(anio: 2026, mes: 12, meses: 1)
        XCTAssertEqual(dic.anio, 2027)
        XCTAssertEqual(dic.mes, 1)
        let ene = CalendarioMensual.corrido(anio: 2026, mes: 1, meses: -1)
        XCTAssertEqual(ene.anio, 2025)
        XCTAssertEqual(ene.mes, 12)
        // Saltos grandes en negativo, que es donde la aritmética de módulo suele
        // dar mes 0 o mes 13.
        let atras = CalendarioMensual.corrido(anio: 2026, mes: 3, meses: -15)
        XCTAssertEqual(atras.anio, 2024)
        XCTAssertEqual(atras.mes, 12)
        for delta in -40...40 {
            let r = CalendarioMensual.corrido(anio: 2026, mes: 6, meses: delta)
            XCTAssertTrue((1...12).contains(r.mes), "delta \(delta) dio mes \(r.mes)")
        }
    }
}
