import SwiftData
import SwiftUI

@main
struct BitacoraApp: App {
    let contenedor: ModelContainer

    init() {
        do {
            contenedor = try ModelContainer(for: EntradaLocal.self)
        } catch {
            // Si SwiftData no abre, la app no puede garantizar que no se pierda
            // una entrada. Mejor morir fuerte que grabar sobre arena.
            fatalError("No se pudo abrir el almacenamiento local: \(error)")
        }
        #if DEBUG
        ImportarSimulacion.siHay(en: contenedor.mainContext)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RaizView(outbox: Outbox(contexto: contenedor.mainContext),
                     contexto: contenedor.mainContext)
        }
        .modelContainer(contenedor)
    }
}

struct RaizView: View {
    let outbox: Outbox
    let contexto: ModelContext

    @Environment(\.scenePhase) private var fase
    private var config = Config.shared

    /// La pestaña elegida vive ahí y no en un `@State`: Mi expediente lleva al
    /// calendario o al chat desde la tarjeta de la próxima consulta.
    @Bindable private var navegacion = Navegacion.shared
    @State private var mostrarNombre = false
    @State private var eligiendoPin = false

    enum Pestana: Hashable { case calendario, hablar, evaluaciones }

    init(outbox: Outbox, contexto: ModelContext) {
        self.outbox = outbox
        self.contexto = contexto
    }

    var body: some View {
        // Sólo los íconos, sin las palabras debajo.
        //
        // Son tres pestañas y los dibujos se entienden solos: un calendario, una
        // onda y un sillón (hasta el 04/10/2026, un portapapeles). Con el rótulo, la barra se lleva el doble de
        // alto para repetir con letras lo que el dibujo ya dijo. El nombre sigue
        // estando para VoiceOver, que es donde de verdad hace falta.
        //
        // EL ORDEN lo pidió Dusan: calendario, chat, evaluaciones. El chat queda
        // en el medio y sigue siendo donde abre la app: es lo que se viene a
        // hacer, y lo de los costados es lo que se viene a mirar.
        TabView(selection: $navegacion.pestana) {
            CalendarioView()
                .tabItem {
                    Image(systemName: "calendar")
                        .accessibilityLabel("Calendario")
                }
                .tag(Pestana.calendario)
            ConversacionView(outbox: outbox, contexto: contexto)
                .tabItem {
                    // Los anillos de la marca (26/10/2026): la charla es el centro.
                    Image(uiImage: AnillosChicos.pestana)
                        .accessibilityLabel("Hablar")
                }
                .tag(Pestana.hablar)
            EvaluacionesView()
                .tabItem {
                    // Tu perfil en un círculo: lo más directo, tú (26/10/2026,
                    // elegido por Dusan entre dieciséis opciones).
                    Image(systemName: "person.crop.circle")
                        .accessibilityLabel("Mi espacio")
                }
                .tag(Pestana.evaluaciones)
        }
        .tint(Paleta.musgo)
        // A pantalla completa y antes que nada. No es una hoja que se baja
        // arrastrando: mientras no conteste, esto ES la app.
        .fullScreenCover(isPresented: $mostrarNombre) { Bienvenida() }
        // El diario de antes de las cuentas (28/10/2026): elige su PIN una vez.
        .fullScreenCover(isPresented: $eligiendoPin) { ElegirPinView { eligiendoPin = false } }
        .task {
            mostrarNombre = !config.nombrePreguntado
            eligiendoPin = config.nombrePreguntado && config.sesion == nil && !config.tokenFijo.isEmpty
            // Una charla que quedó abierta —la app murió, sonó el teléfono, la
            // dejaste en la mesa— se cierra y se sube ahora. Sin esto el
            // borrador sólo serviría para el caso en que vos te acordás de
            // cerrarla, o sea para ninguno de los que importan.
            outbox.rescatarBorradores()
            await outbox.comprobarServidor()
        }
        .onChange(of: fase) { _, nueva in
            guard nueva == .active, config.nombrePreguntado else { return }
            // Reintento silencioso del PUT de ajustes. Si cuando contestaste el
            // nombre no había red —o si cambiaste de zona horaria viajando— el
            // servidor sigue con lo viejo, y el tick cerraría tus días con la
            // hora de otro lado.
            Task {
                await config.aplicar()
                await outbox.comprobarServidor()
                // Las consultas: una que Bitácora propuso, un borrador de
                // evaluación nuevo, o avisar que una ya está evaluada.
                await Agenda.shared.actualizar()
            }
        }
    }
}
