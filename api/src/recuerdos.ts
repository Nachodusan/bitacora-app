import { pool } from './db.ts'
import { config } from './config.ts'
import { registrar, verificarPresupuesto, PresupuestoAgotado } from './llm.ts'

/// La memoria larga de Bitácora.
///
/// `memoria()` en `resumen.ts` le da los últimos siete días, siempre. Esto le
/// agrega lo que quedó más atrás, pero sólo cuando viene al caso: si hoy volvés
/// a nombrar algo de hace tres meses, el resumen de aquel día aparece en el
/// prompt; si no, no.
///
/// SE BUSCA SOBRE LOS RESÚMENES, NO SOBRE LO QUE DIJISTE. Es la regla de que
/// Bitácora no ve la historia cruda, sin tocar: lo que cambia es cuántos resúmenes
/// puede llegar a ver, no qué clase de cosa ve.
///
/// TRES PASOS, y los dos primeros existen para que el tercero reciba poco:
///
///   1. Lo que acabás de decir se convierte en un vector (embedding).
///   2. Postgres devuelve los veinte resúmenes cuyo vector más se le parece.
///      Es rápido y grueso: "parecido" acá es tema, no pertinencia.
///   3. Un segundo modelo (el reordenador) lee cada uno de esos veinte contra tu
///      frase y les pone un puntaje. Quedan los cinco mejores, y sólo si pasan
///      un piso: un recuerdo que no viene al caso es peor que ninguno, porque
///      Bitácora lo va a usar.
///
/// NADA DE ESTO PUEDE ROMPER UN TURNO. Pasa antes de que Bitácora empiece a
/// contestar, así que tiene un timeout corto, y cualquier falla —sin clave, sin
/// red, sin presupuesto, un 500— devuelve una lista vacía. Bitácora contesta igual,
/// con los últimos siete días, que es como andaba antes de que esto existiera.

const DEEPINFRA = 'https://api.deepinfra.com/v1'

/// Cuántos trae Postgres para que el reordenador elija.
const CANDIDATOS = 20
/// Cuántos llegan al prompt como mucho.
const MAXIMO = 5
/// Abajo de esto el reordenador está diciendo que no tiene que ver. El puntaje
/// va de 0 a 1 y se va a los extremos. Medido contra el modelo con ocho
/// resúmenes y cuatro frases: lo que venía al caso dio 0,99, 0,72, 0,40 y 0,26;
/// lo que no, nunca más de 0,03. El piso va en el hueco, más cerca de abajo:
/// con 0,3 se perdía el de 0,26, que era justo el que había que traer.
const PISO = 0.1
/// Un "sí" o un "ajá" no tienen de qué acordarse, y buscar igual cuesta dos
/// llamadas y unos cientos de milisegundos de silencio.
const MIN_CONSULTA = 12
/// Cuántos resúmenes se vectorizan por latido. Sobra: se genera uno por día.
const POR_TANDA = 50

export interface Recuerdo {
  dia: string
  resumen: string
}

/// Las dos llamadas, inyectables para testear sin clave, sin red y sin gastar —
/// el mismo patrón que `llamar` en `llm.ts`.
export type Embeber = (textos: string[]) => Promise<number[][]>
export type Reordenar = (consulta: string, documentos: string[]) => Promise<number[]>

/// Si hay con qué. Sin la clave, la memoria larga está apagada y no es un error.
export function memoriaLargaActiva(): boolean {
  return config.deepinfraApiKey !== null
}

/// Convierte textos en vectores.
///
/// En el mensaje de error va SÓLO el status, igual que en la voz: el cuerpo de
/// un error del proveedor puede devolver el texto que rebotó, y ese mensaje
/// termina en un log en disco.
export async function embeber(
  textos: string[],
  timeoutMs = config.memoriaTimeoutMs,
): Promise<number[][]> {
  await verificarPresupuesto()

  const arranque = Date.now()
  let tokens: number | null = null
  let ok = false
  try {
    const r = await fetch(`${DEEPINFRA}/openai/embeddings`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${config.deepinfraApiKey}`,
        'content-type': 'application/json',
      },
      signal: AbortSignal.timeout(timeoutMs),
      body: JSON.stringify({
        model: config.modeloDeEmbedding,
        input: textos,
        encoding_format: 'float',
      }),
    })
    if (!r.ok) {
      await r.text().catch(() => '')
      throw new Error(`Embedding ${r.status}`)
    }
    const cuerpo = await r.json() as {
      data?: { embedding?: number[] }[]
      usage?: { prompt_tokens?: number }
    }
    tokens = cuerpo.usage?.prompt_tokens ?? null
    const vectores = (cuerpo.data ?? []).map(d => d.embedding ?? [])
    if (vectores.length !== textos.length || vectores.some(v => v.length === 0)) {
      throw new Error('El embedding volvió incompleto')
    }
    ok = true
    return vectores
  } finally {
    await registrar({
      tarea: 'embedding',
      modelo: config.modeloDeEmbedding,
      refId: null,
      tokensIn: tokens,
      tokensOut: null,
      costoUsd: (tokens ?? 0) / 1_000_000 * config.precioEmbeddingPorMTok,
      latenciaMs: Date.now() - arranque,
      ok,
    })
  }
}

/// Le pone un puntaje de 0 a 1 a cada documento contra la consulta.
///
/// No es la API de OpenAI: es el endpoint propio de DeepInfra, con `queries` y
/// `documents`. Devuelve un puntaje por documento, en el mismo orden.
export async function reordenar(
  consulta: string,
  documentos: string[],
  timeoutMs = config.memoriaTimeoutMs,
): Promise<number[]> {
  await verificarPresupuesto()

  const arranque = Date.now()
  let tokens: number | null = null
  let costo: number | null = null
  let ok = false
  try {
    const r = await fetch(`${DEEPINFRA}/inference/${config.modeloDeRerank}`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${config.deepinfraApiKey}`,
        'content-type': 'application/json',
      },
      signal: AbortSignal.timeout(timeoutMs),
      body: JSON.stringify({ queries: [consulta], documents: documentos }),
    })
    if (!r.ok) {
      await r.text().catch(() => '')
      throw new Error(`Rerank ${r.status}`)
    }
    const cuerpo = await r.json() as {
      scores?: number[]
      input_tokens?: number
      inference_status?: { cost?: number }
    }
    tokens = cuerpo.input_tokens ?? null
    costo = cuerpo.inference_status?.cost ?? null
    const puntajes = cuerpo.scores ?? []
    if (puntajes.length !== documentos.length) throw new Error('El reordenado volvió incompleto')
    ok = true
    return puntajes
  } finally {
    await registrar({
      tarea: 'rerank',
      modelo: config.modeloDeRerank,
      refId: null,
      tokensIn: tokens,
      tokensOut: null,
      // El proveedor informa lo que cobró; si no, se estima por tokens.
      costoUsd: costo ?? (tokens ?? 0) / 1_000_000 * config.precioRerankPorMTok,
      latenciaMs: Date.now() - arranque,
      ok,
    })
  }
}

/// Postgres no tiene un tipo de parámetro para vectores: van como texto.
function aVector(v: number[]): string {
  return `[${v.join(',')}]`
}

/// Lo que viene al caso de más atrás que la última semana.
///
/// `yaVistos` son los días que Bitácora ya tiene en el prompt por `memoria()`: no
/// se buscan, para no decirle dos veces lo mismo.
///
/// Devuelve los recuerdos ordenados por fecha, no por puntaje: en el prompt se
/// leen como una historia, y el puntaje ya hizo su trabajo al elegirlos.
export async function recordar(
  dia: string,
  loQueDijo: string,
  yaVistos: string[],
  dep: { embeber: Embeber; reordenar: Reordenar } | null = null,
): Promise<Recuerdo[]> {
  // Con las llamadas inyectadas no hace falta la clave: es un test.
  if (!dep && !memoriaLargaActiva()) return []
  const emb = dep?.embeber ?? embeber
  const reo = dep?.reordenar ?? reordenar

  const consulta = loQueDijo.trim()
  if (consulta.length < MIN_CONSULTA) return []

  try {
    // Antes de gastar nada: ¿hay algo más viejo donde buscar? En las primeras
    // semanas de uso no lo hay, y el turno sigue sin haber llamado a nadie.
    const hay = await pool.query(
      `select 1 from resumenes_dia
        where dia < $1 and not (dia = any($2::date[]))
          and resumen is not null and embedding is not null
        limit 1`,
      [dia, yaVistos],
    )
    if (hay.rowCount === 0) return []

    const [vector] = await emb([consulta])
    const { rows } = await pool.query<Recuerdo>(
      `select dia::text, resumen from resumenes_dia
        where dia < $1 and not (dia = any($2::date[]))
          and resumen is not null and embedding is not null
        order by embedding <=> $3::vector
        limit $4`,
      [dia, yaVistos, aVector(vector!), CANDIDATOS],
    )
    if (rows.length === 0) return []

    const puntajes = await reo(consulta, rows.map(r => r.resumen))
    return rows
      .map((r, i) => ({ r, puntaje: puntajes[i] ?? 0 }))
      .filter(x => x.puntaje >= PISO)
      .sort((a, b) => b.puntaje - a.puntaje)
      .slice(0, MAXIMO)
      .map(x => x.r)
      .sort((a, b) => a.dia.localeCompare(b.dia))
  } catch (e) {
    // Sin recuerdos viejos el turno sale igual. Sólo el mensaje, nunca el texto.
    console.warn('recordar: este turno sale sin memoria larga:',
                 (e instanceof Error ? e.message : String(e)).slice(0, 120))
    return []
  }
}

/// Vectoriza los resúmenes que todavía no tienen vector. Lo corre el latido.
///
/// Es un estado derivado de los datos, como todo lo del latido: un resumen con
/// texto y sin vector es uno pendiente, y si esta tanda falla el próximo latido
/// lo vuelve a encontrar. No hay marca que alguien tenga que acordarse de poner.
///
/// El techo del mes se deja pasar para arriba: el latido sabe qué hacer con él.
///
/// Con el timeout largo del texto y no el corto de la memoria: acá no hay nadie
/// esperando, y una tanda grande no entra en un segundo y medio.
export async function embeberPendientes(
  emb: Embeber = t => embeber(t, config.llmTimeoutMs),
): Promise<number> {
  const { rows } = await pool.query<Recuerdo>(
    `select dia::text, resumen from resumenes_dia
      where resumen is not null and embedding is null
      order by dia limit $1`,
    [POR_TANDA],
  )
  if (rows.length === 0) return 0

  let vectores: number[][]
  try {
    vectores = await emb(rows.map(r => r.resumen))
  } catch (e) {
    if (e instanceof PresupuestoAgotado) throw e
    console.warn('embeberPendientes: se posterga:',
                 (e instanceof Error ? e.message : String(e)).slice(0, 120))
    return 0
  }

  for (const [i, r] of rows.entries()) {
    // Con el texto en la condición: si el resumen se reescribió mientras se
    // calculaba, este vector ya es de otro texto y no se guarda.
    await pool.query(
      `update resumenes_dia set embedding = $1::vector where dia = $2 and resumen = $3`,
      [aVector(vectores[i]!), r.dia, r.resumen],
    )
  }
  return rows.length
}
