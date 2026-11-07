import SwiftData
import SwiftUI
import UIKit

/// El PDF de «Mi resumen», para mandarle al psicólogo.
///
/// Se dibuja en el teléfono con el HTML de `Resumen.html` y el motor de
/// impresión de iOS, que corta las páginas solo: una frase no queda partida
/// entre dos hojas, ni la fecha de un día separada de lo que sigue. Un día
/// entero sí puede seguir en la hoja siguiente: no partirlo dejaba medias
/// páginas en blanco (un mes eran quince hojas). Tamaño A4, que es el de las
/// impresoras de acá.
///
/// El archivo queda en la carpeta temporal y sale del teléfono sólo si la
/// persona lo manda desde la hoja de compartir: nada se sube a ningún lado.
enum ExportarResumen {
    /// A4, en puntos.
    static let pagina = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)

    @MainActor
    static func pdf(html: String, pie: String, nombre: String) throws -> (url: URL, paginas: Int) {
        let paginas = Paginas(pie: pie)
        paginas.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)

        let datos = NSMutableData()
        UIGraphicsBeginPDFContextToData(datos, pagina, [kCGPDFContextTitle as String: nombre])
        paginas.prepare(forDrawingPages: NSRange(location: 0, length: paginas.numberOfPages))
        for i in 0..<paginas.numberOfPages {
            UIGraphicsBeginPDFPage()
            paginas.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let carpeta = FileManager.default.temporaryDirectory.appending(path: "resumen", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let limpio = nombre.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = carpeta.appending(path: "\(limpio).pdf")
        try datos.write(to: url, options: .atomic)
        return (url, paginas.numberOfPages)
    }

    /// Las páginas: el margen y, abajo de cada una, de quién es y qué página.
    private final class Paginas: UIPrintPageRenderer {
        let pie: String

        init(pie: String) {
            self.pie = pie
            super.init()
            footerHeight = 22
        }

        override var paperRect: CGRect { ExportarResumen.pagina }
        override var printableRect: CGRect { ExportarResumen.pagina.insetBy(dx: 52, dy: 46) }

        override func drawFooterForPage(at indice: Int, in rect: CGRect) {
            let texto = "\(pie) · página \(indice + 1) de \(numberOfPages)" as NSString
            let estilo = NSMutableParagraphStyle()
            estilo.alignment = .center
            texto.draw(in: rect.offsetBy(dx: 0, dy: 6), withAttributes: [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor(white: 0.55, alpha: 1),
                .paragraphStyle: estilo,
            ])
        }
    }
}

/// La hoja para exportar: un calendario del mes con los días que tienen algo,
/// para elegirlos uno por uno.
///
/// Al abrir vienen marcados todos los del mes; se tocan para sacarlos o
/// volver a ponerlos, y no tienen que ser seguidos. Así lo pidió Dusan el
/// 04/10/2026, después de probar un «desde / hasta»: si pasó algo puntual que
/// se habló en dos días, que se pueda mandar sólo eso. Los días sin frases
/// quedan apagados: no hay nada que mandar de ellos.
///
/// Las frases se piden al servidor de a un mes, al mirarlo, y el PDF se arma
/// con esas mismas: lo que se ve marcado es lo que va.
///
/// Un día con charla pero sin frases separadas se marca igual que los demás
/// (lo pidió Dusan): en el PDF va lo que dijo en la charla, textual. Las
/// charlas salen del teléfono, como en el calendario. Todos los días con algo
/// se ven iguales; qué es cada cosa lo explica el botón de información, no la
/// pantalla.
struct HojaDeExportar: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var entradas: [EntradaLocal]
    @State private var anio: Int
    @State private var mes: Int
    /// Las frases de cada día, de los meses que ya se miraron.
    @State private var porDia: [String: [NotaDelDia]] = [:]
    @State private var mesesTraidos: Set<String> = []
    @State private var elegidos: Set<String> = []
    /// Si la persona ya eligió algo a mano. Hasta entonces, el mes que se mira
    /// llega con todos sus días marcados.
    @State private var tocado = false
    @State private var cargando = false
    @State private var sinServidorAlMirar = false
    @State private var estado = Estado.eligiendo
    @State private var explicando = false
    /// Lo que eligió de su ficha para su psicólogo (Mi espacio). Va arriba.
    @State private var fichaCompartida: [SeccionDeLaFicha] = []

    enum Estado: Equatable {
        case eligiendo
        case armando
        case listo(URL, paginas: Int, dias: Int)
        case fallo
    }

    init(anio: Int, mes: Int) {
        _anio = State(initialValue: anio)
        _mes = State(initialValue: mes)
    }

    private var claveDelMes: String { String(format: "%04d-%02d", anio, mes) }
    private var grilla: GrillaMes { CalendarioMensual.grilla(anio: anio, mes: mes) }
    private var conCharla: Set<String> { Set(entradas.map(\.diaLogico)) }

    /// Los días de un mes que se pueden mandar: los que tienen frases y los que
    /// tuvieron charla. Sólo si ese mes ya se trajo del servidor: sin las
    /// frases, un día que sí las tiene se mandaría como si no.
    private func conAlgo(_ m: String) -> Set<String> {
        guard mesesTraidos.contains(m) else { return [] }
        return Set(porDia.keys.filter { $0.hasPrefix(m) }).union(conCharla.filter { $0.hasPrefix(m) })
    }

    /// Los elegidos son justo todos los días con algo de un mes: el documento
    /// dice «septiembre de 2026» y no la lista.
    private var esElMes: Bool {
        let meses = Set(elegidos.map { String($0.prefix(7)) })
        guard meses.count == 1, let m = meses.first else { return false }
        return elegidos == conAlgo(m)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Fondo()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        calendario
                            .padding(14)
                            .carta()

                        HStack {
                            Text(elegidos.isEmpty ? "Elige al menos un día"
                                 : Resumen.escrito(dias: Array(elegidos), esElMes: esElMes))
                                .font(.redonda(.subheadline, .semibold))
                                .foregroundStyle(Paleta.tinta)
                            Spacer()
                        }
                        HStack(spacing: 18) {
                            Button("Todo el mes") { marcarElMes(true) }
                            Button("Ninguno") { marcarElMes(false) }
                        }
                        .font(.redonda(.subheadline, .semibold))
                        .foregroundStyle(Paleta.musgo)
                        .disabled(conAlgo(claveDelMes).isEmpty)

                        resultado
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Exportar a PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                        .font(.redonda(.body))
                        .foregroundStyle(Paleta.tintaSuave)
                }
                // La explicación, sólo si la pide: en la pantalla ocupaba lugar
                // cada vez, para algo que se entiende solo después de la primera.
                ToolbarItem(placement: .primaryAction) {
                    Button { explicando = true } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Paleta.tintaSuave)
                    }
                    .accessibilityLabel("Qué es esto")
                    .popover(isPresented: $explicando, arrowEdge: .top) {
                        Text("Arma un PDF con lo que dijiste, para mandarle a tu psicólogo. Vienen marcados todos los días del mes en que hablaste; toca un día para sacarlo o volver a ponerlo. Van tus frases tal como las dijiste, y de los días en que no se separaron frases, lo que dijiste en la charla. El PDF lo mandas tú desde el teléfono; no se sube a ningún lado.")
                            .font(.redonda(.subheadline))
                            .foregroundStyle(Paleta.tinta)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 290)
                            .padding(16)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
        .task(id: claveDelMes) { await traerElMes() }
        // Cambiar los días deja viejo el PDF que ya estaba armado.
        .onChange(of: elegidos) { estado = .eligiendo }
    }

    // MARK: - El calendario

    private var calendario: some View {
        VStack(spacing: 10) {
            HStack {
                flecha("chevron.left", -1, "Mes anterior")
                Spacer()
                Text("\(Resumen.meses[mes - 1]) \(String(anio))")
                    .font(.redonda(.headline))
                    .foregroundStyle(Paleta.tinta)
                Spacer()
                flecha("chevron.right", 1, "Mes siguiente")
            }
            HStack(spacing: 0) {
                ForEach(Array(CalendarioMensual.encabezados.enumerated()), id: \.offset) { _, d in
                    Text(d)
                        .font(.redonda(.caption2, .bold))
                        .foregroundStyle(Paleta.tintaTenue)
                        .frame(maxWidth: .infinity)
                }
            }
            ZStack {
                VStack(spacing: 6) {
                    ForEach(Array(grilla.semanas.enumerated()), id: \.offset) { _, semana in
                        HStack(spacing: 6) {
                            ForEach(Array(semana.enumerated()), id: \.offset) { _, clave in
                                if let clave { celda(clave) } else { Color.clear.frame(maxWidth: .infinity).frame(height: 38) }
                            }
                        }
                    }
                }
                .opacity(cargando ? 0.35 : 1)
                if cargando { ProgressView().tint(Paleta.tintaSuave) }
            }
            if sinServidorAlMirar {
                Text("No se pudo conectar con el servidor para ver este mes.")
                    .font(.redonda(.footnote))
                    .foregroundStyle(Paleta.tintaSuave)
            } else if !cargando && conAlgo(claveDelMes).isEmpty {
                Text("En \(Resumen.meses[mes - 1]) no hay nada guardado.")
                    .font(.redonda(.footnote))
                    .foregroundStyle(Paleta.tintaSuave)
            }
        }
    }

    private func celda(_ clave: String) -> some View {
        let tiene = conAlgo(String(clave.prefix(7))).contains(clave)
        let elegido = elegidos.contains(clave)
        return Button {
            tocado = true
            if elegido { elegidos.remove(clave) } else { elegidos.insert(clave) }
        } label: {
            Text(String(Int(clave.suffix(2))!))
                .font(.redonda(.callout, elegido ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(elegido ? Paleta.fondoAlto : tiene ? Paleta.tinta : Paleta.tintaTenue.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(elegido ? Paleta.musgo : .clear)
                }
                .overlay {
                    if tiene && !elegido {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Paleta.musgo.opacity(0.6), lineWidth: 1.2)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!tiene)
        .accessibilityLabel("\(Resumen.fechaCorta(clave))\(tiene ? "" : ", sin nada guardado")")
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }

    private func flecha(_ icono: String, _ delta: Int, _ etiqueta: String) -> some View {
        Button {
            let r = CalendarioMensual.corrido(anio: anio, mes: mes, meses: delta)
            anio = r.anio
            mes = r.mes
        } label: {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Paleta.tintaSuave)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Paleta.fondoBajo.opacity(0.7)))
        }
        .accessibilityLabel(etiqueta)
    }

    private func marcarElMes(_ todos: Bool) {
        tocado = true
        let delMes = conAlgo(claveDelMes)
        if todos { elegidos.formUnion(delMes) } else { elegidos.subtract(delMes) }
    }

    /// Trae las frases del mes que se está mirando, una vez. Mientras la persona
    /// no haya elegido nada a mano, el mes llega con todos sus días marcados:
    /// por defecto va el mes entero. Así, si abre la hoja en un mes vacío y
    /// pasa al anterior, ese llega marcado.
    private func traerElMes() async {
        let m = claveDelMes
        sinServidorAlMirar = false
        guard !mesesTraidos.contains(m) else { return }
        if mesesTraidos.isEmpty, let f = await SyncClient(config: Config.shared.servidor).fichaCompartida() {
            fichaCompartida = f
        }
        cargando = true
        defer { cargando = false }
        let t = Resumen.mes(anio: anio, mes: mes)
        guard let notas = await SyncClient(config: Config.shared.servidor).notas(desde: t.desde, hasta: t.hasta) else {
            sinServidorAlMirar = true
            return
        }
        for n in notas { porDia[n.dia, default: []].append(n) }
        mesesTraidos.insert(m)
        if !tocado && elegidos.isEmpty { elegidos = conAlgo(m) }
    }

    // MARK: - El documento

    @ViewBuilder private var resultado: some View {
        switch estado {
        case .eligiendo:
            boton("Crear PDF", accion: armar)
                .disabled(elegidos.isEmpty)
                .opacity(elegidos.isEmpty ? 0.5 : 1)
        case .armando:
            HStack(spacing: 10) {
                ProgressView().tint(Paleta.tintaSuave)
                Text("Armando el documento…")
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tintaSuave)
            }
        case .listo(let url, let paginas, let dias):
            VStack(alignment: .leading, spacing: 12) {
                Text("Listo: \(dias == 1 ? "un día" : "\(dias) días"), \(paginas == 1 ? "una página" : "\(paginas) páginas").")
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tinta)
                ShareLink(item: url, preview: SharePreview("Mi resumen")) {
                    Label("Enviar o guardar", systemImage: "square.and.arrow.up")
                        .font(.redonda(.subheadline, .semibold))
                        .foregroundStyle(Paleta.fondoAlto)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Paleta.musgo))
                }
            }
        case .fallo:
            Text("No se pudo armar el PDF. Prueba de nuevo.")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tintaSuave)
            boton("Probar de nuevo", accion: armar)
        }
    }

    private func boton(_ texto: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(texto)
                .font(.redonda(.subheadline, .semibold))
                .foregroundStyle(Paleta.fondoAlto)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(Paleta.musgo))
        }
    }

    private func armar() {
        let dias = elegidos.sorted()
        let notas = dias.flatMap { porDia[$0] ?? [] }
        // De los días sin frases, lo que dijo en cada charla de ese día.
        let charlas: [Resumen.CharlaSinFrases] = dias.filter { porDia[$0] == nil }.flatMap { d in
            entradas.filter { $0.diaLogico == d }
                .sorted { $0.creadoEn < $1.creadoEn }
                .map { Resumen.CharlaSinFrases(dia: d, hora: String($0.creadoLocalISO.dropFirst(11).prefix(5)),
                                               dicho: Transcripcion.loQueDijo($0.transcripcion)) }
                .filter { !$0.dicho.isEmpty }
        }
        guard !notas.isEmpty || !charlas.isEmpty else { return }
        let nombre = Config.shared.nombre.trimmingCharacters(in: .whitespaces)
        let tramo = Resumen.escrito(dias: dias, esElMes: esElMes)
        let html = Resumen.html(notas: notas, charlas: charlas, tramo: tramo,
                                nombre: nombre.isEmpty ? nil : nombre, generado: Agenda.dia(Date()),
                                ficha: fichaCompartida)
        let archivo = nombre.isEmpty ? "Mi resumen - \(tramo)" : "Mi resumen de \(nombre) - \(tramo)"
        let pie = nombre.isEmpty ? "Mi resumen · \(tramo)" : "Mi resumen de \(nombre) · \(tramo)"
        estado = .armando
        // Un respiro para que se vea «Armando…»: el PDF se dibuja en el hilo
        // principal, que es donde vive el motor de impresión.
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            do {
                let r = try ExportarResumen.pdf(html: html, pie: pie, nombre: archivo)
                estado = .listo(r.url, paginas: r.paginas, dias: dias.count)
            } catch {
                estado = .fallo
            }
        }
    }
}
