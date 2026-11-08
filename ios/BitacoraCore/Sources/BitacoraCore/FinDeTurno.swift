import Foundation

/// Cuándo se da por terminado lo que la persona está diciendo.
///
/// LA VOZ DE LA PERSONA TIENE PRIORIDAD. Dusan lo pidió con todas las letras:
/// «no termino lo que quiero decir y se corta para que la IA responda». Los
/// tiempos de antes —1,6 segundos de silencio, 0,9 si el dictado ya había puesto
/// un punto— estaban pensados para que Bitácora contestara rápido, y el costo lo
/// pagaba el que hablaba: una pausa para pensar la palabra que sigue alcanzaba
/// para que le sacaran el turno.
///
/// Ahora se espera más, y cuánto depende de cómo quedó la frase. Y si aun así
/// se cortó antes de tiempo, no se pierde nada: la app sigue escuchando mientras
/// Bitácora prepara la respuesta, y si la persona sigue hablando, esa respuesta se
/// descarta y lo nuevo se suma a lo que venía diciendo (`Conversacion`).
public enum FinDeTurno {
    /// Quedó a mitad de camino, sin signo que cierre.
    public static let silencioAMitad: TimeInterval = 2.2
    /// El dictado ya cerró la oración con punto o signo de pregunta.
    ///
    /// Sigue siendo el más corto, pero ya no es una opinión en la que confiar a
    /// ciegas: el dictado pone un punto en casi cualquier pausa.
    public static let silencioSiCerro: TimeInterval = 1.3
    /// Terminó en una palabra que pide que siga algo, o en una coma. Nadie
    /// termina una idea en «y», en «porque» o en «o sea».
    public static let silencioSiQuedoColgado: TimeInterval = 3.2

    /// Palabras con las que no se termina de hablar.
    private static let colgantes: Set<String> = [
        "y", "e", "o", "u", "pero", "porque", "que", "aunque", "si", "ni", "sino",
        "como", "cuando", "donde", "mientras", "entonces", "pues", "osea",
        "de", "del", "a", "al", "en", "con", "sin", "para", "por", "sobre", "entre",
        "hasta", "desde", "hacia", "el", "la", "los", "las", "un", "una", "unos",
        "unas", "mi", "mis", "tu", "tus", "su", "sus", "lo", "le", "me", "te", "se",
        "es", "era", "fue", "son", "estoy", "esta", "estaba", "tengo", "tiene",
        "hay", "muy", "mas", "tan", "eh", "em", "este", "bueno", "igual", "tipo",
    ]

    /// Cuánto silencio esperar antes de dar el turno por terminado.
    public static func silencio(tras dicho: String) -> TimeInterval {
        let texto = dicho.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ultima = texto.last else { return silencioAMitad }

        // Los puntos suspensivos son lo que el dictado escribe cuando la persona
        // se quedó pensando: lo contrario de un cierre.
        if texto.hasSuffix("...") || texto.hasSuffix("…") || ultima == "," {
            return silencioSiQuedoColgado
        }

        let cerro = ".?!".contains(ultima)
        let palabra = texto
            .trimmingCharacters(in: CharacterSet(charactersIn: ".?!,;:… "))
            .split(separator: " ").last.map(String.init) ?? ""
        let limpia = palabra.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .filter(\.isLetter)

        // «O sea» son dos palabras; pegadas se buscan como una.
        let dos = texto.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .filter { $0.isLetter || $0 == " " }
            .split(separator: " ").suffix(2).joined()

        // Una palabra colgante gana aunque el dictado le haya puesto un punto
        // detrás: «y.» no es una oración.
        if colgantes.contains(limpia) || colgantes.contains(dos) { return silencioSiQuedoColgado }
        return cerro ? silencioSiCerro : silencioAMitad
    }

    /// Junta lo que la persona venía diciendo con lo que agregó después.
    ///
    /// Es lo que pasa cuando se le cortó el turno antes de tiempo y siguió
    /// hablando: las dos partes son una sola cosa dicha.
    public static func unir(_ antes: String?, _ despues: String) -> String {
        let a = (antes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let d = despues.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return d }
        if d.isEmpty { return a }
        return a + " " + d
    }
}
