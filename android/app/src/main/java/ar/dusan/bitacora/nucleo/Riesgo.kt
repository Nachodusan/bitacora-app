package ar.dusan.bitacora.nucleo

import java.text.Normalizer

/**
 * El corte de riesgo, en el teléfono (regla 6).
 *
 * Es el mismo de `Riesgo.swift` y de `api/src/riesgo.ts`: la misma lista, la
 * misma forma de comparar y el mismo mensaje. `riesgo.test.ts`, del lado del
 * servidor, lee este archivo y lo compara: si se agrega una frase acá, va
 * también en los otros dos.
 *
 * LO QUE ESTO ES: un piso. Coincidencia de frases, sin red, en el instante en
 * que la persona termina de hablar, antes de llamar al servidor. LO QUE NO ES:
 * suficiente. La segunda capa es el párrafo de riesgo del prompt.
 *
 * «Me quiero morir» y «no aguanto más» no están, a propósito: se dicen todos
 * los días como exageración y cortaban la charla. El porqué está en
 * `Riesgo.swift`.
 */
object Riesgo {

    /** Autolesión y suicidio. Normalizadas: minúsculas, sin acentos ni puntuación. */
    val senalesDirectas = listOf(
        "matarme", "suicidarme", "suicidio", "quitarme la vida", "terminar con todo",
        "no quiero vivir", "no quiero seguir viviendo", "dejar de existir",
        "estaria mejor muerto", "estaria mejor muerta", "ojala no despertarme",
        "lastimarme", "hacerme dano", "cortarme", "no despertarme mas",
        "me quiero matar", "quiero desaparecer",
    )

    /** Desesperanza. Se tratan igual que las anteriores. */
    val senalesDeDesesperanza = listOf(
        "no le veo sentido a nada", "nada tiene sentido", "no tiene sentido nada",
        "no hay salida", "no puedo mas con nada", "soy una carga",
        "estarian mejor sin mi", "todo me da igual ya", "no vale la pena nada",
        "estoy vacio por dentro", "estoy vacia por dentro",
    )

    /**
     * Lo que se dice cuando dispara. Fijo: nunca lo escribe un modelo, y nunca
     * se manda a sintetizar afuera —lo dice la voz del teléfono—, porque pedir
     * el audio de justo este texto sería avisarle a una empresa que el
     * detector se disparó.
     *
     * El *4141 es la línea de prevención del suicidio de Chile.
     */
    val mensaje: String =
        "Gracias por decirlo aquí.\n\n" +
        "Con esto no te puedo ayudar yo, y no quiero hacerte más preguntas ahora. " +
        "Busca a alguien de confianza y cuéntaselo hoy — o a un profesional, si puedes.\n\n" +
        "Si estás en Chile, puedes llamar gratis al *4141 desde el celular, a cualquier hora: " +
        "atiende un psicólogo.\n\n" +
        "Lo que dijiste queda guardado. Nada más."

    private val marcas = Regex("\\p{M}+")
    private val noPalabra = Regex("[^\\p{L}\\p{N}]+")

    /** Minúsculas, sin acentos, sin puntuación, y entre espacios. La ñ queda n. */
    fun normalizar(texto: String): String {
        val plano = Normalizer.normalize(texto, Normalizer.Form.NFD).replace(marcas, "").lowercase()
        val palabras = plano.split(noPalabra).filter { it.isNotEmpty() }
        return " " + palabras.joinToString(" ") + " "
    }

    /** Palabra completa: «recortarme el pelo» no es «cortarme». */
    fun haySenal(texto: String): Boolean {
        val n = normalizar(texto)
        return (senalesDirectas + senalesDeDesesperanza).any { n.contains(" $it ") }
    }

    /** El *4141, dicho como se marca. Lo que se ve en pantalla no cambia. */
    fun paraDecir(texto: String): String =
        texto.replace(Regex("\\*\\s?4141\\b"), "asterisco cuatro uno cuatro uno")
}
