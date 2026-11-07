import { pool } from './db.ts'
import { fichaEncendida, hablaDe } from './ficha.ts'
import type { Herramienta } from './llm.ts'
import { patrones } from './patrones.ts'

/// LA FICHA DURANTE LA CHARLA (etapa 2, 28/10/2026). Al empezar, Bitácora
/// recibe un resumen fijo de la ficha, con tope. Con estas dos herramientas
/// puede ir a buscar algo puntual cuando hace falta: «¿qué me pasaba con el
/// sueño en septiembre?», o un tema que no entró en el resumen.
///
/// Devuelven lo mismo que ya ve en otras partes —datos de la ficha con las
/// frases de la persona, y resúmenes de días—, nunca transcripciones enteras
/// (regla 2 de la memoria).

/// Un tema de la ficha: el dato, cuántas veces, sus frases con fecha, cómo fue
/// cambiando y con qué se conecta.
export async function recordarTema(tema: string): Promise<string> {
  if (!(await fichaEncendida())) return 'No hay ficha para esta persona todavía.'
  const { rows } = await pool.query<{ id: number; tipo: string; nombre: string; descripcion: string | null;
                                      apodos: string[]; veces: number; primera: string; ultima: string }>(
    `select id::int, tipo, nombre, descripcion, apodos, veces, primera::text, ultima::text
       from ficha_nodos where borrado_en is null`)
  const hallados = rows
    .filter(n => hablaDe(tema, [n.nombre, ...n.apodos, n.descripcion ?? ''].join(' ')))
    .sort((a, b) => b.veces - a.veces)
    .slice(0, 3)
  if (hallados.length === 0) return `No hay nada en la ficha sobre «${tema}».`

  const partes: string[] = []
  const ps = await patrones().catch(() => [])
  for (const n of hallados) {
    const { rows: citas } = await pool.query<{ dia: string; cita: string }>(
      'select dia::text, cita from ficha_evidencias where nodo_id = $1 order by dia desc, id desc limit 5', [n.id])
    const { rows: prog } = await pool.query<{ dia: string; diferencia: string; como_estaba: string }>(
      'select dia::text, diferencia, como_estaba from ficha_progreso where nodo_id = $1 order by dia, id', [n.id])
    const { rows: con } = await pool.query<{ texto: string }>(
      `select case when c.desde = $1 then c.relacion || ' → ' || h.nombre else d.nombre || ' → ' || c.relacion || ' → esto' end as texto
         from ficha_conexiones c join ficha_nodos d on d.id = c.desde join ficha_nodos h on h.id = c.hacia
        where (c.desde = $1 or c.hacia = $1) and d.borrado_en is null and h.borrado_en is null
        order by c.veces desc limit 6`, [n.id])
    partes.push([
      `${n.nombre} (${n.tipo}; ${n.veces === 1 ? 'una vez' : `${n.veces} veces`}, del ${n.primera} al ${n.ultima})` +
        (n.descripcion ? `: ${n.descripcion}` : ''),
      ...citas.map(c => `  ${c.dia}: «${c.cita}»`),
      ...prog.map(p => `  cómo iba el ${p.dia} (${p.diferencia}): ${p.como_estaba}`),
      ...con.map(c => `  se conecta: ${c.texto}`),
      ...ps.filter(p => p.nombre === n.nombre || p.texto.includes(`«${n.nombre}»`))
        .map(p => `  en el tiempo (puede ser casualidad): ${p.texto}`),
    ].join('\n'))
  }
  return partes.join('\n\n')
}

/// Lo que pasó entre dos días: el resumen de cada día y de cada charla. Hasta
/// un mes por vez.
export async function recordarDias(desde: string, hasta: string): Promise<string> {
  const DIA = /^\d{4}-\d{2}-\d{2}$/
  if (!DIA.test(desde) || !DIA.test(hasta)) return 'Las fechas van como AAAA-MM-DD.'
  if (Date.parse(hasta) - Date.parse(desde) > 31 * 864e5) {
    hasta = new Date(Date.parse(desde) + 31 * 864e5).toISOString().slice(0, 10)
  }
  const { rows } = await pool.query<{ dia: string; texto: string }>(
    `select dia::text, resumen as texto from resumenes_dia where dia between $1 and $2 and resumen is not null
     union all
     select dia::text, to_char(creado_local, 'HH24:MI') || ' · ' || resumen from entradas
      where dia between $1 and $2 and resumen is not null and resumen <> ''
     order by 1, 2 limit 60`, [desde, hasta])
  if (rows.length === 0) return `No hay nada guardado entre el ${desde} y el ${hasta}.`
  return rows.map(r => `${r.dia}: ${r.texto}`).join('\n')
}

/// Las dos, como las ve el modelo.
export const HERRAMIENTAS_DE_MEMORIA: Herramienta[] = [
  {
    nombre: 'recordar_tema',
    descripcion: 'Busca en lo que la persona te fue contando en otras charlas un tema (dormir, su jefe, ' +
      'sus papás, el trabajo…): cuántas veces lo habló, sus frases con fecha, cómo fue cambiando y con qué se conecta.',
    parametros: { type: 'object', properties: { tema: { type: 'string', description: 'El tema, en pocas palabras' } },
                  required: ['tema'] },
    ejecutar: (a) => recordarTema(String(a.tema ?? '')),
  },
  {
    nombre: 'recordar_dias',
    descripcion: 'Lo que pasó entre dos fechas: el resumen de cada día y de cada charla. Hasta un mes.',
    parametros: { type: 'object', properties: {
      desde: { type: 'string', description: 'AAAA-MM-DD' }, hasta: { type: 'string', description: 'AAAA-MM-DD' } },
                  required: ['desde', 'hasta'] },
    ejecutar: (a) => recordarDias(String(a.desde ?? ''), String(a.hasta ?? '')),
  },
]

/// Lo que se le dice al modelo sobre las herramientas.
export const BLOQUE_DE_MEMORIA = `--- Para recordar más ---
Tienes dos herramientas: recordar_tema y recordar_dias. Úsalas cuando la persona
te pregunte por algo de antes («¿te acuerdas…?», «¿qué me pasaba en
septiembre?») o cuando necesites un dato puntual que no está arriba. No las
uses en cada turno. No anuncies que vas a buscar ni digas «déjame ver» ni
menciones una ficha: contesta directo, con lo que encontraste, como quien se
acuerda. Si no encuentras nada, dilo con naturalidad.`
