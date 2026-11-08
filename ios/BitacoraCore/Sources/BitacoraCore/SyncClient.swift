import Foundation
#if canImport(FoundationNetworking)
// En Linux y Android URLSession vive en un módulo aparte. Esta línea es la que
// hace que este archivo compile fuera de Apple sin tocar nada más.
import FoundationNetworking
#endif

public struct ConfigServidor: Sendable {
    public let baseURL: URL
    public let token: String
    /// Para subir una entrada. Holgado: perder una entrada por impaciencia es
    /// peor que esperar.
    public let timeoutSeg: TimeInterval
    /// Para preguntar si el servidor está. Corto a propósito.
    ///
    /// Esto decide cuánto tarda la pantalla en darse cuenta de que no hay
    /// servidor, y con los 20 segundos del otro había tiempo de sobra para
    /// tener una conversación entera antes de que apareciera el aviso. En una
    /// red local, un servidor que no contesta en cuatro segundos no está.
    public let timeoutSondeoSeg: TimeInterval

    public init(baseURL: URL, token: String,
                timeoutSeg: TimeInterval = 20, timeoutSondeoSeg: TimeInterval = 4) {
        self.baseURL = baseURL
        self.token = token
        self.timeoutSeg = timeoutSeg
        self.timeoutSondeoSeg = timeoutSondeoSeg
    }
}

/// Cliente HTTP de la bitácora. Sin dependencias: `URLSession` y nada más.
public struct SyncClient: Sendable {
    let config: ConfigServidor
    let ejecutar: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    /// Para los pedidos que no terminan: el turno en vivo. `nil` en los tests,
    /// que inyectan `ejecutar` y no tienen sesión.
    let sesion: URLSession?

    public init(config: ConfigServidor, session: URLSession = .shared) {
        self.config = config
        self.ejecutar = { req in try await session.data(for: req) }
        self.sesion = session
    }

    /// Inyección para tests: permite correr sin red ni servidor.
    public init(config: ConfigServidor,
                ejecutar: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.config = config
        self.ejecutar = ejecutar
        self.sesion = nil
    }

    func pedido(_ metodo: String, _ ruta: String, cuerpo: Data? = nil,
                timeout: TimeInterval? = nil) -> URLRequest {
        var r = URLRequest(url: config.baseURL.appendingPathComponent(ruta),
                           timeoutInterval: timeout ?? config.timeoutSeg)
        r.httpMethod = metodo
        r.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        if let cuerpo {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = cuerpo
        }
        return r
    }

    /// `POST /entradas`. Idempotente por `client_uuid`: si la entrada ya estaba,
    /// el servidor devuelve el id existente en vez de crear un duplicado. Por eso
    /// reintentar una subida que falló por timeout es seguro aunque el servidor
    /// la haya recibido.
    public func subir(_ entrada: EntradaNueva) async -> ResultadoSync {
        let cuerpo: Data
        do {
            cuerpo = try JSONEncoder().encode(entrada)
        } catch {
            // Un fallo de encoding no se arregla reintentando.
            return .rechazada(codigo: 0, motivo: "no se pudo serializar: \(error)")
        }

        do {
            let (data, resp) = try await ejecutar(pedido("POST", "entradas", cuerpo: cuerpo))
            guard let http = resp as? HTTPURLResponse else {
                return .reintentable(motivo: "respuesta no HTTP")
            }
            switch http.statusCode {
            case 200, 201:
                if let r = try? JSONDecoder().decode(RespuestaEntrada.self, from: data) {
                    return .aceptada(r)
                }
                // 2xx con cuerpo ilegible: el servidor probablemente la guardó.
                // Reintentar es seguro (idempotencia) y es preferible a darla
                // por subida sin confirmación.
                return .reintentable(motivo: "2xx con cuerpo ilegible")
            case 401, 403:
                return .sinCredencial(codigo: http.statusCode)
            case 400, 413, 415, 422:
                // Éstos sí son el contenido o el cliente: el servidor va a
                // contestar lo mismo mil veces.
                let detalle = String(data: data, encoding: .utf8) ?? ""
                return .rechazada(codigo: http.statusCode, motivo: detalle.isEmpty ? "rechazada" : detalle)
            default:
                // Todo lo demás se reintenta, INCLUIDOS los otros 4xx. Un 404 es
                // una URL con un path de más o un proxy que no rutea; un 429 es
                // el rate limit de alguien en el medio; un 408 es tiempo. Nada
                // de eso depende de la entrada, y marcarla rechazada la dejaba
                // en disco para siempre — corregir la URL después no la
                // rescataba.
                return .reintentable(motivo: "HTTP \(http.statusCode)")
            }
        } catch {
            return .reintentable(motivo: error.localizedDescription)
        }
    }


    /// En qué estado está el servidor, visto desde el teléfono.
    ///
    /// Los tres casos piden acciones distintas del usuario, así que no pueden
    /// colapsarse en un booleano: uno se arregla en Ajustes, otro prendiendo la
    /// computadora, y el tercero no se arregla, se espera.
    public enum Estado: Equatable, Sendable {
        /// Contestó y aceptó la llave. Es el único en el que el sistema sirve.
        case listo
        /// Contestó 401 o 403: está vivo, pero el token no le cierra.
        case sinToken
        /// No contestó. Servidor apagado, URL equivocada, o no hay señal.
        case inalcanzable
    }

    /// Pregunta contra un endpoint que SÍ pide credencial.
    ///
    /// No sirve `/health` para esto: contesta 200 sin token, así que un "está
    /// vivo" de ahí no dice nada sobre si la app va a poder trabajar.
    public func comprobar() async -> Estado {
        let p = pedido("GET", "ajustes", timeout: config.timeoutSondeoSeg)
        guard let (_, resp) = try? await ejecutar(p),
              let http = resp as? HTTPURLResponse else { return .inalcanzable }
        switch http.statusCode {
        case 200: return .listo
        case 401, 403: return .sinToken
        // Contestó, pero no es nuestro servidor o está roto: un 404 por una URL
        // con path de más, un 502 de un proxy con el backend caído. Antes esto
        // era `.listo`, el orbe se habilitaba, y la charla moría en el primer
        // turno con el mensaje de corte.
        default: return .inalcanzable
        }
    }

    /// `POST /charla`. Devuelve lo que contesta Bitácora.
    ///
    /// El servidor nunca devuelve un error acá: si el turno falla —presupuesto,
    /// timeout, un 429— contesta `ok: false` con una despedida fija. Si en
    /// cambio la que falla es la RED, eso lo resuelve este lado: el `nil` es lo
    /// que la app traduce a "se cortó", con el mismo texto.
    public func turnoDeCharla(turnos: [TurnoDeCharla], dia: String,
                              timbre: String? = nil, preparar: Int? = nil,
                              retoma: String? = nil) async -> RespuestaDeCharla? {
        let cuerpo = PedidoDeCharla(turnos: turnos, dia: dia, timbre: timbre, preparar: preparar, retoma: retoma)
        guard let data = try? JSONEncoder().encode(cuerpo),
              let (resp, http) = try? await ejecutar(pedido("POST", "charla", cuerpo: data)),
              let r = http as? HTTPURLResponse, r.statusCode == 200,
              let d = try? JSONDecoder().decode(RespuestaDeCharla.self, from: resp)
        else { return nil }
        return d
    }

    /// `POST /herramientas/emociones`: las emociones para «Ponerle nombre»,
    /// sacadas de lo que contó. `nil` si no llegó o si hay señal de riesgo
    /// (`cuidado`): ahí la pantalla no se abre.
    public func emociones(turnos: [TurnoDeCharla], dia: String) async -> [String]? {
        struct Respuesta: Decodable { let emociones: [String]; let cuidado: Bool? }
        let cuerpo = PedidoDeCharla(turnos: turnos, dia: dia, timbre: nil, preparar: nil)
        guard let data = try? JSONEncoder().encode(cuerpo),
              let (resp, http) = try? await ejecutar(pedido("POST", "herramientas/emociones", cuerpo: data)),
              let r = http as? HTTPURLResponse, r.statusCode == 200,
              let d = try? JSONDecoder().decode(Respuesta.self, from: resp),
              d.cuidado != true
        else { return nil }
        return d.emociones
    }

    #if !canImport(FoundationNetworking)
    /// `POST /charla/vivo`. El turno de Bitácora mientras se genera.
    ///
    /// Devuelve las tramas a medida que llegan: el texto que se va escribiendo
    /// y el audio que se va sintetizando. Bitácora empieza a hablar cuando tiene la
    /// primera oración, no cuando tiene todo.
    ///
    /// Tira si la conexión no se pudo abrir o se cortó. Quien llama decide qué
    /// hacer según cuánto había llegado: si nada, puede probar por `/charla`.
    ///
    /// Dejar de leer el flujo CIERRA la conexión, y eso es lo que le avisa al
    /// servidor que corte lo que estaba generando. Es lo que pasa cuando la
    /// persona interrumpe a Bitácora.
    ///
    /// No existe fuera de Apple: `URLSession.bytes` no está en Linux.
    ///
    /// Sin `timbre` llega sólo el texto: es para cuando la persona escribe, que
    /// es cuando Bitácora no habla.
    public func charlaEnVivo(turnos: [TurnoDeCharla], dia: String,
                             timbre: String?, preparar: Int? = nil,
                             retoma: String? = nil) -> AsyncThrowingStream<TramaDeCharla, Error> {
        let cuerpo = try? JSONEncoder().encode(PedidoDeCharla(turnos: turnos, dia: dia, timbre: timbre,
                                                              preparar: preparar, retoma: retoma))
        let req = pedido("POST", "charla/vivo", cuerpo: cuerpo)
        let sesion = self.sesion

        return AsyncThrowingStream { salida in
            let tarea = Task {
                do {
                    guard let sesion, cuerpo != nil else { throw URLError(.badURL) }
                    let (bytes, resp) = try await sesion.bytes(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    // Se lee de a lo justo: lo que le falta a la trama en curso.
                    // Juntar de a bloques fijos dejaría una trama corta —el
                    // texto, por ejemplo— esperando bytes que todavía no
                    // salieron del servidor.
                    var lector = LectorDeTramas()
                    var junta = Data()
                    for try await b in bytes {
                        junta.append(b)
                        if junta.count == lector.faltan {
                            for t in lector.recibir(junta) { salida.yield(t) }
                            junta.removeAll(keepingCapacity: true)
                        }
                    }
                    salida.finish()
                } catch {
                    salida.finish(throwing: error)
                }
            }
            salida.onTermination = { _ in tarea.cancel() }
        }
    }
    #endif

    /// `POST /voz`. El audio de un turno de Bitácora, en AAC.
    ///
    /// `nil` es una respuesta esperada y no un error a mostrar: sin red, sin
    /// presupuesto o con el proveedor caído, el teléfono usa la voz de iOS y la
    /// conversación sigue. Que suene peor es infinitamente mejor que que se
    /// calle, así que acá no hay reintentos ni mensajes: se devuelve nada y el
    /// que llama sabe qué hacer.
    ///
    /// El timeout es propio y corto. El de la charla puede ser largo porque del
    /// otro lado alguien espera una respuesta que no tiene reemplazo; acá el
    /// reemplazo existe y está en el teléfono, así que esperar de más sólo
    /// agrega silencio.
    ///
    /// El techo crece con el texto, y tiene que crecer: medido contra el
    /// proveedor, una frase de sesenta caracteres vuelve en tres segundos pero
    /// un turno largo de quinientos setenta tarda casi ocho. Con los nueve fijos
    /// que había antes, los turnos largos —los que más importan— quedaban a un
    /// pelo de cortarse y caer a la voz de iOS.
    ///
    /// Dos segundos de base más veinte milisegundos por caracter, con piso de
    /// seis: un turno corto no espera de más, uno largo llega.
    public func voz(texto: String, timbre: String,
                    timeoutSeg: TimeInterval? = nil) async -> Data? {
        let techo = timeoutSeg ?? max(6, 2 + Double(texto.count) * 0.02)
        let cuerpo = PedidoDeVoz(texto: texto, timbre: timbre)
        guard let data = try? JSONEncoder().encode(cuerpo),
              let (audio, http) = try? await ejecutar(
                  pedido("POST", "voz", cuerpo: data, timeout: techo)),
              let r = http as? HTTPURLResponse, r.statusCode == 200,
              !audio.isEmpty
        else { return nil }
        return audio
    }

    /// `GET /notas`. Lo que dijiste, en tus palabras, para llevar a una sesión,
    /// entre dos días (los dos incluidos), del más reciente al más viejo.
    ///
    /// `nil` si no se pudo preguntar, que no es lo mismo que no tener nada: un
    /// PDF vacío porque se cortó la red se mandaría igual al psicólogo.
    public func notas(desde: String, hasta: String) async -> [NotaDelDia]? {
        var r = pedido("GET", "notas")
        if let url = r.url, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.queryItems = [URLQueryItem(name: "desde", value: desde),
                            URLQueryItem(name: "hasta", value: hasta)]
            r.url = c.url
        }
        guard let (data, resp) = try? await ejecutar(r),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let d = try? JSONDecoder().decode(RespuestaNotas.self, from: data)
        else { return nil }
        return d.notas
    }

    /// `PUT /ajustes`. Tu nombre y tu zona horaria.
    ///
    /// El teléfono guarda su copia en `UserDefaults` igual, así que si esto
    /// falla la app sigue funcionando con lo que elegiste — lo único que queda
    /// viejo es lo que sabe el servidor. Por eso se reintenta cuando la app
    /// vuelve a primer plano en vez de bloquear la pantalla de Ajustes.
    @discardableResult
    public func guardarAjustes(nombre: String?, zona: String) async -> Bool {
        guard let cuerpo = try? JSONEncoder().encode(AjustesQueViajan(nombre: nombre, zona: zona))
        else { return false }
        guard let (_, resp) = try? await ejecutar(pedido("PUT", "ajustes", cuerpo: cuerpo)),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}

/// El cuerpo del `PUT /ajustes`.
struct AjustesQueViajan: Encodable {
    let zona: String
    let nombre: String?

    init(nombre: String?, zona: String) {
        self.zona = zona
        // En blanco es no tener nombre, no un nombre vacío.
        let limpio = (nombre ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.nombre = limpio.isEmpty ? nil : String(limpio.prefix(40))
    }
}

// MARK: - Charla

public struct TurnoDeCharla: Codable, Sendable, Equatable {
    /// "vos" o "bitacora". String y no enum para que el JSON sea el del servidor sin
    /// una capa de traducción en el medio.
    public let de: String
    public let texto: String

    public init(de: String, texto: String) {
        self.de = de
        self.texto = texto
    }
}

struct PedidoDeVoz: Encodable {
    let texto: String
    let timbre: String
}

struct PedidoDeCharla: Encodable {
    let turnos: [TurnoDeCharla]
    let dia: String
    /// Con timbre, el servidor adelanta el audio de la primera frase mientras
    /// todavía está escribiendo el texto, y lo manda en la misma respuesta.
    /// Sin timbre —la voz natural apagada— contesta sólo texto, como antes.
    let timbre: String?
    /// La consulta que se está preparando, si la charla se abrió con «Preparar»
    /// en Mi expediente. Sin ella no viaja (los opcionales en `nil` no se
    /// escriben), y un servidor viejo no la ve.
    let preparar: Int?
    /// El día de una charla anterior que se retomó desde el historial: sus
    /// turnos van primero. Como `preparar`, en `nil` no viaja.
    var retoma: String? = nil
}

public struct RespuestaDeCharla: Decodable, Sendable {
    /// `false` cuando el servidor no pudo generar el turno. El texto igual
    /// viene: es la despedida fija, no un error para mostrar en crudo.
    public let ok: Bool
    public let texto: String
    /// El audio de la primera frase, si el servidor pudo adelantarlo.
    ///
    /// Llega en base64 porque viaja adentro del mismo JSON que el texto: son
    /// unos ochenta kilobytes, un tercio más que en crudo, y a cambio se ahorra
    /// un viaje entero de ida y vuelta al servidor.
    public let audio: Data?
    /// Qué parte del texto cubre ese audio.
    ///
    /// Hace falta porque el teléfono parte el texto con su propio criterio
    /// (`TrozosDeVoz`) y no es idéntico al del servidor: sin esto, en las
    /// respuestas cortas —que el teléfono no parte— se comería todo lo que
    /// viene después de la primera frase.
    public let frase: String?
    /// El corte de riesgo del servidor se disparó: `texto` es el mensaje fijo
    /// de cuidado, no viene audio, y la charla se cierra. El teléfono tiene su
    /// propio corte antes de llamar; esto cubre lo que su lista no tenga.
    public let cuidado: Bool?
}

// MARK: - Notas para terapia

struct RespuestaNotas: Decodable {
    let notas: [NotaDelDia]
}

/// Lo que dijiste un día, en tus palabras.
///
/// No es una nota clínica: son citas literales verificadas contra lo que
/// dictaste, más los temas y dos líneas de contexto. La lectura es de quien te
/// atiende; el material es tuyo.
public struct NotaDelDia: Decodable, Sendable, Identifiable, Hashable {
    public let dia: String
    public let hora: String
    public let temas: [String]
    public let contexto: String?
    public let citas: [Cita]
    /// Emociones, impulsos, conductas y hábitos que contó, cada uno con su
    /// frase. SÓLO para el PDF del psicólogo: ninguna pantalla se lo muestra a
    /// la persona, para que no se autodiagnostique (lo pidió Dusan).
    public let registro: [Registro]

    public struct Cita: Decodable, Sendable, Identifiable, Hashable {
        public let texto: String
        public let sobre: String
        public var id: String { texto }
    }

    public struct Registro: Decodable, Sendable, Hashable {
        /// "emocion", "impulso", "conducta" o "habito".
        public let tipo: String
        public let que: String
        public let cita: String
        public init(tipo: String, que: String, cita: String) {
            self.tipo = tipo; self.que = que; self.cita = cita
        }
    }

    public var id: String { dia + hora }

    public init(dia: String, hora: String, temas: [String], contexto: String?, citas: [Cita],
                registro: [Registro] = []) {
        self.dia = dia; self.hora = hora; self.temas = temas
        self.contexto = contexto; self.citas = citas; self.registro = registro
    }

    private enum CodingKeys: String, CodingKey { case dia, hora, temas, contexto, citas, registro }

    /// Un servidor sin el registro (anterior al 14 de octubre) manda notas sin
    /// ese campo: llegan con el registro vacío.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dia = try c.decode(String.self, forKey: .dia)
        hora = try c.decode(String.self, forKey: .hora)
        temas = try c.decode([String].self, forKey: .temas)
        contexto = try c.decodeIfPresent(String.self, forKey: .contexto)
        citas = try c.decode([Cita].self, forKey: .citas)
        registro = try c.decodeIfPresent([Registro].self, forKey: .registro) ?? []
    }
}
