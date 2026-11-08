import AVFoundation
import SwiftUI

/// La voz de Bitácora. Dos voces, en realidad, y una es el respaldo de la otra.
///
/// LA LINDA la sintetiza el servidor y llega como un archivo de audio. Es la que suena como una
/// persona. Necesita internet y cuesta unos centavos por charla.
///
/// LA DE IOS es `AVSpeechSynthesizer`: on-device, gratis, instantánea, y la que
/// Dusan describió como "muy robótica" — con razón: las voces de Apple son
/// concatenativas y ninguna cantidad de parámetros las hace sonar a alguien.
/// La app igual las exprime todo lo que se puede (ver `puntaje`), porque es lo
/// único que hay cuando no hay red.
///
/// EL ORDEN NO SE NEGOCIA: se intenta la linda, y si no llega en unos segundos
/// —sin datos, sin presupuesto, el proveedor caído— habla la de iOS y nadie se
/// entera. No hay mensaje de error en ningún caso. Que Bitácora suene peor es
/// infinitamente mejor que que Bitácora se quede callada, porque del otro lado hay
/// alguien que acaba de contar algo y está esperando.
///
/// Sobre lo que sale del teléfono: acá viaja el texto que Bitácora acaba de decir,
/// que lo escribió el mismo proveedor al que se lo mandamos. Ya salió, ya viajó
/// entero. El audio de la persona sigue sin salir nunca, que es la regla de
/// verdad.
/// De quién es la voz. Una sola desde el 26/10/2026: hasta ese día Ajustes
/// ofrecía mujer u hombre, y Dusan pidió dejar sólo la de Lupita. Un «hombre»
/// guardado de antes no se lee (`Config`) y vuelve a esta.
enum Timbre: String, CaseIterable, Sendable {
    case mujer

    var nombre: String { "Mujer" }
}

@Observable
@MainActor
final class VozDeBitacora: NSObject {
    private let sintetizador = AVSpeechSynthesizer()
    private var reproductor: AVAudioPlayer?
    private var medidor: Task<Void, Never>?
    private var buscando: Task<Void, Never>?
    /// Lo que falta decir de este turno, en pedazos. Se vacía al terminar y al
    /// callar, así que un turno viejo no puede seguir hablando sobre el nuevo.
    private var pedazos: [String] = []
    /// El pedazo que sigue, pedido mientras suena el actual.
    ///
    /// Antes el pedazo siguiente se pedía recién cuando terminaba de sonar el
    /// anterior, y el servidor tarda entre uno y dos segundos y medio en
    /// devolverlo: eso era un silencio de ese largo entre frase y frase, en
    /// cada turno de más de una oración. Con el pedido ya hecho, cuando termina
    /// un audio el otro está listo y arranca pegado.
    ///
    /// Se adelanta UNO solo, no todos. Si la persona interrumpe, se paga ese
    /// pedazo de más y ninguno de los que venían detrás.
    private var adelantado: (pedazo: String, audio: Task<Data?, Never>)?
    /// El reproductor del turno en vivo, mientras hay uno sonando.
    private var altavoz: Altavoz?
    /// Hay un turno en vivo abierto: el audio va llegando por `sonar`.
    private var enVivo = false
    /// El motor de audio no arrancó. Lo que llegue se ignora y, al cerrar el
    /// turno, lo dice entero la voz de iOS.
    private var sinAltavoz = false
    private var alTerminar: (() -> Void)?
    private var vigia: Task<Void, Never>?

    private(set) var hablando = false

    /// Está buscando el audio del servidor y todavía no suena nada.
    ///
    /// Se ve: la luz sigue respirando como cuando piensa en vez de fingir que
    /// ya está hablando. Es corto —un segundo o dos— pero es silencio, y un
    /// silencio sin explicación se lee como que la app se colgó.
    private(set) var preparando = false

    /// Cuánto suena, 0…1, cuando la voz viene del servidor.
    ///
    /// `nil` con la voz de iOS, que no expone amplitud: ahí la luz se guía por
    /// `ultimaPalabraEn`, que es todo lo que hay. Con el audio sonando esto es
    /// medición de verdad, así que la luz sigue la voz como sigue al micrófono
    /// cuando te escucha a vos.
    private(set) var nivelDeVoz: Double?

    /// Cuándo empezó a decir la última palabra.
    ///
    /// Es la única señal de "cuánto suena" que da `AVSpeechSynthesizer`: no
    /// expone amplitud, pero avisa palabra por palabra. Con eso la luz sabe
    /// cuándo Bitácora está diciendo algo y cuándo hace una pausa, en vez de
    /// moverse igual hable o no. `nil` cuando está callada.
    private(set) var ultimaPalabraEn: Date?

    override init() {
        super.init()
        sintetizador.delegate = self
    }

    /// Cuánto sirve una voz, para el timbre pedido.
    ///
    /// Se puntúa en vez de encadenar condiciones porque las tres cosas que
    /// importan compiten entre sí y el orden no es obvio. El que manda es el
    /// TIMBRE: si pediste voz de mujer, una voz de hombre no sirve por más
    /// premium y mexicana que sea.
    ///
    /// Después va la CALIDAD, y va por encima del acento a propósito. Una voz
    /// mejorada de España suena a persona; una compacta argentina suena a robot
    /// de 2011, y eso se nota mucho más que el acento. Las compactas son las que
    /// vienen de fábrica, y son las que hacen que Bitácora suene mal.
    ///
    /// Y al final el ACENTO. Dusan pidió neutro o mexicano, igual que las voces
    /// del servidor: primero México, después el español latinoamericano genérico,
    /// y el rioplatense —que hasta el 01/10/2026 era el preferido— casi al final.
    static func puntaje(_ v: AVSpeechSynthesisVoice, _ quiero: Timbre) -> Int {
        var p = 0

        switch (v.gender, quiero) {
        case (.female, .mujer): p += 10_000
        // Una voz sin género declarado es mejor que la del timbre contrario.
        case (.unspecified, _): p += 3_000
        default: break
        }

        switch v.quality {
        case .premium: p += 300
        case .enhanced: p += 200
        default: break
        }

        switch v.language {
        case "es-MX": p += 150
        case "es-419", "es-US": p += 120
        case "es-CO", "es-CL": p += 100
        case "es-AR", "es-UY", "es-PY": p += 80
        default: p += 40          // es-ES y el resto
        }

        return p
    }

    /// La mejor voz en español para el timbre pedido, o `nil` si no hay ninguna.
    static func mejorVoz(_ quiero: Timbre) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") }
            .max { puntaje($0, quiero) < puntaje($1, quiero) }
            ?? AVSpeechSynthesisVoice(language: "es-MX")
    }

    /// Qué voz está sonando de verdad, para poder mostrarlo en Ajustes.
    ///
    /// Que se vea NO es un detalle técnico: si suena a robot, el motivo casi
    /// siempre es que sólo está instalada la voz compacta, y eso no lo puede
    /// arreglar la app — las mejoradas las descarga el usuario desde Ajustes de
    /// iOS. Sin mostrarlo, la única lectura posible es "la app suena mal".
    struct VozEnUso {
        let nombre: String
        let idioma: String
        let esCompacta: Bool
        /// Si la voz que va a sonar es del timbre que pediste.
        ///
        /// Puede ser `false` y no es un caso raro: en un iPhone recién salido de
        /// la caja puede haber UNA sola voz en español. Elegís "Hombre", suena
        /// una mujer, y la única conclusión posible es que la app está rota.
        /// Verificado en el simulador, que sólo trae a Paulina.
        let coincideElTimbre: Bool
    }

    static func enUso(_ quiero: Timbre) -> VozEnUso? {
        guard let v = mejorVoz(quiero) else { return nil }
        let esperado: AVSpeechSynthesisVoiceGender = quiero == .mujer ? .female : .male
        return VozEnUso(nombre: v.name, idioma: v.language,
                        esCompacta: v.quality == .default,
                        coincideElTimbre: v.gender == esperado)
    }

    /// Dice un texto que NO puede salir del teléfono.
    ///
    /// Es para los textos fijos de la app: el mensaje de cuidado de la regla 6 y
    /// la despedida de los cortes. El argumento que permite mandar los turnos de
    /// Bitácora al proveedor —los escribió él, ya salieron— no vale para éstos: los
    /// escribió la app, y pedir que sinteticen justo el mensaje de riesgo le
    /// avisa a una empresa que el detector se disparó. El corte de riesgo vive
    /// en el teléfono para no depender de nadie; mandar su mensaje a sintetizar
    /// lo desharía por la puerta de atrás.
    ///
    /// Y hay una segunda razón, del lado de la persona: es el único turno de la
    /// app que no puede esperar tres segundos a que llegue un archivo de audio.
    func decirSinSalir(_ texto: String, alTerminar: @escaping () -> Void) {
        self.alTerminar = alTerminar
        hablando = true
        conVozDeIOS(texto)
    }

    /// Dice un turno de Bitácora, empezando lo antes posible.
    ///
    /// EL TEXTO SE PARTE EN FRASES y se pide de a un pedazo. El primero es
    /// corto: vuelve en un segundo y medio y Bitácora arranca, mientras el segundo
    /// se sintetiza. Antes se pedía el turno entero, y una respuesta larga eran
    /// ocho segundos de pantalla escrita y muda — que es lo que Dusan notó como
    /// "al principio responde lento y después va aumentando". Ahora el tiempo
    /// hasta la primera palabra no depende del largo de la respuesta.
    ///
    /// Los pedidos van encadenados y no todos juntos: si la persona interrumpe
    /// en la primera frase, los pedazos que siguen no se piden ni se pagan.
    /// - Parameters:
    ///   - primerAudio: el audio de la primera frase, si el servidor lo mandó
    ///     junto con el texto. Con esto Bitácora arranca sin pedir nada: el pedido
    ///     ya se hizo mientras se escribía la respuesta.
    ///   - fraseDelAudio: qué parte del texto es ese audio. Se saca del texto y
    ///     el resto se parte como siempre. No se asume que sea el primer pedazo
    ///     de `TrozosDeVoz`: el servidor tiene su propio corte, y en las
    ///     respuestas cortas —que acá no se parten— dar por sentado que
    ///     coinciden se comería todo lo que viene después de la primera frase.
    func decir(_ texto: String, primerAudio: Data? = nil, fraseDelAudio: String? = nil,
               alTerminar: @escaping () -> Void) {
        self.alTerminar = alTerminar
        hablando = true
        // Un pedido adelantado del turno anterior no puede colarse en éste.
        adelantado?.audio.cancel(); adelantado = nil

        let config = Config.shared
        guard config.vozNatural, config.hayServidor else {
            conVozDeIOS(texto)
            return
        }

        // Todavía no dijo nada: `ultimaPalabraEn` en nil mientras busca, para
        // que la luz no muestre una palabra que no sonó.
        ultimaPalabraEn = nil

        if let primerAudio, let frase = fraseDelAudio, texto.hasPrefix(frase) {
            let resto = String(texto.dropFirst(frase.count))
            pedazos = TrozosDeVoz.partir(resto)
            preparando = false
            if reproducir(primerAudio) { return }
            // Llegó pero no se pudo reproducir: se sigue por el camino normal,
            // con el texto entero, como si no hubiera venido.
        }

        pedazos = TrozosDeVoz.partir(texto)
        guard !pedazos.isEmpty else {
            terminar()
            return
        }
        preparando = true
        siguientePedazo()
    }

    // MARK: - En vivo

    /// Abre un turno cuyo audio va a ir llegando de a pedazos.
    ///
    /// Es el camino normal desde el 01/10/2026: el servidor manda la voz
    /// mientras la sintetiza y acá suena a medida que llega. `decir`, más
    /// arriba, queda para cuando eso no se puede —un servidor viejo, la conexión
    /// en vivo que no abre— y para el botón de probar de Ajustes.
    func empezarEnVivo(alTerminar: @escaping () -> Void) {
        limpiar()
        self.alTerminar = alTerminar
        hablando = true
        enVivo = true
        sinAltavoz = false
        // Hasta que no llegue el primer audio, la luz respira como cuando piensa.
        preparando = true
        ultimaPalabraEn = nil
    }

    /// Llegó un pedazo de audio del turno en vivo.
    func sonar(_ pcm: Data, hz: Int) {
        guard hablando, enVivo, !sinAltavoz else { return }

        if altavoz == nil {
            prepararSesionParaSonar()
            guard let a = Altavoz(hz: hz) else {
                sinAltavoz = true
                return
            }
            altavoz = a
            preparando = false
            ultimaPalabraEn = Date()
            arrancarMedidorEnVivo()
        }
        altavoz?.agregar(pcm)
    }

    /// El servidor terminó de mandar el turno.
    ///
    /// Falta que termine de SONAR: el audio llega mucho más rápido de lo que se
    /// escucha, así que en este punto suele quedar casi todo por decir.
    ///
    /// - Parameters:
    ///   - texto: el turno entero, por si no se pudo reproducir nada.
    ///   - faltaDecir: lo que la voz del servidor no llegó a decir. Cuando
    ///     termina lo que hay en cola, eso lo dice la voz de iOS. Cambiar de voz
    ///     a mitad de turno suena raro; comerse el final de la respuesta, peor.
    func cerrarEnVivo(texto: String, faltaDecir: String) {
        guard hablando, enVivo else { return }

        guard let a = altavoz else {
            // No sonó nada: o no llegó audio, o el motor no arrancó.
            enVivo = false
            let todo = sinAltavoz ? texto : faltaDecir
            if todo.isEmpty { terminar() } else { conVozDeIOS(todo) }
            return
        }

        a.alVaciarse { [weak self] in
            Task { @MainActor in
                guard let self, self.hablando, self.altavoz === a else { return }
                self.soltarAltavoz()
                if faltaDecir.isEmpty { self.terminar() } else { self.conVozDeIOS(faltaDecir) }
            }
        }

        // El perro guardián de siempre: si el aviso no llega —una llamada que
        // se llevó la sesión de audio, por ejemplo— el turno termina igual.
        vigia?.cancel()
        let techo = a.porSonar + 3
        vigia = Task { [weak self] in
            try? await Task.sleep(for: .seconds(techo))
            guard !Task.isCancelled else { return }
            await self?.forzarFin()
        }
    }

    private func soltarAltavoz() {
        altavoz?.parar()
        altavoz = nil
        enVivo = false
        medidor?.cancel(); medidor = nil
        nivelDeVoz = nil
    }

    private func arrancarMedidorEnVivo() {
        medidor?.cancel()
        medidor = Task { [weak self] in
            while !Task.isCancelled, let a = self?.altavoz {
                self?.nivelDeVoz = a.nivel
                try? await Task.sleep(for: .milliseconds(33))
            }
            self?.nivelDeVoz = nil
        }
    }

    // MARK: - Por pedazos

    /// Pide el pedazo que toca y lo reproduce; el resto sigue solo desde el
    /// delegado del reproductor.
    ///
    /// Si un pedazo falla, lo que queda por decir lo dice la voz de iOS. Suena
    /// raro cambiar de voz a mitad de turno, y aun así es mejor que las dos
    /// alternativas: cortarla ahí deja la idea por la mitad, y reintentar mete
    /// un silencio largo justo donde ya se estaba escuchando.
    private func siguientePedazo() {
        guard hablando, adelantado != nil || !pedazos.isEmpty else { return }

        // Si ya se había pedido mientras sonaba el anterior, se usa ése: lo más
        // probable es que ya esté, y si no, falta menos que pedirlo de cero.
        let pedazo: String
        let pedido: Task<Data?, Never>
        if let a = adelantado {
            adelantado = nil
            (pedazo, pedido) = a
        } else {
            pedazo = pedazos.removeFirst()
            pedido = pedir(pedazo)
        }
        let quedan = pedazos

        buscando?.cancel()
        buscando = Task { [weak self] in
            let audio = await pedido.value
            guard let self, !Task.isCancelled, self.hablando else { return }
            self.preparando = false
            // Si el audio llegó pero no se puede reproducir (un archivo
            // cortado, la sesión tomada por una llamada), es lo mismo que si no
            // hubiera llegado.
            if let audio, self.reproducir(audio) { return }
            self.pedazos = []
            self.conVozDeIOS(([pedazo] + quedan).joined(separator: " "))
        }
    }

    /// El pedido del audio de un pedazo, como tarea que se puede esperar después.
    private func pedir(_ pedazo: String) -> Task<Data?, Never> {
        let config = Config.shared
        let servidor = config.servidor
        let timbre = config.timbre.rawValue
        return Task {
            await SyncClient(config: servidor).voz(texto: pedazo, timbre: timbre)
        }
    }

    /// Pide el pedazo que sigue, si hay, sin esperar a que termine el que suena.
    private func adelantarElSiguiente() {
        guard hablando, adelantado == nil, !pedazos.isEmpty else { return }
        let pedazo = pedazos.removeFirst()
        adelantado = (pedazo, pedir(pedazo))
    }

    /// El respaldo: la voz del sistema.
    private func conVozDeIOS(_ texto: String) {
        preparando = false
        nivelDeVoz = nil
        // El *4141 del mensaje de cuidado, dicho como se marca.
        let frase = AVSpeechUtterance(string: Riesgo.paraDecir(texto))
        frase.voice = Self.mejorVoz(Config.shared.timbre)
        frase.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        frase.postUtteranceDelay = 0.15
        ultimaPalabraEn = Date()
        sintetizador.speak(frase)

        // Perro guardián.
        //
        // `didFinish` no siempre llega: sin voz instalada, con la sesión de audio
        // interrumpida por una llamada, o en el simulador, el sintetizador se
        // queda callado y no avisa nada. Sin esto la conversación se cuelga para
        // siempre — y el caso que más duele es el del camino de escape, donde el
        // mensaje de cuidado nunca terminaría de mostrarse.
        //
        // El techo es generoso: si el callback llega antes (el caso normal), este
        // Task se cancela y no hace nada.
        // Dos etapas, porque son dos fallas distintas:
        //
        //   a) nunca arrancó (no hay voz, la sesión de audio no abrió). Se nota
        //      enseguida con `isSpeaking`, y ahí no tiene sentido esperar: se
        //      sigue de largo en menos de dos segundos.
        //   b) arrancó y no avisó que terminó. Ahí sí hay que esperar a que la
        //      frase se haya escuchado entera, así que el techo va por largo.
        let techo = max(4, Double(texto.count) * 0.09 + 2.5)
        vigia?.cancel()
        vigia = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            if await self?.nuncaArranco == true {
                await self?.forzarFin()
                return
            }
            try? await Task.sleep(for: .seconds(techo - 1.5))
            guard !Task.isCancelled else { return }
            await self?.forzarFin()
        }
    }

    /// Deja la sesión de audio lista para reproducir. El porqué de cada cosa
    /// está en `reproducir`, que es de donde salió.
    private func prepararSesionParaSonar() {
        let sesionDeAudio = AVAudioSession.sharedInstance()
        if sesionDeAudio.category != .playAndRecord {
            try? sesionDeAudio.setCategory(.playback, mode: .voiceChat, options: [.duckOthers])
        }
        try? sesionDeAudio.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Reproduce el audio del servidor. `false` si no se pudo, y ahí habla iOS.
    private func reproducir(_ audio: Data) -> Bool {
        // La sesión puede no estar activa: si Bitácora habla antes de que vos digas
        // nada —el mensaje de cuidado, por ejemplo— nadie la abrió todavía.
        // `AVSpeechSynthesizer` se arregla solo con esto; `AVAudioPlayer` no.
        //
        // `.playback` y NO `.playAndRecord`, que es lo que usa `CapturaDeVoz`.
        // Para reproducir no hace falta el micrófono, y pedirlo ata la voz de
        // Bitácora al permiso de grabar: probado en el simulador sin permiso, con
        // `.playAndRecord` el `play()` se cuelga y nunca vuelve. Con `.playback`
        // suena. O sea que con el micrófono denegado —o antes de concederlo—
        // Bitácora se habría quedado sin voz linda para siempre, cayendo a la de
        // iOS sin que se entienda por qué.
        //
        // Si la captura ya dejó la sesión en `.playAndRecord` no se toca nada:
        // cambiarle la categoría mientras el micrófono está tomado corta el
        // reconocimiento en la mitad de una frase.
        prepararSesionParaSonar()

        guard let p = try? AVAudioPlayer(data: audio) else { return false }
        p.delegate = self
        p.isMeteringEnabled = true
        guard p.play() else { return false }

        reproductor = p
        ultimaPalabraEn = Date()
        arrancarMedidor()
        adelantarElSiguiente()

        // El mismo perro guardián, pero acá el techo se sabe de verdad: dura lo
        // que dura el audio. El margen es para el caso en que `didFinish` no
        // llegue, que con el sintetizador pasa y no hay motivo para confiar más
        // en el reproductor.
        vigia?.cancel()
        vigia = Task { [weak self] in
            try? await Task.sleep(for: .seconds(p.duration + 2))
            guard !Task.isCancelled else { return }
            await self?.forzarFin()
        }
        return true
    }

    /// Mira cuánto suena, treinta veces por segundo, para que la luz lo siga.
    ///
    /// Treinta y no sesenta: la luz tiene su propia inercia y no ve la
    /// diferencia, y esto corre mientras Bitácora habla.
    private func arrancarMedidor() {
        medidor?.cancel()
        medidor = Task { [weak self] in
            while !Task.isCancelled, let p = self?.reproductor, p.isPlaying {
                p.updateMeters()
                // El medidor da decibeles, de -160 (silencio) a 0 (máximo). Los
                // -45 son el piso útil: más abajo es ruido de fondo del códec y
                // subirlo a la luz sería mostrar movimiento donde no hay voz.
                let db = Double(p.averagePower(forChannel: 0))
                self?.nivelDeVoz = max(0, min(1, (db + 45) / 45))
                try? await Task.sleep(for: .milliseconds(33))
            }
            self?.nivelDeVoz = nil
        }
    }

    private var nuncaArranco: Bool {
        hablando && !sintetizador.isSpeaking && reproductor?.isPlaying != true && altavoz == nil
    }

    /// Da el turno por terminado aunque el sistema no haya avisado.
    private func forzarFin() {
        guard hablando else { return }
        sintetizador.stopSpeaking(at: .immediate)
        reproductor?.stop()
        terminar()
    }

    private func terminar() {
        limpiar()
        hablando = false
        ultimaPalabraEn = nil
        let cb = alTerminar
        alTerminar = nil
        cb?()
    }

    func callar() {
        limpiar()
        alTerminar = nil
        hablando = false
        ultimaPalabraEn = nil
        sintetizador.stopSpeaking(at: .immediate)
    }

    /// Apaga todo lo que puede seguir corriendo solo: el vigía, el pedido del
    /// audio, el medidor y el reproductor. Se llama desde los dos finales
    /// —terminar y callar— porque olvidarse de uno deja a Bitácora hablando encima
    /// de la charla siguiente.
    private func limpiar() {
        vigia?.cancel(); vigia = nil
        buscando?.cancel(); buscando = nil
        adelantado?.audio.cancel(); adelantado = nil
        medidor?.cancel(); medidor = nil
        reproductor?.stop(); reproductor = nil
        altavoz?.parar(); altavoz = nil
        enVivo = false
        pedazos = []
        preparando = false
        nivelDeVoz = nil
    }
}

extension VozDeBitacora: AVAudioPlayerDelegate {
    /// Terminó un pedazo. Si queda otro, sigue; si no, terminó el turno.
    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) {
        Task { @MainActor in
            guard hablando else { return }
            if pedazos.isEmpty, adelantado == nil {
                terminar()
            } else {
                // El vigía del audio que acaba de terminar daba el turno por
                // muerto a los dos segundos. Si el pedazo siguiente tarda más
                // que eso en llegar, cortaba a Bitácora a mitad de la respuesta.
                // De acá en más manda el pedido, que tiene su propio timeout.
                vigia?.cancel(); vigia = nil
                siguientePedazo()
            }
        }
    }

    /// Un audio que se rompió a mitad de camino. Termina igual: el turno ya sonó
    /// en parte y repetirlo con otra voz sería peor que seguir.
    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
        Task { @MainActor in terminar() }
    }
}

extension VozDeBitacora: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in terminar() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        // El cancel lo dispara tanto `callar()` como `forzarFin()`. Los dos ya
        // limpiaron el callback, así que acá sólo queda bajar la bandera.
        Task { @MainActor in hablando = false; ultimaPalabraEn = nil }
    }

    /// Una palabra más. Es lo que sostiene la luz mientras habla.
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString r: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in ultimaPalabraEn = Date() }
    }
}
