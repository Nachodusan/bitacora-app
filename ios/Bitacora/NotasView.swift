import SwiftData
import SwiftUI

/// Lo que dijiste, en tus palabras, para llevar a una sesión: «Mi resumen», la
/// segunda parte de la pestaña «Mi expediente» (`EvaluacionesView`). Hasta el
/// 04/10/2026 era una hoja aparte, «Para tu sesión», que se abría desde el
/// calendario.
///
/// NO es una nota clínica y la pantalla lo dice, no sólo el código. Un texto
/// escrito por un modelo que llega a un profesional con forma de informe carga
/// una autoridad que no se ganó; si alguien va a leer esto, tiene que saber
/// desde el primer renglón qué está leyendo.
///
/// Va DE A UN MES, del día 1 al último, como se lee un diario (lo pidió Dusan
/// el 04/10/2026; antes eran las últimas dos semanas). El botón de abajo arma
/// el PDF para el psicólogo: el mes entero, o los días que se elijan
/// (`HojaDeExportar`).
///
/// UN ÍNDICE Y DESPUÉS EL DÍA, desde la noche del 04/10/2026. Hasta ese momento
/// el mes entero eran tarjetas largas una abajo de otra, con frases, temas y
/// contexto mezclados, y Dusan sintió que quien la abriera se iba a perder.
/// Eligió esto entre tres propuestas: arriba cuántos días y frases tuvo el mes,
/// abajo una fila por día con el comienzo de lo que pasó, y al tocarla el día
/// solo (`DiaDelResumenView`).
///
/// Y EL CONTEXTO PRIMERO, también por pedido suyo. Antes iban primero las citas,
/// que son lo único garantizado —se verifican contra la transcripción antes de
/// guardarse—, y el contexto abajo y chico. Ahora el contexto abre cada día,
/// pero con su autor a la vista, «resumido por Bitácora», para que no se lea
/// como algo que dijo la persona. La aclaración entera (no es un informe ni un
/// diagnóstico) está detrás de ⓘ; en el PDF sigue yendo primero y completa.
///
/// TODOS LOS DÍAS CON CHARLA, tengan frases o no (también pedido de Dusan,
/// esa misma noche): hoy, que todavía no se cerró, y un día del que el latido
/// no sacó frases aparecen igual, con lo que la persona dijo en la charla,
/// textual. Así el psicólogo tiene una idea del mes entero; qué días van al
/// PDF lo decide la persona al elegirlos. Las charlas salen del teléfono, como
/// en el calendario y en el PDF.
struct NotasView: View {
    @Query(sort: \EntradaLocal.creadoEn) private var entradas: [EntradaLocal]
    @State private var anio: Int
    @State private var mes: Int
    @State private var notas: [NotaDelDia] = []
    @State private var estado = Estado.cargando
    @State private var exportando = false
    @State private var verAclaracion = false

    enum Estado { case cargando, listo, sinServidor }

    init() {
        let hoy = CalendarioView.hoyLogico()
        _anio = State(initialValue: Int(hoy.prefix(4))!)
        _mes = State(initialValue: Int(hoy.dropFirst(5).prefix(2))!)
    }

    private var tramo: (desde: String, hasta: String) { Resumen.mes(anio: anio, mes: mes) }

    var body: some View {
        VStack(spacing: 0) {
            encabezadoDeMes
            Group {
                switch estado {
                case .cargando: ProgressView().tint(Paleta.tintaSuave)
                case .sinServidor: sinServidor
                case .listo: if renglones.isEmpty { vacio } else { lista }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // El PDF, a la vista y con su nombre (04/10/2026). Antes era el ícono
        // de compartir arriba a la derecha, que no decía qué hacía: Dusan
        // eligió el botón ancho de la maqueta.
        .safeAreaInset(edge: .bottom) {
            Button { exportando = true } label: {
                Label("Armar el PDF para tu psicólogo", systemImage: "doc.text")
                    .font(.redonda(.body, .semibold))
                    .foregroundStyle(Paleta.fondoAlto)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Paleta.musgo))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $exportando) {
            HojaDeExportar(anio: anio, mes: mes)
        }
        .navigationDestination(for: NotaDelDia.self) { DiaDelResumenView(nota: $0) }
        .navigationDestination(for: DiaSinFrases.self) { DiaSinFrasesView(dia: $0) }
        .task(id: tramo.desde) { await cargar() }
    }

    private func cargar() async {
        estado = .cargando
        let t = tramo
        guard let todas = await SyncClient(config: Config.shared.servidor).notas(desde: t.desde, hasta: t.hasta) else {
            estado = .sinServidor
            return
        }
        // Del 1 al 30, como se lee un diario. El servidor las manda al revés.
        notas = todas.sorted { ($0.dia, $0.hora) < ($1.dia, $1.hora) }
        estado = .listo
    }

    /// Los días del mes con charla y sin frases: lo que dijo la persona en
    /// cada charla, textual (lo mismo que lleva el PDF de un día así).
    private var sinFrases: [DiaSinFrases] {
        let t = tramo
        let conFrases = Set(notas.map(\.dia))
        let delMes = entradas.filter { $0.diaLogico >= t.desde && $0.diaLogico <= t.hasta && !conFrases.contains($0.diaLogico) }
        return Dictionary(grouping: delMes, by: \.diaLogico)
            .compactMap { dia, del in
                let charlas = del.map {
                    CharlaDelDia(hora: String($0.creadoLocalISO.dropFirst(11).prefix(5)),
                                 dicho: Transcripcion.loQueDijo($0.transcripcion))
                }.filter { !$0.dicho.isEmpty }
                return charlas.isEmpty ? nil : DiaSinFrases(dia: dia, charlas: charlas)
            }
    }

    /// Lo que va en el índice, del 1 al último: las notas y los días sin frases.
    private var renglones: [Renglon] {
        (notas.map(Renglon.nota) + sinFrases.map(Renglon.charla))
            .sorted { ($0.dia, $0.hora) < ($1.dia, $1.hora) }
    }

    enum Renglon: Identifiable {
        case nota(NotaDelDia)
        case charla(DiaSinFrases)
        var dia: String {
            switch self { case .nota(let n): n.dia; case .charla(let c): c.dia }
        }
        var hora: String {
            switch self { case .nota(let n): n.hora; case .charla(let c): c.charlas.first?.hora ?? "" }
        }
        var id: String {
            switch self { case .nota(let n): "n" + n.id; case .charla(let c): "c" + c.dia }
        }
    }

    // MARK: - El mes

    private var encabezadoDeMes: some View {
        HStack {
            flecha("chevron.left", -1, "Mes anterior")
            Spacer()
            Text("\(Resumen.meses[mes - 1].capitalized) \(String(anio))")
                .font(.redonda(.title3, .bold))
                .foregroundStyle(Paleta.tinta)
                .contentTransition(.numericText())
            Spacer()
            flecha("chevron.right", 1, "Mes siguiente")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func flecha(_ icono: String, _ delta: Int, _ etiqueta: String) -> some View {
        Button {
            let r = CalendarioMensual.corrido(anio: anio, mes: mes, meses: delta)
            withAnimation(.snappy(duration: 0.22)) {
                anio = r.anio
                mes = r.mes
            }
        } label: {
            Image(systemName: icono)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Paleta.tintaSuave)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Paleta.carta))
                .overlay { Circle().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
        }
        .accessibilityLabel(etiqueta)
    }

    private var vacio: some View {
        VStack(spacing: 10) {
            Libro(grosor: 1.5)
                .frame(width: 30, height: 30)
                .foregroundStyle(Paleta.tintaTenue)
            Text("Nada en \(Resumen.meses[mes - 1])")
                .font(.redonda(.headline))
                .foregroundStyle(Paleta.tinta)
            Text("Las notas se arman al cerrar cada día. Después de un par de "
                 + "charlas vas a encontrar acá lo que dijiste.")
                .font(.redonda(.footnote))
                .foregroundStyle(Paleta.tintaSuave)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
        }
        .padding(.bottom, 60)
    }

    private var sinServidor: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Paleta.tintaTenue)
            Text("No se pudo conectar con el servidor. Lo que dijiste sigue guardado; prueba de nuevo en un rato.")
                .font(.redonda(.footnote))
                .foregroundStyle(Paleta.tintaSuave)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Button("Probar de nuevo") { Task { await cargar() } }
                .font(.redonda(.subheadline, .semibold))
                .foregroundStyle(Paleta.musgo)
        }
        .padding(.bottom, 60)
    }

    private var lista: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                aclaracion
                resumenDelMes
                VStack(spacing: 0) {
                    ForEach(Array(renglones.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Divider().overlay(Paleta.cartaBorde) }
                        switch r {
                        case .nota(let n):
                            NavigationLink(value: n) { fila(n) }
                                .buttonStyle(.plain)
                        case .charla(let c):
                            NavigationLink(value: c) { filaSinFrases(c) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .carta(radio: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            // Para que la última fila no quede debajo del botón y la barra.
            .padding(.bottom, 24)
        }
    }

    /// Una línea: qué es esto. El texto entero, detrás de ⓘ.
    private var aclaracion: some View {
        HStack(spacing: 5) {
            Text("Tus frases, tal como las dijiste · no es un informe")
                .font(.redonda(.caption))
                .foregroundStyle(Paleta.tintaTenue)
            Button { verAclaracion = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Paleta.tintaSuave)
            }
            .accessibilityLabel("Qué es Mi resumen")
            .popover(isPresented: $verAclaracion) {
                Text("Esto son tus propias frases, tal como las dijiste, y un resumen corto de cada día "
                     + "que escribe Bitácora. No es un informe ni un diagnóstico: es material para que lo "
                     + "lleves y lo trabajen ustedes.")
                    .font(.redonda(.footnote))
                    .foregroundStyle(Paleta.tinta)
                    .padding(16)
                    .frame(width: 290)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// El mes de un vistazo: cuántos días y cuántas frases.
    private var resumenDelMes: some View {
        let dias = Set(renglones.map(\.dia)).count
        let frases = notas.reduce(0) { $0 + $1.citas.count }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Resumen.meses[mes - 1].capitalized)
                    .font(.redonda(.headline))
                    .foregroundStyle(Paleta.tinta)
                Text("\(dias) \(dias == 1 ? "día" : "días")"
                     + (frases > 0 ? " · \(frases) \(frases == 1 ? "frase" : "frases")" : ""))
                    .font(.redonda(.footnote))
                    .foregroundStyle(Paleta.tintaSuave)
            }
            Spacer()
            Libro()
                .frame(width: 24, height: 24)
                .foregroundStyle(Paleta.musgo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .carta(radio: 20)
    }

    /// Un día con charla y sin frases: lo primero que dijo, y por qué todavía
    /// no hay frases (hoy no se cerró; otro día, no se separaron).
    private func filaSinFrases(_ c: DiaSinFrases) -> some View {
        let n = c.charlas.count
        let porQue = c.dia == CalendarioView.hoyLogico()
            ? "las frases llegan al cerrar el día"
            : "sin frases separadas"
        return HStack(spacing: 12) {
            numeroDelDia(c.dia)
            VStack(alignment: .leading, spacing: 3) {
                Text("«\(c.charlas.first?.dicho.first ?? "")»")
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tinta)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(n) \(n == 1 ? "charla" : "charlas") · \(porQue)")
                    .font(.redonda(.caption))
                    .foregroundStyle(Paleta.tintaTenue)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Paleta.tintaTenue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func numeroDelDia(_ dia: String) -> some View {
        VStack(spacing: 1) {
            Text(String(Int(dia.suffix(2)) ?? 0))
                .font(.redonda(.title3, .semibold))
                .foregroundStyle(Paleta.tinta)
            Text(Resumen.fechaConDia(dia).prefix(3).lowercased())
                .font(.redonda(.caption2))
                .foregroundStyle(Paleta.tintaTenue)
        }
        .frame(width: 38)
    }

    /// Un día en el índice: el número, el día de la semana, el comienzo de lo
    /// que pasó y cuántas frases tiene.
    private func fila(_ n: NotaDelDia) -> some View {
        let frases = n.citas.count
        let adelanto = n.contexto.flatMap { $0.isEmpty ? nil : $0 } ?? n.citas.first.map { "«\($0.texto)»" } ?? ""
        return HStack(spacing: 12) {
            numeroDelDia(n.dia)
            VStack(alignment: .leading, spacing: 3) {
                Text(adelanto)
                    .font(.redonda(.subheadline))
                    .foregroundStyle(Paleta.tinta)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(n.hora) · \(frases) \(frases == 1 ? "frase" : "frases")")
                    .font(.redonda(.caption))
                    .foregroundStyle(Paleta.tintaTenue)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Paleta.tintaTenue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

}

/// Un día de «Mi resumen», solo: lo que pasó, tus palabras y los temas, en ese
/// orden y con un título cada parte.
///
/// El contexto va primero porque así lo pidió Dusan, con su autor a la vista:
/// lo escribe Bitácora, y las frases de abajo son tuyas y textuales. Las citas
/// conservan la barra al costado, la marca de lo verificado.
struct DiaDelResumenView: View {
    let nota: NotaDelDia

    var body: some View {
        ZStack {
            Fondo()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Resumen.fechaConDia(nota.dia))
                            .font(.redonda(.title2, .bold))
                            .foregroundStyle(Paleta.tinta)
                        Text(nota.hora)
                            .font(.redonda(.footnote))
                            .foregroundStyle(Paleta.tintaTenue)
                    }

                    if let ctx = nota.contexto, !ctx.isEmpty {
                        titulo("Lo que pasó", detalle: "resumido por Bitácora")
                        Text(ctx)
                            .font(.redonda(.body))
                            .foregroundStyle(Paleta.tinta)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !nota.citas.isEmpty {
                        titulo("En tus palabras")
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(nota.citas) { c in
                                HStack(alignment: .top, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Paleta.musgo.opacity(0.5))
                                        .frame(width: 3)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("«\(c.texto)»")
                                            .font(.redonda(.callout))
                                            .foregroundStyle(Paleta.tinta)
                                        if !c.sobre.isEmpty {
                                            Text(c.sobre)
                                                .font(.redonda(.caption))
                                                .foregroundStyle(Paleta.tintaTenue)
                                        }
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !nota.temas.isEmpty {
                        titulo("Temas")
                        Fluido(espacio: 6) {
                            ForEach(nota.temas, id: \.self) { t in
                                Text(t)
                                    .font(.redonda(.caption, .medium))
                                    .foregroundStyle(Paleta.musgo)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Paleta.musgo.opacity(0.14)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                // La barra de pestañas flota encima: sin este colchón los temas
                // quedan tapados.
                .padding(.bottom, 110)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func titulo(_ texto: String, detalle: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(texto.uppercased())
                .font(.redonda(.caption2, .bold))
                .tracking(0.6)
                .foregroundStyle(Paleta.tintaTenue)
            if let detalle {
                Text("· \(detalle)")
                    .font(.redonda(.caption2))
                    .foregroundStyle(Paleta.tintaTenue)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 8)
    }
}

/// Una charla de un día sin frases: su hora y lo que dijo la persona, turno
/// por turno.
struct CharlaDelDia: Hashable {
    let hora: String
    let dicho: [String]
}

/// Un día con charla pero sin frases separadas.
struct DiaSinFrases: Hashable {
    let dia: String
    let charlas: [CharlaDelDia]
}

/// Un día sin frases, abierto: lo que dijo la persona en la charla, textual,
/// con la misma barra de las citas. Es lo mismo que va al PDF de un día así.
struct DiaSinFrasesView: View {
    let dia: DiaSinFrases

    private var esHoy: Bool { dia.dia == CalendarioView.hoyLogico() }

    var body: some View {
        ZStack {
            Fondo()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Resumen.fechaConDia(dia.dia))
                        .font(.redonda(.title2, .bold))
                        .foregroundStyle(Paleta.tinta)

                    Text(esHoy
                         ? "Este día todavía no terminó: el resumen y las frases se arman al cerrarse, a las 4 de la mañana. Mientras tanto, esto es lo que dijiste."
                         : "Ese día no se separaron frases. Esto es lo que dijiste en la charla, textual.")
                        .font(.redonda(.footnote))
                        .foregroundStyle(Paleta.tintaSuave)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Paleta.musgo.opacity(0.10))
                        }
                        .padding(.top, 14)

                    HStack(spacing: 4) {
                        Text("EN TUS PALABRAS")
                            .font(.redonda(.caption2, .bold))
                            .tracking(0.6)
                        Text("· de la charla, textual")
                            .font(.redonda(.caption2))
                    }
                    .foregroundStyle(Paleta.tintaTenue)
                    .padding(.top, 22)
                    .padding(.bottom, 8)

                    ForEach(Array(dia.charlas.enumerated()), id: \.offset) { _, charla in
                        if dia.charlas.count > 1 {
                            Text(charla.hora)
                                .font(.redonda(.caption, .bold))
                                .foregroundStyle(Paleta.musgo)
                                .padding(.top, 6)
                                .padding(.bottom, 6)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(charla.dicho.enumerated()), id: \.offset) { _, texto in
                                HStack(alignment: .top, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Paleta.musgo.opacity(0.5))
                                        .frame(width: 3)
                                    Text("«\(texto)»")
                                        .font(.redonda(.callout))
                                        .foregroundStyle(Paleta.tinta)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
