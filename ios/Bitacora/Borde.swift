import SwiftUI

/// El borde de pantalla.
///
/// La luz vive en los cuatro bordes del teléfono, como Siri: un resplandor azul
/// que crece cuando alguien habla —Bitácora o vos— y afloja cuando para. Quieta, un
/// filo apenas encendido. La conversación queda entera y sin nada encima; abajo
/// sólo la etiqueta, para tocar, que es la que dice quién está hablando.
///
/// Es la opción A de las cinco que se compararon el 06/09, y la que más se
/// parece a lo que hace el sistema hoy. Se dibuja a pantalla completa, por
/// debajo de la barra de pestañas, para que el borde sea el del teléfono y no
/// el de la vista.
///
/// Un solo color y poco rango. Hubo una versión con dorado para Bitácora y un trazo
/// que iba de 3 a 15 puntos latiendo palabra por palabra: "luces de fiesta".
struct Borde: View {
    let modo: ModoDeVoz
    var nivel: Double = 0
    var ultimaPalabra: Date? = nil

    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var seguidor = SenalDeVoz.Seguidor()

    var body: some View {
        TimelineView(.animation(paused: sinMovimiento)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let cruda = SenalDeVoz.energia(modo: modo, nivel: nivel, ultimaPalabra: ultimaPalabra,
                                           ahora: ctx.date, t: t, sinMovimiento: sinMovimiento)
            // Con "reducir movimiento" el TimelineView está pausado y su
            // reloj no avanza: el seguidor vería siempre dt = 0 y se quedaría
            // clavado en el primer cuadro, sin reaccionar a nada. Sin
            // movimiento va la cruda, que ya es un valor fijo por estado.
            let e = sinMovimiento ? cruda : seguidor.seguir(cruda, en: ctx.date)
            let color = SenalDeVoz.color
            // Al cuadrado, para hundir el reposo.
            //
            // El borde vive en un rango angosto —0.25 callado, 0.5 a 0.7 con
            // alguien hablando— y antes la diferencia entre esos dos extremos
            // era de tres niveles de brillo sobre 255, medido en video del
            // simulador: nada. Ahora son diez.
            //
            // De esos diez, la mayor parte la puso bajar el piso de las
            // opacidades, no la curva: el cuadrado por sí solo ACHICA la
            // distancia entre los dos estados, porque comprime todo lo que está
            // abajo de uno. Lo que aporta es justamente eso, que el reposo casi
            // desaparezca, que era la otra mitad de lo que Dusan venía pidiendo
            // desde "la luz es muy invasiva". Y no acelera nada: lo lento lo
            // hace el seguidor, y una curva sobre una señal lenta sigue siendo
            // lenta.
            let p = e * e
            Canvas { g, size in
                // El radio sigue al de la pantalla del iPhone; como va
                // desenfocado, no hace falta que sea exacto.
                let r: CGFloat = 58
                let marco = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
                let camino = Path(roundedRect: marco, cornerRadius: r, style: .continuous)

                // El resplandor: difuso, crece con la voz. Fino a propósito:
                // la primera versión llegaba a 34 puntos hablando y se metía
                // sobre los globos. "Muy invasiva", dijo Dusan en el teléfono.
                g.drawLayer { capa in
                    capa.addFilter(.blur(radius: 7 + 14 * p))
                    capa.stroke(camino, with: .color(color.opacity(0.14 + 0.85 * p)),
                                lineWidth: 2 + 12 * p)
                }
                // El filo: fino y nítido, para que el borde tenga un borde.
                g.stroke(camino, with: .color(color.opacity(0.20 + 0.75 * p)),
                         lineWidth: 1 + 1.8 * p)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
