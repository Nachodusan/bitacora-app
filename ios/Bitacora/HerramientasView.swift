import SwiftUI
import UIKit

/// Las herramientas: «Ponerle nombre» y «Calmarme ya» (26/10/2026).
///
/// Dentro de la charla —también en plena llamada, que queda en pausa— se
/// ofrecen cuando vienen al caso (`Herramienta.sugerida`), y lo que se hace
/// vuelve como un turno tuyo (`alTerminar`): así Bitácora lo retoma, y queda en
/// la transcripción para la nota del psicólogo. Fuera de la charla están en
/// Mi expediente, en el «Espacio para relajarte», para usarlas cuando quieras.
///
/// Van con los colores de la marca, sobre el fondo oscuro de siempre: son la
/// misma familia que los anillos.

/// Los colores de la marca, para los anillos y las herramientas.
enum Marca {
    static let durazno = Color(red: 0.93, green: 0.65, blue: 0.50)
    static let crema = Color(red: 0.86, green: 0.83, blue: 0.70)
    /// Las líneas en modo claro, donde el crema no se ve.
    static let oliva = Color(red: 0.33, green: 0.32, blue: 0.24)
    /// El durazno para TEXTO: en modo claro, más oscuro, porque el de la marca
    /// sobre fondo claro casi no se lee. En oscuro es el mismo.
    static var duraznoTexto: Color { Paleta.adaptativo(Paleta.Tono(claro: 0xB8603A, oscuro: 0xEDA680)) }
    /// El texto sobre el durazno: oscuro siempre, en los dos modos.
    static let sobreDurazno = Color(red: 0.08, green: 0.09, blue: 0.06)
}

// MARK: - Ponerle nombre

struct PonerleNombreView: View {
    /// Lo que se dijo hasta ahora: de ahí salen las emociones.
    let turnos: [Turno]
    let alTerminar: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var emociones: [String]? = nil
    @State private var elegida: String?
    @State private var intensidad = 5.0

    /// Si el servidor no llega: las mismas de `herramientas.ts`.
    private static let deSiempre = ["tristeza", "rabia", "miedo", "cansancio", "frustración", "soledad"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            arriba
            Text("PONERLE NOMBRE")
                .font(.redonda(.caption, .bold))
                .tracking(0.8)
                .foregroundStyle(Marca.durazno)
                .padding(.top, 22)
            Text("Escuché algo como esto.\n¿Cuál se acerca más?")
                .font(.redonda(.title2, .semibold))
                .foregroundStyle(Paleta.tinta)
                .padding(.top, 8)

            nube
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .padding(.vertical, 8)

            fuerza
            Spacer(minLength: 14)

            Button {
                guard let elegida else { return }
                alTerminar(Herramienta.loQueElegiste(elegida, intensidad: Int(intensidad.rounded())))
                dismiss()
            } label: {
                Text("Sí, es eso")
                    .font(.redonda(.body, .semibold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Capsule().fill(Marca.crema.opacity(elegida == nil ? 0.35 : 1)))
            }
            .buttonStyle(.plain)
            .disabled(elegida == nil)

            Button { alTerminar(nil); dismiss() } label: {
                Text("Ninguna — lo digo yo")
                    .font(.redonda(.callout, .medium))
                    .foregroundStyle(Paleta.tinta)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .overlay(Capsule().strokeBorder(Paleta.cartaBorde, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background(Fondo())
        .task {
            let cliente = SyncClient(config: Config.shared.servidor)
            let pedidos = turnos.map { TurnoDeCharla(de: $0.de == .vos ? "vos" : "bitacora", texto: $0.texto) }
            let r = await cliente.emociones(turnos: pedidos, dia: CalendarioView.hoyLogico())
            withAnimation(.snappy(duration: 0.3)) { emociones = (r?.isEmpty == false ? r : nil) ?? Self.deSiempre }
        }
    }

    private var arriba: some View {
        HStack {
            Text("Ponerle nombre")
                .font(.redonda(.footnote))
                .foregroundStyle(Paleta.tintaTenue)
            Spacer()
            Button { alTerminar(nil); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Paleta.tintaSuave)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Paleta.carta))
            }
            .accessibilityLabel("Cerrar")
        }
        .padding(.top, 12)
    }

    /// Las emociones alrededor de los anillos, como en la imagen que eligió
    /// Dusan: seis lugares fijos, para que no se pisen.
    private var nube: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lugares: [CGPoint] = [
                CGPoint(x: 0.24, y: 0.12), CGPoint(x: 0.74, y: 0.08),
                CGPoint(x: 0.16, y: 0.50), CGPoint(x: 0.86, y: 0.48),
                CGPoint(x: 0.28, y: 0.88), CGPoint(x: 0.68, y: 0.92),
            ]
            ZStack {
                Anillos(tamano: 120)
                    .position(x: w / 2, y: h / 2)
                if let emociones {
                    ForEach(Array(emociones.prefix(6).enumerated()), id: \.element) { i, e in
                        chip(e)
                            .position(x: lugares[i].x * w, y: lugares[i].y * h)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                } else {
                    Text("Buscando las palabras…")
                        .font(.redonda(.footnote))
                        .foregroundStyle(Paleta.tintaTenue)
                        .position(x: w / 2, y: h - 10)
                }
            }
        }
    }

    private func chip(_ e: String) -> some View {
        let si = elegida == e
        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.snappy(duration: 0.2)) { elegida = si ? nil : e }
        } label: {
            Text(e)
                .font(.redonda(.callout, .medium))
                .foregroundStyle(si ? Paleta.fondoAlto : Paleta.tinta)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background {
                    Capsule().fill(si ? Marca.durazno : Paleta.carta)
                        .overlay(Capsule().strokeBorder(si ? .clear : Paleta.cartaBorde, lineWidth: 1))
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(si ? .isSelected : [])
    }

    private var fuerza: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("¿Qué tan fuerte, ahora mismo?")
                    .font(.redonda(.subheadline, .medium))
                    .foregroundStyle(Paleta.tinta)
                Spacer()
                Text("\(Int(intensidad.rounded()))")
                    .font(.redonda(.title2, .semibold))
                    .foregroundStyle(Marca.durazno)
                    .contentTransition(.numericText())
            }
            Slider(value: $intensidad, in: 0...10, step: 1)
                .tint(Marca.durazno)
            HStack {
                Text("apenas"); Spacer(); Text("me desborda")
            }
            .font(.redonda(.caption))
            .foregroundStyle(Paleta.tintaTenue)
        }
        .padding(16)
        .carta(radio: 20)
    }
}

// MARK: - Calmarme ya

/// Una respiración guiada: inhala 4, exhala 6, durante tres minutos. Los anillos
/// se abren al inhalar y se cierran al exhalar, y el teléfono vibra suave en
/// cada cambio, así se puede hacer con los ojos cerrados.
///
/// Exhalar más largo que inhalar es lo que calma: es la respiración que
/// proponen los manuales de la guía para bajar la activación del cuerpo.
struct CalmarmeView: View {
    let alTerminar: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var inicio = Date()
    @State private var faseAnterior: Bool?

    private static let inhala = 4.0
    private static let exhala = 6.0
    private static let total = 180.0

    var body: some View {
        TimelineView(.animation) { ctx in
            let pasado = min(Self.total, ctx.date.timeIntervalSince(inicio))
            let ciclo = pasado.truncatingRemainder(dividingBy: Self.inhala + Self.exhala)
            let inhalando = ciclo < Self.inhala
            let enFase = inhalando ? ciclo : ciclo - Self.inhala
            let largo = inhalando ? Self.inhala : Self.exhala
            let progreso = enFase / largo
            let terminado = pasado >= Self.total
            // La apertura: suave al empezar y al terminar cada fase.
            let suave = (1 - cos(progreso * .pi)) / 2
            let apertura = terminado ? 0.5 : (inhalando ? suave : 1 - suave)

            VStack(spacing: 0) {
                HStack {
                    Text("Calmarme ya · \(reloj(pasado)) de \(reloj(Self.total))")
                        .font(.redonda(.footnote))
                        .foregroundStyle(Paleta.tintaTenue)
                        .monospacedDigit()
                    Spacer()
                    Button { cerrar(pasado: pasado, mejor: false) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Paleta.tintaSuave)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Paleta.carta))
                    }
                    .accessibilityLabel("Cerrar")
                }
                .padding(.top, 12)

                Spacer()
                circulos(apertura: sinMovimiento ? 0.5 : apertura)
                    .overlay {
                        VStack(spacing: 4) {
                            Text(terminado ? "✓" : "\(Int(largo - enFase) + 1)")
                                .font(.system(size: 64, weight: .light, design: .rounded))
                                .foregroundStyle(Marca.durazno)
                                .contentTransition(.numericText(countsDown: true))
                                .monospacedDigit()
                            Text(terminado ? "Listo" : inhalando ? "Inhala" : "Exhala")
                                .font(.redonda(.title3, .medium))
                                .foregroundStyle(Paleta.tinta)
                        }
                    }
                Spacer()

                barras(inhalando: inhalando, progreso: terminado ? 1 : progreso)
                    .padding(.bottom, 22)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .foregroundStyle(Paleta.tintaSuave)
                    Text("El teléfono vibra suave en cada cambio, así puedes cerrar los ojos.")
                        .font(.redonda(.footnote))
                        .foregroundStyle(Paleta.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .carta(radio: 18)

                HStack(spacing: 10) {
                    Button { cerrar(pasado: pasado, mejor: true) } label: {
                        Text("Ya estoy mejor")
                            .font(.redonda(.callout, .semibold))
                            .foregroundStyle(Paleta.tinta)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .overlay(Capsule().strokeBorder(Paleta.cartaBorde, lineWidth: 1))
                    }
                    Button { cerrar(pasado: pasado, mejor: false) } label: {
                        Text("Volver a hablar")
                            .font(.redonda(.callout, .semibold))
                            .foregroundStyle(Paleta.fondoAlto)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Capsule().fill(Marca.crema))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .onChange(of: terminado ? nil : inhalando) { _, ahora in
                // Una vibración por cambio de fase, y una más larga al terminar.
                guard faseAnterior != ahora else { return }
                faseAnterior = ahora
                if ahora == nil { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                else { UIImpactFeedbackGenerator(style: ahora == true ? .soft : .light).impactOccurred(intensity: 0.8) }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background(Fondo())
        .onAppear {
            inicio = Date()
            // La pantalla no se apaga en medio de la respiración.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// Cuatro anillos fijos y uno durazno que se abre y se cierra con el aire.
    private func circulos(apertura: Double) -> some View {
        ZStack {
            ForEach(0..<4) { i in
                Circle()
                    .strokeBorder(Marca.crema.opacity(0.55 - Double(i) * 0.1), lineWidth: 1)
                    .frame(width: 170 + CGFloat(i) * 34, height: 170 + CGFloat(i) * 34)
            }
            Circle()
                .strokeBorder(Marca.durazno, lineWidth: 1.5)
                .frame(width: 120 + 140 * apertura, height: 120 + 140 * apertura)
        }
        .frame(width: 280, height: 280)
    }

    /// Dos barras, proporcionales a lo que dura cada fase: 4 y 6.
    private func barras(inhalando: Bool, progreso: Double) -> some View {
        GeometryReader { g in
            let total = g.size.width - 8
            HStack(alignment: .top, spacing: 8) {
                barra("Inhala \(Int(Self.inhala))", lleno: inhalando ? progreso : 0, activa: inhalando)
                    .frame(width: total * Self.inhala / (Self.inhala + Self.exhala))
                barra("Exhala \(Int(Self.exhala))", lleno: inhalando ? 0 : progreso, activa: !inhalando)
                    .frame(width: total * Self.exhala / (Self.inhala + Self.exhala))
            }
        }
        .frame(height: 30)
    }

    private func barra(_ t: String, lleno: Double, activa: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().fill(Paleta.carta)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(Marca.durazno).frame(width: g.size.width * lleno)
                    }
                }
            Text(t)
                .font(.redonda(.caption, activa ? .semibold : .regular))
                .foregroundStyle(activa ? Paleta.tinta : Paleta.tintaTenue)
        }
    }

    private func reloj(_ s: Double) -> String {
        let n = Int(s)
        return String(format: "%d:%02d", n / 60, n % 60)
    }

    /// Lo que entra a la charla. Menos de medio minuto no cuenta como haber
    /// respirado: fue abrir y cerrar.
    private func cerrar(pasado: Double, mejor: Bool) {
        let minutos = max(1, Int((pasado / 60).rounded()))
        alTerminar(pasado >= 30 ? Herramienta.respire(minutos: minutos, mejor: mejor) : nil)
        dismiss()
    }
}

// MARK: - Espacio para relajarte

/// Las herramientas para cuando quieras, desde Mi expediente (26/10/2026). Es un
/// espacio tuyo: lo que haces acá no entra a la charla con Bitácora.
struct EspacioParaRelajarteView: View {
    @State private var abierta: Herramienta?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Anillos(tamano: 110)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Text("Para cuando lo necesites. Lo que hagas aquí es sólo tuyo.")
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tintaSuave)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                opcion(.calmarme, icono: "wind", titulo: "Respirar",
                       detalle: "Tres minutos para bajar un cambio. Inhala 4, exhala 6.")
                opcion(.nombrar, icono: "tag", titulo: "Ponerle nombre",
                       detalle: "Encontrar la palabra para lo que sientes, y cuánto.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .fullScreenCover(item: $abierta) { h in
            switch h {
            case .calmarme: CalmarmeView(alTerminar: { _ in })
            case .nombrar: PonerleNombreView(turnos: [], alTerminar: { _ in })
            }
        }
    }

    private func opcion(_ h: Herramienta, icono: String, titulo: String, detalle: String) -> some View {
        Button { abierta = h } label: {
            HStack(spacing: 14) {
                Image(systemName: icono)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Marca.durazno)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Marca.durazno.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(titulo)
                        .font(.redonda(.headline))
                        .foregroundStyle(Paleta.tinta)
                    Text(detalle)
                        .font(.redonda(.footnote))
                        .foregroundStyle(Paleta.tintaSuave)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Paleta.tintaTenue)
            }
            .padding(16)
            .carta(radio: 20)
        }
        .buttonStyle(.plain)
    }
}

extension Herramienta: @retroactive Identifiable {
    public var id: String { rawValue }
}
