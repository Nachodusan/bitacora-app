import Foundation

/// Parte lo que Bitácora va a decir en pedazos que se sintetizan de a uno.
///
/// POR QUÉ. La voz se pedía entera: hasta que no llegaba el audio completo no
/// sonaba nada, y medido contra el proveedor eso son 1,9 segundos para una
/// respuesta corta y 5,6 para una larga — más lo que tardó el texto. Ocho
/// segundos mirando la respuesta escrita en la pantalla sin que suene nada.
///
/// Partido, el primer pedazo es corto a propósito: vuelve en un segundo y medio
/// y Bitácora arranca a hablar mientras el resto se sintetiza. El tiempo hasta la
/// primera palabra deja de depender del largo de la respuesta, que era justo lo
/// que Dusan notó ("al principio responde lento y después va aumentando").
///
/// LOS PEDAZOS SON FRASES, NO CARACTERES. Cortar por largo dejaría a la voz
/// respirando en el medio de una idea, que es peor que esperar. Se corta donde
/// ya había un punto.
public enum TrozosDeVoz {
    /// El primero va corto: es el único que se escucha como espera.
    static let primero = 90
    /// Los que siguen se generan mientras suena el anterior, así que conviene
    /// que sean grandes: menos pedidos, menos costo fijo por pedido, y menos
    /// riesgo de quedarse sin audio en el medio.
    static let resto = 320
    /// Abajo de esto no se parte nada.
    ///
    /// Medido: una respuesta de 200 caracteres vuelve entera en poco más de dos
    /// segundos, y partirla ahorraría medio segundo a cambio de dos pedidos y
    /// del riesgo de un silencio en el medio. La espera que molesta es la de las
    /// respuestas largas, y ahí sí la ganancia son varios segundos.
    static let sinPartir = 200

    /// Dónde termina una frase. El `…` va aparte porque no es tres puntos.
    private static let cierres: Set<Character> = [".", "?", "!", "…"]

    /// Parte el texto. Devuelve al menos un pedazo si hay algo que decir.
    ///
    /// El corte no mira sólo el signo: un punto adentro de "3.500" o de "Dr." no
    /// termina una frase. Por eso pide además que lo que sigue empiece como
    /// oración nueva —espacio y después mayúscula o comilla— y que el pedazo que
    /// se lleva ya tenga cuerpo suficiente.
    public static func partir(_ texto: String) -> [String] {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return [] }
        guard limpio.count > sinPartir else { return [limpio] }

        var pedazos: [String] = []
        var actual = ""
        let chars = Array(limpio)
        var i = 0

        while i < chars.count {
            actual.append(chars[i])

            let objetivo = pedazos.isEmpty ? primero : resto
            if cierres.contains(chars[i]),
               actual.count >= minimo(objetivo),
               esFinDeFrase(chars, i) {
                pedazos.append(actual.trimmingCharacters(in: .whitespacesAndNewlines))
                actual = ""
            }
            i += 1
        }

        let sobra = actual.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sobra.isEmpty {
            // Una cola muy corta no se pide sola: un "Dale." aparte cuesta un
            // pedido entero y mete un silencio antes. Se pega al anterior.
            // El techo es bajo a propósito: "¿Qué pasó?" pegado al pedazo
            // anterior está bien, pero una pregunta de treinta caracteres es
            // una frase entera y merece su lugar.
            if let ultimo = pedazos.last, sobra.count < 22 {
                pedazos[pedazos.count - 1] = ultimo + " " + sobra
            } else {
                pedazos.append(sobra)
            }
        }
        return pedazos
    }

    /// El piso para cortar. Un pedazo más chico que esto no vale un pedido.
    private static func minimo(_ objetivo: Int) -> Int {
        max(24, objetivo / 3)
    }

    /// ¿El signo en `i` cierra una frase de verdad?
    private static func esFinDeFrase(_ chars: [Character], _ i: Int) -> Bool {
        // "3.500" y "1.": el punto entre dígitos, o pegado al siguiente, no
        // cierra nada.
        if chars[i] == "." {
            let anterior = i > 0 ? chars[i - 1] : " "
            let siguiente = i + 1 < chars.count ? chars[i + 1] : " "
            if anterior.isNumber && siguiente.isNumber { return false }
        }
        // Los signos seguidos —"¿en serio?!"— cortan recién en el último.
        if i + 1 < chars.count, cierres.contains(chars[i + 1]) { return false }
        // Fin del texto: lo resuelve el sobrante, no acá.
        guard i + 1 < chars.count else { return false }
        guard chars[i + 1] == " " || chars[i + 1] == "\n" else { return false }

        // Lo que sigue tiene que arrancar como oración nueva. Así "Dr. Pérez"
        // no se parte y "Bien. Contame" sí.
        var j = i + 1
        while j < chars.count, chars[j] == " " || chars[j] == "\n" { j += 1 }
        guard j < chars.count else { return false }
        let c = chars[j]
        return c.isUppercase || c == "¿" || c == "¡" || c == "\"" || c == "«"
    }
}
