import SwiftData
import SwiftUI

/// La pestaña «Mi expediente», con dos partes. Se llamó «Mi proceso» hasta la
/// noche del 04/10/2026, cuando Dusan la cambió a «Mi expediente».
///
/// CONSULTAS: lo que te llevas de cada sesión de terapia. Una lista de
/// sesiones, la más reciente arriba; cada una se abre para anotar o releer (lo
/// de adentro está en `SesionView`). MI RESUMEN: lo que dijiste en tus
/// palabras, para llevarle a tu terapeuta (`NotasView`). Hasta el 04/10/2026
/// eso era «Para tu sesión», un botón del calendario; Dusan lo trajo acá para
/// que todo lo de la terapia esté junto.
///
/// LA PORTADA. Al abrir la pestaña se ven dos tarjetas, una por parte, con su
/// dibujo, y se entra a cada una como a una pantalla aparte. Hasta el
/// 04/10/2026 eran dos mitades de un selector arriba de la lista, y Dusan
/// sintió que la gente se iba a perder: no se notaba que eran dos lugares
/// distintos. Eligió esta forma entre tres propuestas («como los íconos de la
/// pantalla de inicio»), y el sillón y el libro entre seis dibujos cada uno.
///
/// En el código sigue llamándose «evaluaciones», que fue su primer nombre.
struct EvaluacionesView: View {
    /// La sección se llama «Mi espacio» desde el 26/10/2026 (antes «Mi
    /// expediente»): Dusan la quiso como el lugar de la persona, con el «Espacio
    /// para relajarte» adentro. Su ícono en la pestaña es la persona en un círculo
    /// (`person.crop.circle`), elegida entre dieciséis opciones; antes fue una hoja, una carpeta, un portapapeles y un rato el sillón de Consultas,
    /// y por unas horas los anillos, que pasaron a la pestaña del chat.

    enum Parte: String, Hashable {
        case consultas = "Consultas"
        case resumen = "Mi resumen"
        case relajarte = "Espacio para relajarte"
        case ficha = "Lo que Bitácora sabe de ti"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Fondo()
                portada
            }
            .navigationTitle("Mi espacio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: Parte.self) { parte in
                ZStack {
                    Fondo()
                    switch parte {
                    case .consultas: consultas
                    case .resumen: NotasView()
                    case .relajarte: EspacioParaRelajarteView()
                    case .ficha: MiFichaView()
                    }
                }
                .navigationTitle(parte.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            // Acá y no en la lista: el NavigationStack es de toda la pestaña.
            // Con el contenedor de las sesiones, que la lista recibe aparte.
            .navigationDestination(for: SesionDeTerapia.self) { sesion in
                if let contenedor = AlmacenDeSesiones.contenedor {
                    SesionView(sesion: sesion).modelContainer(contenedor)
                }
            }
        }
    }

    /// Las sesiones se cuentan para la tarjeta de Consultas. Si su archivo no
    /// abrió, la portada sale igual, sin la cuenta: adentro se explica.
    @ViewBuilder private var portada: some View {
        if let contenedor = AlmacenDeSesiones.contenedor {
            PortadaConSesiones().modelContainer(contenedor)
        } else {
            Portada(sesiones: nil, paraRevisar: 0)
        }
    }

    @ViewBuilder private var consultas: some View {
        if let contenedor = AlmacenDeSesiones.contenedor {
            ListaDeSesiones().modelContainer(contenedor)
        } else {
            sinAlmacen
        }
    }

    /// El archivo de las sesiones no abrió. No debería pasar; si pasa, se dice
    /// en vez de mostrar una lista vacía que parezca que no hay nada guardado.
    private var sinAlmacen: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Paleta.bitacora)
            Text("No se pudieron abrir tus sesiones")
                .font(.redonda(.headline))
                .foregroundStyle(Paleta.tinta)
            Text("Cierra la app y vuelve a abrirla. Lo que ya habías anotado sigue guardado en el teléfono.")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)
    }
}

private struct PortadaConSesiones: View {
    @Query private var sesiones: [SesionDeTerapia]

    var body: some View {
        Portada(sesiones: sesiones.count, paraRevisar: sesiones.filter { !$0.revisada }.count)
            // Los borradores de las consultas llegan al abrir la pestaña, y
            // así el aviso de «para revisar» ya está en la tarjeta.
            .task { await Agenda.shared.actualizar() }
    }
}

/// La portada de Mi espacio (propuesta 2, 26/10/2026): la próxima consulta
/// en grande y en durazno, y debajo tres tarjetas anchas. Antes eran dos
/// tarjetas lado a lado y el espacio para relajarte abajo.
///
/// Cada una dice lo justo para saber qué hay adentro sin entrar: cuántas
/// sesiones hay anotadas, y de qué mes es el resumen. Las que llegaron armadas
/// desde una charla y faltan revisar se cuentan aparte, en un círculo dorado
/// sobre el dibujo: es lo único que pide algo de la persona.
private struct Portada: View {
    /// `nil` si el archivo de las sesiones no abrió.
    let sesiones: Int?
    let paraRevisar: Int
    /// La ficha viva, si este diario la tiene (27/10/2026).
    @State private var ficha: Ficha?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ProximaConsulta()
                    .padding(.bottom, 4)
                NavigationLink(value: EvaluacionesView.Parte.consultas) {
                    fila(AnyView(Sillon()), color: Paleta.musgo, titulo: "Consultas",
                         detalle: cuantasSesiones, aviso: paraRevisar)
                }
                NavigationLink(value: EvaluacionesView.Parte.resumen) {
                    fila(AnyView(Libro()), color: Paleta.nota, titulo: "Mi resumen",
                         detalle: "\(mesDeHoy), listo para el PDF", aviso: 0)
                }
                // Las herramientas, para usarlas cuando quieras (26/10/2026).
                NavigationLink(value: EvaluacionesView.Parte.relajarte) {
                    fila(AnyView(Image(systemName: "wind").resizable().scaledToFit().fontWeight(.semibold)),
                         color: Marca.durazno, titulo: "Espacio para relajarte",
                         detalle: "Respirar · ponerle nombre", aviso: 0)
                }
                // Sólo en los diarios que la tienen. El círculo pide leer el
                // aviso, que es lo único que espera algo de la persona.
                if let ficha, ficha.activa {
                    NavigationLink(value: EvaluacionesView.Parte.ficha) {
                        fila(AnyView(Image(systemName: "text.quote").resizable().scaledToFit().fontWeight(.semibold)),
                             color: Marca.duraznoTexto, titulo: "Lo que Bitácora sabe de ti",
                             detalle: ficha.avisada ? cuantosDatos(ficha) : "Léelo antes de que se arme",
                             aviso: ficha.avisada ? 0 : 1)
                    }
                }
                // El ID de la cuenta, para anotarlo (28/10/2026).
                if let id = Config.shared.cuentaId {
                    Text("Tu ID: \(id)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Paleta.tintaTenue)
                        .textSelection(.enabled)
                        .padding(.top, 14)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        .task { ficha = await SyncClient(config: Config.shared.servidor).ficha() }
    }

    private func cuantosDatos(_ f: Ficha) -> String {
        let n = f.secciones.reduce(0) { $0 + $1.datos.count }
        if f.cuentaSeBorraEl != nil { return "Tu cuenta está en la papelera" }
        return n == 0 ? "Se arma con tus charlas" : n == 1 ? "1 dato, con tus palabras" : "\(n) datos, con tus palabras"
    }

    private var cuantasSesiones: String? {
        switch sesiones {
        case nil: nil
        case 0?: "Ninguna todavía"
        case 1?: "1 sesión"
        case let n?: "\(n) sesiones"
        }
    }

    /// El mes con que abre «Mi resumen», que es siempre el de hoy.
    private var mesDeHoy: String {
        let mes = Int(CalendarioView.hoyLogico().dropFirst(5).prefix(2)) ?? 1
        return Resumen.meses[mes - 1].capitalized
    }

    /// Una tarjeta ancha (propuesta 2, 26/10/2026): el ícono en su color, el
    /// título y lo justo para saber qué hay adentro. Lo que falta revisar se
    /// cuenta en un círculo dorado, que es lo único que pide algo de la persona.
    private func fila(_ dibujo: AnyView, color: Color, titulo: String, detalle: String?, aviso: Int) -> some View {
        HStack(spacing: 14) {
            dibujo
                .frame(width: 22, height: 22)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.redonda(.headline))
                    .foregroundStyle(Paleta.tinta)
                if let detalle {
                    Text(detalle)
                        .font(.redonda(.caption))
                        .foregroundStyle(Paleta.tintaTenue)
                }
            }
            Spacer(minLength: 6)
            if aviso > 0 {
                Text("\(aviso)")
                    .font(.redonda(.caption2, .bold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Capsule().fill(Paleta.bitacora))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Paleta.tintaTenue)
        }
        .padding(14)
        .carta(radio: 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([titulo, detalle, aviso > 0 ? "\(aviso) para revisar" : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// Arriba de todo en Mi expediente: la próxima consulta, o cómo agendarla.
///
/// Desde el 06/10/2026. Dusan eligió la propuesta B («la próxima consulta
/// arriba») entre tres para el espacio vacío debajo de las dos tarjetas, y de
/// ella sólo estos dos estados: sin consulta, un botón que lleva al calendario
/// con la hoja de consulta nueva abierta; con consulta, cuándo es y «Preparar»,
/// que abre el chat con Bitácora en el modo de antes de la consulta
/// (`Navegacion.preparando`). Tocar la tarjeta lleva a ese día del calendario.
///
/// Cuenta sólo una consulta confirmada: una que propuso Bitácora se confirma en
/// el calendario, y recién ahí aparece acá.
private struct ProximaConsulta: View {
    private var agenda = Agenda.shared
    private var navegacion = Navegacion.shared

    var body: some View {
        if let e = Evento.proximaConsulta(en: agenda.eventos, ahora: Navegacion.ahora()) {
            conConsulta(e)
        } else {
            sinConsulta
        }
    }

    /// La consulta en grande y en durazno (propuesta 2, 26/10/2026): es lo que
    /// más se mira antes de una sesión. Tocarla lleva a ese día del calendario;
    /// el botón abre el chat para prepararla. El texto va oscuro siempre: sobre
    /// el durazno, el claro no se lee en ningún modo.
    private func conConsulta(_ e: Evento) -> some View {
        let oscuro = Color(red: 0.08, green: 0.09, blue: 0.06)
        return VStack(alignment: .leading, spacing: 0) {
            Button { navegacion.verEnElCalendario(e.dia) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Sillon().frame(width: 15, height: 15)
                        Text("Próxima consulta · "
                             + Evento.cuantoFalta(hasta: e.dia, desde: CalendarioView.hoyLogico()))
                            .font(.redonda(.caption, .medium))
                    }
                    .foregroundStyle(oscuro.opacity(0.7))
                    Text(Agenda.cuando(e))
                        .font(.dicha(.title2))
                        .foregroundStyle(oscuro)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre ese día en el calendario")
            Button { navegacion.preparar(e) } label: {
                Text("Prepararla con Bitácora")
                    .font(.redonda(.subheadline, .semibold))
                    .foregroundStyle(Marca.durazno)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(oscuro))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .accessibilityHint("Abre el chat para preparar la consulta con Bitácora")
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Marca.durazno))
    }

    /// Con el borde punteado: es un lugar que espera algo, no una tarjeta llena.
    private var sinConsulta: some View {
        VStack(spacing: 0) {
            Sillon()
                .frame(width: 26, height: 26)
                .foregroundStyle(Paleta.musgo)
            Text("Sin consulta agendada")
                .font(.redonda(.headline))
                .foregroundStyle(Paleta.tinta)
                .padding(.top, 8)
            Text("Cuando tengas una, anótala aquí")
                .font(.redonda(.caption))
                .foregroundStyle(Paleta.tintaSuave)
                .padding(.top, 2)
            Button { navegacion.agendarConsulta() } label: {
                Label("Agendar consulta", systemImage: "plus")
                    .font(.redonda(.subheadline, .semibold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Paleta.musgo))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Paleta.cartaBorde, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
    }
}

private struct ListaDeSesiones: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: [SortDescriptor(\SesionDeTerapia.fecha, order: .reverse),
                  SortDescriptor(\SesionDeTerapia.numero, order: .reverse)])
    private var sesiones: [SesionDeTerapia]

    /// Se está anotando una sesión nueva, paso por paso.
    @State private var anotandoNueva = false

    var body: some View {
        Group {
            if sesiones.isEmpty { vacio.frame(maxHeight: .infinity) } else { lista }
        }
        // El «+» es de las consultas: en «Mi resumen» no hay nada que anotar.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: nueva) {
                    Image(systemName: "plus")
                        .foregroundStyle(Paleta.tintaSuave)
                }
                .accessibilityLabel("Anotar una sesión nueva")
            }
        }
        // Los borradores de las consultas llegan por acá: al abrir la
        // pestaña, la agenda se pone al día y crea las sesiones para revisar.
        .task { await Agenda.shared.actualizar() }
        // A pantalla completa, por encima de la barra de pestañas: mientras
        // se anota una sesión no hay nada más en la pantalla.
        .fullScreenCover(isPresented: $anotandoNueva) {
            HojaDeSesionNueva(numero: (sesiones.map(\.numero).max() ?? 0) + 1,
                              contexto: contexto) { anotandoNueva = false }
        }
    }

    // MARK: - Sin sesiones todavía

    private var vacio: some View {
        VStack(spacing: 14) {
            Sillon(grosor: 1.5)
                .frame(width: 44, height: 44)
                .foregroundStyle(Paleta.musgoSuave)
            Text("Lo que te llevas de cada sesión")
                .font(.redonda(.title3, .semibold))
                .foregroundStyle(Paleta.tinta)
                .multilineTextAlignment(.center)
            Text("Después de una sesión con tu terapeuta, anota qué entendiste, qué aprendiste, cómo te sentiste, los temas que se trataron y en qué sentiste que avanzaste. Si hablas de la sesión con Bitácora, te la deja armada para revisar.")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
                .multilineTextAlignment(.center)
            Button(action: nueva) {
                Text("Anotar mi primera sesión")
                    .font(.redonda(.subheadline, .semibold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Paleta.musgo))
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        // La barra de pestañas flota abajo: sin esto el bloque queda corrido.
        .padding(.bottom, 60)
    }

    // MARK: - La lista

    /// ORDENADA, desde la noche del 04/10/2026 (Dusan eligió la propuesta A
    /// de tres; sentía que quien la abriera se iba a perder). Arriba lo único
    /// que pide algo, las sesiones para revisar, con una frase que dice de
    /// dónde salieron. Abajo las demás, por mes, un renglón cada una: el número,
    /// el día y lo primero que se escribió. Antes eran tarjetas altas, todas
    /// iguales, con hasta cuatro temas largos cada una.
    private var lista: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sesiones.filter { !$0.revisada }) { s in
                    NavigationLink(value: s) { paraRevisar(s) }
                        .buttonStyle(.plain)
                }
                ForEach(porMes, id: \.clave) { grupo in
                    Text(grupo.titulo.uppercased())
                        .font(.redonda(.caption2, .bold))
                        .tracking(0.6)
                        .foregroundStyle(Paleta.tintaTenue)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(grupo.sesiones.enumerated()), id: \.element.id) { i, s in
                            if i > 0 { Divider().overlay(Paleta.cartaBorde) }
                            NavigationLink(value: s) { fila(s) }
                                .buttonStyle(.plain)
                        }
                    }
                    .carta(radio: 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            // Para que la última fila no quede debajo de la barra flotante.
            .padding(.bottom, 110)
        }
    }

    /// Las revisadas, por mes, del más nuevo al más viejo (ya vienen así).
    private var porMes: [(clave: String, titulo: String, sesiones: [SesionDeTerapia])] {
        let cal = Calendar.current
        let anioActual = cal.component(.year, from: Date())
        var grupos: [(clave: String, titulo: String, sesiones: [SesionDeTerapia])] = []
        for s in sesiones where s.revisada {
            let c = cal.dateComponents([.year, .month], from: s.fecha)
            let clave = "\(c.year ?? 0)-\(c.month ?? 0)"
            if grupos.last?.clave == clave {
                grupos[grupos.count - 1].sesiones.append(s)
            } else {
                let mes = Resumen.meses[max(0, (c.month ?? 1) - 1)]
                let titulo = c.year == anioActual ? mes : "\(mes) de \(c.year ?? 0)"
                grupos.append((clave, titulo, [s]))
            }
        }
        return grupos
    }

    /// Una sesión que armó Bitácora y falta mirar: qué es, de dónde salió y
    /// qué hacer con ella.
    private func paraRevisar(_ s: SesionDeTerapia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sesión \(s.numero) · \(diaLargo(s.fecha))")
                    .font(.redonda(.headline))
                    .foregroundStyle(Paleta.tinta)
                Spacer()
                Text("Para revisar")
                    .font(.redonda(.caption, .bold))
                    .foregroundStyle(Paleta.bitacora)
            }
            Text("Bitácora la armó con lo que le contaste después de la consulta. Mírala y cámbiala si hace falta.")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Revisar")
                .font(.redonda(.subheadline, .semibold))
                .foregroundStyle(Paleta.fondoAlto)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(Paleta.bitacora))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Paleta.bitacora.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Paleta.bitacora.opacity(0.4), lineWidth: 1)
                }
        }
        .contentShape(Rectangle())
    }

    /// Un renglón: el número, el día y lo primero que se escribió.
    private func fila(_ s: SesionDeTerapia) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Sesión \(s.numero)")
                        .font(.redonda(.headline))
                        .foregroundStyle(Paleta.tinta)
                    Text(diaCorto(s.fecha))
                        .font(.redonda(.caption))
                        .foregroundStyle(Paleta.tintaTenue)
                }
                if let (rotulo, texto) = adelanto(s) {
                    Text("\(rotulo): \(texto)")
                        .font(.redonda(.subheadline))
                        .foregroundStyle(Paleta.tintaSuave)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Paleta.tintaTenue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Lo primero que haya escrito, con su rótulo, para reconocer la sesión
    /// sin abrirla.
    private func adelanto(_ s: SesionDeTerapia) -> (String, String)? {
        [("Entendí", s.entendi), ("Me aportó", s.aporte), ("Me sentí", s.sentir), ("Avancé", s.avance)]
            .map { ($0.0, $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .first { !$0.1.isEmpty }
    }

    /// «jue, 24 sept».
    private func diaCorto(_ f: Date) -> String {
        f.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "es")))
    }

    /// «jueves 8 de octubre».
    private func diaLargo(_ f: Date) -> String {
        f.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es")))
            .replacingOccurrences(of: ",", with: "")
    }

    // MARK: - Crear

    private func nueva() { anotandoNueva = true }
}

/// La hoja de una sesión nueva: la crea y la deja anotar paso por paso.
///
/// La sesión se crea ACÁ, cuando la hoja ya está en pantalla, y no en el botón
/// que la abre. Estuvo en el botón, y probando apareció el caso: si la hoja no
/// llegaba a mostrarse —un toque justo mientras se cambiaba de pestaña—, la
/// sesión ya estaba creada y quedaba una tarjeta vacía en la lista que nadie
/// había querido. Así, sin hoja no hay sesión.
///
/// Arranca con el número que sigue y la fecha de hoy, que son los dos primeros
/// pasos y se pueden cambiar ahí. Y se guarda desde el primer momento, no al
/// terminar: si la app se cierra en el paso cuatro, lo anotado en los tres
/// primeros sigue estando. Si la persona sale sin guardar, se borra.
private struct HojaDeSesionNueva: View {
    let numero: Int
    let contexto: ModelContext
    let alCerrar: () -> Void

    @State private var sesion: SesionDeTerapia?

    var body: some View {
        Group {
            if let sesion {
                AnotarSesionView(sesion: sesion, modo: .nueva) { descartar in
                    if descartar { contexto.delete(sesion) }
                    try? contexto.save()
                    alCerrar()
                }
            } else {
                Fondo()
            }
        }
        .onAppear {
            guard sesion == nil else { return }
            let nueva = SesionDeTerapia(numero: numero)
            contexto.insert(nueva)
            try? contexto.save()
            sesion = nueva
        }
    }
}

/// Acomoda lo que tenga adentro en renglones, y pasa al siguiente cuando no
/// entra más. Es lo que hace falta para las etiquetas de los temas, que son de
/// largos distintos.
struct Fluido: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        let filas = acomodar(subviews, ancho: ancho)
        let alto = filas.last.map { $0.y + $0.alto } ?? 0
        let usado = filas.map(\.ancho).max() ?? 0
        return CGSize(width: proposal.width ?? usado, height: alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for fila in acomodar(subviews, ancho: bounds.width) {
            for (indice, x, tamano) in fila.piezas {
                subviews[indice].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + fila.y),
                                       proposal: ProposedViewSize(tamano))
            }
        }
    }

    private struct Fila {
        var y: CGFloat
        var alto: CGFloat = 0
        var ancho: CGFloat = 0
        var piezas: [(Int, CGFloat, CGSize)] = []
    }

    private func acomodar(_ subviews: Subviews, ancho: CGFloat) -> [Fila] {
        var filas = [Fila(y: 0)]
        for (i, vista) in subviews.enumerated() {
            // A lo sumo el ancho del renglón: una etiqueta que no entra en uno
            // pasa a dos líneas en vez de salirse por el borde (04/10/2026, un
            // tema largo de una sesión se cortaba).
            let t = vista.sizeThatFits(ProposedViewSize(width: ancho.isFinite ? ancho : nil, height: nil))
            var fila = filas[filas.count - 1]
            let x = fila.piezas.isEmpty ? 0 : fila.ancho + espacio
            if !fila.piezas.isEmpty, x + t.width > ancho {
                filas.append(Fila(y: fila.y + fila.alto + espacio))
                fila = filas[filas.count - 1]
                fila.piezas.append((i, 0, t))
                fila.ancho = t.width
            } else {
                fila.piezas.append((i, x, t))
                fila.ancho = x + t.width
            }
            fila.alto = max(fila.alto, t.height)
            filas[filas.count - 1] = fila
        }
        return filas
    }
}
