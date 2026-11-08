import SwiftUI

/// Ajustes. Rediseñada el 26/10/2026: Dusan dijo que «se ve muy mal» y pidió
/// sacar lo innecesario. Queda sólo tu nombre. Se fueron el selector de timbre
/// (hay una sola voz, Lupita), el detalle de las voces de iOS, el interruptor
/// de voz natural (siempre prendida, `Config.vozNatural`), el botón de probarla,
/// la luz de la voz (siempre el borde) y la línea de privacidad.
struct AjustesView: View {
    @Environment(\.dismiss) private var dismiss
    private var config = Config.shared
    @State private var nombre = Config.shared.nombre
    @FocusState private var escribiendoNombre: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Fondo()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        seccion("Cómo te llama") {
                            CampoDeNombre(nombre: $nombre, enfocado: $escribiendoNombre)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 15)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .font(.redonda(.body, .semibold))
                        .foregroundStyle(Paleta.vos)
                }
            }
        }
        // GUARDAR SIEMPRE IGUAL (04/10/2026). «Listo» y deslizar la hoja hacia
        // abajo guardan los dos: dos maneras de salir que hacen lo mismo.
        .onDisappear(perform: guardar)
    }

    private func guardar() {
        // Antes de `aplicar`, que es quien lo manda: si se guardara después, el
        // PUT viajaría con el nombre viejo y el servidor quedaría un cambio atrás.
        config.nombre = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await config.aplicar() }
    }

    private func seccion<C: View>(_ titulo: String, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo)
                .font(.redonda(.footnote, .semibold))
                .foregroundStyle(Paleta.tintaSuave)
                .padding(.leading, 4)
            VStack(spacing: 0, content: contenido)
                .carta()
        }
    }
}

/// El campo del nombre, para cambiarlo después del onboarding.
///
/// Vive acá porque es el único lugar que lo usa: la primera vez se pregunta en
/// `Bienvenida`, que tiene su propia pantalla.
struct CampoDeNombre: View {
    @Binding var nombre: String
    var enfocado: FocusState<Bool>.Binding

    var body: some View {
        TextField("", text: $nombre, prompt: Text("Tu nombre").foregroundStyle(Paleta.tintaTenue))
            .font(.redonda(.body))
            .foregroundStyle(Paleta.tinta)
            .textContentType(.givenName)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused(enfocado)
            .onChange(of: nombre) {
                // El mismo techo que el CHECK del servidor. Cortar acá evita
                // que escribas cuarenta y pico y el guardado falle callado.
                if nombre.count > 40 { nombre = String(nombre.prefix(40)) }
            }
    }
}
