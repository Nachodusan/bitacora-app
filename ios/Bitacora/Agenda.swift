import Foundation
import SwiftData

/// Los eventos del calendario en el teléfono: sobre todo las consultas.
///
/// El servidor es el dueño (`api/src/consultas.ts`): Bitácora las tiene que ver
/// para ayudar a preparar una sesión y para preguntar cómo le fue, y puede
/// proponer una que se mencionó en una charla. Acá vive una COPIA, en un
/// archivo, para que el calendario las muestre sin red. Cargar, confirmar o
/// borrar una sí necesita servidor; si no llega, se dice y no se hace.
///
/// Además es el puente con Evaluaciones, en las dos direcciones:
///
///   · Si una consulta trae un borrador de evaluación, crea la sesión con esos
///     campos para que la persona la revise (`SesionDeTerapia.revisada` en
///     falso). Una sola vez por consulta: lo que la persona edite no se pisa.
///   · Si una consulta ya tiene su evaluación guardada —revisada, o anotada a
///     mano el mismo día—, le avisa al servidor, que deja de preguntar por ella
///     y borra el borrador. Lo único que viaja es eso: que está evaluada.
@Observable
@MainActor
final class Agenda {
    static let shared = Agenda()

    private(set) var eventos: [Evento] = []

    private init() {
        eventos = Self.leerCopia()
    }

    private var cliente: SyncClient { SyncClient(config: Config.shared.servidor) }

    // MARK: - Leer

    func delDia(_ dia: String) -> [Evento] {
        eventos.filter { $0.dia == dia }
            .sorted { ($0.hora ?? "") < ($1.hora ?? "") }
    }

    /// Para el punto de la grilla: hay una consulta confirmada, o propuesta.
    func marca(_ dia: String) -> Marca {
        let delDia = eventos.filter { $0.dia == dia }
        if delDia.contains(where: { !$0.esPropuesta }) { return .confirmado }
        if !delDia.isEmpty { return .propuesto }
        return .ninguna
    }

    enum Marca { case ninguna, propuesto, confirmado }

    /// Trae los eventos del servidor. Sin servidor, se queda con la copia.
    func actualizar() async {
        guard let nuevos = await cliente.eventos() else { return }
        reemplazar(nuevos)
        traerBorradores()
        await avisarEvaluadas()
    }

    // MARK: - Cambiar

    /// Carga una consulta (u otro evento) a mano. `false` si no llegó al servidor.
    func agregar(tipo: String, dia: String, hora: String?, titulo: String?) async -> Bool {
        guard let e = await cliente.crearEvento(clientUuid: UUID().uuidString, tipo: tipo,
                                                dia: dia, hora: hora, titulo: titulo)
        else { return false }
        reemplazar(eventos.filter { $0.id != e.id } + [e])
        return true
    }

    func confirmar(_ e: Evento) async -> Bool {
        await cambiar(e, CambioDeEvento(estado: "confirmado"))
    }

    /// Una propuesta que la persona dijo que no. En el servidor queda como
    /// descartada, para que no se vuelva a proponer la misma.
    func descartar(_ e: Evento) async -> Bool {
        guard await cliente.cambiarEvento(id: e.id, CambioDeEvento(estado: "descartado")) != nil
        else { return false }
        reemplazar(eventos.filter { $0.id != e.id })
        return true
    }

    func cambiarHora(_ e: Evento, a hora: String?) async -> Bool {
        await cambiar(e, CambioDeEvento(hora: .some(hora)))
    }

    func borrar(_ e: Evento) async -> Bool {
        guard await cliente.borrarEvento(id: e.id) else { return false }
        reemplazar(eventos.filter { $0.id != e.id })
        return true
    }

    /// La evaluación de esta consulta quedó guardada acá. Si no llega al
    /// servidor, se vuelve a intentar la próxima vez que se actualice.
    func evaluada(_ eventoId: Int) async {
        guard let e = eventos.first(where: { $0.id == eventoId }), !e.evaluada else { return }
        _ = await cambiar(e, CambioDeEvento(evaluada: true))
    }

    private func cambiar(_ e: Evento, _ c: CambioDeEvento) async -> Bool {
        guard let nuevo = await cliente.cambiarEvento(id: e.id, c) else { return false }
        reemplazar(eventos.map { $0.id == nuevo.id ? nuevo : $0 })
        return true
    }

    private func reemplazar(_ nuevos: [Evento]) {
        eventos = nuevos
        guardarCopia()
    }

    // MARK: - El puente con Evaluaciones

    private var sesiones: ModelContext? { AlmacenDeSesiones.contenedor?.mainContext }

    private func todasLasSesiones() -> [SesionDeTerapia] {
        (try? sesiones?.fetch(FetchDescriptor<SesionDeTerapia>())) ?? []
    }

    /// Crea la sesión para revisar de cada consulta que trae borrador y todavía
    /// no tiene una.
    private func traerBorradores() {
        guard let contexto = sesiones else { return }
        var todas = todasLasSesiones()
        for e in eventos where e.esConsulta && !e.esPropuesta && !e.evaluada {
            guard let b = e.borrador, !todas.contains(where: { $0.eventoId == e.id }),
                  let fecha = Self.fecha(e.dia) else { continue }
            let nueva = SesionDeTerapia(numero: (todas.map(\.numero).max() ?? 0) + 1,
                                        fecha: fecha, eventoId: e.id, borrador: b)
            contexto.insert(nueva)
            todas.append(nueva)
        }
        try? contexto.save()
    }

    /// Le avisa al servidor qué consultas ya tienen su evaluación.
    ///
    /// Cuenta la que nació del borrador y ya se revisó, y también una anotada a
    /// mano el mismo día de la consulta: es la evaluación de esa sesión aunque
    /// nadie las haya unido. Se unen acá.
    private func avisarEvaluadas() async {
        let todas = todasLasSesiones()
        let hoy = Self.dia(Date())
        for e in eventos where e.esConsulta && !e.esPropuesta && !e.evaluada && e.dia <= hoy {
            let suya = todas.first { $0.eventoId == e.id }
                ?? todas.first { $0.eventoId == nil && Self.dia($0.fecha) == e.dia }
            guard let suya, suya.revisada else { continue }
            if suya.eventoId == nil { suya.eventoId = e.id; try? sesiones?.save() }
            await evaluada(e.id)
        }
    }

    // MARK: - Fechas

    /// "YYYY-MM-DD" de una fecha, en el calendario del teléfono.
    static func dia(_ fecha: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: fecha)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// «Jueves 9 · 19:00»: la tarjeta de la próxima consulta y el aviso del chat
    /// cuando se está preparando una.
    static func cuando(_ e: Evento) -> String {
        guard let f = fecha(e.dia) else { return e.dia }
        let semana = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
        let c = Calendar.current.dateComponents([.weekday, .day], from: f)
        let dia = "\(semana[(c.weekday ?? 1) - 1]) \(c.day ?? 0)"
        return e.hora.map { "\(dia) · \($0)" } ?? dia
    }

    /// El mediodía de ese día: lejos de cualquier borde de zona horaria.
    static func fecha(_ dia: String) -> Date? {
        let p = dia.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    // MARK: - La copia

    private static var archivo: URL {
        URL.applicationSupportDirectory.appending(path: "eventos.json")
    }

    private static func leerCopia() -> [Evento] {
        guard let datos = try? Data(contentsOf: archivo),
              let e = try? JSONDecoder().decode([Evento].self, from: datos) else { return [] }
        return e
    }

    private func guardarCopia() {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory,
                                                 withIntermediateDirectories: true)
        if let datos = try? JSONEncoder().encode(eventos) {
            try? datos.write(to: Self.archivo, options: .atomic)
        }
    }
}
