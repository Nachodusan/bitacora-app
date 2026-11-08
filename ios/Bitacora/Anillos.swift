import SwiftUI

/// La marca de Bitácora: un punto durazno con anillos ondulados alrededor, como
/// curvas de nivel. Dusan la eligió de dos imágenes el 26/10/2026.
///
/// DOS ESTADOS. Sin `modo` (el inicio, nadie hablando) los anillos van parejos
/// y casi redondos, y respiran despacio. Con un `modo` (la llamada) se
/// desordenan: cada anillo toma su propia forma, con ondas más cerradas que
/// giran a destiempo, así que se cruzan entre sí y la figura nunca se repite.
/// Cuánto se desordenan sale de la misma energía que dibuja el borde
/// (`SenalDeVoz.energia`): más cuando alguien habla, menos en el silencio.
///
/// HABLA CON LA VOZ (26/10/2026). Encima de eso, un pulso rápido sigue el audio
/// sílaba por sílaba —la voz de Bitácora mientras habla, tu micrófono mientras
/// te escucha— y empuja los anillos hacia afuera en ondas: cada anillo recibe
/// el pulso un poco después que el de adentro, así que la voz se ve salir del
/// punto como el sonido. En las pausas, los anillos vuelven en un instante.
///
/// Con «Reducir movimiento» queda quieta, en una forma fija.
struct Anillos: View {
    /// `nil` en el inicio. En la llamada, el estado de la voz.
    var modo: ModoDeVoz? = nil
    /// Nivel del audio, 0…1: el micrófono escuchando, la voz de Bitácora hablando.
    var nivel: Double = 0
    var ultimaPalabra: Date? = nil
    /// `nil`: ocupa lo que le den, y se redibuja a ese tamaño en cada cuadro.
    /// Es lo que usa el viaje del inicio a la llamada, para no estirarse como
    /// una imagen (se veía pixelado, 26/10/2026).
    var tamano: CGFloat? = 96
    /// Puntitos que giran sobre algunas líneas, uno por cada cosa que hay
    /// (26/10/2026): consultas del mes, charlas de hoy, notas. Sólo se ven con
    /// los anillos tranquilos; al desordenarse se apagan.
    var orbitas: [Color] = []
    /// Hacia dónde va el punto, -1…1 (27/10/2026): al deslizar hacia Escribir
    /// (arriba) o Hablar (abajo), el punto durazno se adelanta hacia ese lado.
    var tiron: Double = 0
    static let margen: CGFloat = 80

    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @Environment(\.colorScheme) private var esquema
    @State private var seguidor = SenalDeVoz.Seguidor(sube: 0.25, baja: 0.9)
    /// El paso de tranquila a desordenada, para que no cambie de golpe.
    /// El paso de tranquila a desordenada. Arranca SIEMPRE en tranquila: así,
    /// cuando los anillos bajan del inicio a la llamada, se ve la transformación
    /// en vez de aparecer ya revueltos (26/10/2026).
    @State private var desorden = Rampa(tau: 0.35)
    /// El pulso de la voz: sube y baja en décimas, para seguir cada sílaba.
    @State private var pulso = SenalDeVoz.Seguidor(sube: 0.04, baja: 0.12)
    @State private var historial = Historial()
    @State private var giro = Giro()

    /// Los colores son los de la marca (`Marca`). En modo claro el crema no se
    /// ve sobre el fondo: las líneas pasan a oliva oscuro. El punto queda durazno.
    private var linea: Color { esquema == .dark ? Marca.crema : Marca.oliva }

    var body: some View {
        TimelineView(.animation(paused: sinMovimiento)) { ctx in
            let t = sinMovimiento ? 0 : ctx.date.timeIntervalSinceReferenceDate
            let activa = modo != nil
            let cruda = activa
                ? SenalDeVoz.energia(modo: modo!, nivel: nivel, ultimaPalabra: ultimaPalabra,
                                     ahora: ctx.date, t: t, sinMovimiento: sinMovimiento)
                : 0
            let e = sinMovimiento ? cruda : seguidor.seguir(cruda, en: ctx.date)
            let d = sinMovimiento ? (activa ? 1 : 0) : desorden.seguir(activa ? 1 : 0, en: ctx.date)
            let p = sinMovimiento ? 0 : pulso.seguir(voz(en: ctx.date), en: ctx.date)
            let _ = historial.anotar(p, en: ctx.date)
            // La fase de las ondas revueltas se acumula cuadro a cuadro. Antes era
            // `t * velocidad`, con `t` el reloj absoluto (unos 800 millones de
            // segundos): cada vez que la voz cambiaba la velocidad, la fase
            // saltaba miles de vueltas y las líneas giraban a los tirones.
            let fase = sinMovimiento ? 0 : giro.avanzar(a: 0.35 + 0.15 * d + 0.15 * e, en: ctx.date)
            // El lienzo es más grande que la vista: al estirarse hacia Escribir
            // o Hablar los anillos salen de su cuadro y no se tienen que cortar.
            Canvas { g, lienzo in
                g.translateBy(x: Self.margen, y: Self.margen)
                let size = CGSize(width: lienzo.width - 2 * Self.margen, height: lienzo.height - 2 * Self.margen)
                dibujar(en: &g, size: size, t: t, fase: fase, desorden: d, energia: e, ahora: ctx.date)
                if !orbitas.isEmpty, d < 0.95 {
                    dibujarOrbitas(en: &g, size: size, t: t, desorden: d)
                }
            }
            .padding(-Self.margen)
        }
        .frame(width: tamano, height: tamano)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Cuánto suena en este instante, sin suavizar. Con la voz de iOS no hay
    /// amplitud: cada palabra da un golpe que se apaga en un cuarto de segundo.
    private func voz(en ahora: Date) -> Double {
        guard let modo, modo == .hablando || modo == .escuchando else { return 0 }
        if nivel > 0 { return max(0, min(1, (nivel - 0.15) / 0.75)) }
        guard modo == .hablando, let u = ultimaPalabra else { return 0 }
        return exp(-max(0, ahora.timeIntervalSince(u)) / 0.25)
    }

    /// Cada puntito va sobre su propia línea (la 3.ª, la 5.ª y la 7.ª), con la
    /// misma onda tranquila que esa línea, girando lento y a distinto ritmo.
    private func dibujarOrbitas(en g: inout GraphicsContext, size: CGSize, t: Double, desorden d: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let radioMax = min(size.width, size.height) / 2 * (0.86 - 0.10 * d)
        let radioMin = radioMax * 0.26
        let cantidad = 7
        let respiro = 1 + 0.025 * sin(t * 0.9)
        let lineas = [2, 4, 6]
        let velocidades = [0.22, -0.15, 0.11]
        for (j, color) in orbitas.prefix(3).enumerated() {
            let i = lineas[j]
            let f = Double(i) / Double(cantidad - 1)
            let fi = Double(i)
            let r = (radioMin + (radioMax - radioMin) * f) * respiro
            let a = t * velocidades[j] + Double(j) * 2.1
            let onda = sin(3 * a + t * 0.18 + fi * 0.5) * 0.045 + sin(2 * a - t * 0.11 + 1.3) * 0.03
            // Siguen en su línea aunque el anillo se estire (`dibujar`, el tirón).
            let tir = max(-1, min(1, tiron))
            let temblor = 1 + 0.012 * abs(tir) * sin(t * 11 + fi * 1.3)
            let cy = c.y + CGFloat(tir * (1 - 0.75 * f)) * radioMax * 0.5
            let estiron = 1 + 0.18 * abs(tir) * max(0, sin(a) * (tir >= 0 ? 1 : -1)) * (0.4 + 0.6 * f)
            let rr = r * (1 + onda * (0.75 + 0.35 * f)) * estiron * temblor
            let p = CGPoint(x: c.x + rr * cos(a), y: cy + rr * sin(a))
            let pr = max(2.2, min(size.width, size.height) * 0.024)
            g.fill(Path(ellipseIn: CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)),
                   with: .color(color.opacity(1 - d)))
        }
    }

    private func dibujar(en g: inout GraphicsContext, size: CGSize, t: Double, fase: Double, desorden d: Double,
                         energia e: Double, ahora: Date) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        // Desordenada necesita más margen: las ondas salen más.
        let radioMax = min(size.width, size.height) / 2 * (0.86 - 0.10 * d)
        let radioMin = radioMax * 0.26
        let cantidad = 7
        // El respiro: todos los anillos se abren y cierran juntos.
        let respiro = 1 + 0.025 * sin(t * 0.9) + 0.05 * e

        for i in 0..<cantidad {
            let f = Double(i) / Double(cantidad - 1)
            let fi = Double(i)
            // El pulso que le llega a este anillo: el de hace un rato, más
            // tarde cuanto más afuera.
            let pi = historial.valor(hace: fi * 0.055, desde: ahora)
            let r = (radioMin + (radioMax - radioMin) * f) * respiro * (1 + 0.10 * pi * (1 - 0.4 * f))
            // El tirón (27/10/2026): el sistema entero se deja llevar hacia la
            // opción, pero resistiéndose. Los anillos de adentro se corren más
            // que los de afuera, el lado que mira hacia allá se estira, y todo
            // tiembla apenas, como algo que quiere volver al centro.
            let tir = max(-1, min(1, tiron))
            let temblor = 1 + 0.012 * abs(tir) * sin(t * 11 + fi * 1.3)
            let cy = c.y + CGFloat(tir * (1 - 0.75 * f)) * radioMax * 0.5
            var camino = Path()
            let pasos = 120
            for k in 0...pasos {
                let a = Double(k) / Double(pasos) * 2 * .pi
                // Tranquila: dos ondas suaves, casi iguales en todos los anillos.
                let calma = sin(3 * a + t * 0.18 + fi * 0.5) * 0.045
                          + sin(2 * a - t * 0.11 + 1.3) * 0.03
                // Desordenada: ondas más cerradas, con fase y sentido propios por
                // anillo, para que se crucen.
                let lado = i % 2 == 0 ? 1.0 : -1.0
                let caos = sin(4 * a + lado * fase + fi * 1.7) * 0.07
                         + sin(5 * a - fase * 0.74 + fi * 2.3) * 0.05
                         + sin(7 * a + fase * 1.22 + fi * 0.9) * 0.025
                // En silencio el desorden baja a la mitad; la voz lo sube.
                let onda = calma * (1 - d) + caos * d * (0.45 + 0.9 * pi)
                let estiron = 1 + 0.18 * abs(tir) * max(0, sin(a) * (tir >= 0 ? 1 : -1)) * (0.4 + 0.6 * f)
                let rr = r * (1 + onda * (0.75 + 0.35 * f)) * estiron * temblor
                let p = CGPoint(x: c.x + rr * cos(a), y: cy + rr * sin(a))
                if k == 0 { camino.move(to: p) } else { camino.addLine(to: p) }
            }
            camino.closeSubpath()
            // Más tenues hacia afuera, y un poco más vivas con la voz.
            let opacidad = min(1, (0.85 - 0.25 * f) * (0.8 + 0.45 * pi))
            g.stroke(camino, with: .color(linea.opacity(opacidad)), lineWidth: 1)
        }

        let p0 = historial.valor(hace: 0, desde: ahora)
        let pr = radioMin * 0.55 * (1 + 0.05 * sin(t * 0.9 + 0.6) + 0.35 * p0)
        let cy = c.y + CGFloat(max(-1, min(1, tiron))) * radioMax * 0.75
        let punto = Path(ellipseIn: CGRect(x: c.x - pr, y: cy - pr, width: pr * 2, height: pr * 2))
        g.fill(punto, with: .color(Marca.durazno))
    }
}

/// Lo que valió el pulso en el último medio segundo, para que cada anillo lo
/// reciba con su demora. Clase y no struct por lo mismo que `Seguidor`: la
/// muta el cuadro mientras se dibuja.
/// Va de 0 hacia el objetivo, suave, sin saltar en el primer cuadro (a
/// diferencia de `SenalDeVoz.Seguidor`, que arranca donde está el objetivo).
final class Rampa {
    private var valor = 0.0
    private var ultimo: Date?
    let tau: Double

    init(tau: Double) { self.tau = tau }

    func seguir(_ objetivo: Double, en ahora: Date) -> Double {
        let dt = ultimo.map { min(0.1, max(0, ahora.timeIntervalSince($0))) } ?? 0
        ultimo = ahora
        valor = objetivo + (valor - objetivo) * exp(-dt / tau)
        return valor
    }
}

/// Un ángulo que avanza a la velocidad que se le pida en cada cuadro, sin saltar
/// cuando la velocidad cambia.
final class Giro {
    private var fase = 0.0
    private var ultimo: Date?

    func avanzar(a velocidad: Double, en ahora: Date) -> Double {
        if let u = ultimo { fase += min(0.1, max(0, ahora.timeIntervalSince(u))) * velocidad }
        ultimo = ahora
        return fase
    }
}

final class Historial {
    private var muestras: [(Date, Double)] = []

    func anotar(_ v: Double, en ahora: Date) {
        muestras.append((ahora, v))
        muestras.removeAll { ahora.timeIntervalSince($0.0) > 0.6 }
    }

    /// El valor más cercano a `hace` segundos atrás; el más viejo si no llega.
    func valor(hace: Double, desde ahora: Date) -> Double {
        let objetivo = ahora.addingTimeInterval(-hace)
        return muestras.last(where: { $0.0 <= objetivo })?.1 ?? muestras.first?.1 ?? 0
    }
}

#Preview {
    VStack(spacing: 40) {
        Anillos()
        Anillos(modo: .escuchando, nivel: 0.5, tamano: 160)
    }
    .padding(40)
    .background(Color(red: 0.07, green: 0.08, blue: 0.05))
}
