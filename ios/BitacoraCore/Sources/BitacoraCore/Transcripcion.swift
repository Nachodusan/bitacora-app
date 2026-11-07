import Foundation

/// Quién habla en un turno.
public enum Hablante: String, Codable, Sendable {
    case vos
    case bitacora
}

/// Un turno de la charla.
public struct Turno: Equatable, Codable, Sendable {
    public let de: Hablante
    public let texto: String
    public init(de: Hablante, texto: String) {
        self.de = de
        self.texto = texto
    }
}

/// Cómo se escribe y cómo se lee el diálogo de una charla.
///
/// Es lo único que sobrevivió de `MotorDeConversacion`, el motor de reglas que
/// elegía la próxima pregunta antes de que existiera el compañero. Aquello
/// —temas, repreguntas, marcadores, tope de cuatro preguntas— lo reemplazó
/// `POST /charla` y se borró: mantener un cerebro paralelo al que nadie llama
/// es peor que no tenerlo, sobre todo cuando sus tests siguen en verde.
///
/// Esto no era parte de ese cerebro. Es el formato en que la conversación llega
/// a `entradas.transcripcion` y la forma correcta de volver a leerla.
public enum Transcripcion {

    /// El diálogo completo, marcado.
    ///
    /// Va con las dos voces porque sin la pregunta muchas respuestas no
    /// significan nada ("sí, como a las dos"). La contra es que el campo deja de
    /// ser sólo tus palabras, así que todo lo que cita del lado del servidor
    /// —las notas de terapia— filtra primero las líneas que arrancan con "Vos:".
    /// Sin eso, el modelo puede citar una pregunta de Bitácora como si fuera algo
    /// que dijiste.
    public static func de(_ turnos: [Turno]) -> String {
        turnos
            .map { "\($0.de == .vos ? "Vos" : "Bitácora"): \($0.texto)" }
            .joined(separator: "\n")
    }

    /// La misma transcripción con el rótulo de hoy.
    ///
    /// Hasta el 02/10/2026 Bitácora se llamaba Laya, y las conversaciones de
    /// antes tienen sus líneas rotuladas `Laya:`. Se cambia sólo el rótulo, al
    /// principio de la línea: si la persona dijo «Laya» en lo suyo, eso queda.
    /// La base del servidor se renombró con el delta 3; esto es para las que
    /// viven en el teléfono.
    public static func conRotuloNuevo(_ transcripcion: String) -> String {
        transcripcion.replacingOccurrences(of: #"(?m)^Laya:"#, with: "Bitácora:",
                                           options: .regularExpression)
    }

    /// Sólo tus palabras. Es lo que mira el chequeo de riesgo: una pregunta de
    /// Bitácora no puede disparar el corte.
    public static func soloVos(_ turnos: [Turno]) -> String {
        turnos.filter { $0.de == .vos }.map(\.texto).joined(separator: " ")
    }

    /// Lo que dijo la persona en una charla guardada, turno por turno y
    /// textual: cada línea `Vos:` con las que la siguen hasta el próximo
    /// rótulo (un turno puede tener varios párrafos). Lo de Bitácora no va.
    ///
    /// Es lo que lleva el PDF de «Mi resumen» de un día que no dejó frases
    /// separadas (`Resumen.html`).
    public static func loQueDijo(_ transcripcion: String) -> [String] {
        var turnos: [String] = []
        var actual: String?   // nil: habla Bitácora, o todavía nadie
        func cerrar() {
            if let a = actual?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { turnos.append(a) }
            actual = nil
        }
        for linea in conRotuloNuevo(transcripcion).split(separator: "\n", omittingEmptySubsequences: false) {
            if linea.hasPrefix("Vos:") {
                cerrar()
                actual = String(linea.dropFirst(4))
            } else if linea.hasPrefix("Bitácora:") {
                cerrar()
            } else if actual != nil {
                actual! += "\n" + linea
            }
        }
        cerrar()
        return turnos
    }

    /// La charla guardada, de nuevo en turnos: las dos voces, en orden.
    ///
    /// Es la vuelta de `de(_:)`, para mostrar en el calendario una charla igual
    /// que se vio en el chat —lo tuyo en globo, lo de Bitácora en serifa— y no
    /// como un bloque con «Vos:» y «Bitácora:» delante (lo pidió Dusan el
    /// 04/10/2026). Un turno puede tener varios párrafos: las líneas sin rótulo
    /// se suman al último. Lo que viene antes de cualquier rótulo —una entrada
    /// vieja, de cuando se dictaba sin charla— es de la persona.
    public static func turnos(_ transcripcion: String) -> [Turno] {
        var turnos: [Turno] = []
        var quien: Hablante = .vos
        var texto: String?
        func cerrar() {
            if let t = texto?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                turnos.append(Turno(de: quien, texto: t))
            }
            texto = nil
        }
        for linea in conRotuloNuevo(transcripcion).split(separator: "\n", omittingEmptySubsequences: false) {
            if linea.hasPrefix("Vos:") {
                cerrar()
                quien = .vos
                texto = String(linea.dropFirst(4))
            } else if linea.hasPrefix("Bitácora:") {
                cerrar()
                quien = .bitacora
                texto = String(linea.dropFirst(9))
            } else {
                texto = texto.map { $0 + "\n" + linea } ?? String(linea)
            }
        }
        cerrar()
        return turnos
    }

    /// Cuánto duró una charla, como lo diría una persona: «7 min», no «420s».
    public static func duracion(segundos: Double) -> String {
        segundos < 60 ? "menos de 1 min" : "\(Int((segundos / 60).rounded())) min"
    }
}
