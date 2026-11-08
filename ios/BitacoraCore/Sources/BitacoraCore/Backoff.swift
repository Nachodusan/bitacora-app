import Foundation

/// Backoff exponencial con jitter. Función pura: el jitter entra por parámetro
/// para que los tests sean deterministas.
public enum Backoff {
    public static let baseSeg: TimeInterval = 2
    public static let techoSeg: TimeInterval = 300   // 5 min; no tiene sentido más
                                                     // para ~3 entradas por día

    /// `intento` arranca en 1 (primer reintento después del primer fallo).
    /// `jitter` en [0,1); 0 da el valor exacto, útil en tests.
    public static func espera(intento: Int, jitter: Double = Double.random(in: 0..<1)) -> TimeInterval {
        guard intento >= 1 else { return 0 }
        // El exponente se recorta antes de elevar: 2^n con n grande desborda a
        // .infinity y `min` con infinito devuelve el techo pero por accidente.
        let exp = min(intento - 1, 16)
        let bruto = min(baseSeg * pow(2, Double(exp)), techoSeg)
        // Jitter hacia abajo (full jitter, hasta -25%): evita que varias entradas
        // encoladas salgan todas juntas cuando vuelve la red.
        return bruto * (1 - 0.25 * jitter)
    }
}

/// Cómo terminó un intento de subida. La distinción importa: lo que es culpa
/// del contenido no se reintenta nunca (sería un loop infinito); lo que es del
/// servidor, de la red o de la configuración se reintenta siempre.
public enum ResultadoSync: Equatable, Sendable {
    /// El servidor la creó, o ya la tenía por `client_uuid` (idempotencia).
    case aceptada(RespuestaEntrada)
    /// 400, 413, 415, 422: el servidor la rechazó por lo que trae, y va a
    /// rechazarla igual la próxima vez.
    case rechazada(codigo: Int, motivo: String)
    /// 5xx, timeout, sin red — y también los 4xx que no son del contenido (404
    /// de una URL mal puesta, 429 de un proxy). Se reintenta con backoff.
    case reintentable(motivo: String)
    /// 401 o 403. Va aparte de `rechazada` y no es un detalle.
    ///
    /// Los 4xx de `rechazada` son culpa del contenido de la entrada: el servidor
    /// va a contestar lo mismo mil veces. Este NO: depende del token, que es
    /// configuración del teléfono y el usuario puede arreglar en Ajustes en
    /// diez segundos. Meterlo en la misma bolsa dejaba las entradas dictadas
    /// antes de cargar el token muertas para siempre — el texto seguía en
    /// disco, pero no había ningún camino de vuelta a `pendiente`.
    ///
    /// También va aparte de `reintentable` porque lo que hay que mostrar no es
    /// "sin conexión": el servidor contestó perfecto, lo que falta es la llave.
    case sinCredencial(codigo: Int)
}
