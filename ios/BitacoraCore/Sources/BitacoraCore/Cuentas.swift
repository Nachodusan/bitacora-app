import Foundation

/// Las cuentas (28/10/2026): un ID que da el servidor y un PIN de seis dígitos.
/// Ver `api/src/cuentas.ts`.
public struct PerfilDeCuenta: Codable, Sendable, Equatable {
    public var id: String?
    public var nombre: String?
    /// YYYY-MM-DD. La edad la calcula el servidor cada día.
    public var fecha_nacimiento: String?
    public var pais: String?
    public var ciudad: String?
    public var con_quien: String?

    public init(nombre: String? = nil, fecha_nacimiento: String? = nil, pais: String? = nil,
                ciudad: String? = nil, con_quien: String? = nil) {
        self.nombre = nombre; self.fecha_nacimiento = fecha_nacimiento; self.pais = pais
        self.ciudad = ciudad; self.con_quien = con_quien
    }

    /// Para mandar: sin el ID, y con `null` explícito en lo que no dio.
    func cuerpo(extra: [String: Any] = [:]) -> Data? {
        var d: [String: Any] = extra
        d["nombre"] = nombre ?? NSNull()
        d["fecha_nacimiento"] = fecha_nacimiento ?? NSNull()
        d["pais"] = pais ?? NSNull()
        d["ciudad"] = ciudad ?? NSNull()
        d["con_quien"] = con_quien ?? NSNull()
        return try? JSONSerialization.data(withJSONObject: d)
    }
}

public enum ResultadoDeCuenta: Sendable, Equatable {
    case lista(id: String?, token: String)
    case incorrecto
    /// Cinco errores seguidos: espera hasta esa hora.
    case trabada(hasta: String)
    case sinServidor
}

extension SyncClient {
    private func sinToken(_ metodo: String, _ ruta: String, cuerpo: Data?) -> URLRequest {
        var r = pedido(metodo, ruta, cuerpo: cuerpo)
        r.setValue(nil, forHTTPHeaderField: "Authorization")
        return r
    }

    private func resultado(_ r: URLRequest) async -> ResultadoDeCuenta {
        struct R: Decodable { let id: String?; let token: String?; let trabada_hasta: String? }
        guard let (data, resp) = try? await ejecutar(r), let http = resp as? HTTPURLResponse
        else { return .sinServidor }
        let d = try? JSONDecoder().decode(R.self, from: data)
        switch http.statusCode {
        case 200, 201: return d?.token.map { .lista(id: d?.id, token: $0) } ?? .sinServidor
        case 401: return .incorrecto
        case 423: return .trabada(hasta: d?.trabada_hasta ?? "")
        default: return .sinServidor
        }
    }

    /// `POST /cuentas`: una cuenta nueva, con su perfil. Devuelve el ID y la sesión.
    public func crearCuenta(pin: String, perfil: PerfilDeCuenta, zona: String) async -> ResultadoDeCuenta {
        await resultado(sinToken("POST", "cuentas", cuerpo: perfil.cuerpo(extra: ["pin": pin, "zona": zona])))
    }

    /// `POST /cuentas/entrar`: volver a entrar con ID y PIN.
    public func entrar(id: String, pin: String) async -> ResultadoDeCuenta {
        let cuerpo = try? JSONSerialization.data(withJSONObject: ["id": id, "pin": pin])
        return await resultado(sinToken("POST", "cuentas/entrar", cuerpo: cuerpo))
    }

    /// `POST /cuenta/pin`: el diario de antes de las cuentas elige su PIN.
    public func elegirPin(_ pin: String) async -> ResultadoDeCuenta {
        let cuerpo = try? JSONSerialization.data(withJSONObject: ["pin": pin])
        return await resultado(pedido("POST", "cuenta/pin", cuerpo: cuerpo))
    }

    public func perfil() async -> PerfilDeCuenta? {
        guard let (data, resp) = try? await ejecutar(pedido("GET", "perfil")),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(PerfilDeCuenta.self, from: data)
    }

    @discardableResult
    public func guardarPerfil(_ p: PerfilDeCuenta) async -> Bool {
        guard let (_, resp) = try? await ejecutar(pedido("PUT", "perfil", cuerpo: p.cuerpo())) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}
