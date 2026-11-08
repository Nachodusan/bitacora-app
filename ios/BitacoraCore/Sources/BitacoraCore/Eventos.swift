import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Un evento del calendario, tal como lo manda el servidor (`consultas.ts`).
///
/// Casi siempre una consulta con su terapeuta. Viven en el servidor porque
/// Bitácora las tiene que ver —para ayudar a preparar una sesión y para
/// preguntar cómo le fue— y porque puede proponer una que la persona mencionó
/// en una charla. El teléfono guarda una copia para mostrarlas sin red.
public struct Evento: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let clientUuid: String?
    /// "consulta" u "otro".
    public let tipo: String
    /// "YYYY-MM-DD".
    public let dia: String
    /// "HH:MM", o `nil` si no tiene hora.
    public let hora: String?
    public let titulo: String?
    /// "persona" o "bitacora".
    public let origen: String
    /// "confirmado" o "propuesto". Los descartados no llegan.
    public let estado: String
    /// Lo que eligió llevar, en la charla del día anterior.
    public let paraLlevar: [String]
    /// El borrador de la evaluación, escrito con lo que contó después. Está en
    /// el servidor sólo hasta que la evaluación queda guardada acá.
    public let borrador: BorradorDeEvaluacion?
    public let evaluada: Bool

    public var esConsulta: Bool { tipo == "consulta" }
    public var esPropuesta: Bool { estado == "propuesto" }

    enum CodingKeys: String, CodingKey {
        case id, tipo, dia, hora, titulo, origen, estado, borrador, evaluada
        case clientUuid = "client_uuid"
        case paraLlevar = "para_llevar"
    }

    public init(id: Int, clientUuid: String? = nil, tipo: String, dia: String, hora: String? = nil,
                titulo: String? = nil, origen: String = "persona", estado: String = "confirmado",
                paraLlevar: [String] = [], borrador: BorradorDeEvaluacion? = nil, evaluada: Bool = false) {
        self.id = id
        self.clientUuid = clientUuid
        self.tipo = tipo
        self.dia = dia
        self.hora = hora
        self.titulo = titulo
        self.origen = origen
        self.estado = estado
        self.paraLlevar = paraLlevar
        self.borrador = borrador
        self.evaluada = evaluada
    }
}

// MARK: - La próxima consulta

extension Evento {
    /// Cuándo es, para compararlo con la hora de pared: "YYYY-MM-DD HH:MM". Sin
    /// hora cuenta el mediodía, igual que en el servidor (`MOMENTO`, en
    /// `consultas.ts`): así los dos están de acuerdo en si ya pasó.
    public var momento: String { "\(dia) \(hora ?? "12:00")" }

    /// La próxima consulta confirmada que todavía no pasó, o `nil`. Es la de la
    /// tarjeta de arriba de Mi expediente (desde el 06/10/2026). Una propuesta
    /// de Bitácora no cuenta hasta que la persona la confirme.
    ///
    /// `ahora` es la hora de pared, "YYYY-MM-DD HH:MM".
    public static func proximaConsulta(en eventos: [Evento], ahora: String) -> Evento? {
        eventos.filter { $0.esConsulta && !$0.esPropuesta && $0.momento > ahora }
            .min { $0.momento < $1.momento }
    }

    /// Las consultas que se ven al entrar a la app (26/10/2026): las de este mes,
    /// también las que ya pasaron, más las que vienen en los próximos 30 días.
    /// Lo segundo es para fin de mes: el 25 de octubre, la del 2 de noviembre es
    /// la que importa y «este mes» no la traería. Confirmadas y por fecha.
    public static func consultasDelMes(en eventos: [Evento], ahora: String) -> [Evento] {
        let hoy = String(ahora.prefix(10))
        let mes = String(ahora.prefix(7))
        let hasta = sumarDias(30, a: hoy) ?? hoy
        return eventos
            .filter { $0.esConsulta && !$0.esPropuesta && ($0.dia.hasPrefix(mes) || ($0.dia >= hoy && $0.dia <= hasta)) }
            .sorted { $0.momento < $1.momento }
    }

    private static func sumarDias(_ n: Int, a dia: String) -> String? {
        guard let d = mediodia(dia), let f = Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: d)
        else { return nil }
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: f)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// «hoy», «mañana» o «en 3 días», contando desde el día lógico: a las dos de
    /// la mañana, una consulta de esa tarde es «mañana», como lo piensa quien
    /// todavía no se fue a dormir.
    public static func cuantoFalta(hasta dia: String, desde hoy: String) -> String {
        guard let a = mediodia(hoy), let b = mediodia(dia) else { return "" }
        let dias = Int((b.timeIntervalSince(a) / 86_400).rounded())
        switch dias {
        case ..<1: return "hoy"
        case 1: return "mañana"
        default: return "en \(dias) días"
        }
    }

    private static func mediodia(_ d: String) -> Date? {
        let p = d.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
}

/// Lo que el servidor sacó de las charlas de después de una consulta, para que
/// la evaluación no se cargue a mano. La persona lo revisa antes de guardarla.
///
/// Cada campo puede venir vacío: un campo vacío lo completa ella; uno
/// inventado lo tendría que borrar.
public struct BorradorDeEvaluacion: Codable, Sendable, Equatable {
    public let entendi: String
    public let aporte: String
    public let sentir: String
    public let temas: [String]
    public let avance: String

    public init(entendi: String = "", aporte: String = "", sentir: String = "",
                temas: [String] = [], avance: String = "") {
        self.entendi = entendi
        self.aporte = aporte
        self.sentir = sentir
        self.temas = temas
        self.avance = avance
    }

    /// Tolerante a campos que falten: un borrador viejo o a medias no tiene que
    /// hacer que no se lea ningún evento.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entendi = try c.decodeIfPresent(String.self, forKey: .entendi) ?? ""
        aporte = try c.decodeIfPresent(String.self, forKey: .aporte) ?? ""
        sentir = try c.decodeIfPresent(String.self, forKey: .sentir) ?? ""
        temas = try c.decodeIfPresent([String].self, forKey: .temas) ?? []
        avance = try c.decodeIfPresent(String.self, forKey: .avance) ?? ""
    }
}

/// El cuerpo del `PATCH /eventos/:id`: sólo lo que cambia.
///
/// `hora` y `titulo` son opcionales dobles porque hay tres casos y no dos: no
/// tocarla (`nil`), sacarla (`.some(nil)`, que viaja como `null`) y ponerla.
public struct CambioDeEvento: Encodable, Sendable {
    public var dia: String?
    public var hora: String??
    public var titulo: String??
    /// "confirmado" o "descartado".
    public var estado: String?
    public var evaluada: Bool?

    public init(dia: String? = nil, hora: String?? = nil, titulo: String?? = nil,
                estado: String? = nil, evaluada: Bool? = nil) {
        self.dia = dia
        self.hora = hora
        self.titulo = titulo
        self.estado = estado
        self.evaluada = evaluada
    }

    enum CodingKeys: String, CodingKey { case dia, hora, titulo, estado, evaluada }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(dia, forKey: .dia)
        if let hora { try c.encode(hora, forKey: .hora) }
        if let titulo { try c.encode(titulo, forKey: .titulo) }
        try c.encodeIfPresent(estado, forKey: .estado)
        try c.encodeIfPresent(evaluada, forKey: .evaluada)
    }
}

struct EventoQueViaja: Encodable {
    let clientUuid: String
    let tipo: String
    let dia: String
    let hora: String?
    let titulo: String?

    enum CodingKeys: String, CodingKey {
        case tipo, dia, hora, titulo
        case clientUuid = "client_uuid"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clientUuid, forKey: .clientUuid)
        try c.encode(tipo, forKey: .tipo)
        try c.encode(dia, forKey: .dia)
        try c.encode(hora, forKey: .hora)
        try c.encode(titulo, forKey: .titulo)
    }
}

struct RespuestaEventos: Decodable { let eventos: [Evento] }
struct RespuestaEvento: Decodable { let evento: Evento }

extension SyncClient {

    /// `GET /eventos`. `nil` si no se pudo preguntar, que no es lo mismo que
    /// no tener ninguno: con `nil` el teléfono se queda con su copia.
    public func eventos() async -> [Evento]? {
        guard let (data, resp) = try? await ejecutar(pedido("GET", "eventos")),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let d = try? JSONDecoder().decode(RespuestaEventos.self, from: data)
        else { return nil }
        return d.eventos
    }

    /// `POST /eventos`. Idempotente por `clientUuid`: reintentar no duplica.
    public func crearEvento(clientUuid: String, tipo: String, dia: String,
                            hora: String?, titulo: String?) async -> Evento? {
        let cuerpo = EventoQueViaja(clientUuid: clientUuid, tipo: tipo, dia: dia, hora: hora, titulo: titulo)
        guard let datos = try? JSONEncoder().encode(cuerpo),
              let (data, resp) = try? await ejecutar(pedido("POST", "eventos", cuerpo: datos)),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 201,
              let d = try? JSONDecoder().decode(RespuestaEvento.self, from: data)
        else { return nil }
        return d.evento
    }

    /// `PATCH /eventos/:id`.
    public func cambiarEvento(id: Int, _ cambio: CambioDeEvento) async -> Evento? {
        guard let datos = try? JSONEncoder().encode(cambio),
              let (data, resp) = try? await ejecutar(pedido("PATCH", "eventos/\(id)", cuerpo: datos)),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let d = try? JSONDecoder().decode(RespuestaEvento.self, from: data)
        else { return nil }
        return d.evento
    }

    /// `DELETE /eventos/:id`. Un 404 también es que ya no está.
    public func borrarEvento(id: Int) async -> Bool {
        guard let (_, resp) = try? await ejecutar(pedido("DELETE", "eventos/\(id)")),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 204 || http.statusCode == 404
    }
}
