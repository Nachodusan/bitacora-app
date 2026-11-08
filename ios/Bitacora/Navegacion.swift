import Foundation

/// Lo que una pestaña le pide a otra.
///
/// Nació el 06/10/2026 con la tarjeta de la próxima consulta, arriba de Mi
/// expediente: su botón «Agendar consulta» lleva al calendario con la hoja de
/// consulta nueva abierta, tocarla lleva a ese día, y «Preparar» abre el chat
/// para prepararla. Hasta entonces cada pestaña vivía sola.
///
/// Los pedidos se dejan acá y los atiende la pestaña que corresponde, al
/// aparecer o al cambiar el pedido, y los borra al atenderlos.
@Observable
@MainActor
final class Navegacion {
    static let shared = Navegacion()
    private init() {}

    var pestana = RaizView.Pestana.hablar

    /// El calendario abre la hoja de consulta nueva, en el día de hoy.
    var nuevaConsulta = false

    /// El calendario muestra este día ("YYYY-MM-DD").
    var irAlDia: String?

    /// La consulta que se está preparando en el chat, desde «Preparar».
    ///
    /// Mientras esté, cada turno se lo dice al servidor (`preparar`), que pone a
    /// Bitácora en el modo de antes de la consulta aunque falten días. Se borra al
    /// salir de la conversación, con la cruz del aviso, o cuando la consulta pasa.
    var preparando: Evento?

    /// La consulta que se prepara, si todavía no pasó.
    var preparandoVigente: Evento? {
        guard let e = preparando, e.momento > Self.ahora() else { return nil }
        return e
    }

    func agendarConsulta() {
        nuevaConsulta = true
        pestana = .calendario
    }

    func verEnElCalendario(_ dia: String) {
        irAlDia = dia
        pestana = .calendario
    }

    func preparar(_ consulta: Evento) {
        preparando = consulta
        pestana = .hablar
    }

    /// La hora de pared, "YYYY-MM-DD HH:MM", para compararla con `Evento.momento`.
    static func ahora() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        return String(format: "%04d-%02d-%02d %02d:%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }
}
