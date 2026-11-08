import MapKit
import SwiftUI

/// Las cuentas (28/10/2026). Hasta acá la bienvenida terminaba preguntando el
/// nombre; ahora termina en el registro: crear una cuenta o entrar a una.
///
/// CREAR. Lo primero que se pide son los datos que no salen de las charlas:
/// cómo te llamo, fecha de nacimiento, ciudad y país, y con quién vives. Todo se
/// puede saltar. Lo demás —tu gente, lo que te gusta, tu salud— no se pregunta:
/// Bitácora lo va sabiendo por lo que cuentas. Después, un PIN de seis dígitos
/// dos veces, y el servidor da el ID, que se muestra en grande para anotarlo.
///
/// ENTRAR. Con el ID y el PIN, al reinstalar o en otro teléfono. Si se olvida
/// el PIN no hay cómo recuperarlo todavía: se crea otra cuenta (Dusan, 28/10).
struct Registro: View {
    /// Al terminar: lo que dijo, para guardar el nombre en el teléfono.
    let alTerminar: (PerfilDeCuenta) -> Void
    private var config = Config.shared

    init(alTerminar: @escaping (PerfilDeCuenta) -> Void) { self.alTerminar = alTerminar }

    enum Paso: Hashable { case elegir, datos, pin, repetir, id(String), entrar }
    @State private var paso = Paso.elegir
    @State private var perfil = PerfilDeCuenta()
    @State private var pin = ""
    @State private var pin2 = ""
    @State private var idEscrito = ""
    @State private var error: String?
    @State private var esperando = false

    private var cliente: SyncClient { SyncClient(config: config.servidor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch paso {
            case .elegir: elegir
            case .datos: DatosDelRegistro(perfil: $perfil) { paso = .pin }
            case .pin: pedirPin(titulo: "Elige un PIN\nde 6 dígitos", detalle: "Con él y tu ID vuelves a entrar si cambias de teléfono o reinstalas la app.", valor: $pin) {
                paso = .repetir
            }
            case .repetir: pedirPin(titulo: "Repítelo", detalle: error ?? "Para estar seguros de que es el que quieres.", valor: $pin2) {
                Task { await crear() }
            }
            case .id(let id): mostrarId(id)
            case .entrar: entrar
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 26)
        .animation(.snappy(duration: 0.25), value: paso)
    }

    // MARK: - Elegir

    private var elegir: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text("Tu cuenta")
                .font(.redonda(.largeTitle, .bold))
                .foregroundStyle(Paleta.tinta)
            Text("Lo que hables con Bitácora queda en tu cuenta, separado de cualquier otra persona.")
                .font(.redonda(.body))
                .foregroundStyle(Paleta.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Spacer(minLength: 0)
            Boton(texto: "Crear mi cuenta") { paso = .datos }
            Button("Ya tengo una cuenta") { error = nil; paso = .entrar }
                .font(.redonda(.subheadline, .semibold))
                .foregroundStyle(Paleta.musgo)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
    }

    // MARK: - PIN

    private func pedirPin(titulo: String, detalle: String, valor: Binding<String>,
                          listo: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(titulo)
                .font(.redonda(.largeTitle, .bold))
                .foregroundStyle(Paleta.tinta)
                .fixedSize(horizontal: false, vertical: true)
            Text(detalle)
                .font(.redonda(.subheadline))
                .foregroundStyle(error == nil ? Paleta.tintaSuave : Marca.duraznoTexto)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            CampoDePin(valor: valor) { if valor.wrappedValue.count == 6 { listo() } }
                .padding(.top, 30)
            Spacer(minLength: 0)
            Boton(texto: esperando ? "Un momento…" : "Seguir", habilitado: valor.wrappedValue.count == 6 && !esperando, accion: listo)
        }
    }

    private func crear() async {
        guard pin == pin2 else {
            error = "No coinciden. Elige el PIN otra vez."
            pin = ""; pin2 = ""; paso = .pin
            return
        }
        esperando = true
        defer { esperando = false }
        switch await cliente.crearCuenta(pin: pin, perfil: perfil, zona: TimeZone.current.identifier) {
        case .lista(let id, let token):
            config.sesion = token
            config.cuentaId = id
            error = nil
            paso = .id(id ?? "")
        default:
            error = "No se pudo crear la cuenta. Revisa la conexión y prueba de nuevo."
        }
    }

    private func mostrarId(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text("Este es tu ID")
                .font(.redonda(.largeTitle, .bold))
                .foregroundStyle(Paleta.tinta)
            Text(id)
                .font(.system(size: 44, weight: .semibold, design: .monospaced))
                .foregroundStyle(Marca.duraznoTexto)
                .textSelection(.enabled)
                .padding(.top, 22)
            Text("Anótalo en un lugar seguro. Con tu ID y tu PIN vuelves a entrar si cambias de teléfono. Si los pierdes, no hay forma de recuperarlos.")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            Text("También lo ves en Mi espacio.")
                .font(.redonda(.footnote))
                .foregroundStyle(Paleta.tintaTenue)
                .padding(.top, 8)
            Spacer(minLength: 0)
            Boton(texto: "Lo anoté, empezar") { alTerminar(perfil) }
        }
    }

    // MARK: - Entrar

    private var entrar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text("Entrar")
                .font(.redonda(.largeTitle, .bold))
                .foregroundStyle(Paleta.tinta)
            Text("Tu ID")
                .font(.redonda(.footnote, .semibold))
                .foregroundStyle(Paleta.tintaTenue)
                .padding(.top, 26)
            TextField("ABC-123", text: $idEscrito)
                .font(.system(size: 26, weight: .medium, design: .monospaced))
                .foregroundStyle(Paleta.tinta)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .tint(Paleta.musgo)
            Rectangle().fill(Paleta.tintaSuave.opacity(0.25)).frame(height: 1).padding(.top, 8)
            Text("Tu PIN")
                .font(.redonda(.footnote, .semibold))
                .foregroundStyle(Paleta.tintaTenue)
                .padding(.top, 24)
            CampoDePin(valor: $pin) {}
                .padding(.top, 10)
            if let error {
                Text(error)
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Marca.duraznoTexto)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
            Boton(texto: esperando ? "Un momento…" : "Entrar",
                  habilitado: pin.count == 6 && idEscrito.count >= 6 && !esperando) { Task { await entrarYa() } }
            Button("Volver") { error = nil; pin = ""; paso = .elegir }
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
    }

    private func entrarYa() async {
        esperando = true
        defer { esperando = false }
        switch await cliente.entrar(id: idEscrito, pin: pin) {
        case .lista(_, let token):
            config.sesion = token
            let p = await SyncClient(config: config.servidor).perfil()
            config.cuentaId = p?.id
            alTerminar(p ?? PerfilDeCuenta())
        case .incorrecto:
            error = "El ID o el PIN no son correctos."
            pin = ""
        case .trabada:
            error = "Hubo muchos intentos. Espera unos minutos y vuelve a probar."
            pin = ""
        case .sinServidor:
            error = "No se pudo conectar. Revisa la conexión."
        }
    }
}

/// Los datos del registro, en una sola pantalla. Todos se pueden dejar en blanco.
///
/// La fecha de nacimiento y no la edad (Dusan, 28/10/2026): así la edad se
/// mantiene al día sola, sin volver a preguntarla. Y un solo lugar, ciudad y
/// país, en vez de «dónde vives» y «de dónde eres».
struct DatosDelRegistro: View {
    @Binding var perfil: PerfilDeCuenta
    let listo: () -> Void
    @State private var nacimiento: Date?
    @State private var eligiendoFecha = false
    @State private var eligiendoPais = false
    @State private var eligiendoCiudad = false

    private let conQuien = ["Solo/a", "Familia", "Pareja", "Amigos"]

    private static let hoy = Date()
    private static var dia: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Para conocerte")
                    .font(.redonda(.largeTitle, .bold))
                    .foregroundStyle(Paleta.tinta)
                    .padding(.top, 70)
                Text("Lo que no quieras contar, déjalo en blanco.")
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tintaSuave)
                    .padding(.top, -12)
                campo("¿Cómo quieres que te llame?", texto: enlace(\.nombre, tope: 40), tipo: .givenName)
                fechaDeNacimiento
                // Primero el país, después la ciudad, buscada sólo en ese país
                // (Dusan, 28/10/2026).
                VStack(alignment: .leading, spacing: 6) {
                    Text("¿Dónde vives?")
                        .font(.redonda(.footnote, .semibold))
                        .foregroundStyle(Paleta.tintaTenue)
                    HStack(spacing: 16) {
                        elegible(perfil.pais, marca: "País") { eligiendoPais = true }
                        elegible(perfil.ciudad, marca: "Ciudad", habilitado: perfil.pais != nil) { eligiendoCiudad = true }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("¿Con quién vives? (opcional)")
                        .font(.redonda(.footnote, .semibold))
                        .foregroundStyle(Paleta.tintaTenue)
                    HStack(spacing: 8) {
                        ForEach(conQuien, id: \.self) { o in
                            let elegido = perfil.con_quien == o
                            Button { perfil.con_quien = elegido ? nil : o } label: {
                                Text(o)
                                    .font(.redonda(.subheadline, elegido ? .semibold : .regular))
                                    .foregroundStyle(elegido ? Marca.sobreDurazno : Paleta.tinta)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(elegido ? Marca.durazno : Paleta.carta))
                                    .overlay(Capsule().strokeBorder(Paleta.cartaBorde, lineWidth: elegido ? 0 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Boton(texto: "Seguir", accion: listo)
                    .padding(.top, 10)
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: nacimiento) {
            perfil.fecha_nacimiento = nacimiento.map { Self.dia.string(from: $0) }
        }
        .sheet(isPresented: $eligiendoFecha) {
            HojaDeFecha(inicial: nacimiento) { nacimiento = $0; eligiendoFecha = false }
                .presentationDetents([.height(380)])
        }
        .sheet(isPresented: $eligiendoPais) {
            ElegirPais { p in
                if p != perfil.pais { perfil.ciudad = nil }
                perfil.pais = p
                eligiendoPais = false
            }
        }
        .sheet(isPresented: $eligiendoCiudad) {
            ElegirCiudad(pais: perfil.pais ?? "") { perfil.ciudad = $0; eligiendoCiudad = false }
        }
    }

    /// Un campo que se toca para elegir de una lista.
    private func elegible(_ valor: String?, marca: String, habilitado: Bool = true,
                          accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(valor ?? marca)
                        .font(.redonda(.title3))
                        .foregroundStyle(valor == nil ? Paleta.tintaTenue.opacity(habilitado ? 0.8 : 0.4) : Paleta.tinta)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Paleta.tintaTenue.opacity(habilitado ? 1 : 0.4))
                }
                Rectangle().fill(Paleta.tintaSuave.opacity(0.25)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!habilitado)
    }

    /// Vacía hasta que la elige en la hoja: no se manda una fecha que nadie
    /// eligió. Antes, tocar «Elegir la fecha» ponía una sola (28/10/2026).
    private var fechaDeNacimiento: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("¿Cuándo naciste?")
                .font(.redonda(.footnote, .semibold))
                .foregroundStyle(Paleta.tintaTenue)
            Button { eligiendoFecha = true } label: {
                HStack {
                    Text(nacimiento.map { $0.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "es"))) }
                         ?? "Elegir la fecha")
                        .font(.redonda(.title3))
                        .foregroundStyle(nacimiento == nil ? Paleta.tintaTenue.opacity(0.8) : Paleta.tinta)
                    Spacer()
                    if nacimiento != nil {
                        Button { nacimiento = nil } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Paleta.tintaTenue)
                        }
                        .accessibilityLabel("Quitar la fecha")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(Paleta.tintaSuave.opacity(0.25)).frame(height: 1)
        }
    }

    private func enlace(_ k: WritableKeyPath<PerfilDeCuenta, String?>, tope: Int) -> Binding<String> {
        Binding(get: { perfil[keyPath: k] ?? "" }, set: {
            let v = String($0.prefix(tope))
            perfil[keyPath: k] = v.trimmingCharacters(in: .whitespaces).isEmpty ? nil : v
        })
    }

    private func campo(_ titulo: String, texto: Binding<String>, tipo: UITextContentType? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo)
                .font(.redonda(.footnote, .semibold))
                .foregroundStyle(Paleta.tintaTenue)
            TextField("", text: texto)
                .font(.redonda(.title3))
                .foregroundStyle(Paleta.tinta)
                .textContentType(tipo)
                .tint(Paleta.musgo)
            Rectangle().fill(Paleta.tintaSuave.opacity(0.25)).frame(height: 1)
        }
    }
}

/// La fecha en ruedas (día, mes, año), con «Listo». Hasta que no lo toca, no
/// queda ninguna fecha.
struct HojaDeFecha: View {
    let inicial: Date?
    let listo: (Date) -> Void
    @State private var fecha: Date

    init(inicial: Date?, listo: @escaping (Date) -> Void) {
        self.inicial = inicial
        self.listo = listo
        _fecha = State(initialValue: inicial
            ?? Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date())
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("¿Cuándo naciste?")
                .font(.redonda(.headline))
                .foregroundStyle(Paleta.tinta)
                .padding(.top, 22)
            DatePicker("", selection: $fecha,
                       in: Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))!...Date(),
                       displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es"))
            Boton(texto: "Listo") { listo(fecha) }
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .presentationBackground(Paleta.fondoAlto)
    }
}

/// Todos los países, con su nombre en español, y un buscador.
struct ElegirPais: View {
    let elegir: (String) -> Void
    @State private var buscar = ""

    static let todos: [String] = {
        let es = Locale(identifier: "es")
        return Locale.Region.isoRegions
            .filter { $0.subRegions.isEmpty && $0.identifier.count == 2 && Int($0.identifier) == nil }
            .compactMap { es.localizedString(forRegionCode: $0.identifier) }
            .sorted { $0.compare($1, locale: es) == .orderedAscending }
    }()

    private var lista: [String] {
        let q = buscar.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Self.todos }
        return Self.todos.filter { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        NavigationStack {
            List(lista, id: \.self) { p in
                Button(p) { elegir(p) }
                    .foregroundStyle(Paleta.tinta)
            }
            .searchable(text: $buscar, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar país")
            .navigationTitle("País")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Las ciudades de un país, buscadas en los mapas de Apple mientras escribe.
/// Si la suya no aparece, puede usar lo que escribió tal cual.
struct ElegirCiudad: View {
    let pais: String
    let elegir: (String) -> Void
    @State private var buscar = ""
    @State private var buscador = BuscadorDeCiudades()

    var body: some View {
        NavigationStack {
            List {
                let escrito = buscar.trimmingCharacters(in: .whitespaces)
                ForEach(buscador.ciudades, id: \.self) { c in
                    Button(c) { elegir(c) }.foregroundStyle(Paleta.tinta)
                }
                if !escrito.isEmpty && !buscador.ciudades.contains(where: { $0.caseInsensitiveCompare(escrito) == .orderedSame }) {
                    Button("Usar «\(escrito)»") { elegir(escrito) }
                        .foregroundStyle(Marca.duraznoTexto)
                }
                if escrito.isEmpty {
                    Text("Escribe el nombre de tu ciudad en \(pais).")
                        .foregroundStyle(Paleta.tintaTenue)
                }
            }
            .searchable(text: $buscar, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar ciudad")
            .onChange(of: buscar) { buscador.buscar(buscar, en: pais) }
            .navigationTitle(pais)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@Observable
final class BuscadorDeCiudades: NSObject, MKLocalSearchCompleterDelegate {
    var ciudades: [String] = []
    @ObservationIgnored private var pais = ""
    @ObservationIgnored private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = .address
        if #available(iOS 18.0, *) { c.addressFilter = MKAddressFilter(including: .locality) }
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
    }

    /// Con el país pegado al texto («Santi, Chile») Apple no devuelve nada:
    /// se busca lo escrito, con los mapas centrados en el país, y después se
    /// filtra por país.
    func buscar(_ texto: String, en pais: String) {
        if pais != self.pais {
            self.pais = pais
            CLGeocoder().geocodeAddressString(pais) { [weak self] lugares, _ in
                guard let self, let r = lugares?.first?.region as? CLCircularRegion else { return }
                self.completer.region = MKCoordinateRegion(center: r.center, latitudinalMeters: r.radius * 2,
                                                           longitudinalMeters: r.radius * 2)
            }
        }
        let t = texto.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { ciudades = []; return }
        completer.queryFragment = t
    }

    /// Sólo las de ese país, y cada ciudad una vez.
    func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        var vistas = Set<String>()
        ciudades = c.results
            .filter { $0.subtitle.localizedCaseInsensitiveContains(pais) || $0.title.localizedCaseInsensitiveContains(pais) }
            .map { $0.title.components(separatedBy: ",").first!.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(pais) != .orderedSame && vistas.insert($0.lowercased()).inserted }
    }

    func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) { ciudades = [] }
}

/// Seis puntos que se llenan; el teclado numérico va por detrás.
struct CampoDePin: View {
    @Binding var valor: String
    let completo: () -> Void
    @FocusState private var foco: Bool

    var body: some View {
        ZStack {
            // Detrás de los puntos, sin que se vea lo que se escribe.
            TextField("", text: $valor)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($foco)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(width: 1)
                .opacity(0.02)
                .onChange(of: valor) { _, nuevo in
                    let limpio = String(nuevo.filter(\.isNumber).prefix(6))
                    if limpio != nuevo { valor = limpio; return }
                    // Un respiro para que se vea el sexto punto antes de pasar.
                    if limpio.count == 6 {
                        Task { try? await Task.sleep(for: .milliseconds(250)); completo() }
                    }
                }
            HStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i < valor.count ? Marca.durazno : .clear)
                        .overlay(Circle().strokeBorder(i < valor.count ? Marca.durazno : Paleta.tintaSuave.opacity(0.4), lineWidth: 1.5))
                        .frame(width: 18, height: 18)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { foco = true }
        }
        .onAppear { foco = true }
        .accessibilityLabel("PIN, \(valor.count) de 6 dígitos")
    }
}

/// El botón ancho de la bienvenida.
struct Boton: View {
    let texto: String
    var habilitado = true
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Text(texto)
                .font(.redonda(.body, .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Capsule().fill(habilitado ? Paleta.musgo : Paleta.tintaSuave.opacity(0.18)))
                .foregroundStyle(habilitado ? Paleta.fondoAlto : Paleta.tintaSuave)
        }
        .disabled(!habilitado)
    }
}

/// Para el diario que ya existía antes de las cuentas: elige su PIN una vez,
/// recibe su ID, y de paso completa lo que dio al registrarse.
struct ElegirPinView: View {
    let alTerminar: () -> Void
    private var config = Config.shared
    @State private var paso = 0
    @State private var perfil = PerfilDeCuenta()
    @State private var pin = ""
    @State private var pin2 = ""
    @State private var id: String?
    @State private var error: String?

    init(alTerminar: @escaping () -> Void) { self.alTerminar = alTerminar }

    var body: some View {
        ZStack {
            Fondo()
            VStack(alignment: .leading, spacing: 0) {
                switch paso {
                case 0:
                    Spacer(minLength: 0)
                    Text("Bitácora ahora\ntiene cuentas")
                        .font(.redonda(.largeTitle, .bold))
                        .foregroundStyle(Paleta.tinta)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tu diario sigue igual. Solo falta que elijas un PIN: con él y tu ID entras si cambias de teléfono. Antes, unos datos que no salen de las charlas.")
                        .font(.redonda(.body))
                        .foregroundStyle(Paleta.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    Spacer(minLength: 0)
                    Boton(texto: "Seguir") { paso = 1 }
                case 1:
                    DatosDelRegistro(perfil: $perfil) { paso = 2 }
                case 2:
                    pinView(titulo: "Elige un PIN\nde 6 dígitos", valor: $pin) { paso = 3 }
                case 3:
                    pinView(titulo: "Repítelo", valor: $pin2) { Task { await guardar() } }
                default:
                    Spacer(minLength: 0)
                    Text("Este es tu ID")
                        .font(.redonda(.largeTitle, .bold))
                        .foregroundStyle(Paleta.tinta)
                    Text(id ?? "")
                        .font(.system(size: 44, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Marca.duraznoTexto)
                        .textSelection(.enabled)
                        .padding(.top, 22)
                    Text("Anótalo en un lugar seguro. También lo ves en Mi espacio.")
                        .font(.redonda(.subheadline))
                        .foregroundStyle(Paleta.tintaSuave)
                        .padding(.top, 18)
                    Spacer(minLength: 0)
                    Boton(texto: "Lo anoté", accion: alTerminar)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 26)
        }
        .onAppear { perfil.nombre = config.nombre.isEmpty ? nil : config.nombre }
    }

    private func pinView(titulo: String, valor: Binding<String>, listo: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(titulo)
                .font(.redonda(.largeTitle, .bold))
                .foregroundStyle(Paleta.tinta)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(.redonda(.subheadline)).foregroundStyle(Marca.duraznoTexto).padding(.top, 12)
            }
            CampoDePin(valor: valor) { listo() }.padding(.top, 30)
            Spacer(minLength: 0)
            Boton(texto: "Seguir", habilitado: valor.wrappedValue.count == 6, accion: listo)
        }
    }

    private func guardar() async {
        guard pin == pin2 else {
            error = "No coinciden. Elige el PIN otra vez."
            pin = ""; pin2 = ""; paso = 2
            return
        }
        switch await SyncClient(config: config.servidor).elegirPin(pin) {
        case .lista(let nuevo, let token):
            config.sesion = token
            config.cuentaId = nuevo
            await SyncClient(config: config.servidor).guardarPerfil(perfil)
            if let n = perfil.nombre { config.nombre = n }
            id = nuevo
            error = nil
            paso = 4
        default:
            error = "No se pudo guardar. Revisa la conexión."
            pin = ""; pin2 = ""; paso = 2
        }
    }
}
