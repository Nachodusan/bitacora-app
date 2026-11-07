import SwiftData
import SwiftUI

/// Una sesión ya anotada, para releer.
///
/// Se lee como una nota y no como un formulario: el número, la fecha y debajo
/// lo que la persona escribió, con su pregunta arriba en chico. Para cambiar
/// algo se toca esa parte y se abre sólo esa pregunta, a pantalla completa
/// (`AnotarSesionView`). «Repasar todo», abajo, las repasa de a una.
///
/// Desde la noche del 04/10/2026 (la propuesta A que eligió Dusan) cada parte
/// lleva un ícono y su pregunta —«¿Qué entendiste?»—, en vez de un rótulo en
/// mayúsculas que se veía igual en las cinco, y los dos botones tienen nombre:
/// eran un lápiz y una papelera arriba, que había que adivinar.
///
/// Si la sesión nació de un borrador —la armó el servidor con lo que la persona
/// contó después de la consulta—, arriba lo dice, y queda «para revisar» hasta
/// que la persona la da por buena o la repasa entera.
struct SesionView: View {
    @Bindable var sesion: SesionDeTerapia

    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar

    @State private var editando: AnotarSesionView.Modo?
    @State private var confirmarBorrado = false

    var body: some View {
        ZStack {
            Fondo()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    encabezado
                    if !sesion.revisada { paraRevisar }
                    parte("lightbulb", "¿Qué entendiste?", sesion.entendi, .entendi)
                    parte("leaf", "¿Qué te aportó o qué aprendiste?", sesion.aporte, .aporte)
                    parte("heart", "¿Cómo te sentiste?", sesion.sentir, .sentir)
                    parte("arrow.up.right", "¿En qué avanzaste?", sesion.avance, .avance)
                    temas
                    acciones
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
                // La barra de pestañas flota abajo.
                .padding(.bottom, 120)
            }
        }
        // Sin título en la barra: «Sesión 2» ya está abajo, en grande, y dicho
        // dos veces seguidas se ve como un error.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog("¿Eliminar la sesión \(sesion.numero)?",
                            isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive, action: borrar)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borra lo que anotaste de esta sesión. No se puede deshacer.")
        }
        .fullScreenCover(item: $editando) { modo in
            AnotarSesionView(sesion: sesion, modo: modo) { _ in
                // Repasarla entera es revisarla.
                if modo == .repaso { darPorRevisada() } else { try? contexto.save() }
                editando = nil
            }
        }
    }

    // MARK: - Número y fecha

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { editando = .unSolo(.numero) } label: {
                Text("Sesión \(sesion.numero)")
                    .font(.redonda(.largeTitle, .semibold))
                    .foregroundStyle(Paleta.tinta)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Cambiar el número de sesión")

            Button { editando = .unSolo(.fecha) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                    Text(sesion.fechaEscrita)
                        .font(.redonda(.subheadline))
                }
                .foregroundStyle(Paleta.musgoSuave)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Cambiar la fecha")
        }
        .padding(.bottom, 6)
    }

    // MARK: - Un borrador para revisar

    /// Lo que dice arriba de una sesión que armó el servidor.
    private var paraRevisar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                Text("Para revisar")
                    .font(.redonda(.caption, .bold))
            }
            .foregroundStyle(Paleta.bitacora)
            Text("La armó Bitácora con lo que contaste después de la consulta. Corrige lo que no esté bien y completa lo que falte.")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tinta)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: darPorRevisada) {
                Text("Está bien así")
                    .font(.redonda(.subheadline, .semibold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Paleta.musgo))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Paleta.bitacora.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Paleta.bitacora.opacity(0.4), lineWidth: 1)
                }
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    /// Queda como suya. Si es de una consulta, el servidor se entera de que ya
    /// tiene evaluación: deja de preguntar por ella y borra el borrador.
    private func darPorRevisada() {
        withAnimation(.snappy) { sesion.revisada = true }
        try? contexto.save()
        if let id = sesion.eventoId { Task { await Agenda.shared.evaluada(id) } }
    }

    // MARK: - Lo anotado

    /// Una pregunta con lo que se contestó: su ícono, la pregunta en chico y
    /// el texto para leer. Sin casillero.
    private func parte(_ icono: String, _ pregunta: String, _ texto: String,
                       _ paso: AnotarSesionView.Paso) -> some View {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button { editando = .unSolo(paso) } label: {
            HStack(alignment: .top, spacing: 12) {
                circulo(icono)
                VStack(alignment: .leading, spacing: 5) {
                    Text(pregunta)
                        .font(.redonda(.footnote, .semibold))
                        .foregroundStyle(Paleta.tintaTenue)
                    if limpio.isEmpty {
                        sinAnotar
                    } else {
                        Text(limpio)
                            .font(.redonda(.body))
                            .foregroundStyle(Paleta.tinta)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Tocar para escribir o cambiar")
    }

    private func circulo(_ icono: String) -> some View {
        Image(systemName: icono)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Paleta.musgo)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Paleta.musgo.opacity(0.14)))
    }

    /// Los dos botones, con su nombre.
    private var acciones: some View {
        HStack(spacing: 10) {
            Button { editando = .repaso } label: {
                Label("Repasar todo", systemImage: "pencil")
            }
            .buttonStyle(.capsulaTenue)
            Button { confirmarBorrado = true } label: {
                Label("Eliminar", systemImage: "trash")
                    .foregroundStyle(Paleta.rojo)
            }
            .buttonStyle(.capsulaTenue)
        }
        .padding(.top, 18)
    }

    private var temas: some View {
        Button { editando = .unSolo(.temas) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    circulo("tag")
                    Text("¿Qué temas se trataron?")
                        .font(.redonda(.footnote, .semibold))
                        .foregroundStyle(Paleta.tintaTenue)
                }
                if sesion.temas.isEmpty {
                    sinAnotar.padding(.leading, 44)
                } else {
                    Fluido(espacio: 8) {
                        ForEach(sesion.temas, id: \.self) { tema in
                            Text(tema)
                                .font(.redonda(.subheadline, .medium))
                                .foregroundStyle(Paleta.musgo)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Paleta.musgo.opacity(0.14)))
                        }
                    }
                    // Alineados con el texto de las otras partes, no con su ícono.
                    .padding(.leading, 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Tocar para agregar o quitar temas")
    }

    private var sinAnotar: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14))
            Text("Anotar")
                .font(.redonda(.subheadline, .medium))
        }
        .foregroundStyle(Paleta.musgoSuave)
    }

    private func borrar() {
        contexto.delete(sesion)
        try? contexto.save()
        cerrar()
    }
}

/// Para poder presentar la hoja con `fullScreenCover(item:)`.
extension AnotarSesionView.Modo: Identifiable {
    var id: String {
        switch self {
        case .nueva: "nueva"
        case .repaso: "repaso"
        case .unSolo(let p): "solo-\(p.rawValue)"
        }
    }
}
