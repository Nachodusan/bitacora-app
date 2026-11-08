import Foundation

/// Hora de pared del teléfono, sin zona horaria.
///
/// Existe porque la columna `entradas.creado_local` en Postgres es `timestamp`
/// SIN zona, y el día lógico se calcula sobre ella. Si acá usáramos un `Date`
/// (que es un instante absoluto) tendríamos que elegir una zona para volver a
/// pared, y esa elección es justamente la que el esquema decidió no hacer.
///
/// `Date` responde "qué instante fue"; `HoraDePared` responde "qué hora marcaba
/// el teléfono". Para el corte de las 4am la segunda es la que importa.
public struct HoraDePared: Equatable, Hashable, Sendable {
    public var anio: Int
    public var mes: Int
    public var dia: Int
    public var hora: Int
    public var minuto: Int
    public var segundo: Int

    public init(anio: Int, mes: Int, dia: Int, hora: Int, minuto: Int, segundo: Int = 0) {
        self.anio = anio
        self.mes = mes
        self.dia = dia
        self.hora = hora
        self.minuto = minuto
        self.segundo = segundo
    }

    /// Calendario auxiliar fijado en UTC. No implica que la hora sea UTC: es el
    /// truco de siempre para hacer aritmética de calendario sobre una hora de
    /// pared sin que ninguna zona ni ningún horario de verano la corra.
    static let calendario: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// Lee la hora de pared de un instante, en la zona indicada.
    /// En el teléfono esto se llama con `TimeZone.current`.
    public init(instante: Date, zona: TimeZone) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        let p = c.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instante)
        self.init(anio: p.year!, mes: p.month!, dia: p.day!,
                  hora: p.hour!, minuto: p.minute!, segundo: p.second!)
    }

    var comoFechaAuxiliar: Date {
        HoraDePared.calendario.date(from: DateComponents(
            year: anio, month: mes, day: dia,
            hour: hora, minute: minuto, second: segundo))!
    }

    /// Formato que espera la API para `creado_local`: ISO 8601 sin offset.
    /// Postgres lo parsea directo como `timestamp` sin zona.
    public var iso8601SinZona: String {
        String(format: "%04d-%02d-%02dT%02d:%02d:%02d",
               anio, mes, dia, hora, minuto, segundo)
    }
}

public enum DiaLogico {
    /// Corte del día lógico. Lo que hablás antes de esta hora pertenece al día
    /// anterior. Tiene que coincidir con el `interval '4 hours'` de la columna
    /// generada `entradas.dia`; si cambia uno, cambia el otro.
    public static let horaDeCorte = 4

    /// Réplica exacta de `(creado_local - interval '4 hours')::date`.
    ///
    /// El servidor no recalcula esto: la columna es generada y manda Postgres.
    /// Acá se calcula igual para poder agrupar y mostrar en el teléfono sin
    /// esperar el sync, y el test compara ambos resultados.
    public static func dia(de pared: HoraDePared) -> String {
        let corrido = HoraDePared.calendario.date(
            byAdding: .hour, value: -horaDeCorte, to: pared.comoFechaAuxiliar)!
        let p = HoraDePared.calendario.dateComponents([.year, .month, .day], from: corrido)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
}
