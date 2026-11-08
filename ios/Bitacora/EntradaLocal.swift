import Foundation
import SwiftData

/// La entrada tal como vive en el teléfono.
///
/// Se escribe apenas soltás el botón y no se borra nunca, ni siquiera después de
/// subirla: el teléfono es la primera copia de la fuente de verdad. Si el VPS se
/// pierde, la bitácora sigue acá.
@Model
final class EntradaLocal {
    /// Idempotencia. Es la misma clave que el UNIQUE de `entradas.client_uuid`:
    /// reintentar una subida que ya llegó no crea un duplicado.
    @Attribute(.unique) var clientUuid: String

    var creadoEn: Date          // instante absoluto
    var creadoLocalISO: String  // hora de pared, ya formateada para la API
    var diaLogico: String       // corte 4am, calculado con BitacoraCore
    var transcripcion: String
    var duracionSeg: Double

    var estadoRaw: String
    var intentos: Int
    var proximoIntento: Date?
    var ultimoError: String?
    var servidorId: Int?

    enum Estado: String {
        /// La charla está pasando AHORA. Se reescribe en cada turno y la cola no
        /// la mira: subir media conversación sería resumirla a medias.
        ///
        /// Existe porque la conversación la termina la persona. Antes el motor
        /// local cerraba solo a las cuatro preguntas, así que siempre había un
        /// final y siempre se guardaba. Sin ese tope, el único camino a disco
        /// era que tocaras el orbe — y un desahogo de cuarenta minutos que
        /// termina con el teléfono apoyado en la mesa, con una llamada
        /// entrante o con iOS matando la app se perdía entero. Justo la noche
        /// que más importaba.
        case borrador
        case pendiente   // todavía no llegó al servidor
        case subida      // confirmada, con id del servidor
        case rechazada   // el servidor la rechazó con un 4xx: reintentar no sirve
    }

    var estado: Estado {
        get { Estado(rawValue: estadoRaw) ?? .pendiente }
        set { estadoRaw = newValue.rawValue }
    }

    init(transcripcion: String, duracionSeg: Double, estado: Estado = .pendiente,
         instante: Date = Date(), zona: TimeZone = .current) {
        let pared = HoraDePared(instante: instante, zona: zona)
        self.clientUuid = UUID().uuidString
        self.creadoEn = instante
        self.creadoLocalISO = pared.iso8601SinZona
        self.diaLogico = DiaLogico.dia(de: pared)
        self.transcripcion = transcripcion
        self.duracionSeg = duracionSeg
        self.estadoRaw = estado.rawValue
        self.intentos = 0
        self.proximoIntento = nil
        self.ultimoError = nil
        self.servidorId = nil
    }

    /// El cuerpo que se manda a `POST /entradas`. Se rearma desde lo guardado,
    /// no se recalcula: la hora de pared es la de cuando hablaste, no la de
    /// cuando la cola logró subirla.
    var cuerpo: EntradaNueva {
        EntradaNueva(clientUuid: clientUuid,
                     creadoEn: ISO8601DateFormatter.conOffset.string(from: creadoEn),
                     creadoLocal: creadoLocalISO,
                     fuente: .dictadoIos,
                     transcripcion: transcripcion,
                     duracionSeg: duracionSeg)
    }
}

extension ISO8601DateFormatter {
    static let conOffset: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()
}
