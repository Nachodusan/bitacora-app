import SwiftUI

/// Coordina la conversación: quién habla, cuándo se escucha, cuándo se guarda.
///
/// El ciclo es siempre el mismo — vos hablás, se detecta la pausa, Bitácora
/// contesta, se calla, y vuelve a escuchar. Nunca escucha mientras habla.
///
/// Dos cosas gobiernan todo este archivo:
///
///   · LA CHARLA LA TERMINÁS VOS. No hay tope de turnos ni cierre automático.
///     Por eso la conversación se escribe a disco MIENTRAS PASA, y no al final:
///     el único final es que toques el orbe, y un desahogo de cuarenta minutos
///     que termina con el teléfono en la mesa se perdería entero.
///
///   · HAY UNA ESPERA. El turno tarda algo más de un segundo, así que existe
///     una fase `.pensando` — sin ella el orbe se quedaría quieto y parecería
///     colgado.
///
/// Hubo acá una confirmación de hábitos y un ritual de cierre con preguntas
/// fijas. Se fueron con la pestaña de Hábitos: la charla es la charla.
@Observable
@MainActor
final class Conversacion {

    enum Fase: Equatable {
        case inactiva
        case pensando      // esperando el turno del servidor
        case hablando      // Bitácora
        case escuchando    // vos
        case cerrada
        case cuidado       // regla 6: la conversación se cortó a propósito
    }

    private(set) var fase: Fase = .inactiva
    private(set) var turnos: [Turno] = []

    let captura = CapturaDeVoz()
    let voz = VozDeBitacora()

    private let outbox: Outbox
    private var comienzo: Date?
    /// La fila de SwiftData donde se va escribiendo esta charla.
    private var borrador: EntradaLocal?
    /// Una charla de otro día que se eligió seguir desde el historial
    /// (27/10/2026): sus turnos van primero en `turnos` —en pantalla y al
    /// servidor— pero no se vuelven a guardar. Lo nuevo es una charla de hoy.
    private var anterior: (dia: String, cuantos: Int)?
    /// Cambia en cada `arrancar()`. Un turno del servidor que llega tarde —el
    /// timeout es de 20 segundos— trae la sesión con la que salió, y si no es
    /// ésta, se descarta: si no, la respuesta a una charla que cortaste podía
    /// entrar en la siguiente como si fuera de ella.
    private var sesion = UUID()
    /// Cambia en cada turno que se le pide al servidor.
    ///
    /// La sesión no alcanza desde que el turno llega en vivo. Antes un pedido
    /// volvía de una sola vez y había un único momento para preguntar si
    /// seguía valiendo. Ahora va llegando durante varios segundos, con Bitácora ya
    /// hablando, y en ese rato la podés interrumpir y decir otra cosa: el turno
    /// viejo y el nuevo son de la misma charla. Con esto, lo que siga llegando
    /// del viejo se descarta.
    private var pedido = UUID()

    /// Lo que venías diciendo en un turno que se cerró antes de tiempo.
    ///
    /// Si seguís hablando después de que tu turno se dio por terminado, ese
    /// turno sale de la charla y queda acá hasta que termines de verdad. Lo que
    /// digas se le suma, y lo que se manda al servidor es una sola cosa dicha.
    private var colgado: String?
    /// Desde cuándo SUENA Bitácora en este turno. `nil` mientras todavía no salió
    /// audio: en ese rato se puede seguir transcribiendo sin riesgo de eco.
    private var suenaDesde: Date?

    /// Si cortás a Bitácora antes de esto, se entiende que no habías terminado: su
    /// respuesta se descarta y seguís tu turno. Pasado este tiempo es una
    /// interrupción común: lo que ella dijo queda y lo tuyo es un turno nuevo.
    static let margenParaRetomar: TimeInterval = 2.5

    /// Cómo entró la charla, que decide qué pasa cuando Bitácora termina de hablar.
    ///
    /// EN LLAMADA vuelve a escucharte sola, que es lo de siempre: la
    /// conversación sigue hasta que la cortás. EN SUELTO se queda quieta
    /// esperando lo que escribas o grabes, sin el micrófono abierto. Son dos
    /// maneras distintas de usar la app y conviene que se note: una es hablar
    /// con alguien, la otra es dejarle algo anotado.
    enum Modo { case llamada, suelto }
    private(set) var modo: Modo = .llamada

    /// En llamada, aunque Bitácora esté hablando o pensando, la charla está viva.
    var enLlamada: Bool { modo == .llamada && activa }

    /// Está diciendo la despedida y la charla se está guardando. Mientras tanto
    /// no se puede interrumpir: el callback que guarda se perdería.
    private(set) var cerrando = false

    /// Micrófono silenciado en la llamada: Bitácora no escucha hasta que lo
    /// vuelvas a prender, pero la llamada sigue.
    private(set) var silenciado = false

    /// El tiempo de charla de las veces anteriores de hoy, y desde cuándo corre
    /// la de ahora. Con la conversación abierta todo el día, contar desde que
    /// empezó diría «3 h» por diez minutos de charla.
    private var duracionPrevia: Double = 0
    private var tramoDesde: Date?

    init(outbox: Outbox) {
        self.outbox = outbox
        captura.alTerminarTurno = { [weak self] texto in
            self?.recibirTurno(texto)
        }
        retomarLaDeHoy()
    }

    // MARK: - Una conversación por día

    /// Si hoy ya hubo charla y quedó abierta, se retoma: los mensajes vuelven a
    /// la pantalla y Bitácora sigue desde ahí. Desde el 19 de octubre la
    /// conversación del día no se cierra al salir ni si se muere la app (lo
    /// pidió Dusan, para mantener el hilo); se cierra cuando cambia el día.
    private func retomarLaDeHoy() {
        guard let e = outbox.borradorDeHoy() else { return }
        anterior = nil
        borrador = e
        comienzo = e.creadoEn
        duracionPrevia = e.duracionSeg
        turnos = Transcripcion.turnos(e.transcripcion)
        fase = turnos.isEmpty ? .inactiva : .cerrada
    }

    /// Retoma una charla elegida en el historial. Si es la que está abierta, no
    /// hay nada que hacer; si es otra de hoy, la abierta se cierra (queda
    /// guardada) y la elegida vuelve a la pantalla para seguirla. Una de otro
    /// día también se sigue (27/10/2026): vuelve entera a la pantalla, y lo que
    /// se hable ahora se guarda como charla de hoy (`anterior`), porque esa ya
    /// entró al resumen de su día.
    func retomar(_ e: EntradaLocal) -> Bool {
        guard !activa else { return false }
        if e === borrador { return true }
        if e.diaLogico != CalendarioView.hoyLogico() {
            let viejos = Transcripcion.turnos(e.transcripcion)
            guard !viejos.isEmpty else { return false }
            if let borrador { outbox.cerrarBorrador(borrador) }
            borrador = nil
            comienzo = nil
            duracionPrevia = 0
            tramoDesde = nil
            turnos = viejos
            anterior = (e.diaLogico, viejos.count)
            fase = .cerrada
            return true
        }
        guard outbox.reabrir(e) else { return false }
        anterior = nil
        if let borrador { outbox.cerrarBorrador(borrador) }
        borrador = e
        comienzo = e.creadoEn
        duracionPrevia = e.duracionSeg
        turnos = Transcripcion.turnos(e.transcripcion)
        tramoDesde = nil
        fase = turnos.isEmpty ? .inactiva : .cerrada
        return true
    }

    /// Si la conversación abierta es de un día que ya terminó, se cierra y la
    /// pantalla queda limpia para hoy. Se llama al volver a la app y antes de
    /// cada charla.
    func revisarElDia() {
        guard !activa, let borrador, borrador.diaLogico < CalendarioView.hoyLogico() else { return }
        outbox.cerrarBorrador(borrador)
        self.borrador = nil
        anterior = nil
        comienzo = nil
        turnos = []
        fase = .inactiva
        duracionPrevia = 0
        if let hoy = outbox.borradorDeHoy() {
            self.borrador = hoy
            comienzo = hoy.creadoEn
            duracionPrevia = hoy.duracionSeg
            turnos = Transcripcion.turnos(hoy.transcripcion)
            fase = turnos.isEmpty ? .inactiva : .cerrada
        }
    }

    var activa: Bool { fase == .hablando || fase == .escuchando || fase == .pensando }

    /// Lo que se ve en el globo de abajo mientras hablás, antes de que el turno
    /// se cierre.
    var parcial: String {
        #if DEBUG && targetEnvironment(simulator)
        if DemoDeLlamada.shared.enCurso { return DemoDeLlamada.shared.parcial }
        #endif
        return FinDeTurno.unir(colgado, captura.textoParcial)
    }

    // MARK: - Ciclo

    /// Abre la llamada: el micrófono queda escuchando hasta que cortes.
    func arrancar() {
        modo = .llamada
        abrir()
        #if DEBUG && targetEnvironment(simulator)
        if DemoDeLlamada.shared.preparar() {
            siguienteFraseDeDemo()
            return
        }
        #endif
        Task { await escucharOFrenar() }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// La próxima frase del guion de demostración, como si se dijera. Sin más
    /// frases, la llamada se queda en «Te escucho» (ver `DemoDeLlamada`).
    private func siguienteFraseDeDemo() {
        let demo = DemoDeLlamada.shared
        fase = .escuchando
        guard let frase = demo.siguiente() else {
            demo.guardarAudio()
            return
        }
        Task {
            await demo.decir(frase)
            guard fase == .escuchando, demo.enCurso else { return }
            demo.parcial = ""
            procesar(frase.texto)
        }
    }
    #endif

    /// Manda algo escrito. No abre el micrófono ni deja la charla escuchando.
    func enviarTexto(_ texto: String) {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        // Si ya venías en llamada, escribir no la corta: se suma como un turno
        // más y la llamada sigue. Sólo define el modo cuando la charla arranca.
        if !activa { modo = .suelto; abrir() }
        procesar(limpio)
    }

    /// Graba UN mensaje: escucha, transcribe, lo manda y se queda quieta.
    ///
    /// Es la diferencia con la llamada, y es toda la diferencia: acá el
    /// micrófono se cierra apenas terminás de hablar. Sirve para dejar algo
    /// dicho sin abrir una conversación.
    func grabarUnMensaje() {
        if activa, modo == .suelto, fase == .escuchando {
            // Tocar de nuevo mientras graba: manda lo que haya y cierra.
            if let dicho = captura.loQueQuedoSinDecir() {
                captura.frenar()
                procesar(dicho)
            } else {
                captura.frenar()
                fase = turnos.isEmpty ? .inactiva : .cerrada
            }
            return
        }
        guard !activa else { return }
        modo = .suelto
        abrir()
        Task { await escucharOFrenar() }
    }

    private func abrir() {
        guard !activa else { return }
        revisarElDia()
        sesion = UUID()
        colgado = nil
        suenaDesde = nil
        silenciado = false
        tramoDesde = Date()
        // La conversación de hoy sigue: no se borra lo hablado ni se abre otra.
        if borrador != nil { return }
        duracionPrevia = 0
        if anterior == nil { turnos = [] }
        comienzo = Date()
        // El borrador se abre ANTES de la primera palabra. Si la app se muere
        // en el turno 40, lo que hay ya está en disco.
        borrador = outbox.abrirBorrador(instante: comienzo!)
    }

    /// Abre el micrófono, y si no se puede, no hace como que sí.
    ///
    /// `captura.escuchar()` vuelve sin escuchar cuando falta el permiso, no hay
    /// reconocedor en español, o el motor de audio no arranca. Antes la fase
    /// quedaba en `.escuchando` igual: el orbe decía «Te escucho» y latía, con
    /// el aviso del motivo arriba contradiciéndolo. Acá se mira el estado
    /// después, y si no se pudo, la charla se guarda (si había algo) y se
    /// vuelve al reposo: el aviso queda solo en pantalla, que es lo que hay.
    private func escucharOFrenar() async {
        fase = .escuchando
        captura.dejarDeVigilar()
        await captura.escuchar()
        if case .noDisponible = captura.estado {
            voz.callar()
            devolverLoColgado()
            guardar()
            fase = turnos.isEmpty ? .inactiva : .cerrada
        }
    }

    /// Mientras Bitácora habla, el micrófono escucha por si arrancás vos.
    ///
    /// No transcribe: mira el nivel. Lo que suena mientras Bitácora habla puede
    /// tener eco suyo, y el reconocedor no distingue quién habló — transcribir
    /// eso sería ponerle a tu turno palabras que dijo ella.
    private func vigilarQueNoLaInterrumpas() {
        captura.vigilarInterrupcion { [weak self] in
            Task { @MainActor in self?.interrumpir() }
        }
    }

    /// Cortarla para hablar vos.
    ///
    /// NO es lo mismo que `terminar()`, y ésa era toda la falla: hasta ahora
    /// tocar la pantalla mientras Bitácora hablaba cerraba la conversación entera.
    /// Si te acordaste de algo en la mitad de su respuesta, la única salida era
    /// cerrar y volver a empezar.
    ///
    /// Lo que ya dijo queda en el turno, entero y como estaba: el texto se
    /// escribió cuando llegó del servidor, no a medida que sonaba. Lo que se
    /// pierde es el audio que no llegó a escucharse, y eso no hace falta
    /// guardarlo — está ahí arriba, para leer.
    ///
    /// El mensaje de cuidado no se puede cortar. Es el único turno de la app
    /// que se escucha entero, y la fase `.cuidado` ya lo saca de acá.
    func interrumpir() {
        guard fase == .hablando, !cerrando else { return }
        captura.dejarDeVigilar()
        voz.callar()
        // Lo que siga llegando de este turno ya no vale.
        pedido = UUID()
        // Si recién arrancaba, no la estás interrumpiendo: te cortó ella.
        if let desde = suenaDesde, Date().timeIntervalSince(desde) < Self.margenParaRetomar {
            retomarTuTurno()
            siNoSeguisVuelveAPreguntar()
        }
        Task { await escucharOFrenar() }
    }

    /// Red de seguridad para cuando el corte no fuiste vos.
    ///
    /// Que Bitácora se calle hablándole encima se decide por el nivel del micrófono,
    /// y eso se puede disparar con una tos, un portazo o un resto de su propia
    /// voz. Si pasa en los primeros segundos, su respuesta ya se descartó y tu
    /// turno quedó abierto esperando que sigas. Si no seguís, a los cuatro
    /// segundos se vuelve a pedir la respuesta con lo que ya habías dicho: la
    /// charla no se queda colgada por un ruido.
    private func siNoSeguisVuelveAPreguntar() {
        let este = pedido
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.pedido == este, self.fase == .escuchando,
                  self.colgado != nil, self.captura.textoParcial.isEmpty else { return }
            self.recibirTurno("")
        }
    }

    private func recibirTurno(_ texto: String) {
        guard fase == .escuchando else { return }
        let completo = FinDeTurno.unir(colgado, texto)
        guard !completo.isEmpty else { return }
        colgado = nil
        // En llamada el micrófono queda abierto, y mientras Bitácora no suene se
        // sigue transcribiendo: si no habías terminado, lo que digas ahora
        // todavía cuenta. En un mensaje suelto se suelta ya: no hay conversación
        // que seguir, y dejar el micrófono tomado sin motivo es justamente lo
        // que no hay que hacer.
        if modo == .llamada {
            captura.quedarAtenta { [weak self] in self?.seguisHablando() }
        } else {
            captura.frenar()
        }
        procesar(completo)
    }

    /// Seguiste hablando después de que tu turno se dio por terminado.
    ///
    /// TU VOZ TIENE PRIORIDAD. Bitácora todavía no dijo nada —o está escribiendo y
    /// no salió audio—, así que su respuesta se descarta entera: contestaba a
    /// media idea. Tu turno vuelve a estar abierto con lo que ya habías dicho, y
    /// lo nuevo se le suma.
    private func seguisHablando() {
        guard fase == .pensando || (fase == .hablando && suenaDesde == nil), !cerrando else { return }
        pedido = UUID()
        voz.callar()
        retomarTuTurno()
        fase = .escuchando
    }

    /// Saca de la charla la respuesta que Bitácora estaba dando y deja tu último
    /// turno colgado, para seguirlo.
    private func retomarTuTurno() {
        // Los turnos de una charla retomada de otro día no se tocan.
        let piso = anterior?.cuantos ?? 0
        if turnos.count > piso, turnos.last?.de == .bitacora { turnos.removeLast() }
        if turnos.count > piso, let ultimo = turnos.last, ultimo.de == .vos {
            colgado = FinDeTurno.unir(colgado, ultimo.texto)
            turnos.removeLast()
        }
        suenaDesde = nil
        anotar()
    }

    /// Lo que quedó colgado vuelve a la charla como turno. Se usa antes de
    /// guardar: nada de lo que dijiste se pierde por haberlo dicho de a dos veces.
    private func devolverLoColgado(mas resto: String = "") {
        let texto = FinDeTurno.unir(colgado, resto)
        colgado = nil
        if !texto.isEmpty { turnos.append(Turno(de: .vos, texto: texto)) }
    }

    /// Bitácora empezó a sonar. De acá en más no se transcribe: se mira el nivel.
    private func bitacoraEmpezoASonar() {
        suenaDesde = Date()
        guard modo == .llamada, !silenciado else { return }
        #if DEBUG && targetEnvironment(simulator)
        // En la demostración no hay micrófono que vigilar: abrirlo dejaría que
        // un ruido de la sala cortara a Bitácora en plena grabación.
        if DemoDeLlamada.shared.enCurso { return }
        #endif
        captura.pausarTranscripcion()
        vigilarQueNoLaInterrumpas()
    }

    /// Lo que pasa con cualquier cosa que digas, venga del teclado o del
    /// micrófono: se anota, se chequea la regla 6, y se pide el turno.
    private func procesar(_ texto: String) {
        turnos.append(Turno(de: .vos, texto: texto))
        anotar()

        // REGLA 6, Y VA ANTES QUE EL SERVIDOR.
        //
        // El compañero también tiene la instrucción de acompañar hacia ayuda si
        // aparecen señales, y está bien que la tenga — pero a un modelo se lo
        // puede convencer de lo contrario y a esta función no. Se chequea acá,
        // sobre lo que acabás de decir, antes de gastar un turno y antes de que
        // el modelo tenga la oportunidad de contestar otra cosa.
        //
        // El mensaje es fijo. Es el único texto de la app que aparece en el peor
        // momento posible, y no puede depender de qué se le ocurra generar a un
        // modelo esa vez.
        //
        // El servidor tiene el mismo corte, con la misma lista: si éste no
        // dispara y aquél sí —una lista desactualizada—, la respuesta llega con
        // `cuidado` y termina igual, en `cerrarCon(…, fase: .cuidado)`.
        if Riesgo.haySenal(en: Transcripcion.soloVos(turnos)) {
            cerrarCon(Riesgo.mensaje, fase: .cuidado)
            return
        }

        fase = .pensando
        Task { await pedirTurno() }
    }

    /// Cortar la charla. Lo que quedó a medio decir entra como último turno.
    func terminar() {
        // Durante el mensaje de cuidado no hay orbe, y aunque lo hubiera: ese
        // mensaje se escucha entero. La pantalla de `.cuidado` tiene su propio
        // "Cerrar".
        guard fase != .cuidado else { return }
        #if DEBUG && targetEnvironment(simulator)
        if DemoDeLlamada.shared.enCurso { DemoDeLlamada.shared.terminar() }
        #endif
        devolverLoColgado(mas: captura.loQueQuedoSinDecir() ?? "")
        captura.frenar()
        voz.callar()
        silenciado = false
        guardar()
        fase = .cerrada
    }

    /// Le pide el próximo turno al compañero.
    private func pedirTurno() async {
        let mia = sesion
        let este = UUID()
        pedido = este
        suenaDesde = nil

        // LAYA SÓLO HABLA EN LLAMADA. Si escribiste —o dejaste un mensaje
        // grabado—, contesta por escrito y en silencio. Dusan lo pidió así:
        // «cuando use texto no quiero que hable la IA, sólo cuando esté en
        // llamada». Quien escribe suele estar en un lugar donde no puede, o no
        // quiere, que el teléfono se ponga a hablar.
        let hablada = modo == .llamada

        // Primero en vivo: el texto aparece mientras se escribe y, en llamada,
        // Bitácora empieza a hablar cuando tiene la primera oración. Si la conexión
        // en vivo no abre —un servidor que todavía no la tiene— se sigue por el
        // camino de siempre, que pide el turno entero. Con la voz natural
        // apagada, una llamada va directo por ese camino: ahí habla la voz de
        // iOS, que necesita el texto entero.
        if !hablada || Config.shared.vozNatural {
            if await pedirTurnoEnVivo(sesion: mia, pedido: este, hablada: hablada) { return }
            guard fase == .pensando, sesion == mia, pedido == este else { return }
        }

        let cliente = SyncClient(config: Config.shared.servidor)
        // El timbre viaja con el pedido: es lo que le dice al servidor que
        // adelante el audio de la primera frase mientras escribe el texto, en
        // vez de hacernos esperar el texto entero para recién ahí pedir la voz.
        // Con la voz natural apagada no va, y el servidor contesta sólo texto.
        let config = Config.shared
        let r = await cliente.turnoDeCharla(
            turnos: turnos.map { TurnoDeCharla(de: $0.de == .vos ? "vos" : "bitacora",
                                               texto: $0.texto) },
            dia: CalendarioView.hoyLogico(),
            timbre: hablada && config.vozNatural ? config.timbre.rawValue : nil,
            preparar: Navegacion.shared.preparandoVigente?.id,
            retoma: anterior?.dia)

        // Cortaste mientras esperaba. Va ANTES que el guard de red, y el orden
        // importa: al revés, un turno que además fallaba entraba por el camino
        // de error, hacía hablar a Bitácora sobre una charla ya cerrada, y escribía
        // ese texto en un borrador que ya era `nil` — o sea que se veía en
        // pantalla y no se guardaba en ningún lado.
        //
        // Y la sesión: si cortaste y arrancaste otra antes de que ésta llegara,
        // la fase puede volver a ser `.pensando` — pero de la charla nueva.
        guard fase == .pensando, sesion == mia, pedido == este else { return }

        // `nil` es que no llegamos al servidor; `ok: false` es que el servidor
        // no pudo generar el turno. Del lado tuyo son la misma cosa —Bitácora dejó
        // de contestar— y lo único que importa es que sepas que lo que dijiste
        // quedó guardado. Por eso los dos terminan igual: se dice la despedida
        // y se cierra la charla con todo lo hablado a salvo.
        guard let r, r.ok else {
            cerrarCon(r?.texto ?? MENSAJE_DE_CORTE, fase: .cerrada)
            return
        }
        // El corte de riesgo del servidor: el mensaje fijo, con la voz del
        // teléfono y el panel de cuidado, igual que el corte de acá.
        if r.cuidado == true {
            cerrarCon(r.texto, fase: .cuidado)
            return
        }

        turnos.append(Turno(de: .bitacora, texto: r.texto))
        anotar()
        guard hablada else {
            terminarTurnoEscrito()
            return
        }
        fase = .hablando
        bitacoraEmpezoASonar()
        voz.decir(r.texto, primerAudio: r.audio, fraseDelAudio: r.frase) { [weak self] in
            self?.bitacoraTerminoDeHablar()
        }
    }

    /// Lo que pasa cuando Bitácora termina de decir su turno.
    private func bitacoraTerminoDeHablar() {
        guard fase == .hablando else { return }
        // En llamada vuelve a escucharte; en suelto se queda esperando lo que
        // escribas o grabes, con el micrófono cerrado.
        if modo == .llamada {
            #if DEBUG && targetEnvironment(simulator)
            if DemoDeLlamada.shared.enCurso {
                siguienteFraseDeDemo()
                return
            }
            #endif
            if silenciado { fase = .escuchando; return }
            Task { await escucharOFrenar() }
        } else {
            captura.dejarDeVigilar()
            guardar()
            fase = .cerrada
        }
    }

    /// Bitácora contestó por escrito: no hay nada que esperar a que suene.
    private func terminarTurnoEscrito() {
        captura.dejarDeVigilar()
        guardar()
        fase = .cerrada
    }

    /// El turno, en vivo. Devuelve `false` si no llegó a empezar, y ahí quien
    /// llama prueba por el camino de siempre.
    ///
    /// Con `hablada` en falso llega sólo el texto. La fase se queda en
    /// `.pensando` mientras se escribe —los tres puntos siguen latiendo— y pasa
    /// derecho a `.cerrada` cuando termina: no hay voz que esperar.
    ///
    /// EL TEXTO APARECE MIENTRAS SE ESCRIBE y la voz suena mientras se
    /// sintetiza. El turno de Bitácora entra en `turnos` con la primera palabra y se
    /// va reemplazando por la versión más larga.
    ///
    /// TRES FINALES POSIBLES, y ninguno deja a la persona sin saber qué pasó:
    ///
    ///   · Llega el final del servidor: se anota el texto definitivo y se espera
    ///     a que termine de sonar. Si a la voz del servidor le faltó decir algo,
    ///     eso lo dice la voz de iOS.
    ///   · El servidor avisa que no pudo: la despedida fija, como siempre.
    ///   · La conexión se corta a mitad de turno: lo que llegó a escribirse
    ///     queda, y se cierra con la despedida. No se sigue como si nada con una
    ///     respuesta por la mitad.
    private func pedirTurnoEnVivo(sesion mia: UUID, pedido este: UUID, hablada: Bool) async -> Bool {
        let config = Config.shared
        let flujo = SyncClient(config: config.servidor).charlaEnVivo(
            turnos: turnos.map { TurnoDeCharla(de: $0.de == .vos ? "vos" : "bitacora",
                                               texto: $0.texto) },
            dia: CalendarioView.hoyLogico(),
            timbre: hablada ? config.timbre.rawValue : nil,
            preparar: Navegacion.shared.preparandoVigente?.id,
            retoma: anterior?.dia)

        /// Dónde quedó el turno de Bitácora en `turnos`, una vez que empezó.
        var lugar: Int?
        var hz = 24_000

        func vigente() -> Bool {
            sesion == mia && pedido == este && (fase == .pensando || fase == .hablando)
        }
        func escribir(_ texto: String) {
            if let i = lugar, turnos.indices.contains(i) {
                turnos[i] = Turno(de: .bitacora, texto: texto)
                return
            }
            turnos.append(Turno(de: .bitacora, texto: texto))
            lugar = turnos.count - 1
            guard hablada else { return }
            fase = .hablando
            // Todavía no suena nada: el micrófono sigue transcribiendo, por si
            // no habías terminado. Se deja de transcribir con el primer audio.
            suenaDesde = nil
            voz.empezarEnVivo { [weak self] in self?.bitacoraTerminoDeHablar() }
        }

        do {
            for try await trama in flujo {
                // Interrumpiste, cortaste, o ya hay otro turno pedido. Dejar de
                // leer cierra la conexión, y con eso el servidor corta lo suyo.
                guard vigente() else { return true }

                switch trama {
                case .frecuencia(let f):
                    hz = f
                case .texto(let t):
                    if !t.isEmpty { escribir(t) }
                case .audio(let pcm):
                    guard hablada, lugar != nil else { continue }
                    if suenaDesde == nil { bitacoraEmpezoASonar() }
                    #if DEBUG && targetEnvironment(simulator)
                    if DemoDeLlamada.shared.enCurso { DemoDeLlamada.shared.registrar(pcm, hz: hz) }
                    #endif
                    voz.sonar(pcm, hz: hz)
                case .cuidado(let texto):
                    // El servidor cortó por riesgo. No debería haber turno a
                    // medio escribir —llega en lugar del turno—, pero si lo
                    // hubiera, lo que queda en la charla es el mensaje fijo.
                    if let i = lugar, turnos.indices.contains(i) { turnos.remove(at: i) }
                    voz.callar()
                    cerrarCon(texto, fase: .cuidado)
                    return true
                case .fin(let ok, let texto, let faltaDecir):
                    guard ok else {
                        // El turno a medio escribir se saca: lo que queda en la
                        // charla es la despedida, no una respuesta trunca.
                        if let i = lugar, turnos.indices.contains(i) { turnos.remove(at: i) }
                        voz.callar()
                        cerrarCon(texto, fase: .cerrada)
                        return true
                    }
                    escribir(texto)
                    anotar()
                    guard hablada else {
                        terminarTurnoEscrito()
                        return true
                    }
                    // Sin audio del servidor, lo que viene es la voz de iOS:
                    // también suena, y también hay que dejar de transcribir.
                    if suenaDesde == nil { bitacoraEmpezoASonar() }
                    voz.cerrarEnVivo(texto: texto, faltaDecir: faltaDecir)
                    return true
                }
            }
            // El servidor cerró sin mandar el final.
            throw URLError(.networkConnectionLost)
        } catch {
            guard vigente() else { return true }
            // Todavía no había salido nada: se puede pedir de nuevo, entero.
            guard lugar != nil else { return false }
            voz.callar()
            cerrarCon(MENSAJE_DE_CORTE, fase: .cerrada)
            return true
        }
    }

    /// Cierra diciendo algo. Se usa para la regla 6 y para los cortes.
    ///
    /// Habla SIEMPRE con la voz del teléfono, aunque la voz natural esté
    /// prendida. Los dos mensajes que pasan por acá son fijos y los escribió la
    /// app: mandarlos a sintetizar afuera le contaría a una empresa que el
    /// detector de riesgo se disparó, o que la charla se cortó. Además son los
    /// dos momentos en que menos se puede esperar a que baje un audio —uno de
    /// ellos es el peor momento posible— y en el de los cortes es probable que
    /// justamente no haya red.
    private func cerrarCon(_ mensaje: String, fase final: Fase) {
        devolverLoColgado()
        turnos.append(Turno(de: .bitacora, texto: mensaje))
        captura.frenar()
        anotar()
        // Durante la despedida no se puede interrumpir, y no es por prolijidad:
        // `interrumpir()` llama a `voz.callar()`, que suelta el callback, y ese
        // callback es el que guarda. Un toque en la mitad de la despedida
        // dejaba la charla sin guardar y encima reabierta, con el mensaje de
        // corte ya adentro.
        cerrando = true
        // La fase final se fija ACÁ, no al terminar de hablar. Para el mensaje
        // de cuidado eso es lo que saca el orbe de la pantalla mientras suena:
        // con `.hablando` seguía `activa`, se dibujaba, y un toque lo callaba a
        // la mitad y terminaba en "Guardado · Otra vez" — el panel de cuidado
        // no aparecía nunca. Justo ese mensaje es el único que no tiene que
        // competir con nada. Para los cortes comunes, `.hablando` está bien.
        // Fuera de una llamada tampoco se dice: se muestra. Es la misma regla
        // que para los turnos de Bitácora, y vale también para el mensaje de
        // cuidado, que queda en pantalla con su panel.
        guard modo == .llamada else {
            cerrando = false
            guardar()
            fase = final
            return
        }
        fase = final == .cuidado ? .cuidado : .hablando
        voz.decirSinSalir(mensaje) { [weak self] in
            self?.cerrando = false
            self?.guardar()
            self?.fase = final
        }
    }

    /// Empieza una conversación nueva, desde cero. La anterior se cierra y se
    /// sube tal como quedó: sigue en el calendario. Desde el inicio, escribir,
    /// dictar o llamar empieza una nueva; «Seguir la conversación de hoy»
    /// retoma la que había (lo pidió Dusan el 19 de octubre).
    func nuevaConversacion() {
        guard !activa else { return }
        volverAEmpezar()
    }

    /// Cierra la conversación de hoy de verdad y deja la pantalla limpia. Lo
    /// usa el «Cerrar» del panel de cuidado; más adelante, «Nueva conversación».
    func volverAEmpezar() {
        if let borrador { outbox.cerrarBorrador(borrador) }
        cerrando = false
        silenciado = false
        duracionPrevia = 0
        tramoDesde = nil
        turnos = []
        borrador = nil
        anterior = nil
        colgado = nil
        suenaDesde = nil
        fase = .inactiva
    }

    // MARK: - Guardado

    /// Reescribe el borrador con lo que va de charla. Después de CADA turno.
    private func anotar() {
        guard let borrador else { return }
        // Lo colgado también es algo que dijiste: va al borrador aunque todavía
        // no haya vuelto a ser un turno. Si la app se muere ahora, está en disco.
        let propios = Array(turnos.dropFirst(anterior?.cuantos ?? 0))
        let todos = colgado.map { propios + [Turno(de: .vos, texto: $0)] } ?? propios
        outbox.anotar(borrador,
                      transcripcion: Transcripcion.de(todos),
                      // `max(0, …)`: si el reloj del teléfono se corrió hacia
                      // atrás en medio de la charla, un negativo era 400 y la
                      // entrada quedaba rechazada para siempre.
                      duracionSeg: duracionHastaAhora)
    }

    /// `max(0, …)`: si el reloj se corrió hacia atrás, un negativo era un 400.
    private var duracionHastaAhora: Double {
        duracionPrevia + max(0, tramoDesde.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// Guarda lo que va y lo manda al servidor, SIN cerrar la conversación:
    /// la de hoy sigue abierta hasta que cambie el día (`revisarElDia`).
    /// Antes cerraba el borrador, y el próximo mensaje empezaba una charla nueva
    /// desde cero.
    private func guardar() {
        anotar()
        // Termina este tramo: lo que duró queda sumado.
        duracionPrevia = duracionHastaAhora
        tramoDesde = nil
        if let borrador { outbox.sincronizar(borrador) }
    }

    // MARK: - Dictado y silencio

    /// Descarta lo que se estaba dictando, sin mandarlo.
    func cancelarDictado() {
        guard modo == .suelto, fase == .escuchando else { return }
        captura.frenar()
        colgado = nil
        fase = turnos.isEmpty ? .inactiva : .cerrada
    }

    /// Silencia o vuelve a prender el micrófono en la llamada.
    func silenciar() {
        guard enLlamada else { return }
        silenciado.toggle()
        if silenciado {
            captura.frenar()
            captura.dejarDeVigilar()
        } else if fase == .escuchando {
            Task { await escucharOFrenar() }
        }
    }
}

/// Lo que se dice cuando no llegamos al servidor.
///
/// Es la misma frase que manda el servidor cuando falla de su lado. Está
/// duplicada a propósito: si el teléfono no llega, no hay de dónde traerla.
let MENSAJE_DE_CORTE =
  "Se me cortó aquí, discúlpame. Lo que me contaste quedó guardado. "
  + "Si quieres, seguimos en un rato."
