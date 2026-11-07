import SwiftUI

/// La puerta de entrada a la charla.
///
/// POR QUÉ EXISTE. Antes la pantalla arrancaba con el campo de texto puesto y
/// la barra de pestañas abajo: la app se parecía a una bandeja de mensajes que
/// está siempre ahí esperando. Hablar de lo que te pasó no es revisar el
/// correo, y conviene que entrar cueste un gesto. Un solo toque, pero un toque.
///
/// Lo que pasa al tocar no es decorativo: la barra de pestañas se va, el
/// calendario deja de estar a un dedo de distancia, y la pantalla queda sólo
/// para la conversación. Es lo más cerca que la app puede estar de cerrar la
/// puerta de una habitación.
///
/// LOS ANILLOS SON ONDAS, no un spinner. Nacen del centro y se van, lento, cada
/// dos segundos y medio: es la misma idea que la luz de la voz, que alguien
/// está del otro lado esperando. Con "reducir movimiento" quedan quietos y lo
/// único que se ve es el núcleo.
struct Portal: View {
    let alAbrir: () -> Void

    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var abriendo = false

    /// Cuánto tarda un anillo en ir del centro al borde.
    private let ciclo: Double = 2.5
    private let cuantos = 3

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)

            Button(action: abrir) {
                ZStack {
                    if !sinMovimiento { anillos }
                    nucleo
                }
                .frame(width: 190, height: 190)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir la conversación")
            .scaleEffect(abriendo ? 1.9 : 1)
            .opacity(abriendo ? 0 : 1)

            Text("Toca para abrir")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaTenue)
                .opacity(abriendo ? 0 : 1)

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Las ondas que salen del centro.
    private var anillos: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<cuantos, id: \.self) { i in
                    // Cada anillo arranca corrido un tercio de ciclo, así
                    // siempre hay uno saliendo y otro llegando al borde.
                    let p = ((t / ciclo) + Double(i) / Double(cuantos))
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(Paleta.musgo, lineWidth: 1.5)
                        // Arranca del tamaño del núcleo, no de cero: así parece
                        // que sale de él y no que aparece de la nada.
                        .frame(width: 96 + 94 * p, height: 96 + 94 * p)
                        // Se apaga hacia el final, y entra suave al principio.
                        .opacity((1 - p) * 0.55 * min(1, p * 6))
                }
            }
        }
    }

    private var nucleo: some View {
        ZStack {
            Circle()
                .fill(Paleta.musgo.opacity(0.14))
                .frame(width: 96, height: 96)
            Circle()
                .strokeBorder(Paleta.musgo.opacity(0.4), lineWidth: 1)
                .frame(width: 96, height: 96)
            VozViva(viva: !sinMovimiento)
                .frame(width: 38, height: 38)
                .foregroundStyle(Paleta.musgo)
        }
    }

    /// Se abre con la animación puesta y se avisa cuando terminó de salir.
    ///
    /// El retraso no es un adorno: si la conversación apareciera en el mismo
    /// cuadro en que el portal todavía se está yendo, las dos cosas se pisarían
    /// en pantalla. Medio segundo alcanza para que una salga y entre la otra.
    private func abrir() {
        guard !abriendo else { return }
        if sinMovimiento { alAbrir(); return }
        withAnimation(.easeIn(duration: 0.42)) { abriendo = true }
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            alAbrir()
            // Queda listo para la próxima vez que se cierre la charla.
            abriendo = false
        }
    }
}
