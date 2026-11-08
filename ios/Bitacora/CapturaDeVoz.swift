import AVFoundation
import Speech
import SwiftUI

/// Captura de voz on-device, en modo conversación.
///
/// Tres cosas que no son obvias y que definen este archivo:
///
/// 1. `SFSpeechRecognitionTask` se termina sola. Después de un rato de audio (o
///    de un silencio largo) el reconocedor da el resultado por final y cierra la
///    tarea. Por eso el texto se acumula y, si seguís en la conversación, se
///    abre una tarea nueva sin parar el motor de audio.
///
/// 2. Si el reconocimiento on-device no está disponible, esto NO cae al de
///    servidor. Caer sería mandar tu audio a Apple, que es lo que la regla de
///    privacidad prohíbe. Falla y te dice por qué.
///
/// 3. Mientras Bitácora habla, esto se apaga entero. Es la forma barata de no
///    transcribir su propia voz: en vez de pelear con la cancelación de eco,
///    no se escucha y listo.
@Observable
@MainActor
final class CapturaDeVoz {

    enum Estado: Equatable {
        case inactivo
        case escuchando
        case noDisponible(String)
    }

    private(set) var estado: Estado = .inactivo
    private(set) var textoParcial = ""
    /// 0…1, para la animación del orbe. Suavizado, si no titila.
    private(set) var nivel: Double = 0

    /// Se llama cuando dejaste de hablar por un rato: es el fin de tu turno.
    var alTerminarTurno: ((String) -> Void)?

    // Cuánto silencio hace falta para dar tu turno por terminado lo decide
    // `FinDeTurno`, en el core, según cómo quedó la frase. Estuvo acá, con dos
    // tiempos más cortos (1,6 y 0,9 segundos), y Dusan se quedaba sin terminar
    // lo que quería decir.

    var estaEscuchando: Bool { estado == .escuchando }

    /// Tu turno ya se cerró, pero se sigue transcribiendo por si no habías
    /// terminado. Ver `quedarAtenta`.
    private var atenta = false
    private var alRetomar: (() -> Void)?
    /// Cambia cada vez que se abre o se cancela una tarea de reconocimiento.
    ///
    /// Una tarea cancelada todavía puede entregar un resultado tarde, con el
    /// texto del turno que ya se cerró. Mientras se dejaba de escuchar entre un
    /// turno y otro eso no importaba; ahora que se sigue atenta, ese resultado
    /// viejo se leería como «seguís hablando». Con esto, lo que llega de una
    /// tarea que ya no es la actual se descarta.
    private var generacion = 0

    private let motor = AVAudioEngine()
    private var reconocedor: SFSpeechRecognizer?
    private var pedido: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private var ultimoCambio = Date()
    private var vigilante: Task<Void, Never>?

    static func reconocedorEspanol() -> SFSpeechRecognizer? {
        let soportados = SFSpeechRecognizer.supportedLocales().map(\.identifier)
        let preferidos = ["es-AR", "es-419", "es-MX", "es-US", "es-ES"]
        let elegido = preferidos.first { soportados.contains($0) }
            ?? soportados.first { $0.hasPrefix("es") }
        guard let elegido else { return nil }
        return SFSpeechRecognizer(locale: Locale(identifier: elegido))
    }

    // MARK: - Permisos

    func pedirPermisos() async -> Bool {
        let habla = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard habla == .authorized else {
            estado = .noDisponible("Falta permiso de reconocimiento de voz. Ajustes › Bitácora.")
            return false
        }
        let micro = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micro else {
            estado = .noDisponible("Falta permiso de micrófono. Ajustes › Bitácora.")
            return false
        }
        return true
    }

    // MARK: - Escuchar

    func escuchar() async {
        guard !estaEscuchando else { return }
        guard await pedirPermisos() else { return }

        guard let r = Self.reconocedorEspanol(), r.isAvailable else {
            estado = .noDisponible("No hay reconocedor de voz en español disponible.")
            return
        }
        guard r.supportsOnDeviceRecognition else {
            estado = .noDisponible(
                "El reconocimiento en el dispositivo no está disponible para este idioma. "
                + "Descárgalo en Ajustes › General › Teclado › Dictado. "
                + "No se usa el reconocimiento por internet: el audio no sale del teléfono.")
            return
        }
        reconocedor = r

        guard arrancarMotor() else { return }

        // Si venía atenta, eso se termina acá: ahora se escucha de verdad.
        atenta = false
        alRetomar = nil
        tarea?.cancel()
        tarea = nil
        textoParcial = ""
        ultimoCambio = Date()
        estado = .escuchando
        abrirTarea()
        vigilarSilencio()
    }

    /// Abre el micrófono. Idempotente: si ya estaba abierto, no lo reinicia.
    ///
    /// Que sea idempotente importa: el motor queda corriendo toda la charla —
    /// mientras Bitácora piensa y mientras habla— para poder cortarla hablándole
    /// encima. Reiniciarlo en cada turno metería medio segundo de arranque justo
    /// donde se está tratando de ganar tiempo.
    private func arrancarMotor() -> Bool {
        if motor.isRunning { return true }
        do {
            let sesion = AVAudioSession.sharedInstance()
            // playAndRecord porque en la misma sesión Bitácora también habla.
            try sesion.setCategory(.playAndRecord, mode: .voiceChat,
                                   options: [.duckOthers, .defaultToSpeaker])
            try sesion.setActive(true, options: .notifyOthersOnDeactivation)

            let entrada = motor.inputNode
            // Cancelación de eco del sistema. Sin esto, el micrófono abierto
            // mientras Bitácora habla se escucha a Bitácora, y cortarla hablándole
            // encima sería imposible: se cortaría sola. Va ANTES de leer el
            // formato, porque activarla lo cambia.
            try? entrada.setVoiceProcessingEnabled(true)
            let formato = entrada.outputFormat(forBus: 0)
            entrada.removeTap(onBus: 0)
            entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] buffer, _ in
                self?.pedido?.append(buffer)
                let rms = Self.rms(buffer)
                Task { @MainActor [weak self] in self?.actualizarNivel(rms) }
            }
            motor.prepare()
            try motor.start()
            return true
        } catch {
            estado = .noDisponible("No se pudo abrir el micrófono: \(error.localizedDescription)")
            return false
        }
    }

    /// Deja de transcribir, pero NO suelta el micrófono.
    ///
    /// Es lo que corre cuando terminaste tu turno: nada de lo que suene de acá
    /// en adelante —Bitácora hablando, un ruido— tiene que entrar en la
    /// transcripción, pero el motor sigue abierto para que `vigilarInterrupcion`
    /// pueda saber si empezás a hablar de nuevo.
    ///
    /// El micrófono queda tomado durante toda la charla, entonces, y el punto
    /// naranja de iOS queda prendido. Es el precio de poder cortarla hablándole
    /// encima. Se suelta en `frenar()`, al cerrar.
    func pausarTranscripcion() {
        vigilante?.cancel()
        vigilante = nil
        generacion += 1
        tarea?.cancel()
        tarea = nil
        pedido = nil
        textoParcial = ""
        atenta = false
        alRetomar = nil
        estado = .inactivo
    }

    /// Tu turno se cerró y Bitácora está por contestar, pero todavía no suena nada:
    /// se sigue transcribiendo por si en realidad no habías terminado.
    ///
    /// POR QUÉ. El final de un turno se adivina por el silencio, y adivinar
    /// falla: una pausa para buscar la palabra se parece mucho a haber
    /// terminado. Antes, cuando fallaba, lo que decías después se perdía y Bitácora
    /// contestaba a media idea. Ahora, si seguís hablando, se avisa con
    /// `alRetomar` y esto vuelve a escuchar como si el turno nunca se hubiera
    /// cerrado: quien llama descarta la respuesta que venía en camino y junta
    /// las dos partes.
    ///
    /// SÓLO VALE MIENTRAS LAYA NO SUENA. Con su voz saliendo por el parlante, lo
    /// que entra por el micrófono puede tener eco suyo, y transcribir eso sería
    /// ponerte en la boca palabras de ella. En cuanto arranca su audio hay que
    /// llamar a `pausarTranscripcion`, y de ahí en más se mira sólo el nivel
    /// (`vigilarInterrupcion`).
    ///
    /// Se abre una tarea de reconocimiento NUEVA: la anterior ya entregó tu
    /// turno, y si siguiera, lo primero que diría es ese mismo texto de nuevo.
    func quedarAtenta(alRetomar: @escaping () -> Void) {
        vigilante?.cancel()
        vigilante = nil
        generacion += 1
        tarea?.cancel()
        tarea = nil
        pedido = nil
        textoParcial = ""
        estado = .inactivo
        guard motor.isRunning, reconocedor != nil else { return }
        self.alRetomar = alRetomar
        atenta = true
        abrirTarea()
    }

    private func abrirTarea() {
        guard let reconocedor else { return }
        let p = SFSpeechAudioBufferRecognitionRequest()
        p.shouldReportPartialResults = true
        p.requiresOnDeviceRecognition = true
        p.addsPunctuation = true
        pedido = p
        generacion += 1
        let mia = generacion

        tarea = reconocedor.recognitionTask(with: p) { [weak self] resultado, error in
            Task { @MainActor [weak self] in
                guard let self, self.generacion == mia,
                      self.estaEscuchando || self.atenta else { return }
                if let resultado {
                    let nuevo = resultado.bestTranscription.formattedString
                    if nuevo != self.textoParcial {
                        self.textoParcial = nuevo
                        self.ultimoCambio = Date()   // seguís hablando
                    }
                    // Estaba atenta y apareció texto: no habías terminado. Se
                    // vuelve a escuchar de verdad, con el silencio vigilado, y
                    // se avisa una sola vez.
                    if self.atenta, !nuevo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.atenta = false
                        self.estado = .escuchando
                        self.vigilarSilencio()
                        let aviso = self.alRetomar
                        self.alRetomar = nil
                        aviso?()
                    }
                }
                if (resultado?.isFinal ?? false) || error != nil {
                    // El sistema cortó la tarea, no vos: se abre otra y seguimos.
                    self.pedido = nil
                    self.tarea = nil
                    self.abrirTarea()
                }
            }
        }
    }

    /// Mira si dejaste de hablar. Cuando pasa el silencio, cierra tu turno.
    private func vigilarSilencio() {
        vigilante?.cancel()
        vigilante = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, await self.estaEscuchando else { return }
                await self.chequearSilencio()
            }
        }
    }

    private func chequearSilencio() {
        let dicho = textoParcial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dicho.isEmpty else { return }
        guard Date().timeIntervalSince(ultimoCambio) >= FinDeTurno.silencio(tras: dicho) else { return }
        textoParcial = ""
        alTerminarTurno?(dicho)
    }

    func frenar() {
        vigilante?.cancel()
        vigilante = nil
        dejarDeVigilar()
        // Sin `estaEscuchando`: puede haber quedado el motor abierto por la
        // vigilancia, con el estado en inactivo, y ahí también hay que soltar
        // el micrófono. Antes este guard devolvía temprano y lo dejaba tomado.
        guard motor.isRunning else { return }
        estado = .inactivo
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        generacion += 1
        tarea?.cancel()
        tarea = nil
        pedido = nil
        textoParcial = ""
        atenta = false
        alRetomar = nil
        nivel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Lo que quedó a medio decir cuando cortás la conversación a mano.
    func loQueQuedoSinDecir() -> String? {
        let dicho = textoParcial.trimmingCharacters(in: .whitespacesAndNewlines)
        return dicho.isEmpty ? nil : dicho
    }


    // MARK: - Nivel

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let canal = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var suma: Float = 0
        for i in 0..<Int(buffer.frameLength) { suma += canal[i] * canal[i] }
        return Double((suma / Float(buffer.frameLength)).squareRoot())
    }

    private func actualizarNivel(_ crudo: Double) {
        // El RMS de voz normal ronda 0.02–0.15. El x8 lo lleva a un rango que se
        // ve; el promedio con el valor anterior evita que el orbe titile.
        let escalado = min(1, crudo * 8)
        nivel = nivel * 0.7 + escalado * 0.3
        if vigilandoInterrupcion { mirarSiEmpezasteAHablar() }
    }

    // MARK: - Cortarla hablándole encima

    /// Cuánto nivel, y por cuánto tiempo, cuenta como que empezaste a hablar.
    ///
    /// Alto y sostenido a propósito. Lo que está del otro lado es interrumpir a
    /// Bitácora en la mitad de una frase, y equivocarse es peor que no reaccionar:
    /// una tos, un ruido de la calle o un pedazo de eco que la cancelación no
    /// llegó a matar la callarían sin que nadie haya hablado. Medio segundo de
    /// sonido fuerte y seguido es difícil que sea otra cosa que una persona.
    ///
    /// Se ajustan de a poco y con el teléfono en la mano: en el simulador no hay
    /// micrófono de verdad ni parlante que produzca eco, así que esto no se
    /// puede calibrar acá.
    static let nivelParaInterrumpir: Double = 0.30
    static let sostenidoParaInterrumpir: TimeInterval = 0.45

    private var vigilandoInterrupcion = false
    private var vozDesde: Date?
    private var alEmpezarAHablar: (() -> Void)?

    /// Escucha SÓLO para saber si empezaste a hablar. No transcribe nada.
    ///
    /// Es a propósito que no transcriba: mientras Bitácora suena, lo que entra por
    /// el micrófono puede tener eco suyo, y el reconocedor no distingue quién
    /// habló. Transcribir eso sería poner palabras de Bitácora en tu turno. El nivel
    /// no tiene ese problema — dice que hay sonido, no qué dice.
    ///
    /// El costo es medio segundo: lo que digas antes de que se dispare no queda
    /// transcripto. Se paga porque la alternativa es peor.
    func vigilarInterrupcion(alEmpezarAHablar: @escaping () -> Void) {
        guard arrancarMotor() else { return }
        self.alEmpezarAHablar = alEmpezarAHablar
        vozDesde = nil
        nivel = 0
        vigilandoInterrupcion = true
    }

    func dejarDeVigilar() {
        vigilandoInterrupcion = false
        vozDesde = nil
        alEmpezarAHablar = nil
    }

    private func mirarSiEmpezasteAHablar() {
        guard nivel >= Self.nivelParaInterrumpir else {
            // Un bajón corta la cuenta: lo que vale es sonido SEGUIDO.
            vozDesde = nil
            return
        }
        let desde = vozDesde ?? Date()
        vozDesde = desde
        guard Date().timeIntervalSince(desde) >= Self.sostenidoParaInterrumpir else { return }
        let avisar = alEmpezarAHablar
        dejarDeVigilar()
        avisar?()
    }
}
