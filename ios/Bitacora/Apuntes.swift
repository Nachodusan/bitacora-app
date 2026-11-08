import SwiftData
import SwiftUI

/// Una nota suelta: algo que la persona quiso dejar escrito, y nada más.
///
/// No es una charla con Bitácora ni una sesión de terapia. Dusan lo pidió así: «por
/// si el paciente solamente quiere escribir algo que tiene en su mente, más que
/// hablar con alguien». A veces no se quiere una respuesta; se quiere sacarlo de
/// la cabeza y dejarlo en algún lado.
///
/// En el código se llama `Apunte` y no `Nota` porque `NotasView` ya existe y es
/// otra cosa: las citas para llevar a terapia que arma el servidor. En pantalla
/// dice «Notas», que es como lo dice la persona.
///
/// Vive sólo en el teléfono. No se sube al servidor ni se le pasa a Bitácora.
@Model
final class Apunte {
    var texto: String
    var creadoEn: Date
    var editadoEn: Date

    init(texto: String = "") {
        self.texto = texto
        self.creadoEn = Date()
        self.editadoEn = Date()
    }

    var estaVacio: Bool {
        texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Cuándo se escribió: «Viernes 2 de octubre, 14:32».
    var fechaEscrita: String {
        let t = creadoEn.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()
            .locale(Locale(identifier: "es")))
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

/// Dónde se guardan las notas: en su propio archivo, por lo mismo que las
/// sesiones (ver `AlmacenDeSesiones`). Ninguna pestaña nueva toca el almacén de
/// la bitácora.
enum AlmacenDeApuntes {
    static let contenedor: ModelContainer? = {
        let carpeta = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let config = ModelConfiguration(
            "apuntes",
            schema: Schema([Apunte.self]),
            url: carpeta.appending(path: "apuntes.store"))
        return try? ModelContainer(for: Apunte.self, configurations: config)
    }()
}

/// Lo que abre el botón de notas del chat.
///
/// ABRE DIRECTO EN UNA HOJA EN BLANCO, con el cursor puesto. Quien toca ese
/// botón tiene algo en la cabeza ahora: hacerlo pasar primero por una lista y
/// por un botón de «nueva» es darle dos oportunidades de arrepentirse. Las notas
/// anteriores están un paso atrás, con la flecha.
struct ApuntesView: View {
    var body: some View {
        if let contenedor = AlmacenDeApuntes.contenedor {
            Cuaderno().modelContainer(contenedor)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Paleta.bitacora)
                Text("No se pudieron abrir tus notas")
                    .font(.redonda(.headline))
                    .foregroundStyle(Paleta.tinta)
                Text("Cierra la app y vuelve a abrirla. Lo que ya habías escrito sigue guardado en el teléfono.")
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tintaSuave)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Fondo())
        }
    }
}

private struct Cuaderno: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar
    @Query(sort: \Apunte.editadoEn, order: .reverse) private var apuntes: [Apunte]

    @State private var camino: [Apunte] = []
    @State private var arranco = false

    /// Las que tienen algo escrito. La hoja en blanco que se abre sola no
    /// aparece en la lista hasta que se escriba en ella.
    private var escritos: [Apunte] { apuntes.filter { !$0.estaVacio } }

    var body: some View {
        NavigationStack(path: $camino) {
            ZStack {
                Fondo()
                if escritos.isEmpty { vacio } else { lista }
            }
            .navigationTitle("Notas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { cerrar() }
                        .font(.redonda(.callout))
                        .foregroundStyle(Paleta.tintaSuave)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: nueva) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Paleta.tintaSuave)
                    }
                    .accessibilityLabel("Escribir una nota nueva")
                }
            }
            .navigationDestination(for: Apunte.self) { apunte in
                HojaDeApunte(apunte: apunte, alCerrarTodo: { cerrar() })
            }
        }
        .onAppear {
            // Una sola vez, al abrir: directo a escribir.
            guard !arranco else { return }
            arranco = true
            nueva()
        }
    }

    private var vacio: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Paleta.musgoSuave)
            Text("Todavía no escribiste ninguna nota")
                .font(.redonda(.headline))
                .foregroundStyle(Paleta.tinta)
            Text("Sirven para dejar algo que tienes en la cabeza, sin hablar con nadie.")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
                .multilineTextAlignment(.center)
            Button(action: nueva) {
                Text("Escribir una nota")
                    .font(.redonda(.subheadline, .semibold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Paleta.musgo))
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
    }

    private var lista: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(escritos) { apunte in
                    NavigationLink(value: apunte) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(apunte.fechaEscrita)
                                .font(.redonda(.caption, .medium))
                                .foregroundStyle(Paleta.tintaTenue)
                            Text(apunte.texto.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.redonda(.callout))
                                .foregroundStyle(Paleta.tinta)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .carta(radio: 20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
    }

    /// Abre una hoja en blanco. Si se sale sin escribir nada, se descarta sola
    /// (`HojaDeApunte`).
    private func nueva() {
        let apunte = Apunte()
        contexto.insert(apunte)
        camino.append(apunte)
    }
}

/// Una nota abierta: toda la pantalla para escribir.
///
/// Sin botón de guardar. Lo escrito queda guardado mientras se escribe, y una
/// hoja que se cierra vacía no deja rastro.
private struct HojaDeApunte: View {
    @Bindable var apunte: Apunte
    let alCerrarTodo: () -> Void

    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var volver
    @Environment(\.scenePhase) private var fase

    @State private var seBorro = false
    @State private var confirmarBorrado = false
    @FocusState private var escribiendo: Bool

    var body: some View {
        ZStack {
            Fondo()
            VStack(alignment: .leading, spacing: 10) {
                Text(apunte.fechaEscrita)
                    .font(.redonda(.caption, .medium))
                    .foregroundStyle(Paleta.tintaTenue)
                    .padding(.horizontal, 5)

                ZStack(alignment: .topLeading) {
                    if apunte.texto.isEmpty {
                        Text("Escribe lo que tengas en la cabeza…")
                            .font(.redonda(.body))
                            .foregroundStyle(Paleta.tintaTenue)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $apunte.texto)
                        .font(.redonda(.body))
                        .foregroundStyle(Paleta.tinta)
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .focused($escribiendo)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !apunte.estaVacio {
                    Button { confirmarBorrado = true } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Paleta.tintaSuave)
                    }
                    .accessibilityLabel("Eliminar esta nota")
                }
                Button("Listo") {
                    escribiendo = false
                    alCerrarTodo()
                }
                .font(.redonda(.callout, .semibold))
                .foregroundStyle(Paleta.musgo)
            }
        }
        .confirmationDialog("¿Eliminar esta nota?",
                            isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive, action: borrar)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("No se puede deshacer.")
        }
        .onChange(of: apunte.texto) { apunte.editadoEn = Date() }
        // Si la app se va al fondo a mitad de una frase, lo escrito ya está en
        // disco.
        .onChange(of: fase) { try? contexto.save() }
        .task {
            // El cursor aparece solo, cuando la hoja ya terminó de entrar.
            try? await Task.sleep(for: .milliseconds(450))
            escribiendo = true
        }
        .onDisappear(perform: alSalir)
    }

    private func alSalir() {
        guard !seBorro else { return }
        if apunte.estaVacio { contexto.delete(apunte) }
        try? contexto.save()
    }

    private func borrar() {
        seBorro = true
        contexto.delete(apunte)
        try? contexto.save()
        volver()
    }
}
