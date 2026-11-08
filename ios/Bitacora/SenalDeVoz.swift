import SwiftUI

/// En qué está la charla, visto desde la luz.
enum ModoDeVoz { case quieta, escuchando, pensando, hablando }

/// Cuánto "está pasando", 0…1, a partir del audio real.
///
/// Es la única regla, compartida por todas las formas de mostrarlo (el
/// horizonte, el borde de pantalla): cada una dibuja distinto la misma energía.
/// Así cambiar de forma no cambia lo que se está mostrando.
///
/// Son dos pasos, y los dos importan:
///
///   1. `energia` es la señal CRUDA, sin memoria: qué está pasando en este
///      instante. Escuchando, el nivel del micrófono; hablando, un empujón por
///      palabra sobre una respiración lenta; pensando y quieta, respirar.
///   2. `Seguidor` la sigue con inercia, como la aguja de un medidor de audio:
///      sube en tres décimas, baja en un segundo. Lo que se dibuja es esto,
///      nunca la cruda — salvo con "reducir movimiento", que congela el reloj
///      del `TimelineView` y dejaría al seguidor sin avanzar.
///
/// El seguidor existe porque la primera versión dibujaba la cruda directo, y
/// parecía luces de fiesta —dijo Dusan—: hablando, un pico por palabra que
/// decaía en un cuarto de segundo era un destello cada 300 ms; escuchando, el
/// micrófono cuadro a cuadro son treinta cambios de sentido por segundo.
/// Simulados veinte segundos de cada estado a 120 cuadros por segundo, contando
/// como cambio de sentido sólo los que mueven más de 0.02 —abajo de eso no se
/// ve—: hablando pasó de 6.7 por segundo a 1.2, y escuchando de 16.2 a 1.0. La
/// velocidad, que es lo que de verdad se percibe, baja diez veces en los dos. La
/// franja se angosta pero no se apaga: hablando queda entre 0.48 y 0.67 en vez
/// de 0.29 a 0.72. Lo que sobrevive de cada palabra adentro de una frase es un
/// rizado de 0.07, un tercio del que había. Eso ya no es una fiesta: es una luz
/// que crece cuando alguien habla y afloja cuando para.
///
/// Las respiraciones van a siete, ocho, nueve y diez segundos por ciclo, que es
/// el ritmo de respirar despacio. Antes iban a tres.
enum SenalDeVoz {
    static func energia(modo: ModoDeVoz, nivel: Double, ultimaPalabra: Date?,
                        ahora: Date, t: Double, sinMovimiento: Bool) -> Double {
        // "Reducir movimiento" se contesta acá y de una sola vez, antes que
        // nada. Antes cada estado lo resolvía por su cuenta y escuchando se
        // olvidaba: el piso era fijo pero el nivel del micrófono seguía
        // entrando, y como el `TimelineView` pausado igual se redibuja cuando
        // cambia el nivel, la luz saltaba con cada sílaba. Medido en píxeles,
        // ocho cambios de sentido por segundo contra uno del camino normal:
        // justo al que pide menos movimiento le quedaba la luz de fiesta.
        //
        // Los cuatro valores no son redondos porque no son a ojo: son lo que
        // muestra en promedio el camino normal en cada estado, así que quien
        // tiene la opción prendida ve la misma escalera de brillo, quieta.
        if sinMovimiento {
            switch modo {
            case .quieta: return 0.25
            case .pensando: return 0.30
            case .escuchando, .hablando: return 0.57
            }
        }

        switch modo {
        case .quieta:
            return 0.20 + 0.10 * respiracion(t, periodo: 10)
        case .escuchando:
            // Piso con respiración, no cero: entre frase y frase la luz afloja,
            // no se apaga. Apagarse y prenderse es lo que parecía fiesta.
            let piso = 0.18 + 0.06 * respiracion(t, periodo: 9)
            return conVoz(piso: piso, nivel: nivel)
        case .pensando:
            return 0.18 + 0.24 * respiracion(t, periodo: 7)
        case .hablando:
            let fondo = 0.22 + 0.10 * respiracion(t, periodo: 8)
            // Con la voz del servidor hay amplitud de verdad, medida del audio
            // que está sonando, así que la luz sigue a Bitácora igual que te sigue
            // a vos cuando te escucha. Con la voz de iOS esto es cero —no
            // expone amplitud— y se cae al empujón por palabra de abajo, que es
            // todo lo que da el sintetizador.
            if nivel > 0 { return conVoz(piso: fondo, nivel: nivel) }
            guard let u = ultimaPalabra else { return fondo }
            // Cada palabra empuja un poco y se disipa en medio segundo. El
            // sintetizador no da amplitud, pero avisa cada palabra, y sumadas
            // con el seguidor dan una meseta que baja en las pausas.
            //
            // El `max(0,)` no es de adorno: si el reloj del TimelineView se
            // queda atrás de la palabra, el intervalo es negativo, exp() de un
            // positivo se va por arriba de 1 y la luz salta a tope.
            let empujon = exp(-max(0, ahora.timeIntervalSince(u)) / 0.5)
            return min(1, fondo + 0.40 * empujon)
        }
    }

    /// Cuánta luz para una voz que está sonando, sin que llegue nunca al tope.
    ///
    /// Es una rodilla blanda y no una multiplicación. Antes escuchando hacía
    /// `min(1, max(piso, nivel * 1.3))` sobre un nivel que `CapturaDeVoz` ya
    /// recorta en 1: una voz normal lo dejaba clavado arriba, así que tu propia
    /// voz encendía la pantalla entera —el borde llegaba cuarenta puntos hacia
    /// adentro— y Bitácora, que se mide de otra forma, quedaba mucho más apagada.
    /// Dos personas hablando en la misma charla no pueden dar dos luces
    /// distintas.
    ///
    /// El techo de 0.72 es la franja en la que ya se movía Bitácora, que es la que
    /// tiene calibrada la curva del borde.
    private static func conVoz(piso: Double, nivel: Double) -> Double {
        let n = max(0, min(1, nivel))
        return piso + (0.72 - piso) * n
    }

    /// 0…1, un seno lento. `periodo` en segundos por ciclo completo.
    private static func respiracion(_ t: Double, periodo: Double) -> Double {
        (sin(t * 2 * .pi / periodo) + 1) / 2
    }

    /// El color de la luz. Uno solo, siempre: el azul de la persona.
    ///
    /// Hubo un dorado para cuando hablaba Bitácora. Que la luz cambiara de color
    /// según quién hablaba era parte del efecto fiesta; Dusan pidió que quede
    /// azul, y que quién habla lo diga el texto de la barra.
    ///
    /// Es `vosClaro` y no `vos` por dos motivos que sí se sostienen: es el azul
    /// que la luz ya mostraba cuando hablaba él —o sea, el que pidió— y en modo
    /// oscuro, que es el caso principal de esta app, rinde un veinte por ciento
    /// más de brillo sobre el fondo.
    ///
    /// PENDIENTE: en modo claro ninguno de los dos azules es luz. Los dos quedan
    /// más oscuros que el fondo, así que el borde es una sombra que crece cuando
    /// alguien habla. Se lee igual, pero no es lo que dice el nombre. Para
    /// arreglarlo de verdad habría que aclarar el color con el fondo claro, o
    /// dibujar con otro modo de composición.
    static let color = Paleta.vosClaro

    /// La inercia. Una instancia por forma, guardada en `@State` para que viva
    /// lo que vive la vista; se llama una vez por cuadro con la señal cruda y
    /// devuelve lo que hay que dibujar.
    ///
    /// Es una clase y no un struct a propósito: la muta el cuadro de un
    /// `TimelineView` mientras se dibuja, y SwiftUI no la observa. Si fuera
    /// `@State var valor: Double`, cada cuadro invalidaría la vista que lo
    /// está produciendo.
    final class Seguidor {
        private var valor: Double?
        private var ultimo: Date?
        /// Segundos para recorrer el 63% del camino hacia arriba y hacia abajo.
        let sube: Double
        let baja: Double

        init(sube: Double = 0.30, baja: Double = 1.0) {
            self.sube = sube
            self.baja = baja
        }

        func seguir(_ objetivo: Double, en ahora: Date) -> Double {
            guard let v = valor, let u = ultimo else {
                // El primer cuadro arranca donde está el objetivo: sin rampa
                // desde cero al aparecer.
                valor = objetivo
                ultimo = ahora
                return objetivo
            }
            let dt = max(0, ahora.timeIntervalSince(u))
            ultimo = ahora
            let tau = objetivo > v ? sube : baja
            let nuevo = v + (objetivo - v) * (1 - exp(-dt / tau))
            valor = nuevo
            return nuevo
        }
    }
}
