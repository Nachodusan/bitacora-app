import SwiftUI

/// La luz.
///
/// Reemplaza al orbe: una esfera con brillo, anillos y un micrófono adentro que
/// se comía media pantalla. Esto es más chico y más vivo — manchas de color
/// difusas que se mueven y se funden, y que responden al audio de verdad:
///
/// Dibuja la misma energía que el horizonte y el borde, en el mismo azul, pero
/// la cruda y sin seguidor: se mueve bastante más que las otras dos.
///
/// NO ESTÁ EN AJUSTES y no la instancia nadie. Quedó de la comparación del
/// 06/09 por si hay que volver a mirarla; si no, se borra y está en git.
struct Luz: View {
    typealias Modo = ModoDeVoz

    let modo: Modo
    /// Nivel del micrófono, 0…1. Sólo importa escuchando.
    var nivel: Double = 0
    /// Cuándo empezó la última palabra de Bitácora. Sólo importa hablando.
    var ultimaPalabra: Date? = nil
    var tamano: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    private var color: Color { SenalDeVoz.color }

    var body: some View {
        TimelineView(.animation(paused: sinMovimiento)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let e = energia(en: ctx.date, t: t)
                // `tamano` y no `size`: el lienzo es más grande que la luz a
                // propósito, para que el desenfoque se apague solo en vez de
                // cortarse en un cuadrado en el borde del Canvas.
                let base = tamano * 0.36 * (1 + 0.45 * e)

                // Las manchas, difusas. Cinco, cada una en su órbita lenta y con
                // su fase, para que la forma nunca se repita igual.
                g.addFilter(.blur(radius: base * 0.40))
                for i in 0..<5 {
                    let f = Double(i)
                    let ang = sinMovimiento ? f * 1.26 : t * (0.35 + f * 0.09) + f * 1.26
                    let r = base * (0.28 + 0.12 * sin(t * (0.6 + f * 0.13) + f))
                    let p = CGPoint(x: c.x + cos(ang) * r, y: c.y + sin(ang) * r)
                    let d = base * (1.30 - f * 0.10)
                    let tono = i % 2 == 0 ? color : color.opacity(0.75)
                    g.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                           with: .color(tono.opacity(0.66 + 0.30 * e)))
                }
            }
            // Un núcleo apenas más definido, para que tenga un centro.
            .overlay {
                let e = energia(en: ctx.date, t: t)
                Circle()
                    .fill(color.opacity(0.55 + 0.4 * e))
                    .frame(width: tamano * 0.26, height: tamano * 0.26)
                    .blur(radius: 2.5)
            }
            .frame(width: tamano * 1.8, height: tamano * 1.8)
            .scaleEffect(1 + 0.08 * energia(en: ctx.date, t: t))
        }
        .frame(width: tamano, height: tamano)
        .animation(.easeOut(duration: 0.12), value: nivel)
    }

    private func energia(en ahora: Date, t: Double) -> Double {
        SenalDeVoz.energia(modo: modo, nivel: nivel, ultimaPalabra: ultimaPalabra,
                           ahora: ahora, t: t, sinMovimiento: sinMovimiento)
    }
}
