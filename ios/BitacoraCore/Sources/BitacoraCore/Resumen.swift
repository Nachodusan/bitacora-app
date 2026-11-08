import Foundation

/// «Mi resumen»: las frases para llevar a terapia, de a un mes, y el documento
/// que se le manda al psicólogo.
///
/// Lo que va acá es lo que no depende de la pantalla: qué días son un mes, cómo
/// se escribe un tramo de días y el HTML del documento. El PDF lo dibuja la app
/// con ese HTML (`ExportarResumen.swift`).
public enum Resumen {

    // MARK: - Los días

    /// El primer y el último día de un mes, como "YYYY-MM-DD".
    public static func mes(anio: Int, mes: Int) -> (desde: String, hasta: String) {
        let ultimo = diasDelMes(anio: anio, mes: mes)
        return (dia(anio, mes, 1), dia(anio, mes, ultimo))
    }

    /// El tramo escrito como lo diría una persona: «septiembre de 2026» si es
    /// el mes entero, «15 de septiembre de 2026» si es un día, «del 15 al 16 de
    /// septiembre de 2026», o con los dos meses si cruza.
    public static func escrito(desde: String, hasta: String) -> String {
        guard let a = partes(desde), let b = partes(hasta) else { return "\(desde) a \(hasta)" }
        if a.anio == b.anio, a.mes == b.mes, a.dia == 1, b.dia == diasDelMes(anio: b.anio, mes: b.mes) {
            return "\(meses[a.mes - 1]) de \(a.anio)"
        }
        if desde == hasta { return "\(a.dia) de \(meses[a.mes - 1]) de \(a.anio)" }
        if a.anio == b.anio, a.mes == b.mes {
            return "del \(a.dia) al \(b.dia) de \(meses[b.mes - 1]) de \(b.anio)"
        }
        if a.anio == b.anio {
            return "del \(a.dia) de \(meses[a.mes - 1]) al \(b.dia) de \(meses[b.mes - 1]) de \(b.anio)"
        }
        return "del \(a.dia) de \(meses[a.mes - 1]) de \(a.anio) al \(b.dia) de \(meses[b.mes - 1]) de \(b.anio)"
    }

    /// Días sueltos, elegidos uno por uno en el calendario, escritos como los
    /// diría una persona.
    ///
    /// Con `esElMes` (los elegidos son todos los días del mes que tenían algo):
    /// «septiembre de 2026». Si no: «15 y 16 de septiembre de 2026», «3, 10 y 24
    /// de septiembre de 2026», «28 y 30 de septiembre y 2 de octubre de 2026».
    /// Con más de cinco, la lista ya no se lee: «8 días, del 3 al 24 de
    /// septiembre de 2026».
    public static func escrito(dias: [String], esElMes: Bool) -> String {
        let orden = Array(Set(dias)).sorted()
        guard let primero = orden.first, let ultimo = orden.last,
              let a = partes(primero), let b = partes(ultimo) else { return "ningún día" }
        if esElMes, a.anio == b.anio, a.mes == b.mes { return "\(meses[a.mes - 1]) de \(a.anio)" }
        if orden.count > 5 { return "\(orden.count) días, \(escrito(desde: primero, hasta: ultimo))" }

        // De a un mes: «3, 10 y 24 de septiembre».
        var grupos: [(anio: Int, mes: Int, dias: [Int])] = []
        for d in orden.compactMap(partes) {
            if let g = grupos.last, g.anio == d.anio, g.mes == d.mes {
                grupos[grupos.count - 1].dias.append(d.dia)
            } else {
                grupos.append((d.anio, d.mes, [d.dia]))
            }
        }
        let unAnio = a.anio == b.anio
        let partesEscritas = grupos.map { g in
            "\(enLista(g.dias.map(String.init))) de \(meses[g.mes - 1])" + (unAnio ? "" : " de \(g.anio)")
        }
        return enLista(partesEscritas) + (unAnio ? " de \(a.anio)" : "")
    }

    /// «a», «a y b», «a, b y c».
    static func enLista(_ cosas: [String]) -> String {
        guard cosas.count > 1 else { return cosas.first ?? "" }
        return cosas.dropLast().joined(separator: ", ") + " y " + cosas.last!
    }

    /// «30 de septiembre», sin el año: el de las tarjetas.
    public static func fechaCorta(_ d: String) -> String {
        guard let p = partes(d) else { return d }
        return "\(p.dia) de \(meses[p.mes - 1])"
    }

    public static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                               "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    // MARK: - El documento

    /// Un día con charla pero sin frases separadas: va lo que dijo, textual
    /// (`Transcripcion.loQueDijo`). Lo pidió Dusan: un día así también se le
    /// tiene que poder mandar al psicólogo.
    public struct CharlaSinFrases: Sendable {
        public let dia: String
        public let hora: String
        public let dicho: [String]
        public init(dia: String, hora: String, dicho: [String]) {
            self.dia = dia
            self.hora = hora
            self.dicho = dicho
        }
    }

    /// El HTML del documento para el psicólogo.
    ///
    /// Está escrito PARA ÉL, no para la persona: en tercera persona, y lo
    /// primero que dice es qué es y qué no es. Las frases van textuales, que es
    /// lo único verificado (se comparan con la transcripción antes de
    /// guardarse); los temas y el contexto los escribe un modelo, y el documento
    /// lo dice al lado de cada uno. Un texto de un modelo que llega a un
    /// profesional con forma de informe carga una autoridad que no se ganó.
    ///
    /// Los días van del más viejo al más nuevo, como se lee un diario.
    /// `tramo` es qué días son, ya escrito (`escrito(dias:esElMes:)`).
    public static func html(notas: [NotaDelDia], charlas: [CharlaSinFrases] = [], tramo: String,
                            nombre: String?, generado: String, ficha: [SeccionDeLaFicha] = []) -> String {
        let quien = nombre.map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : esc($0) }
        let deQuien = quien.map { "de \($0)" } ?? "de la persona"
        // Las notas y las charlas sin frases, juntas y por fecha y hora.
        let partes: [(dia: String, hora: String, html: String)] =
            notas.map { ($0.dia, $0.hora, seccion($0)) } + charlas.map { ($0.dia, $0.hora, seccion($0)) }
        var dias = partes.sorted { ($0.dia, $0.hora) < ($1.dia, $1.hora) }.map(\.html).joined()
        if partes.isEmpty {
            dias = "<p class=\"vacio\">No hay nada guardado en estos días.</p>"
        }

        return """
        <!doctype html><html lang="es"><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 11pt; color: #1F1E1B; line-height: 1.45; }
        h1 { font-family: Georgia, 'Times New Roman', serif; font-weight: normal; font-size: 22pt; margin: 0 0 2pt; }
        .meta { color: #63605A; font-size: 10pt; margin: 0 0 14pt; }
        .aviso { background: #EFF1E4; border-left: 3pt solid #4F6029; padding: 8pt 10pt; font-size: 9.5pt; color: #3E3C37; margin: 0 0 18pt; }
        section { margin: 0 0 16pt; }
        h2 { page-break-after: avoid; font-size: 11.5pt; margin: 0 0 6pt; border-bottom: 0.5pt solid #D9D9CC; padding-bottom: 3pt; }
        .hora { color: #96928A; font-weight: normal; font-size: 9.5pt; margin-left: 6pt; }
        blockquote { page-break-inside: avoid; font-family: Georgia, 'Times New Roman', serif; font-size: 11.5pt; margin: 0 0 7pt; padding-left: 9pt; border-left: 2pt solid #A8B98A; }
        .sobre { display: block; font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 8.5pt; color: #96928A; }
        .app { page-break-inside: avoid; font-size: 9pt; color: #63605A; margin: 4pt 0 0; }
        .aviso-dia { margin: 0 0 7pt; }
        .inicio { page-break-inside: avoid; }
        .vacio { color: #63605A; }
        .registro { page-break-inside: avoid; margin: 6pt 0 0; font-size: 9.5pt; border-collapse: collapse; width: 100%; }
        .registro td { vertical-align: top; padding: 2pt 6pt 2pt 0; }
        .registro .tipo { color: #4F6029; font-weight: 600; white-space: nowrap; width: 1%; }
        .registro .que { font-weight: 600; white-space: nowrap; width: 1%; }
        .registro .frase { font-family: Georgia, 'Times New Roman', serif; color: #3E3C37; }
        </style></head><body>
        <h1>Mi resumen</h1>
        <p class="meta">De \(quien ?? "la persona") · \(esc(tramo)) · preparado con Bitácora el \(esc(fechaConAnio(generado)))</p>
        <p class="aviso">Son frases \(deQuien), tal como las dijo en su diario hablado, verificadas contra lo que quedó transcrito. No es un informe clínico ni un diagnóstico: es material para trabajar en sesión. Los temas, el contexto y el registro de cada día los arma la app y están marcados así; pueden equivocarse. El registro (emociones, impulsos, conductas y hábitos que contó) lleva siempre su frase textual y la persona no lo ve en la app.</p>
        \(compartido(ficha, deQuien: deQuien))\(dias)
        </body></html>
        """
    }

    /// Los títulos de la ficha para el psicólogo: en tercera persona.
    static let titulosDeLaFicha: [String: String] = [
        "problematica": "Lo que le pasa", "desencadenante": "Lo que lo activa", "le_sirve": "Lo que le sirve",
        "no_le_sirve": "Lo que no le sirve", "meta": "Lo que quiere", "persona": "Su gente",
        "como_hablarle": "Cómo prefiere que le hablen", "dato": "Quién es",
    ]

    /// Lo que la persona eligió de su ficha para su psicólogo, arriba de los
    /// días. Cada dato con su frase textual más reciente.
    static func compartido(_ ficha: [SeccionDeLaFicha], deQuien: String) -> String {
        let secciones = ficha.filter { !$0.datos.isEmpty }
        guard !secciones.isEmpty else { return "" }
        let cuerpo = secciones.map { s in
            "<p class=\"app\"><b>\(esc(titulosDeLaFicha[s.tipo] ?? s.titulo))</b></p>" + s.datos.map { d in
                "<blockquote>\(esc(d.nombre))" + (d.citas.first.map { "<span class=\"sobre\">\(cita($0.cita)) · "
                    + "\(d.veces == 1 ? "una vez" : "\(d.veces) veces"), la última el \(esc(fechaConDia(d.ultima)))</span>" } ?? "")
                    + "</blockquote>"
            }.joined()
        }.joined()
        return "<section><h2>Lo que eligió compartir</h2><p class=\"app aviso-dia\">Lo arma la app a partir de sus charlas; \(deQuien) eligió qué mostrar.</p>"
            + cuerpo + "</section>"
    }

    private static func titulo(_ dia: String, _ hora: String) -> String {
        "<h2>\(esc(fechaConDia(dia)))<span class=\"hora\">\(esc(hora))</span></h2>"
    }

    private static func cita(_ texto: String) -> String {
        "«\(esc(texto).replacingOccurrences(of: "\n", with: "<br>"))»"
    }

    /// La fecha va pegada a lo primero del día, en un bloque que no se parte:
    /// el `page-break-after: avoid` del título solo, el motor de impresión de
    /// iOS no lo respeta, y la fecha quedaba sola al pie de una hoja.
    private static func conTitulo(_ dia: String, _ hora: String, _ bloques: [String]) -> String {
        guard let primero = bloques.first else { return "<section>" + titulo(dia, hora) + "</section>" }
        return "<section><div class=\"inicio\">" + titulo(dia, hora) + primero + "</div>"
            + bloques.dropFirst().joined() + "</section>"
    }

    private static func seccion(_ n: NotaDelDia) -> String {
        var bloques = n.citas.map { c in
            "<blockquote>\(cita(c.texto))"
                + (c.sobre.isEmpty ? "" : "<span class=\"sobre\">\(esc(c.sobre))</span>")
                + "</blockquote>"
        }
        if !n.temas.isEmpty {
            bloques.append("<p class=\"app\"><b>Temas</b> (los escribe la app): \(n.temas.map(esc).joined(separator: " · "))</p>")
        }
        if let ctx = n.contexto, !ctx.isEmpty {
            bloques.append("<p class=\"app\"><b>Contexto</b> (lo escribe la app): \(esc(ctx))</p>")
        }
        if let reg = registro(n.registro) { bloques.append(reg) }
        return conTitulo(n.dia, n.hora, bloques)
    }

    /// Los cuatro tipos, en este orden y con su nombre para el psicólogo.
    static let tiposDeRegistro: [(clave: String, nombre: String)] =
        [("emocion", "Emoción"), ("impulso", "Impulso"), ("conducta", "Conducta"), ("habito", "Hábito")]

    /// El registro del día: una fila por elemento, agrupado por tipo, con la
    /// frase textual al lado. Sólo existe en este documento.
    private static func registro(_ r: [NotaDelDia.Registro]) -> String? {
        let filas = tiposDeRegistro.flatMap { t in
            r.filter { $0.tipo == t.clave }.map { e in
                "<tr><td class=\"tipo\">\(t.nombre)</td><td class=\"que\">\(esc(e.que))</td><td class=\"frase\">\(cita(e.cita))</td></tr>"
            }
        }
        guard !filas.isEmpty else { return nil }
        return "<p class=\"app\"><b>Registro</b> (lo arma la app con sus frases):</p><table class=\"registro\">"
            + filas.joined() + "</table>"
    }

    private static func seccion(_ c: CharlaSinFrases) -> String {
        let aviso = "<p class=\"app aviso-dia\">Ese día no se separaron frases: va lo que dijo en la charla, textual.</p>"
        let dicho = c.dicho.map { "<blockquote>\(cita($0))</blockquote>" }
        return conTitulo(c.dia, c.hora, [aviso + (dicho.first ?? "")] + dicho.dropFirst())
    }

    // MARK: - Detalles

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let semana = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]

    /// «Martes 15 de septiembre».
    static func fechaConDia(_ d: String) -> String {
        guard let p = partes(d) else { return d }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let f = c.date(from: DateComponents(year: p.anio, month: p.mes, day: p.dia, hour: 12))!
        let nombre = semana[c.component(.weekday, from: f) - 1]
        return "\(nombre.prefix(1).uppercased())\(nombre.dropFirst()) \(p.dia) de \(meses[p.mes - 1])"
    }

    static func fechaConAnio(_ d: String) -> String {
        guard let p = partes(d) else { return d }
        return "\(p.dia) de \(meses[p.mes - 1]) de \(p.anio)"
    }

    private static func partes(_ d: String) -> (anio: Int, mes: Int, dia: Int)? {
        let p = d.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return nil }
        return (p[0], p[1], p[2])
    }

    private static func dia(_ a: Int, _ m: Int, _ d: Int) -> String {
        String(format: "%04d-%02d-%02d", a, m, d)
    }

    static func diasDelMes(anio: Int, mes: Int) -> Int {
        switch mes {
        case 2: return (anio % 4 == 0 && anio % 100 != 0) || anio % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}
