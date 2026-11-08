import SwiftUI

/// Anotar una sesión, de a una cosa por vez.
///
/// La primera versión mostraba todo junto: el número, la fecha y las cuatro
/// preguntas en una sola pantalla llena de casilleros. Dusan la vio y dijo que
/// «se ve muy feo», y pidió lo contrario: que vaya paso por paso y que en la
/// pantalla aparezca sólo lo que hay que anotar en ese momento.
///
/// Tiene sentido más allá de lo estético. Quien anota esto acaba de salir de
/// una sesión; seis casilleros vacíos a la vista son una tarea, y una sola
/// pregunta con toda la pantalla para contestarla es una invitación.
///
/// Siete pasos: qué sesión fue, qué fecha, qué entendí, qué me aportó, cómo me
/// sentí, los temas, y en qué avancé. «Cómo me sentí» se sumó el 03/10/2026;
/// los demás van en el orden en que los pidió Dusan. Ninguno es obligatorio:
/// se puede seguir de largo y volver después.
///
/// Lo que se escribe queda guardado mientras se escribe. Si la app se cierra en
/// el paso cuatro, lo de los tres primeros no se pierde.
struct AnotarSesionView: View {
    enum Paso: Int, CaseIterable, Hashable {
        case numero, fecha, entendi, aporte, sentir, temas, avance
    }

    enum Modo: Equatable {
        /// Una sesión que se está creando: todos los pasos, y salir la descarta.
        case nueva
        /// Repasar una que ya existe, todos los pasos.
        case repaso
        /// Cambiar una sola cosa de una que ya existe.
        case unSolo(Paso)
    }

    @Bindable var sesion: SesionDeTerapia
    let modo: Modo
    /// Se llama al salir. `descartar` es verdadero sólo si era nueva y la
    /// persona eligió no guardarla.
    let alCerrar: (_ descartar: Bool) -> Void

    @State private var paso: Paso
    @State private var avanzando = true
    @State private var temaNuevo = ""
    @State private var confirmarDescarte = false
    @FocusState private var foco: Paso?

    init(sesion: SesionDeTerapia, modo: Modo, alCerrar: @escaping (Bool) -> Void) {
        self.sesion = sesion
        self.modo = modo
        self.alCerrar = alCerrar
        if case .unSolo(let p) = modo { _paso = State(initialValue: p) }
        else { _paso = State(initialValue: .numero) }
    }

    private var esUnSolo: Bool { if case .unSolo = modo { true } else { false } }
    private var esElUltimo: Bool { paso == Paso.allCases.last }

    var body: some View {
        ZStack {
            Fondo()
            VStack(spacing: 0) {
                arriba
                contenido
                    .id(paso)
                    .transition(.asymmetric(
                        insertion: .move(edge: avanzando ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: avanzando ? .leading : .trailing).combined(with: .opacity)))
            }
        }
        // Abajo y no adentro del contenido: así los botones suben con el
        // teclado y quedan siempre a mano, se escriba lo que se escriba.
        .safeAreaInset(edge: .bottom) { botones }
        .confirmationDialog("¿Salir sin guardar esta sesión?",
                            isPresented: $confirmarDescarte, titleVisibility: .visible) {
            Button("Descartar la sesión", role: .destructive) { alCerrar(true) }
            Button("Seguir anotando", role: .cancel) {}
        } message: {
            Text("Se pierde lo que anotaste hasta acá.")
        }
        .task(id: paso) { await enfocar() }
    }

    // MARK: - Arriba: salir y por dónde va

    private var arriba: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: salir) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Paleta.tintaSuave)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Paleta.carta.opacity(0.7)))
                        .overlay { Circle().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
                }
                .accessibilityLabel(modo == .nueva ? "Salir sin guardar" : "Cerrar")
                Spacer()
                if !esUnSolo {
                    Text("Paso \(paso.rawValue + 1) de \(Paso.allCases.count)")
                        .font(.redonda(.footnote, .medium))
                        .foregroundStyle(Paleta.tintaTenue)
                        .contentTransition(.numericText())
                }
                Spacer()
                // Del mismo ancho que la cruz, para que el texto quede centrado.
                Color.clear.frame(width: 40, height: 40)
            }

            if !esUnSolo {
                HStack(spacing: 5) {
                    ForEach(Paso.allCases, id: \.self) { p in
                        Capsule()
                            .fill(p.rawValue <= paso.rawValue ? Paleta.musgo : Paleta.cartaBorde)
                            .frame(height: 4)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: paso)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - El paso que toca

    @ViewBuilder
    private var contenido: some View {
        switch paso {
        case .numero:
            hoja("¿Qué sesión fue?", "El número de la sesión con tu terapeuta.") { numero }
        case .fecha:
            hoja("¿Qué día fue?", "La fecha de la sesión, no la de hoy si la anotas después.") { fecha }
        case .entendi:
            hoja("¿Qué entendiste de la sesión?", "Lo que te quedó claro, con tus palabras. Escribe todo lo que quieras.") {
                escrito($sesion.entendi, "Empieza por lo primero que se te venga a la cabeza…", .entendi)
            }
        case .aporte:
            hoja("¿Qué te aportó o qué aprendiste?", "Algo que no sabías, o que ahora ves distinto.") {
                escrito($sesion.aporte, "Lo que te llevas de esta sesión…", .aporte)
            }
        case .sentir:
            hoja("¿Cómo te sentiste?", "En la sesión, o al salir de ella.") {
                escrito($sesion.sentir, "Cómo llegaste, cómo saliste…", .sentir)
            }
        case .temas:
            hoja("¿Qué temas se trataron?", "Los puntos clave, de a uno. Puedes escribir varios separados por coma.") { temas }
        case .avance:
            hoja("¿En qué sentiste que avanzaste?", "Aunque sea un paso chico.") {
                escrito($sesion.avance, "Algo que hoy puedes y antes no, o que hoy entiendes mejor…", .avance)
            }
        }
    }

    /// La forma de todos los pasos: la pregunta grande arriba, una línea que la
    /// explica, y debajo lo único que hay que hacer.
    private func hoja<C: View>(_ pregunta: String, _ ayuda: String,
                               @ViewBuilder _ cuerpo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pregunta)
                .font(.redonda(.title2, .semibold))
                .foregroundStyle(Paleta.tinta)
                .fixedSize(horizontal: false, vertical: true)
            Text(ayuda)
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            cuerpo()
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 30)
    }

    // MARK: - Lo que va en cada paso

    private var numero: some View {
        VStack(spacing: 6) {
            HStack(spacing: 28) {
                redondo("minus", activo: sesion.numero > 1, nombre: "Una menos") { sesion.numero -= 1 }
                Text("\(sesion.numero)")
                    .font(.cifra(84, .semibold))
                    .foregroundStyle(Paleta.tinta)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 120)
                redondo("plus", activo: sesion.numero < 999, nombre: "Una más") { sesion.numero += 1 }
            }
            Text("Sesión")
                .font(.redonda(.callout))
                .foregroundStyle(Paleta.tintaTenue)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func redondo(_ simbolo: String, activo: Bool, nombre: String,
                         accion: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { accion() } }) {
            Image(systemName: simbolo)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(activo ? Paleta.tinta : Paleta.tintaTenue)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Paleta.carta))
                .overlay { Circle().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
        }
        .disabled(!activo)
        .accessibilityLabel(nombre)
    }

    private var fecha: some View {
        DatePicker("Fecha de la sesión", selection: $sesion.fecha, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "es"))
            .tint(Paleta.musgo)
            .padding(10)
            .carta(radio: 22)
    }

    /// Un campo para escribir largo: ocupa todo lo que queda de pantalla.
    private func escrito(_ texto: Binding<String>, _ marca: String, _ campo: Paso) -> some View {
        ZStack(alignment: .topLeading) {
            if texto.wrappedValue.isEmpty {
                Text(marca)
                    .font(.redonda(.body))
                    .foregroundStyle(Paleta.tintaTenue)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: texto)
                .font(.redonda(.body))
                .foregroundStyle(Paleta.tinta)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .focused($foco, equals: campo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .carta(radio: 22)
        .padding(.bottom, 12)
    }

    private var temas: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                TextField("Un tema", text: $temaNuevo)
                    .font(.redonda(.body))
                    .foregroundStyle(Paleta.tinta)
                    .focused($foco, equals: .temas)
                    .submitLabel(.done)
                    .onSubmit(agregarTema)
                Button(action: agregarTema) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hayTemaNuevo ? Paleta.fondoAlto : Paleta.tintaTenue)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(hayTemaNuevo ? AnyShapeStyle(Paleta.musgo)
                                                  : AnyShapeStyle(Paleta.globoVos)))
                }
                .disabled(!hayTemaNuevo)
                .accessibilityLabel("Agregar el tema")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 9)
            .carta(radio: 22)

            ScrollView {
                Fluido(espacio: 8) {
                    ForEach(sesion.temas, id: \.self) { tema in
                        HStack(spacing: 6) {
                            Text(tema)
                                .font(.redonda(.subheadline, .medium))
                                .foregroundStyle(Paleta.musgo)
                            Button {
                                withAnimation(.snappy) { sesion.temas.removeAll { $0 == tema } }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Paleta.musgoSuave)
                            }
                            .accessibilityLabel("Quitar \(tema)")
                        }
                        .padding(.leading, 14)
                        .padding(.trailing, 11)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Paleta.musgo.opacity(0.14)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var hayTemaNuevo: Bool {
        !temaNuevo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Agrega lo escrito como tema. Si vienen varios separados por coma, entran
    /// de a uno: es como la gente los escribe de corrido.
    private func agregarTema() {
        let nuevos = temaNuevo
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !nuevos.isEmpty else { return }
        withAnimation(.snappy) {
            for tema in nuevos where !sesion.temas.contains(where: { $0.caseInsensitiveCompare(tema) == .orderedSame }) {
                sesion.temas.append(tema)
            }
        }
        temaNuevo = ""
        // El cursor se queda en el campo: lo normal es agregar varios seguidos.
        foco = .temas
    }

    // MARK: - Abajo: atrás y seguir

    private var botones: some View {
        HStack {
            if !esUnSolo, paso != .numero {
                Button(action: atras) {
                    Text("Atrás")
                        .font(.redonda(.callout, .semibold))
                        .foregroundStyle(Paleta.tinta)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(Paleta.carta))
                        .overlay { Capsule().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
                }
            }
            Spacer()
            Button(action: seguir) {
                Text(esUnSolo ? "Listo" : (esElUltimo ? "Guardar" : "Siguiente"))
                    .font(.redonda(.callout, .semibold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Paleta.musgo))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Moverse

    private func seguir() {
        // Un tema a medio escribir cuenta: se agrega en vez de perderse.
        if paso == .temas, hayTemaNuevo { agregarTema() }
        guard !esUnSolo, let sig = Paso(rawValue: paso.rawValue + 1) else {
            foco = nil
            alCerrar(false)
            return
        }
        avanzando = true
        withAnimation(.easeInOut(duration: 0.28)) { paso = sig }
    }

    private func atras() {
        guard let ant = Paso(rawValue: paso.rawValue - 1) else { return }
        avanzando = false
        withAnimation(.easeInOut(duration: 0.28)) { paso = ant }
    }

    private func salir() {
        if paso == .temas, hayTemaNuevo { agregarTema() }
        foco = nil
        guard modo == .nueva else {
            alCerrar(false)
            return
        }
        // Si no escribió nada, no hay nada que preguntar.
        if hayAlgoEscrito { confirmarDescarte = true } else { alCerrar(true) }
    }

    private var hayAlgoEscrito: Bool {
        !sesion.temas.isEmpty || [sesion.entendi, sesion.aporte, sesion.sentir, sesion.avance]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// En los pasos de escribir, el cursor aparece solo. Se espera a que termine
    /// de entrar la hoja: enfocar antes hace que el teclado suba a mitad de la
    /// animación y la pantalla salte.
    private func enfocar() async {
        switch paso {
        case .entendi, .aporte, .sentir, .temas, .avance:
            try? await Task.sleep(for: .milliseconds(350))
            foco = paso
        case .numero, .fecha:
            foco = nil
        }
    }
}
