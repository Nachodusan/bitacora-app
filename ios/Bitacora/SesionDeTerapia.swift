import Foundation
import SwiftData

/// Lo que la persona se lleva de una sesión con su terapeuta.
///
/// No es la charla con Bitácora ni tiene que ver con ella: es lo que la persona
/// anota DESPUÉS de una sesión de terapia de verdad, para que no se le escape
/// entre una y otra. Cinco cosas: qué entendió, qué le aportó o qué aprendió,
/// cómo se sintió, qué temas se trataron y en qué sintió que avanzó. Más el
/// número de sesión y la fecha. «Cómo se sintió» se sumó el 03/10/2026.
///
/// Desde ese día puede nacer de un BORRADOR: si la sesión es una consulta del
/// calendario y la persona habló de ella con Bitácora, el servidor arma los
/// campos con lo que contó y la app crea la sesión para que la revise
/// (`revisada` en falso). Ver `Agenda`.
///
/// Vive sólo en el teléfono. Al servidor sólo le llega que la consulta ya
/// tiene su evaluación, para que deje de preguntar y borre el borrador.
@Model
final class SesionDeTerapia {
    /// Sesión 1, sesión 2… Lo propone la app y se puede corregir: alguien puede
    /// empezar a anotar en su décima sesión.
    var numero: Int
    /// El día de la sesión, no el día en que se anotó.
    var fecha: Date
    var entendi: String
    var aporte: String
    /// Los puntos clave, de a uno, cortos.
    var temas: [String]
    var avance: String
    /// Cómo se sintió en la sesión, o al salir.
    ///
    /// Con valor por defecto, y los dos de abajo también: es lo que deja que
    /// SwiftData abra las sesiones anotadas antes de que existieran.
    var sentir: String = ""
    /// La consulta del calendario a la que corresponde, si se sabe.
    var eventoId: Int? = nil
    /// Falso mientras sea un borrador que la persona todavía no miró.
    var revisada: Bool = true
    var creadoEn: Date

    init(numero: Int, fecha: Date = Date()) {
        self.numero = numero
        self.fecha = fecha
        self.entendi = ""
        self.aporte = ""
        self.temas = []
        self.avance = ""
        self.sentir = ""
        self.eventoId = nil
        self.revisada = true
        self.creadoEn = Date()
    }

    /// Una sesión que nace del borrador del servidor, para revisar.
    convenience init(numero: Int, fecha: Date, eventoId: Int, borrador: BorradorDeEvaluacion) {
        self.init(numero: numero, fecha: fecha)
        entendi = borrador.entendi
        aporte = borrador.aporte
        sentir = borrador.sentir
        temas = borrador.temas
        avance = borrador.avance
        self.eventoId = eventoId
        revisada = false
    }

    /// El día, escrito: «Jueves 2 de octubre de 2026».
    var fechaEscrita: String {
        let t = fecha.formatted(.dateTime.weekday(.wide).day().month(.wide).year()
            .locale(Locale(identifier: "es")))
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

/// Dónde se guardan las sesiones.
///
/// EN UN ARCHIVO APARTE del de la bitácora, y es a propósito. Sumar este modelo
/// al almacén que ya existe obligaba a SwiftData a migrarlo, y si esa migración
/// fallara la app no abriría: `BitacoraApp` prefiere morir antes que arriesgar
/// una entrada. Una pestaña nueva no puede poner en juego las conversaciones
/// que ya están guardadas. Con su propio archivo, lo peor que puede pasar es
/// que esta pestaña no ande, y lo dice.
enum AlmacenDeSesiones {
    static let contenedor: ModelContainer? = {
        let carpeta = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let config = ModelConfiguration(
            "sesiones",
            schema: Schema([SesionDeTerapia.self]),
            url: carpeta.appending(path: "sesiones.store"))
        return try? ModelContainer(for: SesionDeTerapia.self, configurations: config)
    }()
}
