import { pool } from './db.ts'
import { llamar, PresupuestoAgotado } from './llm.ts'
import type { Reloj } from './ajustes.ts'
import { normalizar, soloVos, rotuloClinico } from './notas.ts'
import { fechaLarga, cuandoEs, sumarDias } from './fechas.ts'

/// Las consultas con su terapeuta, y lo que Bitácora hace alrededor de ellas.
///
/// Es el plan que pasó Dusan el 02/10/2026, puntos 5, 6 y 7. Todo sale de una
/// consulta marcada en el calendario:
///
///   · ANTES (desde las 4 de la mañana del día anterior hasta la hora de la
///     consulta): Bitácora pregunta qué quiere llevar, le ofrece lo que habló
///     desde la última consulta y le ayuda a elegir dos o tres cosas. Lo que
///     elige queda anotado en la consulta (`para_llevar`).
///   · DESPUÉS (desde la hora de la consulta y por siete días, o hasta que la
///     evaluación quede guardada): pregunta en la charla qué se llevó de la
///     sesión, una vez por día como mucho.
///   · Con lo que contó después, el latido escribe un BORRADOR de la evaluación.
///     El teléfono lo trae y la persona lo revisa. Apenas la evaluación queda
///     guardada allá, el borrador se borra de acá: las evaluaciones viven en el
///     teléfono.
///
/// Y la otra punta: si en una charla menciona una consulta con día («el jueves
/// tengo terapia a las cinco»), el latido la PROPONE en el calendario. No cuenta
/// para nada hasta que la persona la confirma.
///
/// Una consulta sin hora se toma como si fuera al mediodía, sólo para saber
/// cuándo termina el "antes" y empieza el "después".

export type TipoDeEvento = 'consulta' | 'otro'
export type EstadoDeEvento = 'confirmado' | 'propuesto' | 'descartado'

export interface Borrador {
  entendi: string
  aporte: string
  sentir: string
  temas: string[]
  avance: string
}

export interface Evento {
  id: number
  client_uuid: string | null
  tipo: TipoDeEvento
  dia: string
  /// "HH:MM", o `null` si no tiene hora.
  hora: string | null
  titulo: string | null
  origen: 'persona' | 'bitacora'
  estado: EstadoDeEvento
  para_llevar: string[]
  borrador: Borrador | null
  evaluada: boolean
}

const COLUMNAS = `id::int, client_uuid::text, tipo, dia::text,
  to_char(hora, 'HH24:MI') as hora, titulo, origen, estado, para_llevar, borrador,
  evaluada_en is not null as evaluada`

/// Cuándo "es" la consulta, en hora de pared. Sin hora, el mediodía.
const MOMENTO = `(dia + coalesce(hora, time '12:00'))`

// ------------------------------------------------------------
// Los eventos
// ------------------------------------------------------------

/// Los del calendario entre dos días. Los descartados no se ven.
export async function listarEventos(desde: string, hasta: string): Promise<Evento[]> {
  const { rows } = await pool.query<Evento>(
    `select ${COLUMNAS} from eventos
      where dia between $1 and $2 and estado <> 'descartado'
      order by dia, hora nulls first, id`,
    [desde, hasta],
  )
  return rows
}

export async function leerEvento(id: number): Promise<Evento | null> {
  const { rows } = await pool.query<Evento>(`select ${COLUMNAS} from eventos where id = $1`, [id])
  return rows[0] ?? null
}

export interface EventoNuevo {
  client_uuid: string
  tipo: TipoDeEvento
  dia: string
  hora?: string | null
  titulo?: string | null
}

/// Uno que carga la persona. Idempotente por `client_uuid`, como las entradas:
/// reintentar después de un timeout devuelve el mismo.
export async function crearEvento(e: EventoNuevo): Promise<{ evento: Evento; creado: boolean }> {
  const { rows } = await pool.query<{ id: number }>(
    `insert into eventos (client_uuid, tipo, dia, hora, titulo, origen, estado)
     values ($1, $2, $3, $4, $5, 'persona', 'confirmado')
     on conflict (client_uuid) where client_uuid is not null do nothing
     returning id::int`,
    [e.client_uuid, e.tipo, e.dia, e.hora || null, e.titulo?.trim() || null],
  )
  if (rows[0]) return { evento: (await leerEvento(rows[0].id))!, creado: true }
  const { rows: ya } = await pool.query<Evento>(
    `select ${COLUMNAS} from eventos where client_uuid = $1`, [e.client_uuid])
  return { evento: ya[0]!, creado: false }
}

export interface CambioDeEvento {
  dia?: string
  hora?: string | null
  titulo?: string | null
  /// Confirmar una propuesta, o descartarla.
  estado?: 'confirmado' | 'descartado'
  /// La evaluación de esta consulta quedó guardada en el teléfono.
  evaluada?: boolean
}

/// Cambia lo que venga, y nada más.
///
/// Si cambia el día o la hora, lo que se había derivado de la fecha vieja —lo
/// que eligió llevar, el borrador— ya no corresponde: se borra y el latido lo
/// vuelve a escribir con las charlas de la fecha nueva.
///
/// Marcarla evaluada BORRA el borrador. Es la promesa de que las evaluaciones
/// viven en el teléfono: el borrador estuvo acá sólo hasta que llegó allá.
export async function cambiarEvento(id: number, c: CambioDeEvento): Promise<Evento | null> {
  const sets: string[] = []
  const valores: unknown[] = [id]
  const poner = (sql: string, v: unknown) => { valores.push(v); sets.push(`${sql} = $${valores.length}`) }

  if (c.dia !== undefined) poner('dia', c.dia)
  if (c.hora !== undefined) poner('hora', c.hora || null)
  if (c.titulo !== undefined) poner('titulo', c.titulo?.trim() || null)
  if (c.estado !== undefined) poner('estado', c.estado)
  if (c.dia !== undefined || c.hora !== undefined) {
    sets.push(`para_llevar = '[]'`, 'para_llevar_n = 0', 'borrador = null', 'borrador_n = 0')
  }
  if (c.evaluada === true) sets.push('evaluada_en = coalesce(evaluada_en, now())', 'borrador = null')
  if (c.evaluada === false) sets.push('evaluada_en = null')
  if (sets.length === 0) return leerEvento(id)

  const { rowCount } = await pool.query(`update eventos set ${sets.join(', ')} where id = $1`, valores)
  return rowCount ? leerEvento(id) : null
}

export async function borrarEvento(id: number): Promise<boolean> {
  const { rowCount } = await pool.query('delete from eventos where id = $1', [id])
  return (rowCount ?? 0) > 0
}

// ------------------------------------------------------------
// Antes y después, para el prompt de la charla
// ------------------------------------------------------------

export interface MomentoDeConsulta {
  /// `pedida`: la persona tocó «Preparar» en la app para esta consulta, así que
  /// la charla es para eso desde el primer mensaje.
  antes: { evento: Evento; citas: { dia: string; texto: string }[]; pedida: boolean } | null
  /// `hablaronEl`: el día de la primera charla después de la consulta, o `null`
  /// si todavía no hablaron.
  despues: { evento: Evento; hablaronEl: string | null } | null
}

/// Cuántas frases suyas se le ofrecen como material. Más que eso no se elige:
/// se lee.
const MAX_CITAS = 10

/// Si ahora toca preparar una consulta, o preguntar por una que pasó.
///
/// Pueden tocar las dos a la vez —con terapia todas las semanas, el día antes
/// de una cae en la semana de después de la anterior— y está bien.
///
/// `preparar` es el id de una consulta que la persona pidió preparar con el
/// botón «Preparar» de Mi expediente (desde el 06/10/2026). Ésa toca aunque
/// falten días: sin esto, el modo de antes abría recién a las 4 de la mañana del
/// día anterior, y tres días antes Bitácora no sabía qué consulta preparar. Si
/// ya pasó, o no es una consulta confirmada, se sigue como si no hubiera venido.
export async function momentoDeConsulta(reloj: Reloj, preparar?: number): Promise<MomentoDeConsulta> {
  const ahora = reloj.ahoraLocal

  const { rows: pedidas } = preparar === undefined ? { rows: [] as Evento[] } : await pool.query<Evento>(
    `select ${COLUMNAS} from eventos
      where id = $2 and tipo = 'consulta' and estado = 'confirmado'
        and $1::timestamp < ${MOMENTO}`,
    [ahora, preparar],
  )
  const { rows: proximas } = pedidas.length > 0 ? { rows: pedidas } : await pool.query<Evento>(
    `select ${COLUMNAS} from eventos
      where tipo = 'consulta' and estado = 'confirmado'
        and $1::timestamp >= (dia - 1) + time '04:00'
        and $1::timestamp < ${MOMENTO}
      order by dia, hora nulls last limit 1`,
    [ahora],
  )
  const { rows: pasadas } = await pool.query<Evento>(
    `select ${COLUMNAS} from eventos
      where tipo = 'consulta' and estado = 'confirmado' and evaluada_en is null
        and $1::timestamp >= ${MOMENTO}
        and $1::timestamp < ${MOMENTO} + interval '7 days'
      order by dia desc, hora desc nulls last limit 1`,
    [ahora],
  )

  let antes: MomentoDeConsulta['antes'] = null
  const proxima = proximas[0]
  if (proxima) {
    // El material es desde la última consulta confirmada; si no hubo, las dos
    // últimas semanas, que es lo que suele haber entre una sesión y otra.
    const { rows: previa } = await pool.query<{ dia: string }>(
      `select dia::text from eventos
        where tipo = 'consulta' and estado = 'confirmado' and dia < $1
        order by dia desc limit 1`,
      [proxima.dia],
    )
    const desde = previa[0]?.dia ?? sumarDias(proxima.dia, -15)
    const { rows: citas } = await pool.query<{ dia: string; texto: string }>(
      `select n.dia::text, c->>'texto' as texto
         from notas_terapia n, jsonb_array_elements(n.citas) c
        where n.dia > $1 and n.dia < $2
        order by n.dia desc
        limit $3`,
      [desde, proxima.dia, MAX_CITAS],
    )
    antes = { evento: proxima, citas: citas.reverse(), pedida: pedidas.length > 0 }
  }

  let despues: MomentoDeConsulta['despues'] = null
  const pasada = pasadas[0]
  if (pasada) {
    // Cualquier charla desde la hora de la consulta, no sólo las de hoy: con
    // «hoy», en la simulación del 03/10/2026 le volvió a preguntar cómo le fue
    // al día siguiente y cinco días después, cuando ya se lo había contado.
    // El tope en `ahora` es para el reloj inyectado de los tests.
    const { rows } = await pool.query<{ dia: string | null }>(
      `select min(e.dia)::text as dia from entradas e, eventos v
        where v.id = $1
          and e.creado_local >= (v.dia + coalesce(v.hora, time '12:00'))
          and e.creado_local < $2::timestamp`,
      [pasada.id, ahora],
    )
    despues = { evento: pasada, hablaronEl: rows[0]?.dia ?? null }
  }

  return { antes, despues }
}

function cuandoYHora(e: Evento, hoy: string): string {
  const cuando = cuandoEs(e.dia, hoy)
  const fecha = cuando.startsWith('el ') ? cuando : `${cuando}, ${fechaLarga(e.dia, false)}`
  return e.hora ? `${fecha}, a las ${e.hora}` : fecha
}

/// Los bloques del prompt para la consulta de antes y la de después, o `null`.
///
/// Como el resto del prompt, dicen la FORMA de lo que tiene que hacer —una
/// pregunta por vez, dos o tres cosas, no volver a preguntar— y no sólo la
/// intención: es lo que el modelo cumple.
///
/// `hoy` es el día lógico, el mismo del bloque de la fecha: a las dos de la
/// mañana del sábado, una consulta el sábado a la tarde es «mañana», que es como
/// lo piensa quien todavía no se fue a dormir. Con la fecha del calendario, los
/// dos bloques decían «hoy» de días distintos.
export function bloqueDeConsulta(m: MomentoDeConsulta, hoy: string): string | null {
  const bloques: string[] = []

  if (m.antes) {
    const { evento: e, citas } = m.antes
    // Dice CUÁNDO preguntar, y no «si la charla lo permite»: escrito así, en la
    // primera prueba contra el modelo (03/10/2026) contestó «hola» dos veces
    // sin nombrar la consulta. Y no le explica de dónde sale el material: le
    // decía «no hay frases suyas guardadas», y el modelo se lo repetía a la
    // persona tal cual.
    const lineas = [
      '--- Antes de la consulta ---',
      `Tiene consulta con su terapeuta ${cuandoYHora(e, hoy)}.`,
      // Con «Preparar» ya dijo a qué viene: esperar a que «baje» sería hacerla
      // pedirlo dos veces.
      ...(m.antes.pedida
        ? ['Abrió esta charla para preparar esa consulta: tocó «Preparar» en la app. Desde',
           'tu primera respuesta ayúdale con eso. Si su primer mensaje es sólo un saludo,',
           'pregúntale qué quiere llevar a la sesión.']
        : ['Si su primer mensaje es sólo un saludo, tu primera respuesta termina',
           'preguntándole qué quiere llevar a la sesión. Si abre contando algo —cómo está,',
           'algo que le pasó—, primero respóndele a eso; la pregunta va más adelante, cuando',
           'baje. Se pregunta una sola vez por charla.']),
      'Ayúdale a elegir dos o tres cosas, no más. Lo que lleva lo decide ella: no le',
      'armes la sesión ni le digas qué trabajar. Si no quiere hablar de eso, déjalo.',
    ]
    if (e.para_llevar.length > 0) {
      lineas.push(`Ya eligió llevar: ${e.para_llevar.join('; ')}. No se lo vuelvas a preguntar;`,
                  'si sale el tema, recuérdaselo.')
    }
    if (citas.length > 0) {
      lineas.push('Para ofrecerle, lo que dijo desde la última consulta, con sus palabras (no le',
                  'expliques de dónde lo sacas):',
                  ...citas.map(c => `- «${c.texto}» (${fechaLarga(c.dia, false)})`))
    } else {
      lineas.push('Si arriba tienes resúmenes de estos días, ofrécele lo que fue saliendo; si no,',
                  'pregúntale qué le estuvo dando vueltas desde la última consulta. No inventes',
                  'temas que no estén escritos acá.')
    }
    bloques.push(lineas.join('\n'))
  }

  if (m.despues) {
    const { evento: e, hablaronEl } = m.despues
    const lineas = [
      '--- Después de la consulta ---',
      `Tuvo consulta con su terapeuta ${cuandoYHora(e, hoy)}.`,
    ]
    if (e.para_llevar.length > 0) lineas.push(`Antes de ir eligió llevar: ${e.para_llevar.join('; ')}.`)
    if (hablaronEl) {
      lineas.push(`Ya hablaron después de la consulta, ${cuandoEs(hablaronEl, hoy)}: no le vuelvas a`,
                  'preguntar cómo le fue. Si la trae ella, síguela.')
    } else {
      // Con la forma de la respuesta, igual que el de antes: con «en algún
      // momento de la charla, sin forzarlo», cuatro de cuatro respuestas no
      // nombraron la consulta (03/10/2026).
      lineas.push(
        'Si su primer mensaje es sólo un saludo, tu primera respuesta termina',
        'preguntándole cómo le fue en la consulta. Si abre contando algo —cómo está, algo',
        'que le pasó—, primero respóndele a eso; la pregunta va más adelante, cuando',
        'baje. Se pregunta una sola vez por charla. Después',
        'sigue lo que conteste —qué entendió, qué le aportó, cómo se sintió, en qué siente',
        'que avanzó—, una pregunta por vez. Si no quiere hablar de eso, suéltalo.',
      )
    }
    bloques.push(lineas.join('\n'))
  }

  return bloques.length > 0 ? bloques.join('\n\n') : null
}

// ------------------------------------------------------------
// Lo que hace el latido
// ------------------------------------------------------------

/// Sin alguna de estas palabras no hay consulta que buscar, y no se paga una
/// llamada para confirmarlo. Es la mayoría de las charlas.
const HABLA_DE_CONSULTA = /terap|psic[oó]log|psiquiatr|consulta|sesi[oó]n|turno con|hora con|cita con/i

/// Hasta cuántos días adelante se acepta una consulta mencionada. Más que eso
/// es un error de cálculo del modelo más seguido que una consulta de verdad.
const HORIZONTE_DIAS = 60

const SISTEMA_CONSULTA = `Buscas en una conversación si la persona mencionó una consulta FUTURA con su
terapeuta, psicólogo o psiquiatra, con un día que se pueda saber.

Te paso la fecha de la conversación y la conversación. Las líneas "Vos:" son de
la persona; las "Bitácora:" son de la app y no cuentan.

Devuelves \`consultas\`, una por cada consulta mencionada:
- \`dia\`: la fecha, AAAA-MM-DD. Calcúlala desde la fecha de la conversación:
  "mañana", "el jueves", "el 14". Si no se puede saber el día con certeza, no la
  incluyas.
- \`hora\`: "HH:MM" en 24 horas si la dijo; si no, "".
- \`cita\`: la frase de la persona donde lo dijo, copiada tal cual.

Sólo consultas con un profesional de salud mental que todavía no pasaron. Nada
de otras citas (médico, trabajo, amigos), ni consultas que ya fueron, ni algo
que "quiere pedir" sin día. Si no hay ninguna, \`consultas\` vacío.`

const SCHEMA_CONSULTA = {
  type: 'object',
  additionalProperties: false,
  required: ['consultas'],
  properties: {
    consultas: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['dia', 'hora', 'cita'],
        properties: { dia: { type: 'string' }, hora: { type: 'string' }, cita: { type: 'string' } },
      },
    },
  },
} as const

function diaValido(d: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(d) && new Date(`${d}T12:00:00Z`).toISOString().slice(0, 10) === d
}

function horaValida(h: string): boolean {
  const m = /^(\d{2}):(\d{2})$/.exec(h)
  return !!m && Number(m[1]) < 24 && Number(m[2]) < 60
}

function fallo(e: unknown): string {
  return (e instanceof Error ? e.message : String(e)).slice(0, 160)
}

/// Busca consultas mencionadas en las charlas que todavía no se revisaron, y
/// propone las que encuentre. Devuelve cuántas propuso.
///
/// La frase donde lo dijo se VERIFICA contra lo que dijo, como las citas de las
/// notas: una consulta que el modelo se imaginó no puede aparecer en el
/// calendario de nadie. Y no se propone un día que ya tiene una consulta, ni
/// uno donde se descartó una propuesta: decir que no es una respuesta.
///
/// Mira también las charlas de hoy, a diferencia de las notas: una consulta
/// mencionada esta tarde puede ser mañana.
export async function proponerConsultas(hoy: string, ventanaDias: number, llamada = llamar): Promise<number> {
  const { rows: pendientes } = await pool.query<{ id: number; dia: string; transcripcion: string }>(
    `select id::int, dia::text, transcripcion from entradas
      where consultas_revisadas_en is null
        and dia <= $1::date and dia >= $1::date - $2::int
      order by dia, creado_local`,
    [hoy, ventanaDias],
  )

  let propuestas = 0
  for (const e of pendientes) {
    try {
      const dicho = soloVos(e.transcripcion)
      if (HABLA_DE_CONSULTA.test(dicho)) {
        const { datos } = await llamada<{ consultas: { dia: string; hora: string; cita: string }[] }>({
          tarea: 'consulta',
          refId: e.id,
          sistema: SISTEMA_CONSULTA,
          usuario: `Fecha de la conversación: ${fechaLarga(e.dia)} (${e.dia}).\n\n${e.transcripcion}`,
          nombreSchema: 'consultas',
          schema: SCHEMA_CONSULTA as unknown as Record<string, unknown>,
        })
        const fuente = normalizar(dicho)
        for (const c of datos.consultas ?? []) {
          const aguja = normalizar(c.cita ?? '')
          if (!aguja || !fuente.includes(aguja)) continue
          if (!diaValido(c.dia) || c.dia < hoy || c.dia > sumarDias(e.dia, HORIZONTE_DIAS)) continue
          const hora = horaValida(c.hora ?? '') ? c.hora : null
          const { rowCount } = await pool.query(
            `insert into eventos (tipo, dia, hora, origen, estado, entrada_id)
             select 'consulta', $1, $2, 'bitacora', 'propuesto', $3
              where not exists (select 1 from eventos where tipo = 'consulta' and dia = $1)`,
            [c.dia, hora, e.id],
          )
          propuestas += rowCount ?? 0
        }
      }
      await pool.query('update entradas set consultas_revisadas_en = now() where id = $1', [e.id])
    } catch (err) {
      if (err instanceof PresupuestoAgotado) throw err
      // Sin marca: el próximo latido lo vuelve a intentar.
      console.warn(`consultas: la entrada ${e.id} se posterga:`, fallo(err))
    }
  }
  return propuestas
}

const SISTEMA_PARA_LLEVAR = `Te paso las conversaciones que una persona tuvo con Bitácora, una app, antes
de su consulta con su terapeuta. Las líneas "Vos:" son de la persona; las
"Bitácora:" son de la app.

Devuelves \`para_llevar\`: las cosas que la persona eligió llevar a la consulta,
de una a tres, cada una en pocas palabras y en primera persona, como ella lo
diría ("lo que me pasó con mi hermana", "que no estoy durmiendo bien").

Sólo lo que ella dijo que quiere llevar, o aceptó cuando se lo ofrecieron. Nada
que haya propuesto Bitácora y ella no tomó. Sin interpretar ni nombrar cuadros.
Si no eligió nada, \`para_llevar\` vacío.`

const SCHEMA_PARA_LLEVAR = {
  type: 'object',
  additionalProperties: false,
  required: ['para_llevar'],
  properties: { para_llevar: { type: 'array', items: { type: 'string' } } },
} as const

const SISTEMA_EVALUACION = `Te paso lo que una persona habló con Bitácora, una app, la primera vez que
hablaron después de su consulta con su terapeuta y el día siguiente. Las líneas
"Vos:" son de la persona; las "Bitácora:" son de la app y no son material.

Con eso escribes el borrador de su evaluación de la sesión: una nota suya, para
ella. Cinco campos, en primera persona, con sus palabras y cortos:
- \`entendi\`: qué entendió en la sesión.
- \`aporte\`: qué le aportó o qué aprendió.
- \`sentir\`: cómo se sintió.
- \`temas\`: los temas que se trataron, de uno a cinco, en pocas palabras cada uno.
- \`avance\`: en qué siente que avanzó.

Sólo lo que dijo sobre ESA sesión. Lo que cuenta de su día —el trabajo, la
familia, algo que probó— no va, aunque suene a avance. Si de un campo no dijo
nada, va vacío ("" o []): un campo vacío lo completa ella; uno inventado lo
tiene que borrar. Nada de interpretar, de diagnosticar ni de nombrar cuadros.`

const SCHEMA_EVALUACION = {
  type: 'object',
  additionalProperties: false,
  required: ['entendi', 'aporte', 'sentir', 'temas', 'avance'],
  properties: {
    entendi: { type: 'string' },
    aporte: { type: 'string' },
    sentir: { type: 'string' },
    temas: { type: 'array', items: { type: 'string' } },
    avance: { type: 'string' },
  },
} as const

/// Lo que se le pasa al modelo: las charlas de una ventana, en orden.
async function charlasEntre(desde: string, hasta: string): Promise<string[]> {
  const { rows } = await pool.query<{ transcripcion: string }>(
    `select transcripcion from entradas
      where creado_local >= $1::timestamp and creado_local < $2::timestamp
      order by creado_local`,
    [desde, hasta],
  )
  return rows.map(r => r.transcripcion)
}

/// Un texto del modelo que nombra un cuadro que la persona no nombró se cae.
///
/// Si la palabra la dijo ella —«la psicóloga me dijo que es ansiedad»—, puede
/// quedar: es su evaluación. Si la puso el modelo, no: es exactamente lo que
/// esta app no hace.
function sinRotuloAjeno(texto: string, dicho: string): string {
  const r = rotuloClinico(texto)
  return r && !normalizar(dicho).includes(normalizar(r)) ? '' : texto
}

/// Escribe lo que eligió llevar y los borradores de las evaluaciones que estén
/// en su ventana y tengan charlas nuevas.
///
/// Las dos son derivadas, como los resúmenes: se reescriben cuando cambia
/// cuántas charlas hay en la ventana (`para_llevar_n`, `borrador_n`), y nunca
/// por las dudas. Con terapia una vez por semana son una o dos llamadas por
/// charla de esos días. Las dos ventanas se cierran solas —la de antes en la
/// consulta, la del borrador al terminar el día siguiente a la primera charla
/// de después—, y desde ahí no se tocan más.
export async function prepararConsultas(reloj: Reloj, llamada = llamar): Promise<{ para_llevar: number; borradores: number }> {
  const ahora = reloj.ahoraLocal
  const r = { para_llevar: 0, borradores: 0 }

  // ANTES: desde que empezó la ventana hasta un día después de la consulta,
  // para alcanzar a leer una charla que se subió tarde.
  const { rows: proximas } = await pool.query<{ id: number; desde: string; hasta: string; n: number; ya: number }>(
    `select v.id::int,
            to_char((v.dia - 1) + time '04:00', 'YYYY-MM-DD HH24:MI:SS') as desde,
            to_char(v.dia + coalesce(v.hora, time '12:00'), 'YYYY-MM-DD HH24:MI:SS') as hasta,
            v.para_llevar_n as ya,
            (select count(*)::int from entradas e
              where e.creado_local >= (v.dia - 1) + time '04:00'
                and e.creado_local < v.dia + coalesce(v.hora, time '12:00')) as n
       from eventos v
      where v.tipo = 'consulta' and v.estado = 'confirmado'
        and $1::timestamp >= (v.dia - 1) + time '04:00'
        and $1::timestamp < v.dia + coalesce(v.hora, time '12:00') + interval '1 day'`,
    [ahora],
  )
  for (const v of proximas) {
    if (v.n === 0 || v.n === v.ya) continue
    try {
      const textos = await charlasEntre(v.desde, v.hasta)
      const { datos } = await llamada<{ para_llevar: string[] }>({
        tarea: 'para_llevar',
        refId: v.id,
        sistema: SISTEMA_PARA_LLEVAR,
        usuario: textos.join('\n\n'),
        nombreSchema: 'para_llevar',
        schema: SCHEMA_PARA_LLEVAR as unknown as Record<string, unknown>,
      })
      const dicho = textos.map(soloVos).join('\n')
      const items = (datos.para_llevar ?? [])
        .map(t => sinRotuloAjeno((t ?? '').trim().slice(0, 120), dicho))
        .filter(Boolean)
        .slice(0, 3)
      await pool.query('update eventos set para_llevar = $2, para_llevar_n = $3 where id = $1',
                       [v.id, JSON.stringify(items), v.n])
      r.para_llevar++
    } catch (err) {
      if (err instanceof PresupuestoAgotado) throw err
      console.warn(`consultas: lo de llevar de la consulta ${v.id} se posterga:`, fallo(err))
    }
  }

  // DESPUÉS: mientras no esté evaluada, con las charlas del día de la primera
  // que hubo después de la consulta y las del día siguiente. Con toda la semana
  // —como era hasta el 03/10/2026— el borrador de una consulta terminó con un
  // almuerzo de dos días después y un plazo negociado cinco días después. Y
  // como la ventana se cierra, el borrador deja de reescribirse solo.
  const { rows: pasadas } = await pool.query<{ id: number; desde: string; hasta: string; n: number; ya: number }>(
    `with v as (
       select id, borrador_n, dia + coalesce(hora, time '12:00') as momento
         from eventos
        where tipo = 'consulta' and estado = 'confirmado' and evaluada_en is null
          and $1::timestamp >= dia + coalesce(hora, time '12:00')
          and $1::timestamp < dia + coalesce(hora, time '12:00') + interval '8 days'
     ), w as (
       select v.*, least(v.momento + interval '7 days',
                         (select (min(e.dia) + 2) + time '04:00' from entradas e
                           where e.creado_local >= v.momento
                             and e.creado_local < v.momento + interval '7 days')) as hasta
         from v
     )
     select w.id::int,
            to_char(w.momento, 'YYYY-MM-DD HH24:MI:SS') as desde,
            to_char(w.hasta, 'YYYY-MM-DD HH24:MI:SS') as hasta,
            w.borrador_n as ya,
            (select count(*)::int from entradas e
              where e.creado_local >= w.momento and e.creado_local < w.hasta) as n
       from w`,
    [ahora],
  )
  for (const v of pasadas) {
    if (v.n === 0 || v.n === v.ya) continue
    try {
      const textos = await charlasEntre(v.desde, v.hasta)
      const { datos } = await llamada<Borrador>({
        tarea: 'evaluacion',
        refId: v.id,
        sistema: SISTEMA_EVALUACION,
        usuario: textos.join('\n\n'),
        nombreSchema: 'evaluacion',
        schema: SCHEMA_EVALUACION as unknown as Record<string, unknown>,
      })
      const dicho = textos.map(soloVos).join('\n')
      const limpio = (t: unknown) => sinRotuloAjeno(String(t ?? '').trim().slice(0, 600), dicho)
      const b: Borrador = {
        entendi: limpio(datos.entendi),
        aporte: limpio(datos.aporte),
        sentir: limpio(datos.sentir),
        temas: (datos.temas ?? []).map(t => limpio(t).slice(0, 60)).filter(Boolean).slice(0, 5),
        avance: limpio(datos.avance),
      }
      const vacio = !b.entendi && !b.aporte && !b.sentir && !b.avance && b.temas.length === 0
      await pool.query('update eventos set borrador = $2, borrador_n = $3 where id = $1',
                       [v.id, vacio ? null : JSON.stringify(b), v.n])
      if (!vacio) r.borradores++
    } catch (err) {
      if (err instanceof PresupuestoAgotado) throw err
      console.warn(`consultas: el borrador de la consulta ${v.id} se posterga:`, fallo(err))
    }
  }

  return r
}
