import Foundation

/// La ficha viva, como la ve la persona en Mi espacio (`api/src/ficha.ts`).
public struct Ficha: Decodable, Sendable {
    /// Si este diario la tiene. Si no, Mi espacio no la muestra.
    public let activa: Bool
    /// Si ya leyó el aviso. Sin eso el servidor no la arma.
    public let avisada: Bool
    /// El día en que se borra la cuenta, si está en la papelera.
    public let cuentaSeBorraEl: String?
    public var secciones: [SeccionDeLaFicha]

    enum CodingKeys: String, CodingKey {
        case activa, avisada, secciones
        case cuentaSeBorraEl = "cuenta_se_borra_el"
    }
}

public struct SeccionDeLaFicha: Decodable, Sendable, Identifiable, Hashable {
    public let tipo: String
    public let titulo: String
    public var datos: [DatoDeLaFicha]
    public var id: String { tipo }

    public init(tipo: String, titulo: String, datos: [DatoDeLaFicha]) {
        self.tipo = tipo; self.titulo = titulo; self.datos = datos
    }
}

public struct DatoDeLaFicha: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let nombre: String
    public let descripcion: String?
    public let veces: Int
    public let primera: String
    public let ultima: String
    public var compartir: Bool
    public let citas: [Cita]
    /// Cómo más le dice («el viejo» por «su papá»). Un servidor viejo no lo manda.
    public var apodos: [String] = []
    /// Cuándo le sirve (lo más seguido primero) y para qué. Sólo en «Qué le sirve».
    public var momentos: [String] = []
    public var para: [String] = []

    enum CodingKeys: String, CodingKey { case id, nombre, descripcion, veces, primera, ultima, compartir, citas, apodos, momentos, para }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); nombre = try c.decode(String.self, forKey: .nombre)
        descripcion = try c.decodeIfPresent(String.self, forKey: .descripcion); veces = try c.decode(Int.self, forKey: .veces)
        primera = try c.decode(String.self, forKey: .primera); ultima = try c.decode(String.self, forKey: .ultima)
        compartir = try c.decode(Bool.self, forKey: .compartir); citas = try c.decode([Cita].self, forKey: .citas)
        apodos = try c.decodeIfPresent([String].self, forKey: .apodos) ?? []
        momentos = try c.decodeIfPresent([String].self, forKey: .momentos) ?? []
        para = try c.decodeIfPresent([String].self, forKey: .para) ?? []
    }

    public struct Cita: Decodable, Sendable, Hashable {
        public let dia: String
        public let cita: String
        public init(dia: String, cita: String) { self.dia = dia; self.cita = cita }
    }

    public init(id: Int, nombre: String, descripcion: String?, veces: Int, primera: String,
                ultima: String, compartir: Bool, citas: [Cita]) {
        self.id = id; self.nombre = nombre; self.descripcion = descripcion; self.veces = veces
        self.primera = primera; self.ultima = ultima; self.compartir = compartir; self.citas = citas
    }
}

extension SyncClient {
    /// `GET /ficha`. `nil` si no se pudo preguntar.
    public func ficha() async -> Ficha? {
        guard let (data, resp) = try? await ejecutar(pedido("GET", "ficha")),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Ficha.self, from: data)
    }

    /// `GET /ficha/compartida`: lo que eligió para su psicólogo, para el PDF.
    public func fichaCompartida() async -> [SeccionDeLaFicha]? {
        struct R: Decodable { let secciones: [SeccionDeLaFicha] }
        guard let (data, resp) = try? await ejecutar(pedido("GET", "ficha/compartida")),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONDecoder().decode(R.self, from: data))?.secciones
    }

    public func leyoElAviso() async -> Bool { await ok("POST", "ficha/aviso", cuerpo: Data("{}".utf8)) }

    public func compartir(dato: Int, _ si: Bool) async -> Bool {
        await ok("PATCH", "ficha/\(dato)", cuerpo: Data("{\"compartir\":\(si)}".utf8))
    }

    public func quitar(dato: Int) async -> Bool { await ok("DELETE", "ficha/\(dato)") }

    /// Borra la conversación en el servidor, con lo que salió de ella.
    public func borrarConversacion(uuid: String) async -> Bool { await ok("DELETE", "entradas/\(uuid)") }

    /// Manda la cuenta a la papelera. Devuelve el día en que se borra del todo.
    public func borrarCuenta() async -> String? {
        struct R: Decodable { let se_borra_el: String }
        guard let (data, resp) = try? await ejecutar(pedido("POST", "cuenta/borrar", cuerpo: Data("{}".utf8))),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONDecoder().decode(R.self, from: data))?.se_borra_el
    }

    public func recuperarCuenta() async -> Bool { await ok("POST", "cuenta/recuperar", cuerpo: Data("{}".utf8)) }

    private func ok(_ metodo: String, _ ruta: String, cuerpo: Data? = nil) async -> Bool {
        guard let (_, resp) = try? await ejecutar(pedido(metodo, ruta, cuerpo: cuerpo)),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}

extension DatoDeLaFicha {
    /// «En la noche · para: le cuesta dormir», o nil si no se sabe ni cuándo ni para qué.
    public var cuandoYParaQue: String? {
        let partes = [momentos.prefix(2).joined(separator: " y ").capitalizedPrimera,
                      para.isEmpty ? "" : "para: " + para.prefix(3).joined(separator: ", ")].filter { !$0.isEmpty }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }
}

extension String {
    var capitalizedPrimera: String { prefix(1).uppercased() + dropFirst() }
}
