import SwiftUI

/// Los dos íconos del compositor, dibujados acá y no tomados de SF Symbols.
///
/// POR QUÉ DIBUJARLOS. El de la llamada no existe en el catálogo del sistema:
/// lo que hay son teléfonos y formas de onda, y ninguna de las dos dice "estoy
/// hablando con alguien que me contesta". El del micrófono sí existe, pero
/// si uno es propio y el otro del sistema no pesan igual, y se nota.
///
/// SE DIBUJAN PARA DIECISÉIS PUNTOS. La primera versión tenía seis y siete
/// trazos finos cada uno —ondas que se volvían renglones de texto, arcos
/// enfrentados con un punto— y a ese tamaño se leían como un borrón. Dusan lo
/// dijo derecho: "no se ven para nada bien". Estos tienen dos formas cada uno y
/// la silueta se reconoce de un vistazo.

/// Grabar un mensaje y transcribirlo.
///
/// Un micrófono macizo. Es la forma más reconocible que existe para esto, y a
/// este tamaño la legibilidad gana sobre la originalidad: un ícono que hay que
/// descifrar es un ícono que falló.
struct Microfono: View {
    var body: some View {
        GeometryReader { geo in
            let l = min(geo.size.width, geo.size.height)
            let u = l / 24          // el dibujo está pensado en una grilla de 24
            ZStack {
                // La cápsula del micrófono.
                Capsule()
                    .frame(width: 5.8 * u, height: 10.8 * u)
                    .offset(y: -4.2 * u)
                // El arco que lo sostiene.
                Arco()
                    .stroke(style: StrokeStyle(lineWidth: 2.1 * u, lineCap: .round))
                    .frame(width: 11.6 * u, height: 5.8 * u)
                    .offset(y: 1.6 * u)
                // El pie.
                Capsule()
                    .frame(width: 2.1 * u, height: 3.4 * u)
                    .offset(y: 6.4 * u)
                Capsule()
                    .frame(width: 7.6 * u, height: 2.1 * u)
                    .offset(y: 8.4 * u)
            }
            .frame(width: l, height: l)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Media circunferencia abierta hacia arriba.
    private struct Arco: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.addArc(center: CGPoint(x: r.midX, y: r.minY),
                     radius: r.width / 2,
                     startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            return p
        }
    }
}

/// La llamada: una voz que irradia.
///
/// Un núcleo lleno con dos arcos alrededor. No es un teléfono —nadie llama por
/// teléfono a una app— ni un ecualizador, que es lo que usa todo el mundo para
/// decir "audio" y acá tendría que decir otra cosa: que hay alguien del otro
/// lado contestando.
///
/// Con `viva` en true los arcos respiran, y eso es lo único que distingue la
/// llamada abierta de la cerrada.
struct VozViva: View {
    var viva: Bool = false
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        GeometryReader { geo in
            let l = min(geo.size.width, geo.size.height)
            let u = l / 24
            TimelineView(.animation(paused: !viva || sinMovimiento)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                // Dos segundos por ciclo: el mismo ritmo lento que la luz.
                let pulso = viva && !sinMovimiento
                    ? 0.82 + 0.18 * (sin(t * .pi) + 1) / 2
                    : 1.0
                ZStack {
                    // El núcleo chico y los arcos bien afuera: pegados se leían
                    // como un ojo, no como una voz saliendo.
                    Circle().frame(width: 5.6 * u, height: 5.6 * u)
                    ArcoLateral(izquierda: true)
                        .stroke(style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
                        .frame(width: 17 * u, height: 17 * u)
                        .scaleEffect(pulso)
                    ArcoLateral(izquierda: false)
                        .stroke(style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
                        .frame(width: 17 * u, height: 17 * u)
                        .scaleEffect(pulso)
                }
                .frame(width: l, height: l)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Un arco de un costado, como un paréntesis.
    private struct ArcoLateral: Shape {
        let izquierda: Bool
        func path(in r: CGRect) -> Path {
            var p = Path()
            let radio = r.height / 2
            let centro = CGPoint(x: r.midX, y: r.midY)
            if izquierda {
                p.addArc(center: centro, radius: radio,
                         startAngle: .degrees(145), endAngle: .degrees(215), clockwise: false)
            } else {
                p.addArc(center: centro, radius: radio,
                         startAngle: .degrees(-35), endAngle: .degrees(35), clockwise: false)
            }
            return p
        }
    }
}

// MARK: - La portada de «Mi expediente»

/// Consultas: el sillón de la consulta.
///
/// Lo eligió Dusan el 04/10/2026, entre seis, para la portada de «Mi expediente».
/// Se reconoce como terapia sin parecerse a nada más de la app: el calendario
/// ya tiene su almanaque y el chat su onda. Es el `armchair` de Tabler Icons
/// (licencia MIT) pasado a trazos; el mismo dibujo está en `Iconos.kt`.
struct Sillon: View {
    /// El grueso del trazo, en la grilla de 24. Con 2 se lee en la portada; en
    /// los dibujos grandes de los estados vacíos conviene uno más fino.
    var grosor: CGFloat = 2
    var body: some View { DibujoDeLineas(dibujo: .sillon, grosor: grosor) }
}

/// Mi resumen: un libro, lo que se escribe y se relee. Elegido junto con el
/// sillón; es el `book-2` de Tabler Icons.
struct Libro: View {
    var grosor: CGFloat = 2
    var body: some View { DibujoDeLineas(dibujo: .libro, grosor: grosor) }
}

/// Una carpeta: el `folder` de Tabler Icons. Fue el ícono de «Mi expediente»
/// hasta el 26/10/2026, cuando la sección pasó a ser «Mi espacio», con una hoja.
struct Carpeta: View {
    var grosor: CGFloat = 2
    var body: some View { DibujoDeLineas(dibujo: .carpeta, grosor: grosor) }
}

/// La pestaña del chat (26/10/2026): la marca en chico, tres anillos
/// ondulados y el punto, en líneas como los otros íconos. Reemplazó a las
/// ondas (`waveform`): la charla es el centro de la app, y lleva la marca. Se ve
/// en la barra de pestañas, pasada a imagen (`AnillosChicos.pestana`).
struct AnillosChicos: View {
    var grosor: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width, geo.size.height) / 24
            ZStack {
                ForEach(0..<3) { i in
                    Self.anillo(radio: (3.9 + Double(i) * 3.0) * u, centro: CGPoint(x: 12 * u, y: 12 * u), i: i)
                        .stroke(style: StrokeStyle(lineWidth: grosor * u, lineCap: .round, lineJoin: .round))
                }
                Circle()
                    .frame(width: 3.2 * u, height: 3.2 * u)
                    .position(x: 12 * u, y: 12 * u)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// La barra de pestañas sólo acepta imágenes, no dibujos de SwiftUI: se
    /// pasa a una imagen una vez, en modo plantilla, para que la barra la pinte
    /// de musgo cuando está elegida y de gris cuando no.
    @MainActor static let pestana: UIImage = {
        let render = ImageRenderer(content: AnillosChicos(grosor: 1.6)
            .frame(width: 26, height: 26)
            .foregroundStyle(.black))
        render.scale = 3
        let imagen = render.uiImage ?? UIImage(systemName: "waveform") ?? UIImage()
        return imagen.withRenderingMode(.alwaysTemplate)
    }()

    /// La misma onda tranquila de `Anillos`, congelada.
    private static func anillo(radio r: Double, centro c: CGPoint, i: Int) -> Path {
        var p = Path()
        let pasos = 72
        for k in 0...pasos {
            let a = Double(k) / Double(pasos) * 2 * .pi
            let onda = sin(3 * a + 0.7 + Double(i) * 0.5) * 0.06 + sin(2 * a + 0.9) * 0.04
            let rr = r * (1 + onda)
            let punto = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            if k == 0 { p.move(to: punto) } else { p.addLine(to: punto) }
        }
        p.closeSubpath()
        return p
    }
}

/// Las notas sueltas: una libreta. Es el `notebook` de Tabler Icons (no se
/// llama `Cuaderno` porque así se llama la lista de notas, en `Apuntes.swift`).
///
/// Reemplazó el 04/10/2026 al lápiz sobre un cuadrado, que en Claude o ChatGPT
/// quiere decir «charla nueva»: Dusan lo eligió en la maqueta, con la palabra
/// «Notas» al lado.
struct Libreta: View {
    var grosor: CGFloat = 2
    var body: some View { DibujoDeLineas(dibujo: .libreta, grosor: grosor) }
}

/// Un dibujo de líneas en la grilla de 24, con las puntas y los codos redondos.
private struct DibujoDeLineas: View {
    let dibujo: Trazos.Cual
    let grosor: CGFloat

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width, geo.size.height) / 24
            Trazos(cual: dibujo)
                .stroke(style: StrokeStyle(lineWidth: grosor * u, lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Las líneas, tal como están en el SVG original: cada arco de ahí es un
/// cuarto o media vuelta de radio 2 o 3 alrededor del centro que se anota.
private struct Trazos: Shape {
    enum Cual { case sillon, libro, libreta, carpeta }
    let cual: Cual

    func path(in r: CGRect) -> Path {
        var p = Path()
        switch cual {
        case .sillon:
            // El asiento con los dos brazos, de una sola vez.
            p.move(to: CGPoint(x: 5, y: 11))
            p.arco(5, 13, 2, -90, 0)
            p.addLine(to: CGPoint(x: 7, y: 15))
            p.addLine(to: CGPoint(x: 17, y: 15))
            p.addLine(to: CGPoint(x: 17, y: 13))
            p.arco(19, 13, 2, 180, 360)
            p.addLine(to: CGPoint(x: 21, y: 17))
            p.arco(19, 17, 2, 0, 90)
            p.addLine(to: CGPoint(x: 5, y: 19))
            p.arco(5, 17, 2, 90, 180)
            p.addLine(to: CGPoint(x: 3, y: 13))
            p.arco(5, 13, 2, 180, 270)
            // El respaldo.
            p.move(to: CGPoint(x: 5, y: 11))
            p.addLine(to: CGPoint(x: 5, y: 6))
            p.arco(8, 6, 3, 180, 270)
            p.addLine(to: CGPoint(x: 16, y: 3))
            p.arco(16, 6, 3, 270, 360)
            p.addLine(to: CGPoint(x: 19, y: 11))
            // Las patas.
            p.move(to: CGPoint(x: 6, y: 19))
            p.addLine(to: CGPoint(x: 6, y: 21))
            p.move(to: CGPoint(x: 18, y: 19))
            p.addLine(to: CGPoint(x: 18, y: 21))
        case .libro:
            // La tapa.
            p.move(to: CGPoint(x: 19, y: 4))
            p.addLine(to: CGPoint(x: 19, y: 20))
            p.addLine(to: CGPoint(x: 7, y: 20))
            p.arco(7, 18, 2, 90, 180)
            p.addLine(to: CGPoint(x: 5, y: 6))
            p.arco(7, 6, 2, 180, 270)
            p.closeSubpath()
            // El borde de las hojas.
            p.move(to: CGPoint(x: 19, y: 16))
            p.addLine(to: CGPoint(x: 7, y: 16))
            p.arco(7, 18, 2, 270, 180)
            // El renglón del título.
            p.move(to: CGPoint(x: 9, y: 8))
            p.addLine(to: CGPoint(x: 15, y: 8))
        case .libreta:
            // La tapa, con la esquina del lomo apenas redonda.
            p.move(to: CGPoint(x: 6, y: 4))
            p.addLine(to: CGPoint(x: 17, y: 4))
            p.arco(17, 6, 2, 270, 360)
            p.addLine(to: CGPoint(x: 19, y: 18))
            p.arco(17, 18, 2, 0, 90)
            p.addLine(to: CGPoint(x: 6, y: 20))
            p.arco(6, 19, 1, 90, 180)
            p.addLine(to: CGPoint(x: 5, y: 5))
            p.arco(6, 5, 1, 180, 270)
            // El lomo.
            p.move(to: CGPoint(x: 9, y: 4))
            p.addLine(to: CGPoint(x: 9, y: 20))
            // Dos renglones.
            p.move(to: CGPoint(x: 13, y: 8))
            p.addLine(to: CGPoint(x: 15, y: 8))
            p.move(to: CGPoint(x: 13, y: 12))
            p.addLine(to: CGPoint(x: 15, y: 12))
        case .carpeta:
            // La pestaña de arriba y el cuerpo, de una sola vez.
            p.move(to: CGPoint(x: 5, y: 4))
            p.addLine(to: CGPoint(x: 9, y: 4))
            p.addLine(to: CGPoint(x: 12, y: 7))
            p.addLine(to: CGPoint(x: 19, y: 7))
            p.arco(19, 9, 2, 270, 360)
            p.addLine(to: CGPoint(x: 21, y: 17))
            p.arco(19, 17, 2, 0, 90)
            p.addLine(to: CGPoint(x: 5, y: 19))
            p.arco(5, 17, 2, 90, 180)
            p.addLine(to: CGPoint(x: 3, y: 6))
            p.arco(5, 6, 2, 180, 270)
            p.closeSubpath()
        }
        let u = min(r.width, r.height) / 24
        return p.applying(CGAffineTransform(translationX: r.midX - 12 * u, y: r.midY - 12 * u)
            .scaledBy(x: u, y: u))
    }
}

private extension Path {
    /// Un arco de `desde` a `hasta`, en grados de pantalla (y hacia abajo):
    /// si `hasta` es mayor, gira como las agujas del reloj.
    mutating func arco(_ cx: CGFloat, _ cy: CGFloat, _ radio: CGFloat, _ desde: Double, _ hasta: Double) {
        addArc(center: CGPoint(x: cx, y: cy), radius: radio,
               startAngle: .degrees(desde), endAngle: .degrees(hasta), clockwise: hasta < desde)
    }
}
