import Foundation
import Network
import SwiftData
import SwiftUI

/// La cola de salida.
///
/// Lo que la cola garantiza:
/// las operaciones, no por la red — la entrada se escribe en SwiftData ANTES de
/// intentar subirla, y la fila local no se toca hasta que el servidor confirma.
/// Si la app muere en el medio, al arrancar sigue pendiente y se reintenta.
///
/// Sube de a una y en orden cronológico. Con ~3 entradas por día no hay nada que
/// ganar paralelizando, y en orden es más fácil de leer cuando algo falla.
@Observable
@MainActor
final class Outbox {
    private(set) var subiendo = false
    private(set) var hayRed = true
    /// En qué estado está el servidor. `nil` mientras no se preguntó todavía.
    ///
    /// Gobierna dos cosas: el color del indicador y si se puede arrancar una
    /// conversación. Lo segundo es lo importante — sin servidor Bitácora no
    /// contesta, así que hablarle sería teatro.
    private(set) var servidor: SyncClient.Estado?

    private let contexto: ModelContext
    // `nonisolated(unsafe)` para poder frenarlos desde `deinit`, que no corre en
    // el main actor. Los dos se escriben una sola vez, en `init`.
    private nonisolated(unsafe) let monitor = NWPathMonitor()
    private nonisolated(unsafe) var tareaPeriodica: Task<Void, Never>?

    init(contexto: ModelContext) {
        self.contexto = contexto
        renombrarRotuloViejo()

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let antes = self.hayRed
                self.hayRed = (path.status == .satisfied)
                // Volvió la red: drenar ya, sin esperar el backoff. Este es el
                // caso del modo avión.
                if !antes && self.hayRed { await self.drenar(ignorandoBackoff: true) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "bitacora.red"))

        // Reloj de respaldo, por si el backoff venció sin que cambie la red.
        tareaPeriodica = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                // Sólo se vuelve a preguntar mientras algo esté mal: cuando el
                // servidor está listo, este ciclo no genera ni un pedido de más.
                // Así, si prendés la computadora, la app se destraba sola en
                // menos de 15 segundos sin que haya que reiniciarla.
                if await self?.servidor != .listo { await self?.comprobarServidor() }
                await self?.drenar()
            }
        }
    }

    deinit {
        monitor.cancel()
        tareaPeriodica?.cancel()
    }

    /// Las conversaciones guardadas acá antes del 02/10/2026 tienen las líneas
    /// de Bitácora rotuladas `Laya:`, su nombre de antes. Se renombran una vez,
    /// al arrancar y antes de que la cola suba nada: así el calendario las
    /// muestra con el nombre de hoy, y una que quedó pendiente llega al
    /// servidor igual que las que ya estaban allá. Correrlo de nuevo no cambia
    /// nada: sin rótulos viejos, no hay qué guardar.
    private func renombrarRotuloViejo() {
        let todas = (try? contexto.fetch(FetchDescriptor<EntradaLocal>())) ?? []
        var cambio = false
        for e in todas {
            let nueva = Transcripcion.conRotuloNuevo(e.transcripcion)
            guard nueva != e.transcripcion else { continue }
            e.transcripcion = nueva
            cambio = true
        }
        if cambio { try? contexto.save() }
    }

    var pendientes: [EntradaLocal] {
        let pendiente = EntradaLocal.Estado.pendiente.rawValue
        let d = FetchDescriptor<EntradaLocal>(
            predicate: #Predicate { $0.estadoRaw == pendiente },
            sortBy: [SortDescriptor(\.creadoEn)])
        return (try? contexto.fetch(d)) ?? []
    }

    // MARK: - La charla, mientras pasa

    /// Abre el borrador de una conversación que recién arranca.
    ///
    /// `instante` es cuándo EMPEZÓ la charla, no cuándo terminó: la hora de
    /// pared —y con ella el día lógico— tienen que ser las de cuando hablaste.
    /// Una charla que arranca a las 23:50 y termina a las 00:20 es del día que
    /// arrancó.
    func abrirBorrador(instante: Date = Date()) -> EntradaLocal {
        let e = EntradaLocal(transcripcion: "", duracionSeg: 0,
                             estado: .borrador, instante: instante)
        contexto.insert(e)
        try? contexto.save()
        return e
    }

    /// Reescribe el borrador. Se llama después de CADA turno.
    func anotar(_ e: EntradaLocal, transcripcion: String, duracionSeg: Double) {
        e.transcripcion = transcripcion
        e.duracionSeg = duracionSeg
        try? contexto.save()
    }

    /// Cierra el borrador y lo manda a la cola.
    func cerrarBorrador(_ e: EntradaLocal) {
        guard e.estado == .borrador else { return }
        // Un borrador sin nada tuyo adentro no es una entrada: si sólo habló
        // Bitácora y cortaste, no hay bitácora que guardar.
        guard e.transcripcion.contains("Vos:") else {
            contexto.delete(e)
            try? contexto.save()
            return
        }
        e.estado = .pendiente
        try? contexto.save()
        Task { await drenar(ignorandoBackoff: true) }
    }

    /// Vuelve a abrir una charla de hoy que ya se había cerrado, para seguirla
    /// desde el historial (26/10/2026). Sólo de hoy: una de otro día ya entró
    /// al resumen de ese día. El servidor la actualiza por `client_uuid` cuando
    /// llegue más larga, así que se puede reabrir aunque ya se haya subido.
    func reabrir(_ e: EntradaLocal, hoy: String = CalendarioView.hoyLogico()) -> Bool {
        guard e.diaLogico == hoy, e.estado != .borrador else { return e.estado == .borrador }
        e.estado = .borrador
        try? contexto.save()
        return true
    }

    /// Rescata las charlas que quedaron abiertas de DÍAS ANTERIORES.
    ///
    /// Se llama al arrancar la app. La de hoy no se toca: desde el 19 de
    /// octubre hay una sola conversación por día que no se cierra al salir ni
    /// cuando se muere la app (lo pidió Dusan, para mantener el hilo), y al
    /// volver se retoma (`borradorDeHoy`). Las de días anteriores sí terminaron:
    /// el día se cortó a las 4 de la mañana.
    func rescatarBorradores(hoy: String = CalendarioView.hoyLogico()) {
        let borrador = EntradaLocal.Estado.borrador.rawValue
        let d = FetchDescriptor<EntradaLocal>(
            predicate: #Predicate { $0.estadoRaw == borrador })
        for e in (try? contexto.fetch(d)) ?? [] where e.diaLogico < hoy {
            cerrarBorrador(e)
        }
    }

    /// La conversación de hoy que sigue abierta, si hay. La más reciente.
    func borradorDeHoy(hoy: String = CalendarioView.hoyLogico()) -> EntradaLocal? {
        let borrador = EntradaLocal.Estado.borrador.rawValue
        var d = FetchDescriptor<EntradaLocal>(
            predicate: #Predicate { $0.estadoRaw == borrador && $0.diaLogico == hoy },
            sortBy: [SortDescriptor(\.creadoEn, order: .reverse)])
        d.fetchLimit = 1
        return (try? contexto.fetch(d))?.first
    }

    /// Manda la conversación de hoy tal como va, SIN cerrarla.
    ///
    /// El servidor la actualiza si llega más larga (`POST /entradas`). Así lo
    /// hablado llega aunque mañana no abras la app, y el resumen de la noche y
    /// las notas para el psicólogo lo tienen. Si no hay red no pasa nada: va de
    /// nuevo en el próximo turno, y al cerrarse el día entra a la cola común.
    func sincronizar(_ e: EntradaLocal) {
        guard e.estado == .borrador, e.transcripcion.contains("Vos:"), hayRed else { return }
        let cuerpo = e.cuerpo
        Task {
            if case .aceptada(let r) = await SyncClient(config: Config.shared.servidor).subir(cuerpo) {
                e.servidorId = Int(r.id)
                try? contexto.save()
            }
        }
    }

    /// Pregunta cómo está el servidor, sin esperar a que haya algo para subir.
    ///
    /// Se llama al abrir la app, al volver a primer plano, al guardar Ajustes y
    /// cada 15 segundos mientras algo esté mal. Sin esto, la app no se enteraba
    /// de que no llegaba a ningún lado hasta la primera grabación.
    func comprobarServidor() async {
        guard hayRed else { servidor = .inalcanzable; return }
        servidor = await SyncClient(config: Config.shared.servidor).comprobar()
    }

    func drenar(ignorandoBackoff: Bool = false) async {
        guard !subiendo, hayRed else { return }
        let ahora = Date()
        let lista = pendientes.filter {
            ignorandoBackoff || ($0.proximoIntento ?? .distantPast) <= ahora
        }
        guard !lista.isEmpty else { return }

        subiendo = true
        defer { subiendo = false }

        let cliente = SyncClient(config: Config.shared.servidor)
        for entrada in lista {
            switch await cliente.subir(entrada.cuerpo) {
            case .aceptada(let r):
                entrada.estado = .subida
                entrada.servidorId = Int(r.id)
                entrada.ultimoError = nil
                entrada.proximoIntento = nil
                servidor = .listo

            case .rechazada(let codigo, let motivo):
                // No se reintenta: el servidor va a contestar lo mismo siempre.
                // Queda visible en la lista para que se pueda ver qué pasó.
                entrada.estado = .rechazada
                entrada.ultimoError = "HTTP \(codigo): \(motivo)"

            case .sinCredencial(let codigo):
                // Sigue PENDIENTE. Un 401 no es culpa de la entrada: la app
                // trae un token que el servidor no reconoce, y eso se arregla
                // instalándola de nuevo con el bueno. Si acá la diéramos por
                // rechazada, todo lo que hayas dictado antes quedaría muerto
                // aunque después llegue el token bueno —guardado en disco, pero
                // sin ningún camino de vuelta.
                //
                // Con el backoff normal el reintento se espacia hasta 5 minutos,
                // así que insistir contra un token equivocado no quema batería.
                entrada.intentos += 1
                entrada.ultimoError = "HTTP \(codigo): falta el token o no coincide"
                entrada.proximoIntento = ahora.addingTimeInterval(
                    Backoff.espera(intento: entrada.intentos))
                servidor = .sinToken
                try? contexto.save()
                // Como en el caso de abajo: si a una le falta la llave, a todas.
                return

            case .reintentable(let motivo):
                entrada.intentos += 1
                entrada.ultimoError = motivo
                entrada.proximoIntento = ahora.addingTimeInterval(
                    Backoff.espera(intento: entrada.intentos))
                try? contexto.save()
                // Si falló una, las siguientes van a fallar igual: cortamos y
                // esperamos al próximo ciclo en vez de quemar la batería.
                return
            }
            try? contexto.save()
        }
    }
}
