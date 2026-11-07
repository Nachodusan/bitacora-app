import SwiftData
import SwiftUI

struct ConversacionView: View {
    let outbox: Outbox
    @State private var charla: Conversacion
    @State private var mostrarAjustes = false
    @State private var mostrarApuntes = false
    @State private var mostrarHistorial = false
    @State private var charlaVieja: EntradaLocal?
    /// La herramienta abierta («Ponerle nombre», «Calmarme ya»).
    @State private var herramienta: Herramienta?
    /// Los anillos del saludo y los de la llamada son el mismo objeto: al
    /// llamar, bajan y se transforman (26/10/2026).
    @Namespace private var marca
    /// El gesto sobre los anillos del inicio (26/10/2026): cuánto los arrastró,
    /// ya con la resistencia aplicada. Arriba escribe, abajo llama.
    @State private var arrastre: CGFloat = 0
    /// Escribiendo desde el inicio: el campo aparece aunque no haya charla.
    @State private var modoEscribir = false
    /// Mantener presionado el anillo abre el menú: Consultas, Conversaciones,
    /// Notas (26/10/2026).
    @State private var menuDelAnillo = false
    /// Cuántas notas sueltas hay. Viven en otro archivo (`AlmacenDeApuntes`):
    /// se cuentan al volver al inicio.
    @State private var cuantasNotas = 0
    /// El dedo está sobre el anillo: se encienden las dos luces.
    @State private var presionando = false
    private static let umbral: CGFloat = 64
    /// Cuántos turnos había cuando se usó o se cerró la última sugerencia: no
    /// se vuelve a ofrecer la misma hasta que haya algo nuevo.
    @State private var sugerenciaVista = -1
    /// Si la herramienta se abrió en plena llamada: la llamada quedó en pausa
    /// (micrófono silenciado) y hay que retomarla al volver.
    @State private var llamadaEnPausa = false
    @State private var escrito = ""
    @FocusState private var escribiendo: Bool
    /// Desde cuándo se está dictando, para el contador de la barra.
    @State private var dictandoDesde: Date?
    private var config = Config.shared
    /// «Preparar», desde la tarjeta de la próxima consulta en Mi expediente.
    private var navegacion = Navegacion.shared
    private var agenda = Agenda.shared
    @Environment(\.scenePhase) private var escena

    @Query(sort: \EntradaLocal.creadoEn, order: .reverse)
    private var entradas: [EntradaLocal]

    init(outbox: Outbox, contexto: ModelContext) {
        self.outbox = outbox
        _charla = State(initialValue: Conversacion(outbox: outbox))
    }

    /// Saliste al inicio. La conversación de hoy NO se cierra ni se borra:
    /// se vuelve a ella con la tarjeta del inicio o escribiendo de nuevo.
    @State private var enInicio = false

    /// Va el saludo en vez de la conversación: todavía no se dijo nada hoy,
    /// o saliste al inicio.
    private var vacia: Bool {
        (enInicio && !charla.activa) || (charla.turnos.isEmpty && charla.parcial.isEmpty && !charla.activa)
    }
    private var hayCharlaHoy: Bool { !charla.turnos.isEmpty }
    /// Lo último que dijo Bitácora, para recordar dónde quedó la charla.

    /// Se está dictando un mensaje suelto.
    private var dictando: Bool { charla.modo == .suelto && charla.fase == .escuchando }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Fondo()
                // La luz va DEBAJO de la conversación, sólo en la llamada.
                if charla.enLlamada { luz }
                if vacia {
                    saludo
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 80)
                        .contentShape(Rectangle())
                        .simultaneousGesture(bajarParaVolver)
                        .transition(.opacity)
                } else {
                    conversacion
                }
                abajo
                if menuDelAnillo {
                    Color.black.opacity(0.55).ignoresSafeArea()
                        .onTapGesture { cerrarMenu() }
                        .transition(.opacity)
                }
                anillosViajeros
                // El panel de charlas anteriores, desde la izquierda, como en
                // Claude o Gemini. Va por encima de todo, también de la barra.
                // Una charla de hoy se retoma; una de otro día se abre para leer.
                CajonDeCharlas(abierto: $mostrarHistorial) { e in
                    if charla.retomar(e) {
                        withAnimation(.easeInOut(duration: 0.25)) { enInicio = false }
                    } else {
                        charlaVieja = e
                    }
                }
            }
            .animation(Self.viaje, value: vacia)
            // Desde el 19 de octubre (propuesta D) la barra de pestañas queda
            // siempre, como en el resto de la app. Se va sólo en la llamada,
            // que es la pantalla entera.
            .toolbar(charla.enLlamada || mostrarHistorial ? .hidden : .visible, for: .tabBar)
            .toolbar(mostrarHistorial ? .hidden : .visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // En el inicio la esquina queda limpia (27/10/2026): las charlas
                // anteriores se abren desde el menú del anillo. Sólo dentro de
                // una charla aparece la cruz para volver.
                ToolbarItem(placement: .topBarLeading) {
                    if !vacia && !charla.enLlamada && charla.fase != .cuidado {
                        // Salir al inicio. La charla queda guardada tal cual.
                        Button { escribiendo = false; withAnimation(.easeInOut(duration: 0.25)) { enInicio = true } } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(Paleta.tintaSuave)
                        }
                        .accessibilityLabel("Salir al inicio")
                    }
                }
            }
            .sheet(isPresented: $mostrarAjustes) { AjustesView() }
            .sheet(isPresented: $mostrarApuntes) { ApuntesView() }
            .fullScreenCover(item: $herramienta) { h in
                switch h {
                case .nombrar:
                    PonerleNombreView(turnos: charla.turnos, alTerminar: volverDeHerramienta)
                case .calmarme:
                    CalmarmeView(alTerminar: volverDeHerramienta)
                }
            }
            .sheet(item: $charlaVieja) { e in
                NavigationStack {
                    CharlaGuardadaView(entrada: e)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { charlaVieja = nil } } }
                }
            }
            // Si pasaron las 4 de la mañana con la app abierta, la charla de
            // ayer se cierra y la pantalla queda para hoy.
            // Escribir, dictar o llamar desde el inicio vuelve a la charla.
            .onChange(of: charla.activa) { _, activa in if activa { enInicio = false } }
            .onChange(of: charla.turnos.count) { enInicio = false }
            // Escribir desde el inicio: si se cierra el teclado sin escribir
            // nada, vuelve el inicio con el anillo.
            .onChange(of: escribiendo) { _, ahora in
                if !ahora, escrito.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, vacia {
                    withAnimation(.easeInOut(duration: 0.3)) { modoEscribir = false }
                }
            }
            .onChange(of: charla.activa) { _, activa in if activa { modoEscribir = false } }
            .onAppear(perform: contarNotas)
            .onChange(of: mostrarApuntes) { _, abierta in if !abierta { contarNotas() } }
            .onChange(of: escena) { _, nueva in
                if nueva == .active { charla.revisarElDia(); contarNotas() }
            }
            .onChange(of: charla.fase) { _, f in
                if dictando { if dictandoDesde == nil { dictandoDesde = Date() } } else { dictandoDesde = nil }
                _ = f
            }
        }
    }

    // MARK: - El inicio: todavía no hablaron hoy

    /// La marca, una pregunta que cambia con la hora, y las consultas del mes.
    /// Desde el 26/10/2026 no hay barra abajo: se presiona el anillo y se
    /// desliza hacia arriba para escribir o hacia abajo para hablar.
    private var saludo: some View {
        VStack(spacing: 16) {
            // El lugar de los anillos; los dibuja `anillosViajeros`. El gesto va
            // acá: se presiona el anillo y se desliza, como desbloquear.
            Color.clear.frame(width: 180, height: 180)
                .matchedGeometryEffect(id: "anillos", in: marca, isSource: true)
                .contentShape(Circle())
                // Al presionar se encienden las dos luces (Escribir arriba,
                // Hablar abajo); dos toques abren el menú.
                .overlay { objetivos }
                // Los dos toques van como gesto principal y el de mantener
                // presionado en paralelo: al revés, la espera del segundo se
                // quedaba con los toques y el menú no abría.
                .gesture(TapGesture(count: 2).onEnded {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
                        presionando = false
                        menuDelAnillo = true
                    }
                })
                .simultaneousGesture(gestoDelAnillo)
                .accessibilityElement()
                .accessibilityLabel("Bitácora")
                .accessibilityHint("Mantén presionado y desliza hacia arriba para escribir o hacia abajo para hablar. Dos toques abren el menú.")
                .accessibilityAction(named: "Escribir") { abrirEscritura() }
                .accessibilityAction(named: "Hablar") { llamarDesdeElInicio() }
                .accessibilityAction(named: "Consultas") { elegir(.consultas) }
                .accessibilityAction(named: "Conversaciones") { elegir(.conversaciones) }
                .accessibilityAction(named: "Notas") { elegir(.notas) }
            Text(pregunta)
                .font(.dicha(.title))
                .foregroundStyle(Paleta.tinta)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                // Con el menú abierto o el dedo sobre el anillo, la pregunta deja
                // el lugar a las burbujas o a la luz de «Hablar».
                .opacity(menuDelAnillo || presionando ? 0 : 1)
        }
    }

    /// «¿Qué trajo la noche, Tomás?», según la hora.
    private var pregunta: String {
        let hora = Calendar.current.component(.hour, from: Date())
        let momento = hora < 5 ? "la noche" : hora < 12 ? "la mañana" : hora < 20 ? "la tarde" : "la noche"
        let nombre = config.nombre.trimmingCharacters(in: .whitespaces)
        return nombre.isEmpty ? "¿Qué trajo\n\(momento)?" : "¿Qué trajo\n\(momento), \(nombre)?"
    }

    /// Los anillos del saludo y de la llamada son UNA sola vista que viaja entre
    /// los dos lugares (`Color.clear` con `isSource`). Antes eran dos que se
    /// fundían, y SwiftUI estiraba una como imagen: se veía pixelado. Ésta se
    /// redibuja en cada cuadro a su tamaño real, y como es la misma, pasa de
    /// tranquila a revuelta (y vuelve) sin cortes.
    @ViewBuilder
    private var anillosViajeros: some View {
        if vacia || charla.enLlamada {
            Anillos(modo: charla.enLlamada ? modoDeLaLuz : nil, nivel: nivelDeLaLuz,
                    ultimaPalabra: charla.voz.ultimaPalabraEn, tamano: nil,
                    orbitas: charla.enLlamada ? [] : orbitas,
                    tiron: charla.enLlamada || !presionando ? 0 : Double(arrastre / Self.umbral))
                .scaleEffect(charla.enLlamada ? 1 : (menuDelAnillo ? 1.25 : 1 + abs(arrastre) / 900))
                .allowsHitTesting(false)
                .overlay { if menuDelAnillo && !charla.enLlamada { menuAlrededor } }
                .matchedGeometryEffect(id: "anillos", in: marca, properties: .frame, isSource: false)
                .offset(y: charla.enLlamada ? 0 : arrastre)
                .transition(.opacity)
        }
    }

    // MARK: - El gesto del anillo

    /// Mantener presionado el anillo un segundo y deslizar: hacia arriba se
    /// abre el campo para escribir (con el dictado en el micrófono), hacia abajo
    /// arranca la llamada. Sigue al dedo con resistencia, vibra al pasar el
    /// umbral, y si se suelta antes vuelve a su lugar.
    private var gestoDelAnillo: some Gesture {
        // Primero hay que mantener presionado (26/10/2026, lo pidió Dusan): así
        // un toque o los dos toques del menú nunca encienden las luces por
        // accidente. Recién después de la espera se puede deslizar.
        LongPressGesture(minimumDuration: Self.espera, maximumDistance: 14)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { valor in
                guard case .second(true, let drag) = valor else { return }
                if !presionando {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { presionando = true }
                }
                guard let drag else { return }
                let antes = arrastre
                let y = drag.translation.height
                // Resistencia: cuanto más lejos, menos avanza.
                arrastre = (y >= 0 ? 1 : -1) * 140 * (1 - exp(-abs(y) / 170))
                if abs(antes) < Self.umbral, abs(arrastre) >= Self.umbral {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.3)) { presionando = false }
                let final = arrastre
                if final <= -Self.umbral {
                    abrirEscritura()
                    withAnimation(.spring(duration: 0.5, bounce: 0.2)) { arrastre = 0 }
                } else if final >= Self.umbral, modoEscribir {
                    // Escribiendo, hacia abajo es volver al saludo, no llamar.
                    cerrarEscritura()
                    withAnimation(.spring(duration: 0.45, bounce: 0.35)) { arrastre = 0 }
                } else if final >= Self.umbral {
                    // El anillo sigue de largo hacia la llamada: el viaje lo
                    // lleva desde donde lo soltaste.
                    llamarDesdeElInicio()
                    withAnimation(Self.viaje) { arrastre = 0 }
                } else {
                    withAnimation(.spring(duration: 0.45, bounce: 0.35)) { arrastre = 0 }
                }
            }
    }

    /// Cuánto hay que mantener presionado el anillo para que salgan las luces.
    private static let espera: Double = 0.5

    private func abrirEscritura() {
        withAnimation(.easeInOut(duration: 0.3)) { modoEscribir = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { escribiendo = true }
    }

    /// Volver de escribir al saludo, sin mandar nada (27/10/2026).
    private func cerrarEscritura() {
        escribiendo = false
        withAnimation(.easeInOut(duration: 0.3)) { modoEscribir = false }
    }

    /// Escribiendo desde el inicio, deslizar hacia abajo en cualquier parte
    /// vuelve al saludo, como cerrar una hoja. No hace falta presionar el anillo.
    private var bajarParaVolver: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                guard modoEscribir, vacia, v.translation.height > 80,
                      v.translation.height > abs(v.translation.width) * 1.5 else { return }
                cerrarEscritura()
            }
    }

    private func llamarDesdeElInicio() {
        escribiendo = false
        modoEscribir = false
        desdeElInicio()
        charla.arrancar()
    }

    // MARK: - El menú del anillo

    enum Opcion { case consultas, conversaciones, notas }

    private var consultasDeEsteMes: Int {
        Evento.consultasDelMes(en: agenda.eventos, ahora: Navegacion.ahora()).count
    }

    private var charlasDeHoy: Int {
        let hoy = CalendarioView.hoyLogico()
        return entradas.filter { $0.diaLogico == hoy && $0.transcripcion.contains("Vos:") }.count
    }

    /// Los puntitos: uno por cada cosa que hay, del color de su opción.
    private var orbitas: [Color] {
        var c: [Color] = []
        if consultasDeEsteMes > 0 { c.append(Paleta.verde) }
        if charlasDeHoy > 0 || !charla.turnos.isEmpty { c.append(Paleta.musgo) }
        if cuantasNotas > 0 { c.append(Paleta.nota) }
        return c
    }

    /// Las tres burbujas alrededor del anillo agrandado.
    private var menuAlrededor: some View {
        ZStack {
            burbuja("Consultas", detalle: consultasDeEsteMes == 1 ? "1 este mes" : "\(consultasDeEsteMes) este mes",
                    color: Paleta.verde) { elegir(.consultas) }
                .offset(x: -96, y: -112)
            burbuja("Conversaciones", detalle: charlasDeHoy == 1 ? "1 hoy" : "\(charlasDeHoy) hoy",
                    color: Paleta.musgo) { elegir(.conversaciones) }
                .offset(x: 96, y: -112)
            burbuja("Notas", detalle: cuantasNotas == 1 ? "1 nota" : "\(cuantasNotas) notas",
                    color: Paleta.nota) { elegir(.notas) }
                .offset(y: 140)
        }
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func burbuja(_ titulo: String, detalle: String, color: Color,
                         accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo)
                        .font(.redonda(.subheadline, .semibold))
                        .foregroundStyle(Paleta.tinta)
                    Text(detalle)
                        .font(.redonda(.caption2))
                        .foregroundStyle(Paleta.tintaTenue)
                }
            }
            .fixedSize()
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background {
                Capsule().fill(Paleta.carta)
                    .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }

    private func cerrarMenu() {
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { menuDelAnillo = false }
    }

    /// Consultas: la próxima del mes en el calendario, o Mi espacio si no hay.
    /// Conversaciones: la de hoy si hay, si no las anteriores. Notas: el cuaderno.
    private func elegir(_ o: Opcion) {
        cerrarMenu()
        switch o {
        case .consultas:
            let ahora = Navegacion.ahora()
            let consultas = Evento.consultasDelMes(en: agenda.eventos, ahora: ahora)
            if let e = consultas.first(where: { $0.momento > ahora }) ?? consultas.last {
                navegacion.verEnElCalendario(e.dia)
            } else {
                navegacion.pestana = .evaluaciones
            }
        case .conversaciones:
            // Siempre el historial del día (27/10/2026): antes, con una charla
            // abierta hoy, saltaba directo a ella.
            withAnimation(.spring(duration: 0.32)) { mostrarHistorial = true }
        case .notas:
            mostrarApuntes = true
        }
    }

    private func contarNotas() {
        guard let contenedor = AlmacenDeApuntes.contenedor else { return }
        let contexto = ModelContext(contenedor)
        cuantasNotas = (try? contexto.fetchCount(FetchDescriptor<Apunte>())) ?? 0
    }

    /// Las dos luces que aparecen al presionar el anillo (26/10/2026): arriba
    /// «Escribir», abajo «Hablar». La del lado hacia el que vas crece y brilla
    /// más; soltar sobre una la abre. Reemplazaron a las flechitas que
    /// respiraban: en reposo el inicio queda limpio.
    private var objetivos: some View {
        ZStack {
            luz(icono: "ellipsis.message", texto: "Escribir", hacia: -arrastre)
                .offset(y: -178)
            luz(icono: modoEscribir ? "chevron.down" : "dot.radiowaves.left.and.right",
                texto: modoEscribir ? "Volver" : "Hablar", hacia: arrastre)
                .offset(y: 178)
        }
        .opacity(presionando && !menuDelAnillo ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// Cada luz es un anillo chico de la marca (27/10/2026): tres curvas de
    /// nivel finas, casi redondas, que se mueven despacio y se cruzan, con el
    /// ícono adentro. La del lado hacia el que vas crece y se enciende.
    private func luz(icono: String, texto: String, hacia: CGFloat) -> some View {
        let f = Double(min(1, max(0, hacia / Self.umbral)))
        let semilla = Double(icono.count)
        return VStack(spacing: 10) {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle()
                        .fill(Marca.durazno)
                        .frame(width: 60, height: 60)
                        .blur(radius: 24)
                        .opacity(0.06 + 0.25 * f)
                    CurvaDeNivel(fase: t * 1.3 + semilla, onda: 0.05, corrida: CGSize(width: 2, height: 1))
                        .stroke(Marca.durazno.opacity(0.7 + 0.3 * f), lineWidth: 1.1)
                        .frame(width: 78, height: 72)
                    CurvaDeNivel(fase: -t * 1.0 + semilla * 2, onda: 0.06, corrida: CGSize(width: -2, height: 2))
                        .stroke(Marca.durazno.opacity(0.4 + 0.3 * f), lineWidth: 1)
                        .frame(width: 66, height: 61)
                    CurvaDeNivel(fase: t * 0.8 + semilla * 3, onda: 0.07, corrida: CGSize(width: 1, height: -2))
                        .stroke(Marca.durazno.opacity(0.25 + 0.25 * f), lineWidth: 1)
                        .frame(width: 90, height: 84)
                }
            }
            .frame(width: 94, height: 88)
            .overlay {
                Image(systemName: icono)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Marca.durazno)
            }
            Text(texto)
                .font(.redonda(.footnote, .semibold))
                .foregroundStyle(Marca.duraznoTexto)
        }
        .scaleEffect(0.95 + 0.2 * f)
        .fixedSize()
    }

    /// Entrar a la llamada o salir de ella es un viaje: los anillos bajan desde
    /// el saludo hasta encima de «Te escucho» (o suben al colgar), con un
    /// resorte suave. El resto de los cambios de pantalla siguen siendo cortos.
    static let viaje = Animation.spring(duration: 0.9, bounce: 0.12)

    // MARK: - Las herramientas

    /// Qué herramienta ofrecer debajo de la respuesta de Bitácora, si alguna:
    /// la que pide lo último que dijiste (`Herramienta.sugerida`). Sólo con la
    /// respuesta ya dada, fuera del cuidado, y una vez por turno.
    private var sugerencia: Herramienta? {
        guard charla.fase != .cuidado, !charla.activa || charla.enLlamada,
              charla.turnos.last?.de == .bitacora, sugerenciaVista != charla.turnos.count,
              let respuesta = charla.turnos.last,
              let dicho = charla.turnos.last(where: { $0.de == .vos })
        else { return nil }
        // Lo que pide lo que dijiste, o lo que Bitácora te acaba de ofrecer.
        return Herramienta.sugerida(para: dicho.texto) ?? Herramienta.ofrecida(en: respuesta.texto)
    }

    private func sugerenciaDeHerramienta(_ h: Herramienta) -> some View {
        HStack(spacing: 10) {
            Button { abrirHerramienta(h) } label: {
                HStack(spacing: 10) {
                    Image(systemName: h == .calmarme ? "wind" : "tag")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Marca.durazno)
                    Text(h.invitacion)
                        .font(.redonda(.subheadline, .semibold))
                        .foregroundStyle(Paleta.tinta)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background {
                    Capsule().fill(Marca.durazno.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Marca.durazno.opacity(0.4), lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            Button { withAnimation { sugerenciaVista = charla.turnos.count } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Paleta.tintaTenue)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Ahora no")
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// En plena llamada, la herramienta no la corta: la pone en pausa. Bitácora
    /// deja de hablar y el micrófono se silencia mientras eliges o respiras; al
    /// volver, la llamada sigue donde estaba (26/10/2026, lo pidió Dusan).
    private func abrirHerramienta(_ h: Herramienta) {
        sugerenciaVista = charla.turnos.count
        llamadaEnPausa = false
        if charla.enLlamada {
            charla.interrumpir()
            if !charla.silenciado { charla.silenciar(); llamadaEnPausa = true }
        }
        herramienta = h
    }

    /// Lo que se hizo en la herramienta vuelve como un turno tuyo, y si la
    /// llamada estaba en pausa, se retoma.
    private func volverDeHerramienta(_ texto: String?) {
        let retomar = llamadaEnPausa
        llamadaEnPausa = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if retomar, charla.enLlamada, charla.silenciado { charla.silenciar() }
            guard let texto else { return }
            enInicio = false
            charla.enviarTexto(texto)
        }
    }

    // MARK: - Arriba: la conversación

    private var conversacion: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let consulta = navegacion.preparandoVigente {
                        avisoDePreparar(consulta)
                    }
                    ForEach(Array(charla.turnos.enumerated()), id: \.offset) { i, turno in
                        globo(turno)
                            .id(i)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    // En llamada la sugerencia va abajo, junto a los anillos.
                    if !charla.enLlamada, let s = sugerencia { sugerenciaDeHerramienta(s) }
                    // Lo que estás diciendo ahora, todavía sin cerrar el turno.
                    if !charla.parcial.isEmpty {
                        globo(Turno(de: .vos, texto: charla.parcial), tentativo: true)
                            .id("parcial")
                    }
                    if case .noDisponible(let motivo) = charla.captura.estado {
                        aviso(motivo)
                    }
                    // El colchón de abajo ES el ancla a la que se baja, y no un
                    // margen aparte. Estuvo como margen, con el ancla arriba de
                    // él: al bajar "hasta el fondo" la pantalla se detenía en el
                    // ancla y el margen quedaba sin recorrer, así que las últimas
                    // líneas terminaban justo debajo de los botones. En llamada
                    // era lo que Dusan veía: la respuesta de Bitácora tapada por
                    // «Te escucho» y por la cruz.
                    Color.clear.frame(height: colchonDeAbajo).id("fondo")
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .animation(.spring(duration: 0.35), value: charla.turnos.count)
            }
            .mask { desvanecidoDeAbajo.ignoresSafeArea(edges: .top) }
            .onChange(of: charla.turnos.count) { bajar(scroll) }
            .onChange(of: charla.parcial) { bajar(scroll) }
            // El turno de Bitácora llega en vivo: el texto crece sin que cambie la
            // cantidad de turnos, y sin esto la pantalla se quedaba donde estaba
            // mientras la respuesta seguía escribiéndose por debajo del borde.
            .onChange(of: charla.turnos.last?.texto) { bajar(scroll) }
            .onChange(of: charla.enLlamada) { bajar(scroll) }
        }
    }

    /// Arriba de la charla, mientras se prepara una consulta: cuál es, y cómo
    /// dejar de prepararla. Sin esto, el modo quedaba invisible y no se sabía
    /// por qué Bitácora hablaba de la consulta.
    private func avisoDePreparar(_ consulta: Evento) -> some View {
        HStack(spacing: 12) {
            Sillon()
                .frame(width: 22, height: 22)
                .foregroundStyle(Paleta.musgo)
            // Como la tarjeta de Mi expediente: el rótulo, cuándo, y qué hacer.
            VStack(alignment: .leading, spacing: 2) {
                Text("Preparando tu consulta")
                    .font(.redonda(.caption))
                    .foregroundStyle(Paleta.tintaTenue)
                Text(Agenda.cuando(consulta))
                    .font(.redonda(.headline))
                    .foregroundStyle(Paleta.tinta)
                Text("Cuéntale qué quieres llevarle, escribiendo o en llamada.")
                    .font(.redonda(.caption))
                    .foregroundStyle(Paleta.tintaSuave)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button { navegacion.preparando = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Paleta.tintaSuave)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dejar de preparar la consulta")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .carta(radio: 16)
        .padding(.bottom, 4)
    }

    private func bajar(_ scroll: ScrollViewProxy) {
        withAnimation { scroll.scrollTo("fondo", anchor: .bottom) }
    }

    /// Cuánto ocupa lo que flota abajo, sin contar el área segura.
    ///
    /// En llamada son el estado y la cruz; si no, el compositor de una línea.
    /// Son medidas de lo que dibujan `enLlamada` y `compositor`: si cambian
    /// allá, cambian acá.
    private var altoDeLoDeAbajo: CGFloat { charla.enLlamada ? 128 + Self.anillosEnLlamada + 14 : 70 }
    private static let anillosEnLlamada: CGFloat = 150

    /// El tramo en que el texto se va apagando antes de llegar a los botones.
    private let entradaDelDesvanecido: CGFloat = 64

    /// Lo que hay que dejar libre al final de la conversación para que la última
    /// línea se lea entera, por encima del desvanecido.
    private var colchonDeAbajo: CGFloat { altoDeLoDeAbajo + entradaDelDesvanecido + 6 }

    /// El texto se desvanece al acercarse a los botones de abajo.
    ///
    /// Arriba ya pasaba: lo que sube por detrás del título se va apagando, y eso
    /// lo hace iOS solo. Abajo no hay barra del sistema que lo haga, así que el
    /// texto llegaba entero hasta el borde y se cruzaba con el estado de la
    /// llamada y con la cruz. Dusan pidió lo mismo que arriba.
    ///
    /// Es una máscara y no un degradado pintado encima: lo que queda detrás del
    /// texto es la luz de la voz, y un degradado del color del fondo la taparía.
    private var desvanecidoDeAbajo: some View {
        let zona = altoDeLoDeAbajo + entradaDelDesvanecido
        return VStack(spacing: 0) {
            Rectangle()
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .clear, location: entradaDelDesvanecido / zona),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
                .frame(height: zona)
        }
        .animation(Self.viaje, value: charla.enLlamada)
    }

    // La pantalla vacía queda vacía. Había un saludo grande —"Contame cómo
    // viene el día"— con una línea abajo explicando los tres botones. Dusan lo
    // sacó, y tiene sentido: es un cartel que se lee una vez y después estorba
    // todas las demás. Lo que hay que hacer ya está dibujado abajo.

    private func aviso(_ texto: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Paleta.bitacora)
            Text(texto)
                .font(.redonda(.footnote))
                .foregroundStyle(Paleta.tintaSuave)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Paleta.bitacora.opacity(0.12))
        }
        .padding(.top, 4)
    }

    /// Un turno, dibujado como en todos lados (`TurnoDibujado`).
    private func globo(_ turno: Turno, tentativo: Bool = false) -> some View {
        TurnoDibujado(turno: turno, tentativo: tentativo)
    }

    // MARK: - Abajo: el horizonte y la barra

    /// Lo único que hay debajo de la conversación: un resplandor que sube desde
    /// el borde y una línea de texto que es el botón. Lo que había —esfera,
    /// anillos, etiquetas, botón de "Otra vez", cápsula de estado— se comía
    /// media pantalla.
    @ViewBuilder
    private var abajo: some View {
        if charla.fase == .cuidado {
            // Regla 6: acá no va luz ni botón de seguir hablando.
            panelDeCuidado
        } else if let traba = motivoParaNoHablar, !charla.activa {
            // Sin servidor no hay Bitácora: nadie contesta. Se corta acá y se dice
            // por qué, en vez de dejar hablar al vacío. Mira `!charla.activa` a
            // propósito: si el servidor se cae en medio de una charla, esa
            // charla TERMINA y se guarda.
            sinServidor(traba)
        } else if vacia && !modoEscribir && !charla.activa {
            // En el inicio no hay barra: se escribe o se llama desde el anillo.
            Text("Mantén presionado el anillo  ·  dos toques para el menú")
                .font(.redonda(.footnote))
                .foregroundStyle(Paleta.tintaTenue)
                .opacity(menuDelAnillo ? 0 : 1)
                .padding(.bottom, 26)
                .accessibilityHidden(true)
        } else {
            barra
        }
    }

    /// La luz de la voz: los bordes de la pantalla. Hasta el 26/10/2026 Ajustes
    /// dejaba elegir entre ésta y Horizonte, un resplandor desde abajo; Dusan
    /// se quedó con el borde y Horizonte se fue (está en git).
    private var luz: some View {
        Borde(modo: modoDeLaLuz, nivel: nivelDeLaLuz,
              ultimaPalabra: charla.voz.ultimaPalabraEn)
    }

    /// El compositor: el campo con los dos botones adentro.
    ///
    /// Un campo grande con todo adentro, y no una barra con botones al costado.
    /// Es la pieza que más define el aspecto que pidió Dusan: en Claude y en
    /// ChatGPT el campo es el centro de gravedad de la pantalla, no un accesorio
    /// pegado abajo.
    ///
    /// Y es la única parte de la app que ofrece TRES maneras de decir lo mismo:
    /// escribir, dejar un mensaje grabado, o abrir la llamada. Las tres mandan
    /// el mismo texto al servidor; lo único que cambia es cómo entrás.
    private var barra: some View {
        VStack(spacing: 0) {
            if charla.enLlamada {
                enLlamada
            } else if dictando {
                barraDeDictado
            } else {
                compositor
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// La caja de abajo: escribir y el micrófono para dictar. Hasta el
    /// 26/10/2026 tenía también el botón verde de llamar (propuesta D, 19 de
    /// octubre); ahora la llamada se abre deslizando el anillo hacia abajo.
    private var compositor: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Cuéntale a Bitácora…", text: $escrito, axis: .vertical)
                .font(.redonda(.callout))
                .foregroundStyle(Paleta.tinta)
                .lineLimit(1...5)
                .focused($escribiendo)
                .submitLabel(.send)
                .onSubmit(mandarLoEscrito)
                .padding(.vertical, 12)
                .padding(.leading, 8)

            if charla.fase == .pensando {
                Pensando().padding(.bottom, 17).padding(.trailing, 10)
            } else if escrito.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { escribiendo = false; desdeElInicio(); charla.grabarUnMensaje() } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Paleta.tintaSuave)
                        .frame(width: 42, height: 46)
                }
                .accessibilityLabel("Dictar un mensaje")
                // El botón de llamar se fue el 26/10/2026: la llamada se abre
                // deslizando el anillo del inicio hacia abajo.
            } else {
                Button(action: mandarLoEscrito) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Paleta.fondoAlto)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Paleta.musgo))
                }
                .accessibilityLabel("Enviar")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Paleta.carta)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Paleta.cartaBorde, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// Mientras dictas, la caja se vuelve la onda de tu voz: cancelar a la
    /// izquierda, enviar a la derecha. Lo que dices se escribe arriba, en tu
    /// globo, como un mensaje que se está escribiendo.
    private var barraDeDictado: some View {
        HStack(spacing: 8) {
            Button { charla.cancelarDictado() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Paleta.rojo)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Paleta.rojo.opacity(0.16)))
            }
            .accessibilityLabel("Cancelar el dictado")
            OndaEnVivo(nivel: charla.captura.nivel)
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: .now, by: 1)) { t in
                Text(contador(hasta: t.date))
                    .font(.redonda(.subheadline).monospacedDigit())
                    .foregroundStyle(Paleta.tintaSuave)
            }
            Button { charla.grabarUnMensaje() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Paleta.musgo))
            }
            .accessibilityLabel("Enviar lo dictado")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Paleta.carta)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Paleta.cartaBorde, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func contador(hasta ahora: Date) -> String {
        let s = Int(max(0, ahora.timeIntervalSince(dictandoDesde ?? ahora)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// Lo que se ve mientras la llamada está abierta: el estado y la cruz.
    ///
    /// La conversación sigue a la vista arriba. Esto no es un capricho: OpenAI
    /// tenía el orbe a pantalla completa y lo sacó, porque si no escuchabas bien
    /// algo tenías que salir del modo voz para leerlo.
    private var enLlamada: some View {
        VStack(spacing: 14) {
            // Si lo que dijiste pide una herramienta, se ofrece acá, a la vista:
            // en llamada la conversación de arriba queda tapada por los anillos.
            if let s = sugerencia { sugerenciaDeHerramienta(s) }
            // Los anillos, desordenados y siguiendo la voz (26/10/2026): reemplazan
            // al indicador chico que había al lado del estado.
            Color.clear.frame(width: Self.anillosEnLlamada, height: Self.anillosEnLlamada)
                .matchedGeometryEffect(id: "anillos", in: marca, isSource: true)
            Text(etiqueta)
                .font(.redonda(.subheadline, .medium))
                .foregroundStyle(Paleta.tinta)
                .contentTransition(.opacity)

            // Silenciar y colgar (propuesta D). Silenciar no corta: Bitácora
            // deja de escucharte hasta que lo vuelvas a tocar.
            HStack(spacing: 30) {
                Button { charla.silenciar() } label: {
                    Image(systemName: charla.silenciado ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(charla.silenciado ? Paleta.fondoAlto : Paleta.tinta)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(charla.silenciado ? AnyShapeStyle(Paleta.tinta)
                                                  : AnyShapeStyle(Paleta.tinta.opacity(0.1))))
                }
                .accessibilityLabel(charla.silenciado ? "Volver a prender el micrófono" : "Silenciar el micrófono")
                Button(action: { charla.terminar() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Paleta.rojo))
                }
                .accessibilityLabel("Cortar la llamada")
            }
        }
        .padding(.bottom, 18)
    }

    /// Escribir, dictar o llamar desde el inicio empieza una conversación nueva.
    private func desdeElInicio() {
        guard enInicio, hayCharlaHoy, !charla.activa else { return }
        charla.nuevaConversacion()
        enInicio = false
    }

    private func mandarLoEscrito() {
        if !escrito.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { desdeElInicio() }
        let texto = escrito
        escrito = ""
        charla.enviarTexto(texto)
    }

    /// Un botón del compositor. Todos iguales de tamaño y forma: lo único que
    /// cambia es si lleva el acento o no.
    private func boton<C: View>(acentuado: Bool = false, grabando: Bool = false,
                                accion: @escaping () -> Void, etiqueta: String,
                                @ViewBuilder contenido: () -> C) -> some View {
        Button(action: accion) {
            contenido()
                .frame(width: acentuado ? 34 : 32, height: acentuado ? 34 : 32)
                .foregroundStyle(acentuado ? Paleta.fondoAlto
                                 : (grabando ? Paleta.musgo : Paleta.tintaSuave))
                .background {
                    Circle().fill(acentuado ? AnyShapeStyle(Paleta.musgo)
                                  : AnyShapeStyle(grabando ? Paleta.musgo.opacity(0.18)
                                                  : Paleta.globoVos))
                }
        }
        .accessibilityLabel(etiqueta)
    }

    private func tocarLaLuz() {
        switch charla.fase {
        case .cerrada:
            // Un solo toque para seguir: limpia y arranca. Antes había un botón
            // aparte de "Otra vez" y después había que tocar el orbe.
            charla.volverAEmpezar()
            charla.arrancar()
        case .inactiva:
            charla.arrancar()
        case .hablando:
            // Mientras habla, el toque la calla y te escucha: no cierra la
            // charla. Es el caso de acordarte de algo en la mitad de su
            // respuesta, que antes obligaba a cerrar y volver a empezar.
            charla.interrumpir()
        default:
            charla.terminar()
        }
    }

    private var modoDeLaLuz: ModoDeVoz {
        // Mientras busca el audio del servidor la fase ya es `.hablando`, pero
        // todavía no suena nada: sigue siendo espera, y la luz tiene que
        // respirar como cuando piensa en vez de fingir una voz que no está.
        if charla.voz.preparando { return .pensando }
        switch charla.fase {
        case .escuchando: return .escuchando
        case .pensando: return .pensando
        case .hablando: return .hablando
        default: return .quieta
        }
    }

    /// Cuánto suena, venga de donde venga: tu micrófono cuando hablás vos, el
    /// audio de Bitácora cuando habla ella. Con la voz de iOS no hay amplitud y
    /// esto es cero, que es lo que hace que la luz use el aviso por palabra.
    private var nivelDeLaLuz: Double {
        charla.fase == .hablando ? (charla.voz.nivelDeVoz ?? 0) : charla.captura.nivel
    }

    private var panelDeCuidado: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Paleta.bitacora)
            Text("Conversación pausada")
                .font(.redonda(.subheadline, .medium))
                .foregroundStyle(Paleta.tintaSuave)
            Button { charla.volverAEmpezar() } label: {
                Text("Cerrar")
                    .font(.redonda(.subheadline, .semibold))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
            }
            .background(Capsule().fill(Paleta.carta))
            .overlay { Capsule().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
            .foregroundStyle(Paleta.tinta)
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Paleta.carta.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    /// Por qué no se puede hablar, o `nil` si se puede.
    ///
    /// Mientras `servidor` es `nil` todavía no se preguntó: se deja pasar en vez
    /// de trabar, porque bloquear por una respuesta que no llegó todavía sería
    /// un parpadeo feo cada vez que abrís la app.
    ///
    /// Desde el 06/10/2026 ninguno lleva a Ajustes: la dirección y el token
    /// vienen dentro de la app (ver `Config`), y lo único que se puede revisar
    /// desde el teléfono es que Tailscale esté prendido.
    private var motivoParaNoHablar: (titulo: String, detalle: String)? {
        if !outbox.hayRed {
            return ("Sin conexión",
                    "Necesito llegar al servidor para que lo que digas sirva de algo. "
                    + "Revisa el wifi o los datos y vuelve a probar.")
        }
        switch outbox.servidor {
        case .sinToken:
            return ("El servidor no reconoce la app",
                    "Está andando, pero la llave que trae esta app no le sirve. "
                    + "Hay que volver a instalarla.")
        case .inalcanzable:
            return ("No llego al servidor",
                    "Revisa que Tailscale esté prendido. Sin el servidor Bitácora "
                    + "no puede contestarte, así que prefiero no hacerte hablar "
                    + "al vacío.")
        case .listo, .none:
            return nil
        }
    }

    private func sinServidor(_ m: (titulo: String, detalle: String)) -> some View {
        VStack(spacing: 12) {
            Image(systemName: outbox.hayRed ? "bolt.horizontal.circle" : "wifi.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Paleta.rojo)

            Text(m.titulo)
                .font(.redonda(.headline))
                .foregroundStyle(Paleta.tinta)

            Text(m.detalle)
                .font(.redonda(.footnote))
                .foregroundStyle(Paleta.tintaSuave)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Reintentar") {
                Task { await outbox.comprobarServidor() }
            }
            .buttonStyle(.capsulaTenue)
            .padding(.top, 2)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Paleta.carta.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var etiqueta: String {
        switch charla.fase {
        case .inactiva: "Toca para hablar"
        // Desde que los anillos reemplazaron a los tres puntos de `Pensando`,
        // pensar vuelve a decirse con palabras.
        case .pensando: "Pensando…"
        // Dice qué pasa si tocás, que ahora no es cerrar sino cortarla. En la
        // despedida no se puede, así que ahí no se ofrece.
        case .hablando: charla.cerrando ? "Bitácora…" : "Bitácora… toca para cortarla"
        case .escuchando: charla.silenciado ? "Micrófono silenciado" : (charla.parcial.isEmpty ? "Te escucho" : "Sigue…")
        case .cerrada: "Guardado · toca para seguir"
        case .cuidado: ""
        }
    }

    /// El semáforo de la cola, reducido a un punto.
    ///
    /// Decía "Todo sincronizado" en verde con entradas tiradas: contaba sólo las
    /// pendientes, y una entrada con el token mal ni siquiera cambiaba de color.
    /// El verde tiene que significar algo. Ahora, además, sólo habla cuando hay
    /// algo que decir: el estado normal es un punto verde y nada más.
    // El punto de estado se fue del compositor.
    //
    // Decía "sin servidor", "sin token" o "N en cola" con un color, y era
    // redundante: cuando el servidor no está, la pantalla entera lo explica con
    // `sinServidor(_:)`, que tiene lugar para decir qué pasa y ofrecer
    // reintentar. Un punto de color en una esquina no agrega nada a eso y le
    // mete ruido al campo, que es lo único que tiene que mirarse.
    //
    // Lo que sí se pierde es el aviso de entradas en cola, que era menor y
    // nunca bloqueaba nada: la cola sube sola cuando vuelve la red.
}

/// La onda de tu voz mientras dictas: barritas que suben con el nivel del
/// micrófono.
struct OndaEnVivo: View {
    var nivel: Double
    var barras = 26
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: sinMovimiento)) { t in
            let s = t.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.6) {
                ForEach(0..<barras, id: \.self) { i in
                    let forma = 0.35 + 0.65 * abs(sin(Double(i) * 1.31 + s * 5))
                    Capsule()
                        .fill(Paleta.musgo)
                        .frame(width: 3, height: max(4, 26 * forma * (0.25 + 0.75 * min(1, nivel * 1.6))))
                }
            }
        }
    }
}


/// Las charlas anteriores en un panel lateral, como el historial de Claude o
/// Gemini: buscador arriba, agrupadas por cuándo fueron, una línea cada una.
struct CajonDeCharlas: View {
    @Binding var abierto: Bool
    let alElegir: (EntradaLocal) -> Void
    @Query(sort: \EntradaLocal.creadoEn, order: .reverse) private var entradas: [EntradaLocal]
    @State private var buscar = ""
    @FocusState private var buscando: Bool
    @Environment(\.modelContext) private var contexto
    /// La charla que se va a borrar, esperando que confirme (27/10/2026).
    @State private var borrando: EntradaLocal?
    @State private var noSeBorro = false

    var body: some View {
        GeometryReader { geo in
            let ancho = min(geo.size.width * 0.84, 340)
            ZStack(alignment: .leading) {
                if abierto {
                    Color.black.opacity(0.5).ignoresSafeArea()
                        .onTapGesture { cerrar() }
                        .transition(.opacity)
                    panel
                        .frame(width: ancho)
                        .frame(maxHeight: .infinity)
                        .background(Paleta.fondoAlto.ignoresSafeArea())
                        .overlay(alignment: .trailing) { Rectangle().fill(Paleta.cartaBorde).frame(width: 1).ignoresSafeArea() }
                        .transition(.move(edge: .leading))
                        .gesture(DragGesture().onEnded { g in if g.translation.width < -60 { cerrar() } })
                }
            }
        }
        .confirmationDialog("¿Borrar esta charla?",
                            isPresented: Binding(get: { borrando != nil }, set: { if !$0 { borrando = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { if let e = borrando { Task { await borrar(e) } } }
        } message: {
            Text("Se borra de este teléfono y del servidor, con lo que Bitácora anotó de ella. No se puede deshacer.")
        }
        .alert("No se pudo borrar", isPresented: $noSeBorro) {
            Button("Bueno", role: .cancel) {}
        } message: {
            Text("Hace falta conexión para borrarla también del servidor. Prueba de nuevo en un rato.")
        }
    }

    private func cerrar() {
        buscando = false
        withAnimation(.spring(duration: 0.3)) { abierto = false }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversaciones")
                        .font(.dicha(.title2))
                        .foregroundStyle(Paleta.tinta)
                    Text("Hoy es \(Self.fechaDeHoy()) · toca una para seguirla")
                        .font(.redonda(.subheadline))
                        .foregroundStyle(Paleta.tintaTenue)
                }
                Spacer()
                Button { cerrar() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Paleta.tintaSuave)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Paleta.carta))
                }
                .accessibilityLabel("Cerrar")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Paleta.tintaTenue)
                TextField("Buscar", text: $buscar)
                    .font(.redonda(.callout))
                    .foregroundStyle(Paleta.tinta)
                    .focused($buscando)
                if !buscar.isEmpty {
                    Button { buscar = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Paleta.tintaTenue) }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Paleta.carta))
            .padding(.horizontal, 14)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if grupos.isEmpty {
                        Text(buscar.isEmpty ? "Todavía no hay charlas." : "Nada con «\(buscar)».")
                            .font(.redonda(.subheadline))
                            .foregroundStyle(Paleta.tintaTenue)
                            .padding(.horizontal, 18).padding(.top, 20)
                    }
                    ForEach(grupos, id: \.0) { grupo in
                        Text(grupo.0)
                            .font(.redonda(.caption, .semibold))
                            .foregroundStyle(Paleta.tintaTenue)
                            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 4)
                        ForEach(grupo.1, id: \.clientUuid) { e in fila(e) }
                    }
                }
                .padding(.bottom, 30)
            }
            .padding(.top, 10)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func fila(_ e: EntradaLocal) -> some View {
        Button {
            cerrar()
            alElegir(e)
        } label: {
            HStack(spacing: 10) {
                Text(Self.tituloDe(e))
                    .font(.redonda(.callout))
                    .foregroundStyle(Paleta.tinta)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(Self.cuando(e))
                    .font(.redonda(.caption))
                    .foregroundStyle(Paleta.tintaTenue)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { borrando = e } label: { Label("Borrar esta charla", systemImage: "trash") }
        }
    }

    /// Borrar una charla: del servidor, con lo que la ficha sacó de ella, y
    /// después del teléfono. Si nunca llegó al servidor, sólo del teléfono. Sin
    /// red no se borra a medias: se avisa y queda como estaba.
    private func borrar(_ e: EntradaLocal) async {
        borrando = nil
        if e.servidorId != nil || e.estado != .borrador {
            guard await SyncClient(config: Config.shared.servidor).borrarConversacion(uuid: e.clientUuid) else {
                noSeBorro = true
                return
            }
        }
        contexto.delete(e)
        try? contexto.save()
    }

    /// La primera frase que dijiste, como título de la charla.
    static func tituloDe(_ e: EntradaLocal) -> String {
        let t = Transcripcion.turnos(e.transcripcion).first(where: { $0.de == .vos })?.texto ?? "Charla"
        let limpia = t.replacingOccurrences(of: "\n", with: " ")
        if let fin = limpia.firstIndex(where: { ".?!".contains($0) }), limpia.distance(from: limpia.startIndex, to: fin) > 12 {
            return String(limpia[...fin])
        }
        return limpia
    }

    static func fechaDeHoy() -> String {
        let k = CalendarioView.hoyLogico()
        let d = Int(k.suffix(2)) ?? 1, m = Int(k.dropFirst(5).prefix(2)) ?? 1
        let meses = ["enero","febrero","marzo","abril","mayo","junio","julio","agosto","septiembre","octubre","noviembre","diciembre"]
        return "\(d) de \(meses[m - 1])"
    }

    static func cuando(_ e: EntradaLocal) -> String {
        let hoy = CalendarioView.hoyLogico()
        if e.diaLogico == hoy { return String(e.creadoLocalISO.suffix(8).prefix(5)) }
        let d = Int(e.diaLogico.suffix(2)) ?? 1, m = Int(e.diaLogico.dropFirst(5).prefix(2)) ?? 1
        let meses = ["ene","feb","mar","abr","may","jun","jul","ago","sept","oct","nov","dic"]
        return "\(d) \(meses[m - 1])"
    }

    /// Hoy, Ayer, Esta semana, Este mes, y después cada mes.
    private var grupos: [(String, [EntradaLocal])] {
        let q = buscar.trimmingCharacters(in: .whitespaces).lowercased()
        let lista = entradas.filter {
            // Todas, no sólo las de hoy (27/10/2026): cualquiera se puede seguir.
            $0.transcripcion.contains("Vos:") && (q.isEmpty || $0.transcripcion.lowercased().contains(q))
        }
        let hoy = CalendarioView.hoyLogico()
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func fecha(_ k: String) -> Date? {
            cal.date(from: DateComponents(year: Int(k.prefix(4)), month: Int(k.dropFirst(5).prefix(2)), day: Int(k.suffix(2))))
        }
        let meses = ["Enero","Febrero","Marzo","Abril","Mayo","Junio","Julio","Agosto","Septiembre","Octubre","Noviembre","Diciembre"]
        var orden: [String] = []
        var por: [String: [EntradaLocal]] = [:]
        for e in lista {
            var g: String
            if let a = fecha(e.diaLogico), let b = fecha(hoy) {
                let dias = cal.dateComponents([.day], from: a, to: b).day ?? 0
                if dias <= 0 { g = "Hoy" }
                else if dias == 1 { g = "Ayer" }
                else if dias < 7 { g = "Esta semana" }
                else if e.diaLogico.prefix(7) == hoy.prefix(7) { g = "Este mes" }
                else {
                    let m = Int(e.diaLogico.dropFirst(5).prefix(2)) ?? 1
                    g = meses[m - 1] + (e.diaLogico.prefix(4) == hoy.prefix(4) ? "" : " " + e.diaLogico.prefix(4))
                }
            } else { g = "Antes" }
            if por[g] == nil { orden.append(g) }
            por[g, default: []].append(e)
        }
        return orden.map { ($0, por[$0]!) }
    }
}

/// Las charlas guardadas, día por día, de la más nueva a la más vieja.
/// Tocar una la abre entera, como desde el calendario.
struct HistorialDeCharlas: View {
    @Environment(\.dismiss) private var cerrar
    @Query(sort: \EntradaLocal.creadoEn, order: .reverse) private var entradas: [EntradaLocal]

    private var porDia: [(String, [EntradaLocal])] {
        let con = entradas.filter { $0.transcripcion.contains("Vos:") }
        let g = Dictionary(grouping: con, by: \.diaLogico)
        return g.keys.sorted(by: >).map { ($0, g[$0]!.sorted { $0.creadoEn > $1.creadoEn }) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Fondo()
                if porDia.isEmpty {
                    Text("Todavía no hay charlas guardadas.")
                        .font(.redonda(.subheadline))
                        .foregroundStyle(Paleta.tintaTenue)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(porDia, id: \.0) { dia, lista in
                                Text(titulo(dia))
                                    .font(.redonda(.caption, .bold))
                                    .foregroundStyle(Paleta.tintaTenue)
                                    .textCase(.uppercase)
                                    .padding(.top, 14)
                                ForEach(lista, id: \.clientUuid) { e in
                                    NavigationLink(value: e) { fila(e) }.buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Charlas")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EntradaLocal.self) { CharlaGuardadaView(entrada: $0) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
    }

    private func fila(_ e: EntradaLocal) -> some View {
        let turnos = Transcripcion.turnos(e.transcripcion)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(e.creadoLocalISO.suffix(8).prefix(5) + (e.duracionSeg > 0 ? " · \(Transcripcion.duracion(segundos: e.duracionSeg))" : ""))
                    .font(.redonda(.caption, .bold))
                    .foregroundStyle(Paleta.musgo)
                Text(turnos.first(where: { $0.de == .vos })?.texto ?? "")
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tinta)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Paleta.tintaTenue)
        }
        .padding(14)
        .carta()
    }

    private func titulo(_ clave: String) -> String {
        if clave == CalendarioView.hoyLogico() { return "Hoy" }
        let d = Int(clave.suffix(2)) ?? 1, m = Int(clave.dropFirst(5).prefix(2)) ?? 1
        let meses = ["enero","febrero","marzo","abril","mayo","junio","julio","agosto","septiembre","octubre","noviembre","diciembre"]
        return "\(d) de \(meses[m - 1])"
    }
}

/// Una curva de nivel suelta, como las de los anillos: un óvalo apenas
/// ondulado. `fase` la hace moverse; `corrida` corre su centro, para que dos
/// curvas no queden concéntricas y se crucen.
struct CurvaDeNivel: Shape {
    var fase: Double
    var onda: Double = 0.05
    var corrida: CGSize = .zero

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX + corrida.width, y: rect.midY + corrida.height)
        var camino = Path()
        for k in 0...96 {
            let a = Double(k) / 96 * 2 * .pi
            let r = 1 + onda * sin(2 * a + fase) + onda * 0.6 * sin(3 * a - fase * 0.7)
            let p = CGPoint(x: c.x + rect.width / 2 * r * cos(a) * 0.9,
                            y: c.y + rect.height / 2 * r * sin(a) * 0.9)
            if k == 0 { camino.move(to: p) } else { camino.addLine(to: p) }
        }
        camino.closeSubpath()
        return camino
    }
}
