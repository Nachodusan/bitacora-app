import SwiftUI

/// Los tres puntos de "Pensando".
///
/// Reemplaza a un "Pensando…" escrito con puntos suspensivos, que es un texto
/// quieto: no se distingue de una app colgada, que es justo lo que la persona
/// se pregunta mientras espera. Estos puntos se encienden en ola y dicen que
/// algo está pasando.
///
/// LENTO A PROPÓSITO, como la luz. Un ciclo cada segundo y medio y un cambio de
/// brillo suave, no un parpadeo. La app ya tuvo una versión de la luz que Dusan
/// describió como "luces de fiesta"; esto es lo contrario, y comparte el mismo
/// criterio: si algo se mueve rápido acá adentro, molesta.
///
/// Con "reducir movimiento" quedan los tres puntos encendidos, quietos y
/// parejos: se sigue viendo que está esperando, sin nada que se mueva.
struct Pensando: View {
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    /// Segundos por ciclo completo de la ola.
    private let ciclo: Double = 1.5
    /// Cuánto se atrasa cada punto respecto del anterior, en fracción de ciclo.
    private let atraso: Double = 0.16

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                if sinMovimiento {
                    punto(0.7)
                } else {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        punto(brillo(t, i))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pensando")
    }

    private func punto(_ brillo: Double) -> some View {
        Circle()
            .fill(Paleta.tinta.opacity(0.25 + 0.6 * brillo))
            .frame(width: 6, height: 6)
            // El tamaño acompaña apenas: sin esto la ola se lee como un
            // parpadeo de brillo y no como algo que se mueve de izquierda a
            // derecha.
            .scaleEffect(0.85 + 0.3 * brillo)
    }

    /// 0…1 para el punto `i`, con la ola corrida un poco en cada uno.
    private func brillo(_ t: Double, _ i: Int) -> Double {
        let fase = (t / ciclo - Double(i) * atraso) * 2 * .pi
        return (sin(fase) + 1) / 2
    }
}
