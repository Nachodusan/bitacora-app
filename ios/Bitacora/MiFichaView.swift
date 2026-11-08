import SwiftData
import SwiftUI

/// «Lo que Bitácora sabe de ti», en Mi espacio (27/10/2026, etapa 1 de la
/// ficha viva). La persona ve su ficha entera, con la frase suya de donde
/// salió cada dato; elige qué le llega a su psicólogo (va arriba en el PDF de
/// «Mi resumen») y quita lo que no quiere que esté.
///
/// La primera vez se ve el aviso: qué se guarda y qué se arma. Hasta que lo
/// lee, el servidor no arma la ficha ni la usa en la charla (transparencia).
///
/// Acá también se borra la cuenta entera: treinta días en la papelera, por si
/// se arrepiente. Una conversación se borra desde Conversaciones.
struct MiFichaView: View {
    @Environment(\.modelContext) private var contexto
    @State private var ficha: Ficha?
    @State private var sinServidor = false
    @State private var abierto: Int?
    @State private var quitando: DatoDeLaFicha?
    @State private var borrandoCuenta = false

    private var cliente: SyncClient { SyncClient(config: Config.shared.servidor) }

    var body: some View {
        Group {
            if let ficha {
                if !ficha.avisada { AvisoDeLaFicha { await leyo() } } else { lista(ficha) }
            } else if sinServidor {
                Text("No se pudo traer tu ficha. Revisa la conexión y vuelve a entrar.")
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tintaSuave)
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .task { await cargar() }
        .confirmationDialog("¿Quitar «\(quitando?.nombre ?? "")» de tu ficha?",
                            isPresented: Binding(get: { quitando != nil }, set: { if !$0 { quitando = nil } }),
                            titleVisibility: .visible) {
            Button("Quitar", role: .destructive) { if let d = quitando { Task { await quitar(d) } } }
        } message: {
            Text("Bitácora deja de usarlo y no vuelve a anotarlo. Tus conversaciones no se tocan.")
        }
        .confirmationDialog("¿Borrar tu cuenta?", isPresented: $borrandoCuenta, titleVisibility: .visible) {
            Button("Borrar mi cuenta", role: .destructive) { Task { await borrarCuenta() } }
        } message: {
            Text("Todo lo tuyo va a la papelera por 30 días: tus conversaciones, tu ficha y tus resúmenes. En ese tiempo puedes recuperarla; después se borra para siempre, también de este teléfono.")
        }
    }

    private func cargar() async {
        CuentaEnLaPapelera.borrarLoLocalSiVencio(contexto)
        if let f = await cliente.ficha() { ficha = f } else { sinServidor = true }
    }

    private func leyo() async {
        if await cliente.leyoElAviso() { await cargar() }
    }

    private func quitar(_ d: DatoDeLaFicha) async {
        quitando = nil
        guard await cliente.quitar(dato: d.id) else { return }
        withAnimation {
            for i in ficha?.secciones.indices ?? 0..<0 { ficha?.secciones[i].datos.removeAll { $0.id == d.id } }
            ficha?.secciones.removeAll { $0.datos.isEmpty }
        }
    }

    private func compartir(_ d: DatoDeLaFicha, _ si: Bool) async {
        guard await cliente.compartir(dato: d.id, si) else { return }
        for i in ficha?.secciones.indices ?? 0..<0 {
            if let j = ficha?.secciones[i].datos.firstIndex(where: { $0.id == d.id }) { ficha?.secciones[i].datos[j].compartir = si }
        }
    }

    private func borrarCuenta() async {
        guard let dia = await cliente.borrarCuenta() else { return }
        CuentaEnLaPapelera.seBorraEl = dia
        await cargar()
    }

    private func recuperar() async {
        guard await cliente.recuperarCuenta() else { return }
        CuentaEnLaPapelera.seBorraEl = nil
        await cargar()
    }

    // MARK: - La ficha

    private func lista(_ f: Ficha) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let dia = f.cuentaSeBorraEl { papelera(dia) }
                Text("Sale de lo que contaste en tus charlas, con tus palabras. Toca un dato para ver de dónde salió, mandárselo a tu psicólogo o quitarlo.")
                    .font(.redonda(.footnote))
                    .foregroundStyle(Paleta.tintaSuave)
                    .padding(.horizontal, 4)
                if f.secciones.isEmpty {
                    Text("Todavía no hay nada. Se va armando con tus charlas, al cerrar cada día.")
                        .font(.redonda(.subheadline))
                        .foregroundStyle(Paleta.tintaTenue)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                }
                ForEach(f.secciones) { s in
                    Text(s.titulo.uppercased())
                        .font(.redonda(.caption2, .bold))
                        .tracking(0.6)
                        .foregroundStyle(Paleta.tintaTenue)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                    VStack(spacing: 0) {
                        ForEach(Array(s.datos.enumerated()), id: \.element.id) { i, d in
                            if i > 0 { Divider().overlay(Paleta.cartaBorde) }
                            fila(d)
                        }
                    }
                    .carta(radio: 18)
                }
                if f.cuentaSeBorraEl == nil {
                    Button { borrandoCuenta = true } label: {
                        Text("Borrar mi cuenta")
                            .font(.redonda(.footnote, .semibold))
                            .foregroundStyle(Paleta.tintaTenue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .padding(.top, 18)
                    Text("Para borrar una conversación, mantenla apretada en Conversaciones.")
                        .font(.redonda(.caption))
                        .foregroundStyle(Paleta.tintaTenue)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 90)
        }
    }

    private func fila(_ d: DatoDeLaFicha) -> some View {
        let abierta = abierto == d.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { abierto = abierta ? nil : d.id }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.nombre)
                            .font(.redonda(.callout, .semibold))
                            .foregroundStyle(Paleta.tinta)
                        Text(cuantas(d))
                            .font(.redonda(.caption))
                            .foregroundStyle(Paleta.tintaTenue)
                        if let c = d.cuandoYParaQue {
                            Text(c)
                                .font(.redonda(.caption, .medium))
                                .foregroundStyle(Marca.duraznoTexto)
                        }
                        if !d.apodos.isEmpty {
                            Text("También le dices: " + d.apodos.joined(separator: ", "))
                                .font(.redonda(.caption))
                                .foregroundStyle(Paleta.tintaTenue)
                        }
                    }
                    Spacer(minLength: 6)
                    if d.compartir {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Marca.duraznoTexto)
                            .accessibilityLabel("Para tu psicólogo")
                    }
                    Image(systemName: abierta ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Paleta.tintaTenue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if abierta {
                ForEach(d.citas, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("«\(c.cita)»")
                            .font(.dicha(.subheadline))
                            .foregroundStyle(Paleta.tinta)
                        Text(Self.fecha(c.dia))
                            .font(.redonda(.caption2))
                            .foregroundStyle(Paleta.tintaTenue)
                    }
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Marca.durazno.opacity(0.6)).frame(width: 2) }
                }
                Toggle(isOn: Binding(get: { d.compartir }, set: { si in Task { await compartir(d, si) } })) {
                    Text("Para mi psicólogo")
                        .font(.redonda(.subheadline))
                        .foregroundStyle(Paleta.tinta)
                }
                .tint(Marca.durazno)
                Button(role: .destructive) { quitando = d } label: {
                    Text("Quitar de mi ficha")
                        .font(.redonda(.subheadline, .semibold))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func cuantas(_ d: DatoDeLaFicha) -> String {
        let veces = d.veces == 1 ? "Lo contaste una vez" : "Lo contaste \(d.veces) veces"
        return veces + ", la última el " + Self.fecha(d.ultima)
    }

    static func fecha(_ dia: String) -> String {
        let d = Int(dia.suffix(2)) ?? 1, m = Int(dia.dropFirst(5).prefix(2)) ?? 1
        return "\(d) de \(Resumen.meses[m - 1])"
    }

    private func papelera(_ dia: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tu cuenta se borra el \(Self.fecha(dia))")
                .font(.redonda(.headline))
                .foregroundStyle(Marca.sobreDurazno)
            Text("Mientras tanto Bitácora no arma nada nuevo. Si te arrepientes, la recuperas entera.")
                .font(.redonda(.footnote))
                .foregroundStyle(Marca.sobreDurazno.opacity(0.75))
            Button { Task { await recuperar() } } label: {
                Text("Recuperar mi cuenta")
                    .font(.redonda(.subheadline, .semibold))
                    .foregroundStyle(Marca.durazno)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Marca.sobreDurazno))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Marca.durazno))
    }
}

/// El aviso, antes de ver la ficha por primera vez. Dice qué se guarda, qué se
/// arma con eso y qué puede hacer la persona.
private struct AvisoDeLaFicha: View {
    let entendido: () async -> Void
    @State private var enviando = false

    private let puntos: [(String, String)] = [
        ("text.quote", "Tus charlas se guardan tal como las dijiste. Nadie las cambia."),
        ("square.text.square", "Con ellas, Bitácora arma una ficha: lo que te pasa, lo que te sirve, tu gente, lo que quieres. Cada dato lleva la frase tuya de donde salió."),
        ("stethoscope", "No hace diagnósticos. Anota sólo lo que contaste, con tus palabras."),
        ("bubble.left.and.text.bubble.right", "La usa para hablarte a ti y no a cualquiera. A tu psicólogo le llega sólo lo que elijas."),
        ("trash", "Puedes quitar cualquier dato, borrar una conversación o tu cuenta entera."),
        ("phone", "Si alguna vez estás en peligro, Bitácora te da el *4141 al momento. Eso no pasa por la ficha."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Antes de verla")
                    .font(.dicha(.title2))
                    .foregroundStyle(Paleta.tinta)
                ForEach(puntos, id: \.1) { icono, texto in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icono)
                            .font(.system(size: 15))
                            .foregroundStyle(Marca.duraznoTexto)
                            .frame(width: 24)
                        Text(texto)
                            .font(.redonda(.subheadline))
                            .foregroundStyle(Paleta.tintaSuave)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    enviando = true
                    Task { await entendido(); enviando = false }
                } label: {
                    Text(enviando ? "Un momento…" : "Entendido, ver mi ficha")
                        .font(.redonda(.subheadline, .semibold))
                        .foregroundStyle(Marca.sobreDurazno)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(Marca.durazno))
                }
                .buttonStyle(.plain)
                .disabled(enviando)
                .padding(.top, 6)
            }
            .padding(24)
            .padding(.bottom, 80)
        }
    }
}

/// Lo que queda en el teléfono cuando la cuenta va a la papelera. El servidor
/// borra lo suyo a los treinta días; el teléfono, cuando ve que ya pasaron.
enum CuentaEnLaPapelera {
    private static let clave = "bitacora.cuenta_se_borra_el"

    static var seBorraEl: String? {
        get { UserDefaults.standard.string(forKey: clave) }
        set { UserDefaults.standard.set(newValue, forKey: clave) }
    }

    @MainActor static func borrarLoLocalSiVencio(_ contexto: ModelContext) {
        guard let dia = seBorraEl, CalendarioView.hoyLogico() >= dia else { return }
        try? contexto.delete(model: EntradaLocal.self)
        try? contexto.save()
        seBorraEl = nil
    }
}
