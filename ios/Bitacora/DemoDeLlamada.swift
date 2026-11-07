#if DEBUG && targetEnvironment(simulator)
import Foundation
import Observation

/// Una llamada de demostración, para grabar el video de presentación.
///
/// El simulador no tiene el reconocedor de español que corre en el teléfono,
/// así que ahí una llamada no puede escuchar. Con `bitacora.demo_llamada` en
/// las preferencias —una lista de frases «texto|segundos»—, abrir la llamada
/// hace que esas frases entren como si se dijeran: palabra por palabra, en ese
/// tiempo. Todo lo demás es la llamada de verdad: el turno en vivo, la voz del
/// servidor y la luz.
///
/// El simulador tampoco graba el sonido, así que lo que dice Bitácora queda en
/// `Documents/demo-llamada.wav`, con un `.json` al lado que dice en qué instante
/// empezó a sonar, para montarlo después sobre la imagen.
///
/// No existe fuera del simulador ni en una versión que no sea de prueba.
@Observable
@MainActor
final class DemoDeLlamada {
    static let shared = DemoDeLlamada()

    private(set) var enCurso = false
    /// Lo que se ve en el globo mientras «habla» la persona.
    var parcial = ""

    private var frases: [(texto: String, segundos: Double)] = []

    @ObservationIgnored private var muestras = Data()
    @ObservationIgnored private var hz = 24_000
    @ObservationIgnored private var inicio: Date?
    @ObservationIgnored private var finPrevisto: Date?

    /// Lee el guion de las preferencias. `false` si no hay: la llamada de siempre.
    func preparar() -> Bool {
        guard let guion = UserDefaults.standard.stringArray(forKey: "bitacora.demo_llamada"),
              !guion.isEmpty else { return false }
        frases = guion.map { linea in
            let partes = linea.split(separator: "|", maxSplits: 1).map(String.init)
            return (partes[0], partes.count > 1 ? Double(partes[1]) ?? 3 : 3)
        }
        enCurso = true
        parcial = ""
        muestras = Data()
        inicio = nil
        finPrevisto = nil
        return true
    }

    func siguiente() -> (texto: String, segundos: Double)? {
        frases.isEmpty ? nil : frases.removeFirst()
    }

    /// Escribe la frase palabra por palabra, repartida en sus segundos, como
    /// la va escribiendo el reconocedor mientras alguien habla.
    func decir(_ frase: (texto: String, segundos: Double)) async {
        let palabras = frase.texto.split(separator: " ").map(String.init)
        let paso = frase.segundos / Double(max(palabras.count, 1))
        for i in palabras.indices {
            try? await Task.sleep(for: .seconds(paso))
            parcial = palabras[...i].joined(separator: " ")
        }
        // La pausa con la que se da por terminado un turno.
        try? await Task.sleep(for: .seconds(1.3))
    }

    /// Anota un pedazo de la voz de Bitácora en el momento en que va a sonar.
    ///
    /// El altavoz encola los pedazos uno detrás de otro: el que llega mientras
    /// suena el anterior empieza cuando ése termina; el que llega tarde, cuando
    /// llega. Entre medio va silencio, así el archivo dura lo que duró de verdad.
    func registrar(_ pcm: Data, hz nuevo: Int) {
        hz = nuevo
        let ahora = Date()
        let empieza = max(ahora, finPrevisto ?? ahora)
        if inicio == nil { inicio = empieza }
        let desde = Int(empieza.timeIntervalSince(inicio!) * Double(hz)) * 2
        if desde > muestras.count { muestras.append(Data(count: desde - muestras.count)) }
        muestras.append(pcm)
        finPrevisto = empieza.addingTimeInterval(Double(pcm.count / 2) / Double(hz))
    }

    /// Guarda lo que sonó hasta ahora.
    func guardarAudio() {
        guard let inicio, !muestras.isEmpty else { return }
        var wav = Data()
        func agregar<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); agregar(UInt32(36 + muestras.count))
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); agregar(UInt32(16)); agregar(UInt16(1)); agregar(UInt16(1))
        agregar(UInt32(hz)); agregar(UInt32(hz * 2)); agregar(UInt16(2)); agregar(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); agregar(UInt32(muestras.count))
        wav.append(muestras)
        let carpeta = URL.documentsDirectory
        try? wav.write(to: carpeta.appending(path: "demo-llamada.wav"))
        let datos = ["inicio": inicio.timeIntervalSince1970, "hz": Double(hz)]
        try? JSONSerialization.data(withJSONObject: datos).write(to: carpeta.appending(path: "demo-llamada.json"))
    }

    func terminar() {
        guardarAudio()
        enCurso = false
        parcial = ""
    }
}
#endif
