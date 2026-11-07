import Foundation

/// Las herramientas: momentos guiados dentro de la charla (26/10/2026).
///
/// «Ponerle nombre» ayuda a decir qué se siente cuando no sale la palabra;
/// «Calmarme ya» es una respiración guiada para cuando el cuerpo está
/// acelerado. Esto decide CUÁNDO ofrecerlas, a partir de lo que la persona
/// acaba de decir: una lista de frases, como el corte de riesgo, para que sea
/// inmediato, gratis y no dependa de la red.
///
/// Se ofrecen, no se imponen: aparecen como un botón debajo de la respuesta.
/// Y con cualquier señal de riesgo no se ofrece nada: ahí manda el cuidado.
public enum Herramienta: String, Sendable, CaseIterable {
    case nombrar
    case calmarme

    /// Lo que dice el botón.
    public var invitacion: String {
        switch self {
        case .nombrar: "Ponerle nombre a lo que siento"
        case .calmarme: "Respirar juntos un momento"
        }
    }

    /// El cuerpo acelerado va primero: si dice las dos cosas, respirar es lo
    /// que sirve ahora, y el nombre puede venir después.
    private static let delCuerpo = [
        "ansiedad", "ansios", "panico", "ataque de", "no puedo respirar", "me falta el aire",
        "falta de aire", "me ahogo", "pecho apretado", "presion en el pecho", "el corazon a mil",
        "taquicardia", "estoy temblando", "no paro de temblar", "muy nervios", "estoy nervios",
        "me desborda", "desbordad", "no puedo calmarme", "no me puedo calmar", "estoy acelerad",
        "no puedo parar de llorar", "hiperventil",
    ]

    private static let sinPalabras = [
        "no se como me siento", "no se que siento", "no se lo que siento", "no se que me pasa",
        "no se lo que me pasa", "no me sale la palabra", "no encuentro la palabra",
        "no se como explicar", "no se explicarlo", "no se describir", "no se como describir",
        "no se ni que siento", "no entiendo lo que siento", "no entiendo que siento",
        "me siento rar", "algo raro", "no se ponerle nombre", "no se que es lo que siento",
    ]

    /// Qué herramienta ofrecer después de esto, si alguna.
    public static func sugerida(para texto: String) -> Herramienta? {
        if Riesgo.haySenal(en: texto) { return nil }
        let t = Riesgo.normalizar(texto)
        if delCuerpo.contains(where: t.contains) { return .calmarme }
        if sinPalabras.contains(where: t.contains) { return .nombrar }
        return nil
    }

    /// Qué herramienta ofreció Bitácora en su respuesta, si alguna (27/10/2026).
    /// Bitácora puede invitar a usarlas por su cuenta («abajo tienes una
    /// respiración guiada»); si el botón sólo dependiera de lo que dijo la
    /// persona, la invitación quedaba sin botón y la persona no lo encontraba.
    public static func ofrecida(en respuesta: String) -> Herramienta? {
        let t = Riesgo.normalizar(respuesta)
        let respirar = ["respiracion guiada", "respirar juntos", "calmarme ya", "respirar un momento"]
        let nombrar = ["ponerle nombre a lo que", "ponerle nombre"]
        if respirar.contains(where: t.contains) { return .calmarme }
        if nombrar.contains(where: t.contains) { return .nombrar }
        return nil
    }

    /// Lo que entra a la charla cuando la persona eligió una emoción: así
    /// Bitácora lo toma, y queda en la transcripción para la nota del psicólogo.
    public static func loQueElegiste(_ emocion: String, intensidad: Int) -> String {
        "Le puse nombre a lo que siento: \(emocion), \(intensidad) de 10."
    }

    /// Lo que entra a la charla al terminar la respiración.
    public static func respire(minutos: Int, mejor: Bool) -> String {
        let cuanto = minutos <= 1 ? "un minuto" : "\(minutos) minutos"
        return mejor ? "Respiré \(cuanto) con la app. Ya estoy un poco mejor."
                     : "Respiré \(cuanto) con la app."
    }
}
