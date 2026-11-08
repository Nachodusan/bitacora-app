import Foundation

/// Detección de señales de desesperanza o autolesión (regla 6).
///
/// LO QUE ESTO ES: un piso. Coincidencia de frases, en el teléfono, sin red y
/// sin costo, que corre en el instante en que terminás de hablar.
///
/// LO QUE ESTO NO ES: suficiente. Una lista de frases tiene muchísimos falsos
/// negativos. La otra capa es el system prompt de Bitácora (`charla.ts`), que
/// desde el 02/10/2026 vuelve a tener la instrucción: ante señales, dejar de
/// aconsejar y de preguntar, y derivar.
///
/// ESTÁ TAMBIÉN EN EL SERVIDOR (`api/src/riesgo.ts`), con la misma lista y el
/// mismo mensaje. Acá funciona sin red; allá cubre a un cliente que no lo
/// tenga, como la versión de Android. `riesgo.test.ts`, del lado del servidor,
/// lee este archivo y compara: si se agrega una frase acá, va también allá.
public enum Riesgo {

    /// Normaliza para comparar: minúsculas, sin acentos, sin puntuación.
    /// Sin esto "matarme" y "MATARME." no coinciden, y en español los acentos
    /// se comen la mitad de las coincidencias.
    static func normalizar(_ texto: String) -> String {
        let plano = texto.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "es"))
        let limpio = plano.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return " " + String(limpio).split(separator: " ").joined(separator: " ") + " "
    }

    /// Autolesión y suicidio.
    static let senalesDirectas = [
        "matarme", "suicidarme", "suicidio", "quitarme la vida", "terminar con todo",
        "no quiero vivir", "no quiero seguir viviendo", "dejar de existir",
        "estaria mejor muerto", "estaria mejor muerta", "ojala no despertarme",
        "lastimarme", "hacerme dano", "cortarme", "no despertarme mas",
        "me quiero matar", "quiero desaparecer"
    ]

    /// Desesperanza. La regla 6 las trata igual que las anteriores.
    ///
    /// «Me quiero morir» y «no aguanto más» estuvieron un día y se sacaron
    /// (02/10/2026). Se dicen todos los días como exageración —«me quiero morir
    /// de la vergüenza», «no aguanto más el calor»— y cada vez cortaban la
    /// charla con el mensaje de cuidado, igual que «recortarme el pelo». Cuando
    /// sí son una señal, las lee el párrafo de riesgo del prompt.
    static let senalesDeDesesperanza = [
        "no le veo sentido a nada", "nada tiene sentido", "no tiene sentido nada",
        "no hay salida", "no puedo mas con nada", "soy una carga",
        "estarian mejor sin mi", "todo me da igual ya", "no vale la pena nada",
        "estoy vacio por dentro", "estoy vacia por dentro"
    ]

    /// Palabra completa, con espacios a los dos lados.
    ///
    /// Hubo un `|| n.contains($0)` acá que anulaba el chequeo con espacios, y
    /// entonces "cortarme" calzaba adentro de "re-cortarme": «quiero recortarme
    /// el pelo» cortaba la charla en seco con el mensaje de cuidado. El sesgo
    /// hacia disparar es deliberado, pero este falso positivo no costaba «un
    /// mensaje amable de más»: terminaba la conversación. `normalizar` deja la
    /// frase entre espacios, así que el chequeo con espacios ya cubre el
    /// principio y el final.
    public static func haySenal(en texto: String) -> Bool {
        let n = normalizar(texto)
        return (senalesDirectas + senalesDeDesesperanza).contains { n.contains(" \($0) ") }
    }

    /// El mensaje del camino de escape.
    ///
    /// Corto a propósito. No da consejos, no propone un plan, no analiza, no
    /// pregunta nada más. Sugiere hablar con una persona y sale del medio.
    ///
    /// El *4141 es la línea de prevención del suicidio de Chile, del Ministerio
    /// de Salud: gratis desde el celular, todos los días, a toda hora, y atiende
    /// un psicólogo. Agregado el 02/10/2026.
    ///
    /// En español neutro, de tú, como todo lo que dice Bitácora desde el 01/10/2026.
    public static let mensaje = """
        Gracias por decirlo aquí.

        Con esto no te puedo ayudar yo, y no quiero hacerte más preguntas ahora. \
        Busca a alguien de confianza y cuéntaselo hoy — o a un profesional, si puedes.

        Si estás en Chile, puedes llamar gratis al *4141 desde el celular, a cualquier hora: \
        atiende un psicólogo.

        Lo que dijiste queda guardado. Nada más.
        """

    /// Cómo se dice el número de la línea, para la voz del teléfono.
    ///
    /// Escrito "*4141", una voz puede leerlo como «cuatro mil ciento cuarenta y
    /// uno» o saltearse el asterisco, y queda un número que no se marca. Se dice
    /// como se marca. Lo que se ve en pantalla no cambia. El servidor hace lo
    /// mismo antes de sintetizar (`paraDecir`, en `voz.ts`).
    public static func paraDecir(_ texto: String) -> String {
        texto.replacingOccurrences(of: #"\*\s?4141\b"#, with: "asterisco cuatro uno cuatro uno",
                                   options: .regularExpression)
    }
}
