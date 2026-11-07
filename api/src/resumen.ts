import { pool } from './db.ts'
import { llamar } from './llm.ts'
import { config } from './config.ts'

/// La memoria de Bitácora: dos o tres líneas por día.
///
/// Es lo único que el modelo de la charla ve de los días anteriores. Nunca la
/// transcripción — ni de ayer, ni de hace una semana. Es la regla 4 en su forma
/// más simple: un resumen corto, sin cifras, de cada uno de los últimos días.

const SISTEMA = `Escribes el resumen de un día de un diario hablado.

Te paso lo que la persona habló ese día con Bitácora, la compañera de la app. Devuelves 2 o 3
líneas que digan qué le pasó. Español latinoamericano neutro, de tú: nunca voseo
ni modismos de un país, aunque la persona hable así.

SEGUNDA PERSONA, SIEMPRE. Le hablas a ella: "dormiste mal", "te costó",
"contaste que". NUNCA en primera persona: no eres tú quien vivió ese día.

NADA DE CIFRAS. Ni dígitos ni números escritos con letras. Este resumen es para
lo que los números no dicen: cómo le fue, qué le pasó, qué apareció. Un resumen
con una cifra se descarta entero.

NO REINTERPRETES UN DATO COMO OTRO. Una duración no es un horario. "Siete horas
y media" es cuánto durmió, NO que se levantó a las siete y media.

Es un REGISTRO, no un consejo. No sugieres nada, no felicitas, no regañas, no
sacas conclusiones. Describes.

No inventes nada que no esté en el texto. Si el día tiene poca información, el
resumen es corto: una línea floja es mejor que tres rellenas.

Nada de números clínicos ni de diagnósticos.

La transcripción es un diálogo. Las líneas "Vos:" son de la persona y las
"Bitácora:" son de la compañera. El resumen es sobre la persona: lo que preguntó
Bitácora no es algo que haya pasado en su día.

Ejemplo. Texto:
  "Vos: Dormí como siete horas y media. Fui a nadar cuarenta y cinco minutos."
Bien:  "Dormiste bien y fuiste a nadar. Contaste poco más del día."
Mal:   "Hoy me levanté a las 7:30 y nadé 45 minutos."
       (primera persona, con dígitos, y convirtió una duración en un horario)`

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['resumen'],
  properties: { resumen: { type: 'string' } },
} as const

/// Cuántas veces se intenta resumir un día antes de dejarlo sin resumen.
///
/// Existe para que un día que el modelo no logra resumir sin cifras no se
/// reintente en cada tick para siempre, a una llamada por vez. Tres es
/// generoso: si a la tercera sigue metiendo números, el problema es el día,
/// no la suerte.
export const MAX_INTENTOS = 3

export interface ResultadoResumen {
  dia: string
  /// `null` si el modelo devolvió algo que no se puede guardar.
  resumen: string | null
  n_entradas: number
}

/// Las transcripciones de un día, en orden. Es el único lugar del sistema donde
/// el modelo ve más de una entrada junta — y sigue siendo UN día.
async function textoDelDia(dia: string): Promise<string[]> {
  const { rows } = await pool.query<{ transcripcion: string }>(
    `select transcripcion from entradas where dia = $1 order by creado_local`,
    [dia],
  )
  return rows.map(r => r.transcripcion)
}

/// Escribe (o reescribe) el resumen de un día.
///
/// Si el modelo devuelve algo con cifras o vacío, la fila queda igual con
/// `resumen` en NULL y un intento más. Se descarta en vez de guardarlo: un día
/// sin resumen es un hueco en la memoria de Bitácora; un día con un resumen
/// inventado es una mentira que se le repite todos los días.
export async function resumirDia(dia: string, llamada = llamar): Promise<ResultadoResumen | null> {
  const textos = await textoDelDia(dia)
  if (textos.length === 0) return null

  let resumen: string | null = null
  try {
    const { datos } = await llamada<{ resumen: string }>({
      tarea: 'resumen_dia',
      refId: null,
      sistema: SISTEMA,
      usuario: textos.join('\n\n'),
      nombreSchema: 'resumen_dia',
      schema: SCHEMA as unknown as Record<string, unknown>,
    })
    const r = (datos.resumen ?? '').trim()
    // Los dígitos son donde se cuela el invento. Mejor sin resumen que con uno
    // que diga que te levantaste a una hora que no dijiste.
    resumen = r && !/\d/.test(r) ? r : null
  } catch (e) {
    // Una llamada que falló ya quedó registrada en llm_llamadas. Acá se decide
    // si CUENTA como intento. Lo que es del entorno —red, timeout, 5xx, rate
    // limit, clave o modelo mal configurados— no suma: no queremos que un
    // proveedor caído se lleve tres intentos en tres ticks y deje el día sin
    // resumen para siempre. Todo lo demás es el modelo diciendo que con este
    // día no puede (un 400 por contenido, una respuesta sin texto, un JSON
    // cortado), y eso sí suma: sin tope, un día así se reintentaría cada diez
    // minutos y bloquearía a los que vienen atrás.
    if (esFallaDelEntorno(e)) throw e
  }

  await pool.query(
    `insert into resumenes_dia (dia, resumen, intentos, n_entradas, modelo)
     values ($1, $2, case when $2::text is null then 1 else 0 end, $3, $4)
     on conflict (dia) do update set
       resumen    = excluded.resumen,
       intentos   = case when excluded.resumen is null
                         then resumenes_dia.intentos + 1 else 0 end,
       n_entradas = excluded.n_entradas,
       modelo     = excluded.modelo,
       -- El vector era del texto anterior. Se borra y el latido lo recalcula.
       embedding  = null,
       creado_en  = now()`,
    [dia, resumen, textos.length, config.modeloDeFondo],
  )

  return { dia, resumen, n_entradas: textos.length }
}

/// Lo que no es culpa del día y no tiene que quemarle un intento.
///
/// 5xx y 429 son el proveedor; 401, 403 y 404 son la configuración (clave,
/// modelo); timeout y fetch failed son la red. Nada de eso cambia si volvemos a
/// intentar con el mismo texto — pero cambia solo cuando el entorno se arregla.
export function esFallaDelEntorno(e: unknown): boolean {
  const m = e instanceof Error ? e.message : String(e)
  return /LLM (5\d\d|429|401|403|404)/.test(m)
      || /timeout|aborted|fetch failed|ECONN|ENOTFOUND|socket/i.test(m)
}

/// Lo que Bitácora se acuerda: los últimos días con resumen, antes de `dia`.
///
/// Siete y no más. Es la ventana de "qué me viene pasando" que una persona
/// tiene en la cabeza, y es lo que mantiene el prompt chico.
export async function memoria(dia: string, cuantos = 7): Promise<{ dia: string; resumen: string }[]> {
  const { rows } = await pool.query<{ dia: string; resumen: string }>(
    `select dia::text, resumen from resumenes_dia
      where dia < $1 and resumen is not null
      order by dia desc limit $2`,
    [dia, cuantos],
  )
  return rows.reverse()
}

const SISTEMA_CHARLA = SISTEMA
  .replace('el resumen de un día', 'el resumen de una charla')
  .replace('lo que la persona habló ese día', 'una charla de la persona')
  .replace('qué le pasó', 'de qué habló') + `

SÓLO LO QUE DIJO LA PERSONA. Bitácora a veces cuenta lo que recuerda de otros
días: eso no pasó en esta charla y no va. Tampoco digas lo que NO contó («no
diste detalles de tu día»): si casi no dijo nada, una línea corta con lo poco
que dijo.`

/// El resumen de UNA charla, apenas se guarda (27/10/2026). Es lo que deja que
/// Bitácora sepa de qué hablaron hace un rato sin ver la transcripción (regla
/// 2): el del día se escribe recién cuando el día termina. Mismas reglas que el
/// del día —segunda persona, sin cifras, sin inventar—, pero de una sola charla.
export async function resumirCharla(id: number, llamada = llamar): Promise<string | null> {
  const { rows } = await pool.query<{ transcripcion: string }>(
    'select transcripcion from entradas where id = $1', [id])
  const texto = rows[0]?.transcripcion
  if (!texto || !texto.includes('Vos:')) return null
  // Una charla donde casi no dijo nada —un «Hola», una frase cortada— no tiene
  // de qué hacer resumen, y el modelo lo rellenaba inventando («dormiste mal»).
  // Queda vacío: Bitácora no la cuenta (`charlasDeHoy`).
  const dicho = texto.split('\n').filter(l => l.startsWith('Vos:')).map(l => l.slice(4).trim()).join(' ')
  if (dicho.length < 60) {
    await pool.query("update entradas set resumen = '', resumen_largo = length($2) where id = $1", [id, texto])
    return ''
  }
  let resumen: string | null = null
  try {
    const { datos } = await llamada<{ resumen: string }>({
      tarea: 'resumen_charla',
      refId: id,
      sistema: SISTEMA_CHARLA,
      usuario: texto,
      nombreSchema: 'resumen_dia',
      schema: SCHEMA as unknown as Record<string, unknown>,
    })
    const r = (datos.resumen ?? '').trim()
    resumen = r && !/\d/.test(r) ? r : null
  } catch (e) {
    console.warn(`resumirCharla ${id}:`, e instanceof Error ? e.message.slice(0, 120) : e)
    return null
  }
  await pool.query('update entradas set resumen = $2, resumen_largo = length($3) where id = $1 and length(transcripcion) = length($3)',
    [id, resumen, texto])
  return resumen
}

/// Las charlas de hoy con su resumen, en orden. Las que todavía no tienen uno
/// van igual, sin texto: Bitácora sabe que existen.
export interface CharlaDeHoy { hora: string; resumen: string | null }

export async function charlasDeHoy(dia: string): Promise<CharlaDeHoy[]> {
  const { rows } = await pool.query<CharlaDeHoy>(
    `select to_char(creado_local, 'HH24:MI') as hora, resumen from entradas
     where dia = $1 and transcripcion like '%Vos:%' and resumen is distinct from ''
     order by creado_local`, [dia])
  return rows
}
