import Foundation

/// La grilla de un mes, en semanas de 7 celdas.
///
/// Las celdas son claves de día lógico ("yyyy-MM-dd"), las mismas que produce
/// `DiaLogico.dia(de:)` y las mismas que guarda `entradas.dia` en Postgres. Así
/// el calendario se arma cruzando strings y nunca vuelve a mezclar "fecha del
/// reloj" con "día de la bitácora", que es donde el corte de las 4am se rompe.
///
/// `nil` es relleno: días de otro mes que completan la primera y la última semana.
public struct GrillaMes: Equatable, Sendable {
    public let anio: Int
    public let mes: Int
    public let semanas: [[String?]]

    /// Todas las claves reales del mes, en orden.
    public var dias: [String] { semanas.flatMap { $0 }.compactMap { $0 } }
}

public enum CalendarioMensual {

    /// 1 = domingo, 2 = lunes (igual que `Calendar.firstWeekday`). Acá arranca
    /// en lunes porque es como se lee un calendario en Argentina.
    public static let primerDiaDeSemana = 2

    public static func grilla(anio: Int, mes: Int) -> GrillaMes {
        let cal = HoraDePared.calendario
        let primero = cal.date(from: DateComponents(year: anio, month: mes, day: 1))!
        let cantidadDeDias = cal.range(of: .day, in: .month, for: primero)!.count

        // Cuántas celdas vacías van antes del día 1.
        let diaSemanaDelPrimero = cal.component(.weekday, from: primero)   // 1=domingo
        let relleno = (diaSemanaDelPrimero - primerDiaDeSemana + 7) % 7

        var celdas: [String?] = Array(repeating: nil, count: relleno)
        for d in 1...cantidadDeDias {
            celdas.append(String(format: "%04d-%02d-%02d", anio, mes, d))
        }
        // Completar la última semana.
        while celdas.count % 7 != 0 { celdas.append(nil) }

        return GrillaMes(anio: anio, mes: mes,
                         semanas: stride(from: 0, to: celdas.count, by: 7).map {
                             Array(celdas[$0..<$0 + 7])
                         })
    }

    /// Mes anterior / siguiente, sin pasarse de diciembre ni de enero.
    public static func corrido(anio: Int, mes: Int, meses delta: Int) -> (anio: Int, mes: Int) {
        let total = anio * 12 + (mes - 1) + delta
        return (total / 12, total % 12 + 1)
    }

    /// Nombres de las columnas, empezando por el `primerDiaDeSemana`.
    public static let encabezados = ["L", "M", "M", "J", "V", "S", "D"]
}
