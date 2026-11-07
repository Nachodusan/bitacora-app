import AVFoundation

/// Reproduce audio que todavía está llegando.
///
/// `AVAudioPlayer`, que es lo que usa el resto de `VozDeBitacora`, necesita el
/// archivo entero antes de sonar. Con la voz en vivo no hay archivo: llegan
/// muestras de a pedazos, y lo que se busca es justamente empezar con el
/// primero. Acá cada pedazo se encola en un nodo de `AVAudioEngine` y suena
/// pegado al anterior.
///
/// Si la red se atrasa y la cola se vacía, no pasa nada grave: hay silencio
/// hasta que llega el pedazo siguiente y sigue desde ahí. Medido contra el
/// servidor, el audio llega unas tres veces más rápido de lo que se escucha,
/// así que en la práctica la cola va siempre adelantada.
///
/// Tiene su propio motor, aparte del de `CapturaDeVoz`. Es a propósito: aquél
/// tiene encendido el procesamiento de voz para cancelar el eco, y enchufarle
/// la reproducción cambiaría cómo se comporta el micrófono. Así queda igual que
/// con `AVAudioPlayer`, que también suena por fuera.
final class Altavoz: @unchecked Sendable {
    private let motor = AVAudioEngine()
    private let nodo = AVAudioPlayerNode()
    private let formato: AVAudioFormat
    private let hz: Double

    /// El byte suelto de una muestra que llegó partida entre dos pedazos.
    private var suelto: UInt8?
    /// Cuántos segundos de audio se encolaron, y desde cuándo suenan.
    private var encolado: Double = 0
    private var desde: Date?

    private let candado = NSLock()
    private var ultimoNivel: Double = 0

    /// `nil` si el motor no arranca. Ahí Bitácora habla con la voz de iOS.
    init?(hz: Int) {
        guard hz > 0, let f = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: Double(hz), channels: 1,
                                            interleaved: false) else { return nil }
        formato = f
        self.hz = Double(hz)

        motor.attach(nodo)
        motor.connect(nodo, to: motor.mainMixerNode, format: f)
        let mezcla = motor.mainMixerNode
        mezcla.installTap(onBus: 0, bufferSize: 1024,
                          format: mezcla.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.medir(buffer)
        }
        do { try motor.start() } catch {
            mezcla.removeTap(onBus: 0)
            return nil
        }
        nodo.play()
    }

    /// Encola un pedazo: muestras de 16 bits, mono, little-endian.
    func agregar(_ datos: Data) {
        var bytes = datos
        if let s = suelto { bytes.insert(s, at: bytes.startIndex); suelto = nil }
        if bytes.count % 2 == 1 { suelto = bytes.removeLast() }
        let n = bytes.count / 2
        guard n > 0, let buffer = AVAudioPCMBuffer(pcmFormat: formato,
                                                   frameCapacity: AVAudioFrameCount(n)),
              let canal = buffer.floatChannelData?[0] else { return }

        bytes.withUnsafeBytes { crudo in
            for i in 0..<n {
                let m = Int16(littleEndian: crudo.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
                canal[i] = Float(m) / 32768
            }
        }
        buffer.frameLength = AVAudioFrameCount(n)
        nodo.scheduleBuffer(buffer, completionHandler: nil)

        if desde == nil { desde = Date() }
        encolado += Double(n) / hz
    }

    /// Avisa cuando terminó de SONAR todo lo encolado hasta ahora.
    ///
    /// Va con un pedacito de silencio al final de la cola, y el aviso es el de
    /// "ya se escuchó", no el de "ya se procesó": con el otro, Bitácora daría el
    /// turno por terminado con medio segundo de voz todavía por salir.
    func alVaciarse(_ aviso: @escaping @Sendable () -> Void) {
        let n = AVAudioFrameCount(hz / 100)
        guard let silencio = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: n) else {
            aviso()
            return
        }
        silencio.frameLength = n
        if let canal = silencio.floatChannelData?[0] {
            for i in 0..<Int(n) { canal[i] = 0 }
        }
        nodo.scheduleBuffer(silencio, completionCallbackType: .dataPlayedBack) { _ in aviso() }
    }

    /// Cuánto falta para que termine de sonar lo encolado, a ojo.
    var porSonar: Double {
        guard let desde else { return 0 }
        return max(0, encolado - Date().timeIntervalSince(desde))
    }

    /// Cuánto suena ahora, 0…1, con la misma escala que el medidor de
    /// `AVAudioPlayer`: -45 dB es el piso y 0 dB el techo.
    var nivel: Double {
        candado.lock(); defer { candado.unlock() }
        return ultimoNivel
    }

    func parar() {
        motor.mainMixerNode.removeTap(onBus: 0)
        nodo.stop()
        motor.stop()
    }

    private func medir(_ buffer: AVAudioPCMBuffer) {
        guard let canal = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var suma: Float = 0
        for i in 0..<Int(buffer.frameLength) { suma += canal[i] * canal[i] }
        let rms = (suma / Float(buffer.frameLength)).squareRoot()
        let db = 20 * log10(Double(max(rms, 1e-7)))
        let n = max(0, min(1, (db + 45) / 45))
        candado.lock(); ultimoNivel = n; candado.unlock()
    }
}
