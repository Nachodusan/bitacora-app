import Foundation
import SwiftUI

/// Dónde está el backend y cómo te llamás.
///
/// EL SERVIDOR VIENE DENTRO DE LA APP (06/10/2026). La dirección sale del
/// Info.plist y el token de `Servidor.plist`, que git ignora. Hasta ese día
/// los dos se podían cambiar en Ajustes; desde que el servidor vive en el VPS,
/// con una dirección de Tailscale que no cambia, Dusan pidió que no aparezcan
/// en la app.
@Observable
@MainActor
final class Config {
    static let shared = Config()

    private enum Claves {
        static let url = "bitacora.api_url"
        static let token = "bitacora.token"
        static let timbre = "bitacora.timbre"
        static let nombre = "bitacora.nombre"
        static let nombrePreguntado = "bitacora.nombre_preguntado"
        static let vozNatural = "bitacora.voz_natural"
        static let sesion = "bitacora.sesion"
        static let cuentaId = "bitacora.cuenta_id"
    }

    let urlTexto: String
    /// El token fijo de antes de las cuentas (`Servidor.plist`). Sólo sirve
    /// para que el diario que ya existía elija su PIN.
    let tokenFijo: String

    /// La sesión de la cuenta (28/10/2026), en el llavero. Con ella, todo va
    /// a la base de esa cuenta.
    var sesion: String? {
        didSet { Llavero.guardar(sesion, en: Claves.sesion) }
    }
    /// El ID de la cuenta, para mostrarlo y anotarlo.
    var cuentaId: String? {
        didSet { UserDefaults.standard.set(cuentaId, forKey: Claves.cuentaId) }
    }

    /// Con la sesión si hay; si no, el token fijo (sólo el diario de antes).
    var token: String { sesion ?? tokenFijo }

    /// Cómo querés que Bitácora te llame.
    ///
    /// Vacío es una respuesta válida y no un estado a medias: nadie está
    /// obligado a dar su nombre para escribir un diario, y sin nombre la charla
    /// funciona igual — simplemente no te nombra.
    var nombre: String {
        didSet { UserDefaults.standard.set(nombre, forKey: Claves.nombre) }
    }

    /// Si la pregunta del nombre ya se hizo alguna vez.
    ///
    /// Tiene que ser una marca, no `nombre.isEmpty`: dejarlo en blanco es una
    /// respuesta válida, y preguntar de nuevo en cada arranque sería no haberla
    /// escuchado.
    var nombrePreguntado: Bool {
        didSet { UserDefaults.standard.set(nombrePreguntado, forKey: Claves.nombrePreguntado) }
    }


    /// De quién es la voz de Bitácora.
    var timbre: Timbre {
        didSet { UserDefaults.standard.set(timbre.rawValue, forKey: Claves.timbre) }
    }

    /// Si Bitácora habla con la voz del servidor o con la de iOS.
    ///
    /// Prendido de fábrica: la voz de iOS es la que Dusan describió como "muy
    /// robótica", y ninguna cantidad de parámetros la arregla. Apagarlo tiene
    /// sentido igual —sin datos, con el teléfono en avión, o si preferís que
    /// nada salga— y no rompe nada: la charla funciona idéntica, sólo cambia
    /// quién pone la voz.
    ///
    /// Apagado NO es lo mismo que sin red. Sin red la app cae sola a la voz de
    /// iOS sin preguntar; esto es para no intentarlo siquiera.
    var vozNatural: Bool {
        didSet { UserDefaults.standard.set(vozNatural, forKey: Claves.vozNatural) }
    }

    /// Un valor guardado que está vacío es como si no estuviera: una cadena
    /// vacía es un `String` perfectamente válido, y `??` la daría por buena.
    private static func siTieneAlgo(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    /// El token, del `Servidor.plist` que va dentro de la app. Si no está
    /// —alguien compiló sin armarlo—, vacío: la app avisa que el servidor no
    /// la reconoce en vez de caerse.
    private static var tokenDelBundle: String? {
        guard let url = Bundle.main.url(forResource: "Servidor", withExtension: "plist"),
              let datos = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: datos, format: nil)
                as? [String: Any]
        else { return nil }
        return siTieneAlgo(plist["BITACORA_TOKEN"] as? String)
    }

    private init() {
        let d = UserDefaults.standard
        let info = Bundle.main.infoDictionary
        #if targetEnvironment(simulator)
        // En el simulador se puede apuntar a un servidor de prueba escribiendo
        // estas dos claves desde afuera (`simctl spawn … defaults write`), para
        // no ensuciar el diario. Ver «Probar en el simulador» en docs/arquitectura.md.
        let urlDePrueba = Config.siTieneAlgo(d.string(forKey: Claves.url))
        let tokenDePrueba = Config.siTieneAlgo(d.string(forKey: Claves.token))
        #else
        // En el teléfono, lo que haya quedado de cuando se cargaban en Ajustes
        // se borra: apuntaba a la Mac, y el token ya no abre nada.
        d.removeObject(forKey: Claves.url)
        d.removeObject(forKey: Claves.token)
        let urlDePrueba: String? = nil
        let tokenDePrueba: String? = nil
        #endif
        urlTexto = urlDePrueba
            ?? Config.siTieneAlgo(info?["BITACORA_API_URL"] as? String)
            ?? "http://localhost:3000"
        tokenFijo = tokenDePrueba ?? Config.tokenDelBundle ?? ""
        sesion = Llavero.leer(Claves.sesion)
        cuentaId = d.string(forKey: Claves.cuentaId)
        nombre = d.string(forKey: Claves.nombre) ?? ""
        nombrePreguntado = d.bool(forKey: Claves.nombrePreguntado)
        timbre = d.string(forKey: Claves.timbre).flatMap(Timbre.init(rawValue:)) ?? .mujer
        // `object(forKey:)` y no `bool(forKey:)`: el segundo devuelve false
        // cuando la clave no existe, así que la voz linda habría venido apagada
        // de fábrica sin que nadie la apagara.
        // Siempre prendida desde el 26/10/2026: Ajustes ya no tiene el interruptor,
        // y alguien que la hubiera apagado antes quedaría con la voz de iOS sin
        // forma de volver. Sin internet igual habla la de iOS.
        vozNatural = true
    }

    /// Si hay a dónde llamar. Un token vacío es "todavía no configuraste
    /// nada", y para la voz eso significa no intentarlo: el pedido rebotaría
    /// con 401 y el único efecto sería un segundo de silencio antes de caer a
    /// la voz de iOS.
    var hayServidor: Bool {
        !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var servidor: ConfigServidor {
        ConfigServidor(baseURL: URL(string: urlTexto) ?? URL(string: "http://localhost:3000")!,
                       token: token)
    }

    /// Manda al servidor lo que necesita saber de vos: el nombre y la zona.
    ///
    /// La zona sale del sistema en cada llamada y no se guarda: si te mudás o
    /// viajás, el teléfono ya lo sabe y no hay que ir a corregirlo a mano. El
    /// tick la usa para decidir qué días ya terminaron.
    func aplicar() async {
        await SyncClient(config: servidor).guardarAjustes(nombre: nombre,
                                                           zona: TimeZone.current.identifier)
    }
}

/// Lo mínimo del llavero de iOS, para la sesión. A diferencia de
/// `UserDefaults`, sobrevive cifrado y no viaja en las copias sin cifrar.
enum Llavero {
    private static func consulta(_ clave: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "bitacora",
         kSecAttrAccount as String: clave]
    }

    static func leer(_ clave: String) -> String? {
        var q = consulta(clave)
        q[kSecReturnData as String] = true
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func guardar(_ valor: String?, en clave: String) {
        SecItemDelete(consulta(clave) as CFDictionary)
        guard let valor else { return }
        var q = consulta(clave)
        q[kSecValueData as String] = Data(valor.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}
