#if DEBUG
import Foundation
import SwiftData

/// Carga en el teléfono un mes de la simulación (`api/scripts/simular-mes.ts`),
/// para recorrerlo en la app: las charlas y las evaluaciones viven acá, no en el
/// servidor, así que apuntar la app a la base de la simulación no alcanza.
///
/// Sólo en DEBUG, y sólo si alguien dejó `simulacion.json` en Documents del
/// contenedor de la app (en el simulador, con `simctl`). En un teléfono ese
/// archivo no aparece solo.
///
/// REEMPLAZA las charlas, las sesiones y las notas sueltas que haya: respaldar
/// el contenedor antes. Al terminar borra el archivo, para que no se repita.
enum ImportarSimulacion {
    private struct Archivo: Decodable {
        struct Entrada: Decodable {
            let clientUuid: String
            let creadoEn: Date
            let creadoLocal: String
            let dia: String
            let transcripcion: String
            let duracionSeg: Double
            let servidorId: Int
        }
        struct Sesion: Decodable {
            let numero: Int
            let dia: String
            let revisadaEl: String
            let eventoId: Int
            let entendi: String
            let aporte: String
            let sentir: String
            let temas: [String]
            let avance: String
        }
        let entradas: [Entrada]
        let sesiones: [Sesion]
    }

    @MainActor
    static func siHay(en bitacora: ModelContext) {
        let url = URL.documentsDirectory.appending(path: "simulacion.json")
        guard let datos = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let a = try? decoder.decode(Archivo.self, from: datos) else {
            print("ImportarSimulacion: simulacion.json no se pudo leer")
            return
        }

        try? bitacora.delete(model: EntradaLocal.self)
        for e in a.entradas {
            let x = EntradaLocal(transcripcion: e.transcripcion, duracionSeg: e.duracionSeg,
                                 estado: .subida, instante: e.creadoEn)
            // La hora de pared y el día, tal como quedaron en el servidor.
            x.clientUuid = e.clientUuid
            x.creadoLocalISO = e.creadoLocal
            x.diaLogico = e.dia
            x.servidorId = e.servidorId
            bitacora.insert(x)
        }
        try? bitacora.save()

        if let sesiones = AlmacenDeSesiones.contenedor?.mainContext {
            try? sesiones.delete(model: SesionDeTerapia.self)
            for s in a.sesiones {
                guard let fecha = Agenda.fecha(s.dia) else { continue }
                let x = SesionDeTerapia(numero: s.numero, fecha: fecha)
                x.entendi = s.entendi
                x.aporte = s.aporte
                x.sentir = s.sentir
                x.temas = s.temas
                x.avance = s.avance
                x.eventoId = s.eventoId
                x.revisada = true
                x.creadoEn = Agenda.fecha(s.revisadaEl) ?? fecha
                sesiones.insert(x)
            }
            try? sesiones.save()
        }

        if let apuntes = AlmacenDeApuntes.contenedor?.mainContext {
            try? apuntes.delete(model: Apunte.self)
            try? apuntes.save()
        }

        try? FileManager.default.removeItem(at: url)
        print("ImportarSimulacion: \(a.entradas.count) charlas y \(a.sesiones.count) sesiones")
    }
}
#endif
