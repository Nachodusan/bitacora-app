import Foundation

/// Lo que llega por un turno en vivo (`POST /charla/vivo`).
///
/// El servidor no manda una respuesta: deja la conexión abierta y por ella van
/// saliendo tramas mientras Bitácora escribe y la voz se sintetiza. Cada trama es
/// un byte que dice qué es, cuatro con el largo, y el contenido.
public enum TramaDeCharla: Equatable, Sendable {
    /// El texto de Bitácora hasta ahora, entero. Reemplaza al anterior.
    case texto(String)
    /// La frecuencia del audio, en hertz. Llega una vez, antes del primer audio.
    case frecuencia(Int)
    /// Audio: muestras de 16 bits, mono, little-endian.
    case audio(Data)
    /// El final del turno.
    ///
    /// `ok` en falso es que el servidor no pudo generar el turno, y `texto` es
    /// la despedida fija. `faltaDecir` es lo que la voz del servidor no llegó a
    /// decir —se quedó sin presupuesto, se cayó el proveedor—: vacío si lo dijo
    /// todo, y si no, lo que el teléfono tiene que decir con la voz de iOS.
    case fin(ok: Bool, texto: String, faltaDecir: String)
    /// El corte de riesgo del servidor se disparó. Llega en lugar del turno,
    /// sin texto ni audio antes: `texto` es el mensaje fijo de cuidado, que dice
    /// la voz del teléfono, y la charla se cierra.
    case cuidado(texto: String)
}

/// Arma las tramas a partir de los bytes que van llegando.
///
/// Los pedazos de red no coinciden con las tramas: una puede llegar partida en
/// tres, y en un mismo pedazo pueden venir cuatro. Acá se junta lo que llega y
/// se devuelven las que ya están completas.
public struct LectorDeTramas: Sendable {
    private var resto = Data()

    public init() {}

    /// Cuántos bytes faltan para completar la trama en curso. Sirve para leer
    /// la conexión de a lo justo, sin esperar bytes que todavía no salieron.
    public var faltan: Int {
        guard resto.count >= 5 else { return 5 - resto.count }
        return 5 + Self.largo(resto) - resto.count
    }

    public mutating func recibir(_ datos: Data) -> [TramaDeCharla] {
        resto.append(datos)
        var tramas: [TramaDeCharla] = []
        while resto.count >= 5 {
            let largo = Self.largo(resto)
            guard resto.count >= 5 + largo else { break }
            let tipo = resto[resto.startIndex]
            let cuerpo = resto.subdata(in: (resto.startIndex + 5)..<(resto.startIndex + 5 + largo))
            resto = resto.subdata(in: (resto.startIndex + 5 + largo)..<resto.endIndex)
            if let t = Self.trama(tipo, cuerpo) { tramas.append(t) }
        }
        return tramas
    }

    private static func largo(_ d: Data) -> Int {
        let i = d.startIndex
        return Int(d[i + 1]) << 24 | Int(d[i + 2]) << 16 | Int(d[i + 3]) << 8 | Int(d[i + 4])
    }

    /// Una trama de un tipo que no se conoce se saltea: así el servidor puede
    /// agregar una nueva sin romper a un teléfono que no se actualizó.
    private static func trama(_ tipo: UInt8, _ cuerpo: Data) -> TramaDeCharla? {
        switch tipo {
        case UInt8(ascii: "T"):
            return .texto(String(decoding: cuerpo, as: UTF8.self))
        case UInt8(ascii: "H"):
            return Int(String(decoding: cuerpo, as: UTF8.self)).map { .frecuencia($0) }
        case UInt8(ascii: "A"):
            return .audio(cuerpo)
        case UInt8(ascii: "F"):
            guard let f = try? JSONDecoder().decode(Fin.self, from: cuerpo) else { return nil }
            if f.cuidado == true { return .cuidado(texto: f.texto) }
            return .fin(ok: f.ok, texto: f.texto,
                        faltaDecir: desde(f.hablado ?? 0, en: f.texto))
        default:
            return nil
        }
    }

    private struct Fin: Decodable {
        let ok: Bool
        let texto: String
        let hablado: Int?
        let cuidado: Bool?
    }

    /// Lo que queda del texto a partir de `n`, sin espacios de más.
    ///
    /// `n` lo cuenta el servidor, que está en JavaScript: son unidades UTF-16,
    /// no caracteres como los cuenta Swift. Con un emoji o ciertos acentos las
    /// dos cuentas difieren, y cortar con la equivocada repetiría o se comería
    /// una letra.
    static func desde(_ n: Int, en texto: String) -> String {
        let u = texto.utf16
        guard n > 0 else { return texto.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard n < u.count, let i = u.index(u.startIndex, offsetBy: n, limitedBy: u.endIndex),
              let corte = i.samePosition(in: texto) else { return "" }
        return String(texto[corte...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
