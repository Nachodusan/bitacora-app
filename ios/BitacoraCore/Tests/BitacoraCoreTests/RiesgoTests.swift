import XCTest
@testable import BitacoraCore

/// La regla 6 en el teléfono. Hasta septiembre de 2026 no tenía ni un test, y
/// el primero que se escribió encontró un falso positivo que cortaba la charla.
final class RiesgoTests: XCTestCase {

    func testLasSenalesDirectasDisparan() {
        for f in ["no quiero seguir viviendo", "pensé en quitarme la vida",
                  "a veces quiero lastimarme", "ojalá no despertarme"] {
            XCTAssertTrue(Riesgo.haySenal(en: f), "debería disparar: \(f)")
        }
    }

    func testLaDesesperanzaDispara() {
        XCTAssertTrue(Riesgo.haySenal(en: "la verdad que no le veo sentido a nada"))
        XCTAssertTrue(Riesgo.haySenal(en: "siento que soy una carga para todos"))
    }

    /// El falso positivo que motivó este archivo. «cortarme» calzaba adentro de
    /// «recortarme» y la app cortaba la conversación en seco.
    func testUnaPalabraAdentroDeOtraNoEsUnaSenal() {
        XCTAssertFalse(Riesgo.haySenal(en: "quiero recortarme el pelo"))
        XCTAssertFalse(Riesgo.haySenal(en: "tengo que rematarme el trabajo hoy"))
    }

    func testUnDiaComunNoDispara() {
        for f in ["hoy dormí mal y estoy cansado", "me peleé con mi hermana",
                  "no tengo ganas de nada hoy", "estoy medio bajoneado"] {
            XCTAssertFalse(Riesgo.haySenal(en: f), "no debería disparar: \(f)")
        }
    }

    /// El mensaje es una constante: nunca lo escribe el modelo.
    func testElMensajeEsFijoYNoHacePreguntas() {
        XCTAssertFalse(Riesgo.mensaje.isEmpty)
        XCTAssertTrue(Riesgo.mensaje.contains("queda guardado"))
        XCTAssertFalse(Riesgo.mensaje.contains("?"))
    }

    /// Pedido del 02/10/2026. Son las mismas que en `api/src/riesgo.ts`.
    func testLasFrasesNuevasDisparan() {
        for f in ["Me quiero matar.", "quiero desaparecer"] {
            XCTAssertTrue(Riesgo.haySenal(en: f), "debería disparar: \(f)")
        }
    }

    /// Estuvieron en la lista un día y se sacaron: cortaban la charla por una
    /// exageración, como «recortarme el pelo».
    func testLasExageracionesDeTodosLosDiasNoCortan() {
        for f in ["me quiero morir de la vergüenza", "no aguanto más el calor",
                  "me quiero morir de risa", "ya no aguanto más esta fila"] {
            XCTAssertFalse(Riesgo.haySenal(en: f), "no debería disparar: \(f)")
        }
    }

    /// La línea de prevención del suicidio de Chile, en el mensaje y dicha como
    /// se marca por la voz del teléfono.
    func testElMensajeTraeEl4141YSeDiceComoSeMarca() {
        XCTAssertTrue(Riesgo.mensaje.contains("*4141"))
        XCTAssertFalse(Riesgo.paraDecir(Riesgo.mensaje).contains("4141"))
        XCTAssertEqual(Riesgo.paraDecir("Llama al *4141."), "Llama al asterisco cuatro uno cuatro uno.")
        XCTAssertEqual(Riesgo.paraDecir("son 41410 pesos"), "son 41410 pesos")
    }
}
