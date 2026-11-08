import SwiftData
import SwiftUI

struct CalendarioView: View {
    @Query(sort: \EntradaLocal.creadoEn, order: .reverse)
    private var entradas: [EntradaLocal]

    @State private var anio: Int
    @State private var mes: Int
    @State private var seleccionado: String?
    /// Las notas sueltas. Viven en otro archivo que las conversaciones, así que
    /// no entran por `@Query`: se leen cada vez que se abre esta pestaña.
    @State private var apuntes: [Apunte] = []
    /// Se está cargando una consulta en el día elegido.
    @State private var agregando = false
    /// Se está escribiendo una nota para el día elegido.
    @State private var escribiendoNota = false
    /// Qué se muestra del día. Vacío es todo; cada filtro que se toca se suma
    /// (26/10/2026: antes había un «Todo» y se elegía una sola cosa).
    @State private var filtros: Set<Filtro> = []
    /// La nota que se está editando, al tocarla.
    @State private var editando: Apunte?
    /// El menú del «+» está abierto.
    @State private var menuAbierto = false
    enum Filtro: String, CaseIterable { case charlas = "Charlas", sesion = "Sesión", notas = "Notas" }
    /// Las consultas y otros eventos. Una copia del servidor (`Agenda`).
    private var agenda = Agenda.shared
    /// Los pedidos de Mi expediente: agendar una consulta, o ver su día.
    private var navegacion = Navegacion.shared

    init() {
        let hoy = Self.hoyLogico()
        _anio = State(initialValue: Int(hoy.prefix(4))!)
        _mes = State(initialValue: Int(hoy.dropFirst(5).prefix(2))!)
        _seleccionado = State(initialValue: hoy)
    }

    /// El "hoy" de la bitácora, no el del reloj. A las 2am son días distintos y
    /// el que vale es este.
    static func hoyLogico() -> String {
        DiaLogico.dia(de: HoraDePared(instante: Date(), zona: .current))
    }

    /// Cuántas entradas hay por día lógico. Agrupar por `diaLogico` y no por
    /// `creadoEn` es lo que hace que la entrada de la madrugada caiga en la
    /// celda correcta.
    private var porDia: [String: [EntradaLocal]] {
        // Una charla abierta en la que todavía no dijiste nada no es una charla.
        Dictionary(grouping: entradas.filter { $0.transcripcion.contains("Vos:") }, by: \.diaLogico)
    }

    /// Las notas, por el mismo día lógico que las conversaciones: una nota
    /// escrita a las dos de la mañana es del día que todavía no terminó.
    private var notasPorDia: [String: [Apunte]] {
        Dictionary(grouping: apuntes) {
            DiaLogico.dia(de: HoraDePared(instante: $0.creadoEn, zona: .current))
        }
    }

    private func cargarApuntes() {
        let todos = (try? AlmacenDeApuntes.contenedor?.mainContext.fetch(
            FetchDescriptor<Apunte>(sortBy: [SortDescriptor(\.creadoEn)]))) ?? []
        apuntes = todos.filter { !$0.estaVacio }
    }

    private var grilla: GrillaMes { CalendarioMensual.grilla(anio: anio, mes: mes) }

    var body: some View {
        NavigationStack {
            ZStack {
                Fondo()
                VStack(spacing: 0) {
                    encabezadoDeMes
                    diasDeLaSemana
                    celdas
                    detalleDelDia
                }
                .padding(.horizontal, 16)
                menuAbiertoVista
            }
            .navigationDestination(for: EntradaLocal.self) { CharlaGuardadaView(entrada: $0) }
            // Agregar va en el encabezado, con nombre y un menú que dice qué
            // hace cada cosa (19/10/2026, propuesta elegida por Dusan).
            // Lo que dijiste para llevar a terapia ya no se abre desde acá:
            // desde el 04/10/2026 es «Mi resumen», en «Mi expediente».
            .sheet(isPresented: $agregando) {
                if let seleccionado { HojaDeEvento(dia: seleccionado) }
            }
            .sheet(isPresented: $escribiendoNota, onDismiss: cargarApuntes) {
                if let seleccionado { NotaDelDiaHoja(dia: seleccionado) }
            }
            .sheet(item: $editando, onDismiss: cargarApuntes) { a in
                NotaDelDiaHoja(dia: seleccionado ?? Self.hoyLogico(), apunte: a)
            }
            // Cada vez que se entra a la pestaña: una nota escrita recién en el
            // chat tiene que estar acá al llegar, y una consulta que Bitácora
            // propuso al cerrar la última charla, también.
            .onAppear(perform: cargarApuntes)
            .onAppear(perform: atenderPedidos)
            .onChange(of: navegacion.nuevaConsulta) { atenderPedidos() }
            .onChange(of: navegacion.irAlDia) { atenderPedidos() }
            .task { await agenda.actualizar() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Encabezado

    fileprivate static let nombresDeMes = [
        "enero", "febrero", "marzo", "abril", "mayo", "junio",
        "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"
    ]

    private var encabezadoDeMes: some View {
        HStack(spacing: 8) {
            // Tocar el mes vuelve a hoy: después de mirar meses atrás, es la
            // manera de volver sin contar flechas.
            Button(action: volverAHoy) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.nombresDeMes[mes - 1].capitalized)
                        .font(.dicha(.title))
                        .foregroundStyle(Paleta.tinta)
                        // «Noviembre» se partía en dos renglones cuando el
                        // botón de agregar todavía decía «+ Agregar».
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(String(anio))
                        .font(.dicha(.title3))
                        .foregroundStyle(Paleta.tintaTenue)
                }
                .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Vuelve a hoy")
            Spacer()
            flecha("chevron.left", -1, "Mes anterior")
            flecha("chevron.right", 1, "Mes siguiente")
            menuDeAgregar
        }
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    /// El «+». Abre un menú propio (y no el del sistema) para que cada opción
    /// diga qué hace: el del sistema no muestra la segunda línea.
    ///
    /// Hasta el 26/10/2026 era una cápsula que decía «+ Agregar», y era tan
    /// ancha que el nombre del mes se partía en dos renglones. Ahora es un
    /// círculo del tamaño de las flechas, el único con color, y gira a «×»
    /// mientras el menú está abierto.
    private var menuDeAgregar: some View {
        Button { withAnimation(.snappy(duration: 0.2)) { menuAbierto.toggle() } } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Marca.sobreDurazno)
                .rotationEffect(.degrees(menuAbierto ? 45 : 0))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Marca.durazno))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Agregar una sesión o una nota")
    }

    @ViewBuilder
    private var menuAbiertoVista: some View {
        if menuAbierto, let seleccionado {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { withAnimation(.snappy(duration: 0.2)) { menuAbierto = false } }
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.paraElDia(seleccionado))
                        .font(.redonda(.caption))
                        .foregroundStyle(Paleta.tintaTenue)
                        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
                    opcionDeMenu("sofa", Paleta.verde, "Agendar sesión", "Con tu psicólogo/a") { agregando = true }
                    Divider().overlay(Paleta.cartaBorde).padding(.horizontal, 12)
                    opcionDeMenu("square.and.pencil", Paleta.nota, "Escribir una nota", "Algo para recordar ese día") { escribiendoNota = true }
                }
                .padding(.bottom, 6)
                .frame(width: 270)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Paleta.carta)
                        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                }
                .padding(.top, 52)
                .padding(.trailing, 16)
                .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }

    private func opcionDeMenu(_ icono: String, _ c: Color, _ t: String, _ x: String, _ accion: @escaping () -> Void) -> some View {
        Button {
            menuAbierto = false
            accion()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icono)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(c.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(t).font(.redonda(.subheadline, .semibold)).foregroundStyle(Paleta.tinta)
                    Text(x).font(.redonda(.caption)).foregroundStyle(Paleta.tintaSuave)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func paraElDia(_ clave: String) -> String {
        let d = Int(clave.suffix(2))!
        let m = Int(clave.dropFirst(5).prefix(2))!
        return "Agregar al \(d) de \(nombresDeMes[m - 1])"
    }

    private func flecha(_ icono: String, _ delta: Int, _ etiqueta: String) -> some View {
        Button { correr(delta) } label: {
            Image(systemName: icono)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Paleta.tintaSuave)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Paleta.carta))
                .overlay { Circle().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
        }
        .accessibilityLabel(etiqueta)
    }

    /// Lo que pidió Mi expediente desde la tarjeta de la próxima consulta: abrir
    /// la hoja de consulta nueva (en hoy; ahí se elige el día), o mostrar el día
    /// de la consulta. Se atiende una vez y se borra.
    private func atenderPedidos() {
        if let dia = navegacion.irAlDia {
            navegacion.irAlDia = nil
            withAnimation(.snappy(duration: 0.22)) {
                anio = Int(dia.prefix(4)) ?? anio
                mes = Int(dia.dropFirst(5).prefix(2)) ?? mes
                seleccionado = dia
            }
        }
        if navegacion.nuevaConsulta {
            navegacion.nuevaConsulta = false
            volverAHoy()
            agregando = true
        }
    }

    private func volverAHoy() {
        let hoy = Self.hoyLogico()
        withAnimation(.snappy(duration: 0.22)) {
            anio = Int(hoy.prefix(4))!
            mes = Int(hoy.dropFirst(5).prefix(2))!
            seleccionado = hoy
        }
    }

    private func correr(_ delta: Int) {
        let r = CalendarioMensual.corrido(anio: anio, mes: mes, meses: delta)
        withAnimation(.snappy(duration: 0.22)) {
            anio = r.anio
            mes = r.mes
        }
    }

    private var diasDeLaSemana: some View {
        HStack(spacing: 0) {
            ForEach(Array(CalendarioMensual.encabezados.enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(.redonda(.caption2, .bold))
                    .foregroundStyle(Paleta.tintaTenue)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Grilla

    private var celdas: some View {
        VStack(spacing: 5) {
            ForEach(Array(grilla.semanas.enumerated()), id: \.offset) { _, semana in
                HStack(spacing: 5) {
                    ForEach(Array(semana.enumerated()), id: \.offset) { _, clave in
                        if let clave {
                            celda(clave)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 46)
                        }
                    }
                }
            }
        }
        // Deslizar a los lados cambia de mes, como pasar una hoja. Simultáneo
        // para que un dedo que arranca sobre un día también lo cuente.
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { g in
            let dx = g.translation.width
            guard abs(dx) > 50, abs(dx) > abs(g.translation.height) else { return }
            correr(dx < 0 ? 1 : -1)
        })
    }

    /// Un día: el número y, abajo, una franja por cada cosa que hubo. Verde
    /// musgo si hablaste, verde azulado si hubo sesión, celeste si hay nota
    /// (19/10/2026: franjas en vez de puntos, se leen mejor). Hoy va en un
    /// círculo musgo; el día elegido, con borde.
    private func celda(_ clave: String) -> some View {
        let n = (porDia[clave] ?? []).count
        let notas = (notasPorDia[clave] ?? []).count
        let marca = agenda.marca(clave)
        let esHoy = clave == Self.hoyLogico()
        let esta = clave == seleccionado
        let numero = String(Int(clave.suffix(2))!)

        return Button {
            withAnimation(.snappy(duration: 0.18)) { seleccionado = clave }
        } label: {
            VStack(spacing: 0) {
                Text(numero)
                    .font(.redonda(.callout, esHoy ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(esHoy ? Marca.sobreDurazno : Paleta.tinta)
                    .frame(width: 25, height: 25)
                    .background { if esHoy { Circle().fill(Marca.durazno) } }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    if n > 0 { franja(Marca.durazno) }
                    if marca == .confirmado { franja(Paleta.verde) }
                    if marca == .propuesto { franja(Paleta.verde.opacity(0.4)) }
                    if notas > 0 { franja(Paleta.nota) }
                }
                .frame(height: 4)
            }
            .padding(.top, 5)
            .padding(.bottom, 5)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(esta ? Marca.durazno.opacity(0.16) : Paleta.carta.opacity(0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(esta ? Marca.durazno : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(numero): \(n) conversación\(n == 1 ? "" : "es")"
                            + (notas > 0 ? ", \(notas) nota\(notas == 1 ? "" : "s")" : "")
                            + (marca == .ninguna ? "" : ", con sesión"))
    }

    private func franja(_ c: Color) -> some View {
        Capsule().fill(c).frame(maxWidth: .infinity).frame(height: 4)
    }

    // MARK: - Detalle

    @ViewBuilder
    private var detalleDelDia: some View {
        if let seleccionado {
            let delDia = (porDia[seleccionado] ?? []).sorted { $0.creadoEn < $1.creadoEn }
            let notasDelDia = notasPorDia[seleccionado] ?? []
            // Charlas y notas en una sola lista, por hora: el día se lee como
            // pasó. Las sesiones van primero: es lo que estaba previsto.
            let charlas: [DelDia] = muestra(.charlas) ? delDia.map(DelDia.charla) : []
            let notas: [DelDia] = muestra(.notas) ? notasDelDia.map(DelDia.nota) : []
            let todo = (charlas + notas).sorted { $0.cuando < $1.cuando }
            let eventosDelDia = muestra(.sesion) ? agenda.delDia(seleccionado) : []
            let vacio = delDia.isEmpty && notasDelDia.isEmpty && agenda.delDia(seleccionado).isEmpty
            VStack(alignment: .leading, spacing: 0) {
                Text(titulo(seleccionado))
                    .font(.redonda(.title3, .bold))
                    .foregroundStyle(Paleta.tinta)
                    .padding(.top, 20)
                if !vacio { pestanas.padding(.top, 10).padding(.bottom, 12) }

                if vacio {
                    diaVacio(seleccionado).padding(.top, 12)
                    Spacer()
                } else if todo.isEmpty && eventosDelDia.isEmpty {
                    Text(filtros.count == 1
                         ? (filtros.contains(.sesion) ? "No hay sesión este día."
                            : filtros.contains(.notas) ? "No hay notas este día." : "No hay charlas este día.")
                         : "No hay nada de eso este día.")
                        .font(.redonda(.subheadline))
                        .foregroundStyle(Paleta.tintaTenue)
                        .padding(.top, 4)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(eventosDelDia) { TarjetaDeEvento(evento: $0) }
                            ForEach(todo) { cosa in
                                switch cosa {
                                case .charla(let e): tarjeta(e)
                                case .nota(let a): tarjetaDeNota(a)
                                }
                            }
                        }
                        // La barra de pestañas flota encima del contenido.
                        .padding(.bottom, 72)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            // Siempre a todo el ancho: con un texto corto («No hay sesión este
            // día») el bloque se achicaba y quedaba centrado, y las pestañas
            // saltaban de lugar.
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: seleccionado) { filtros = [] }
        }
    }

    /// Sin ningún filtro se ve todo el día.
    private func muestra(_ f: Filtro) -> Bool { filtros.isEmpty || filtros.contains(f) }

    /// Charlas, Sesión, Notas: filtran lo del día y se suman. Cada uno se pinta
    /// con su color cuando está marcado.
    private var pestanas: some View {
        HStack(spacing: 6) {
            ForEach(Filtro.allCases, id: \.self) { f in
                let color: Color = f == .sesion ? Paleta.verde : f == .notas ? Paleta.nota : Marca.duraznoTexto
                let marcado = filtros.contains(f)
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        if marcado { filtros.remove(f) } else { filtros.insert(f) }
                    }
                } label: {
                    Text(f.rawValue)
                        .font(.redonda(.footnote, marcado ? .bold : .medium))
                        .foregroundStyle(marcado ? Paleta.fondoAlto : color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            Capsule().fill(marcado ? color : Paleta.carta)
                                .overlay { Capsule().strokeBorder(marcado ? .clear : Paleta.cartaBorde, lineWidth: 1) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(marcado ? .isSelected : [])
            }
        }
    }

    /// Un día sin nada invita a hacer algo, en vez de decir «Nada este día».
    private func diaVacio(_ clave: String) -> some View {
        VStack(spacing: 14) {
            Text("Todavía no hay nada este día")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
            HStack(spacing: 8) {
                botonInvitacion("+ Agendar sesión", Paleta.verde) { agregando = true }
                botonInvitacion("+ Escribir nota", Paleta.nota) { escribiendoNota = true }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .carta()
    }

    private func botonInvitacion(_ t: String, _ c: Color, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(t)
                .font(.redonda(.subheadline, .semibold))
                .foregroundStyle(c)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.opacity(0.1))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(c.opacity(0.35), lineWidth: 1) }
                }
        }
        .buttonStyle(.plain)
    }

    /// Una charla del día, corta: la hora, cuánto duró y cómo empezó.
    ///
    /// LA CHARLA COMO CHARLA, desde el 04/10/2026. Hasta ese día era la
    /// transcripción entera en un bloque, con «Vos:» y «Bitácora:» delante, y
    /// lo más largo del día tapaba todo lo demás. Ahora el adelanto va con el
    /// mismo dibujo que el chat —lo tuyo en globo, lo de Bitácora en serifa— y
    /// al tocarla se abre entera (`CharlaGuardadaView`).
    ///
    /// La duración, como la diría una persona («7 min», no «420s»), y el estado
    /// de la subida sólo si algo falló: que se subió es lo normal y no hace
    /// falta decirlo.
    private func tarjeta(_ e: EntradaLocal) -> some View {
        let turnos = Transcripcion.turnos(e.transcripcion)
        return NavigationLink(value: e) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(e.creadoLocalISO.suffix(8).prefix(5))
                        .font(.redonda(.caption, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Marca.duraznoTexto)
                    if e.duracionSeg > 0 {
                        Text("· \(Transcripcion.duracion(segundos: e.duracionSeg))")
                            .font(.redonda(.caption))
                            .foregroundStyle(Paleta.tintaTenue)
                    }
                    if e.estado == .rechazada {
                        Label("No se pudo subir", systemImage: "xmark.octagon.fill")
                            .font(.redonda(.caption, .semibold))
                            .foregroundStyle(Paleta.rojo)
                    }
                    Spacer()
                }
                if let tuya = turnos.first(where: { $0.de == .vos }) {
                    TurnoDibujado(turno: tuya, lineas: 3)
                }
                if let suya = turnos.first(where: { $0.de == .bitacora }) {
                    TurnoDibujado(turno: suya, lineas: 3)
                }
                Text("Ver la charla entera ›")
                    .font(.redonda(.subheadline, .semibold))
                    .foregroundStyle(Marca.duraznoTexto)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .carta()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Una nota suelta. Mismo lugar que una conversación, otro color.
    ///
    /// Celeste en el borde, en el fondo y en el rótulo, para que se distinga de
    /// lejos de las conversaciones: es lo que la persona escribió para sí, sin
    /// hablar con nadie, y si la quiere mostrar en una consulta tiene que poder
    /// encontrarla sin leer todo el día.
    private func tarjetaDeNota(_ a: Apunte) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(a.creadoEn.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                    .locale(Locale(identifier: "es_ES"))))
                    .font(.redonda(.caption, .bold))
                    .monospacedDigit()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10, weight: .bold))
                Text("Nota")
                    .font(.redonda(.caption, .bold))
                Spacer()
            }
            .foregroundStyle(Paleta.nota)
            Text(a.texto.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tinta)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Paleta.nota.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Paleta.nota.opacity(0.45), lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { editando = a }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nota: \(a.texto)")
        .accessibilityHint("Toca para editarla")
        .accessibilityAddTraits(.isButton)
    }

    private func titulo(_ clave: String) -> String {
        let d = Int(clave.suffix(2))!
        let m = Int(clave.dropFirst(5).prefix(2))!
        let semana = ["Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        let y = Int(clave.prefix(4))!
        let w = c.date(from: DateComponents(year: y, month: m, day: d)).map { c.component(.weekday, from: $0) } ?? 1
        if clave == Self.hoyLogico() { return "Hoy · \(semana[w - 1]) \(d)" }
        return "\(semana[w - 1]) \(d) de \(Self.nombresDeMes[m - 1])"
    }
}

/// Una charla guardada, entera, como se vio en el chat.
///
/// Se abre desde su tarjeta en el calendario. Las dos voces van con el mismo
/// dibujo de la conversación (`TurnoDibujado`): si el chat y el diario
/// mostraran la misma charla de dos maneras, parecerían dos cosas distintas.
struct CharlaGuardadaView: View {
    let entrada: EntradaLocal

    private var titulo: String {
        let d = Int(entrada.diaLogico.suffix(2)) ?? 1
        let m = Int(entrada.diaLogico.dropFirst(5).prefix(2)) ?? 1
        return "\(d) de \(CalendarioView.nombresDeMes[m - 1])"
    }

    private var subtitulo: String {
        let hora = String(entrada.creadoLocalISO.suffix(8).prefix(5))
        return entrada.duracionSeg > 0
            ? "\(hora) · \(Transcripcion.duracion(segundos: entrada.duracionSeg))"
            : hora
    }

    var body: some View {
        ZStack {
            Fondo()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(subtitulo)
                        .font(.redonda(.footnote))
                        .foregroundStyle(Paleta.tintaTenue)
                        .frame(maxWidth: .infinity)
                    ForEach(Array(Transcripcion.turnos(entrada.transcripcion).enumerated()), id: \.offset) { _, turno in
                        TurnoDibujado(turno: turno)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                // La barra de pestañas flota encima: sin este colchón el
                // último turno queda tapado.
                .padding(.bottom, 110)
            }
        }
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Lo que puede haber en un día del calendario: una conversación o una nota.
private enum DelDia: Identifiable {
    case charla(EntradaLocal)
    case nota(Apunte)

    var cuando: Date {
        switch self {
        case .charla(let e): e.creadoEn
        case .nota(let a): a.creadoEn
        }
    }

    var id: String {
        switch self {
        case .charla(let e): "charla-\(e.clientUuid)"
        case .nota(let a): "nota-\(a.creadoEn.timeIntervalSince1970)"
        }
    }
}

/// Escribir una nota para un día del calendario.
///
/// Es la misma nota suelta de «Notas» (`Apunte`), sólo que fechada en el día
/// elegido: así aparece en ese día y no en hoy. Si es hoy, lleva la hora de
/// ahora; si es otro día, el mediodía.
struct NotaDelDiaHoja: View {
    let dia: String
    /// Si viene, se edita esa nota en vez de escribir una nueva.
    var apunte: Apunte? = nil
    @Environment(\.dismiss) private var cerrar
    @State private var texto = ""
    @State private var confirmarBorrado = false
    @FocusState private var foco: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Fondo()
                TextEditor(text: $texto)
                    .font(.redonda(.body))
                    .foregroundStyle(Paleta.tinta)
                    .scrollContentBackground(.hidden)
                    .focused($foco)
                    .padding(.horizontal, 14)
                if texto.isEmpty {
                    Text("Algo para recordar ese día…")
                        .font(.redonda(.body))
                        .foregroundStyle(Paleta.tintaTenue)
                        .padding(.horizontal, 19)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Nota del " + CalendarioView.paraElDia(dia).replacingOccurrences(of: "Agregar al ", with: "").replacingOccurrences(of: " de ", with: "/").components(separatedBy: "/").first!)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar(); cerrar() }
                        .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if apunte != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) { confirmarBorrado = true } label: {
                            Label("Borrar nota", systemImage: "trash")
                        }
                        .tint(Paleta.rojo)
                    }
                }
            }
            .confirmationDialog("¿Borrar esta nota?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { borrar(); cerrar() }
            }
            .onAppear {
                if let apunte { texto = apunte.texto } else { foco = true }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func borrar() {
        guard let apunte, let contexto = AlmacenDeApuntes.contenedor?.mainContext else { return }
        contexto.delete(apunte)
        try? contexto.save()
    }

    private func guardar() {
        guard let contexto = AlmacenDeApuntes.contenedor?.mainContext else { return }
        if let apunte {
            apunte.texto = texto
            apunte.editadoEn = Date()
            try? contexto.save()
            return
        }
        let a = Apunte(texto: texto)
        if dia != CalendarioView.hoyLogico() {
            var c = Calendar.current
            c.timeZone = .current
            let y = Int(dia.prefix(4))!, m = Int(dia.dropFirst(5).prefix(2))!, d = Int(dia.suffix(2))!
            if let f = c.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) {
                a.creadoEn = f; a.editadoEn = f
            }
        }
        contexto.insert(a)
        try? contexto.save()
    }
}
