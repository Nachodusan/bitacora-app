import Foundation

/// De dónde salió el texto. El audio no se sube nunca, así que no hay una
/// fuente "transcripto en el servidor": sería mentir sobre lo que hace la app.
public enum Fuente: String, Codable, Sendable {
    case dictadoIos = "dictado_ios"
    case texto
}

/// El cuerpo exacto de `POST /entradas`. Los nombres de las claves son los del
/// contrato del backend, no los de Swift.
public struct EntradaNueva: Codable, Equatable, Sendable {
    public let clientUuid: String
    public let creadoEn: String      // ISO 8601 con offset — instante absoluto
    public let creadoLocal: String   // ISO 8601 sin offset — hora de pared
    public let fuente: Fuente
    public let transcripcion: String
    public let duracionSeg: Double

    enum CodingKeys: String, CodingKey {
        case clientUuid = "client_uuid"
        case creadoEn = "creado_en"
        case creadoLocal = "creado_local"
        case fuente
        case transcripcion
        case duracionSeg = "duracion_seg"
    }

    public init(clientUuid: String, creadoEn: String, creadoLocal: String,
                fuente: Fuente, transcripcion: String, duracionSeg: Double) {
        self.clientUuid = clientUuid
        self.creadoEn = creadoEn
        self.creadoLocal = creadoLocal
        self.fuente = fuente
        self.transcripcion = transcripcion
        self.duracionSeg = duracionSeg
    }

    /// Arma la entrada desde el instante de grabación. Emite los dos timestamps
    /// que pide la regla 2: el absoluto y el de pared. El servidor no deriva uno
    /// del otro — no puede, porque no conoce la zona del teléfono.
    public static func desde(instante: Date,
                            zona: TimeZone,
                            transcripcion: String,
                            duracionSeg: Double,
                            fuente: Fuente = .dictadoIos,
                            clientUuid: String = UUID().uuidString) -> EntradaNueva {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = zona
        return EntradaNueva(
            clientUuid: clientUuid,
            creadoEn: f.string(from: instante),
            creadoLocal: HoraDePared(instante: instante, zona: zona).iso8601SinZona,
            fuente: fuente,
            transcripcion: transcripcion,
            duracionSeg: duracionSeg
        )
    }
}

public struct RespuestaEntrada: Codable, Equatable, Sendable {
    public let id: Int64
    public let dia: String?
    public init(id: Int64, dia: String? = nil) {
        self.id = id
        self.dia = dia
    }
}
