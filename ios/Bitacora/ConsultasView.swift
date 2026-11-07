import SwiftUI

/// Una consulta (u otro evento) en el detalle de un día del calendario.
///
/// Va en verde azulado, que no usa nada más del calendario: las charlas son
/// musgo y las notas celeste, y una consulta tiene que verse de lejos.
///
/// Si es una PROPUESTA —Bitácora la sacó de algo que la persona dijo en una
/// charla—, lo dice y pregunta si se agrega. Hasta que diga que sí no cuenta
/// para nada: Bitácora no prepara ni pregunta por una consulta sin confirmar.
struct TarjetaDeEvento: View {
    let evento: Evento

    @State private var trabajando = false
    @State private var fallo = false
    @State private var cambiandoHora = false
    @State private var confirmarBorrado = false
    @State private var paraLlevarAbierto = false

    private var agenda: Agenda { Agenda.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                // El sillón, el mismo de Consultas en «Mi expediente», para que una
                // consulta se reconozca igual en los dos lados.
                if evento.esConsulta {
                    Sillon(grosor: 2.4).frame(width: 14, height: 14)
                } else {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(nombre)
                    .font(.redonda(.caption, .bold))
                Text(evento.hora ?? "Sin hora")
                    .font(.redonda(.caption, evento.hora == nil ? .regular : .bold))
                    .monospacedDigit()
                    .opacity(evento.hora == nil ? 0.7 : 1)
                Spacer()
                if !evento.esPropuesta { menu }
            }
            .foregroundStyle(Paleta.verde)

            if evento.esPropuesta { propuesta }

            // Lo que eligió llevar, resumido: se abre al tocarlo. Desde el
            // 04/10/2026; antes iba siempre entero y la tarjeta de la consulta
            // ocupaba medio día.
            if !evento.paraLlevar.isEmpty {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { paraLlevarAbierto.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text("Para llevar: \(evento.paraLlevar.count) \(evento.paraLlevar.count == 1 ? "cosa" : "cosas")")
                            .font(.redonda(.subheadline))
                            .foregroundStyle(Paleta.tintaSuave)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Paleta.tintaTenue)
                            .rotationEffect(.degrees(paraLlevarAbierto ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !evento.paraLlevar.isEmpty && paraLlevarAbierto {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(evento.paraLlevar, id: \.self) { cosa in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle().fill(Paleta.verde).frame(width: 4, height: 4)
                            Text(cosa)
                                .font(.redonda(.subheadline))
                                .foregroundStyle(Paleta.tinta)
                        }
                    }
                }
            }

            if fallo {
                Text("No llego al servidor. Prueba de nuevo en un rato.")
                    .font(.redonda(.caption))
                    .foregroundStyle(Paleta.rojo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Paleta.verde.opacity(evento.esPropuesta ? 0.05 : 0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Paleta.verde.opacity(0.45),
                                      style: StrokeStyle(lineWidth: 1, dash: evento.esPropuesta ? [5, 4] : []))
                }
        }
        .sheet(isPresented: $cambiandoHora) {
            HojaDeEvento(dia: evento.dia, cambiando: evento)
        }
        .confirmationDialog("¿Eliminar esta \(evento.esConsulta ? "consulta" : "cosa") del calendario?",
                            isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { hacer { await agenda.borrar(evento) } }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var nombre: String {
        evento.esConsulta ? "Consulta" : (evento.titulo ?? "Evento")
    }

    private var propuesta: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("La anotó Bitácora por algo que dijiste en una charla. ¿La agrego a tu calendario?")
                .font(.redonda(.subheadline))
                .foregroundStyle(Paleta.tinta)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { hacer { await agenda.confirmar(evento) } } label: {
                    Text("Agregar")
                        .font(.redonda(.subheadline, .semibold))
                        .foregroundStyle(Paleta.fondoAlto)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Paleta.verde))
                }
                Button { hacer { await agenda.descartar(evento) } } label: {
                    Text("No")
                        .font(.redonda(.subheadline, .semibold))
                        .foregroundStyle(Paleta.tinta)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Paleta.carta))
                        .overlay { Capsule().strokeBorder(Paleta.cartaBorde, lineWidth: 1) }
                }
                if trabajando { ProgressView().controlSize(.small) }
            }
            .disabled(trabajando)
        }
    }

    private var menu: some View {
        Menu {
            Button { cambiandoHora = true } label: { Label("Cambiar la hora", systemImage: "clock") }
            Button(role: .destructive) { confirmarBorrado = true } label: {
                Label("Eliminar", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Opciones de la \(evento.esConsulta ? "consulta" : "cosa")")
    }

    private func hacer(_ accion: @escaping () async -> Bool) {
        trabajando = true
        fallo = false
        Task {
            let ok = await accion()
            trabajando = false
            fallo = !ok
        }
    }
}

/// Cargar una consulta en un día, o cambiarle la hora a una que ya está.
///
/// Una hoja chica y no una pantalla de pasos como Evaluaciones: son dos datos,
/// y uno es optativo. El día viene elegido: el que se estaba mirando en el
/// calendario. Desde el 04/10/2026 el botón que la abre está arriba y no al
/// lado del día, así que al agregar el día también se puede cambiar acá.
struct HojaDeEvento: View {
    let dia: String
    /// Si viene, es para cambiarle la hora a ésta.
    var cambiando: Evento? = nil

    init(dia: String, cambiando: Evento? = nil) {
        self.dia = dia
        self.cambiando = cambiando
        _fecha = State(initialValue: Agenda.fecha(dia) ?? Date())
    }

    @Environment(\.dismiss) private var cerrar
    /// El día de una consulta nueva. Al cambiarle la hora a una, no se toca.
    @State private var fecha: Date
    @State private var esConsulta = true
    @State private var titulo = ""
    @State private var conHora = true
    @State private var hora = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var guardando = false
    @State private var fallo = false

    var body: some View {
        NavigationStack {
            ZStack {
                Fondo()
                VStack(alignment: .leading, spacing: 18) {
                    if cambiando == nil {
                        HStack {
                            Text("Día")
                                .font(.redonda(.body))
                            Spacer()
                            // Con su letra y no la redonda: con la redonda, el
                            // botón no crecía y el año salía cortado.
                            DatePicker("Día", selection: $fecha, displayedComponents: .date)
                                .labelsHidden()
                                .tint(Paleta.verde)
                                .environment(\.locale, Locale(identifier: "es_ES"))
                                // Lunes primero, como el calendario de la app: si
                                // no, sigue la región del teléfono y puede
                                // empezar en domingo.
                                .environment(\.calendar, Self.lunesPrimero)
                        }
                    } else {
                        Text(Self.diaEscrito(dia))
                            .font(.redonda(.subheadline))
                            .foregroundStyle(Paleta.tintaSuave)
                    }

                    if cambiando == nil {
                        Picker("Qué es", selection: $esConsulta) {
                            Text("Consulta").tag(true)
                            Text("Otra cosa").tag(false)
                        }
                        .pickerStyle(.segmented)

                        if !esConsulta {
                            TextField("Qué es", text: $titulo)
                                .font(.redonda(.body))
                                .padding(12)
                                .carta(radio: 16)
                        } else {
                            Text("Con tu terapeuta. El día anterior, Bitácora te ayuda a elegir qué llevar; después, te pregunta cómo te fue.")
                                .font(.redonda(.footnote))
                                .foregroundStyle(Paleta.tintaTenue)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Toggle("A una hora", isOn: $conHora.animation(.snappy))
                        .font(.redonda(.body))
                        .tint(Paleta.verde)
                    if conHora {
                        DatePicker("Hora", selection: $hora, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            // En 24 horas, como el resto de las horas de la app: con la
                            // región de Chile la rueda salía con a. m. y p. m.
                            .environment(\.locale, Locale(identifier: "es_ES"))
                            .frame(maxWidth: .infinity)
                    }

                    if fallo {
                        Text("No llego al servidor: no se guardó. Prueba de nuevo en un rato.")
                            .font(.redonda(.footnote))
                            .foregroundStyle(Paleta.rojo)
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(cambiando == nil ? "Agregar" : "Cambiar la hora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando {
                        ProgressView()
                    } else {
                        Button("Guardar", action: guardar)
                            .disabled(!esConsulta && titulo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear(perform: cargar)
        }
        .presentationDetents([.large])
    }

    private func cargar() {
        guard let e = cambiando else { return }
        esConsulta = e.esConsulta
        if let h = e.hora {
            let p = h.split(separator: ":").compactMap { Int($0) }
            if p.count == 2, let d = Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date()) {
                hora = d
            }
        } else {
            conHora = false
        }
    }

    private var horaElegida: String? {
        guard conHora else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: hora)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private func guardar() {
        guardando = true
        fallo = false
        Task {
            let ok: Bool
            if let e = cambiando {
                ok = await Agenda.shared.cambiarHora(e, a: horaElegida)
            } else {
                let t = titulo.trimmingCharacters(in: .whitespacesAndNewlines)
                ok = await Agenda.shared.agregar(tipo: esConsulta ? "consulta" : "otro", dia: Agenda.dia(fecha),
                                                 hora: horaElegida, titulo: esConsulta ? nil : t)
            }
            guardando = false
            if ok { cerrar() } else { fallo = true }
        }
    }

    private static var lunesPrimero: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    /// «Jueves 9 de octubre».
    static func diaEscrito(_ dia: String) -> String {
        guard let f = Agenda.fecha(dia) else { return dia }
        let t = f.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es")))
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}
