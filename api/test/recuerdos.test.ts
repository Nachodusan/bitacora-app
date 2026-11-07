import './_setup.ts'
import assert from 'node:assert/strict'
import { after, beforeEach, describe, test } from 'node:test'

import type { Turno } from '../src/charla.ts'

const { recordar, embeberPendientes } = await import('../src/recuerdos.ts')
const { resumirDia } = await import('../src/resumen.ts')
const { siguienteTurno } = await import('../src/charla.ts')
const { registrar } = await import('../src/llm.ts')
const { pool, cerrarPool } = await import('../src/db.ts')

// Lejos de todo: los otros tests viven en 2027 y los datos reales, después de
// 2026. Acá "hoy" es el último día de 2001.
const HOY = '2001-12-31'
const FRASE = 'Volví a discutir con mi hermana por lo de la casa.'

/// Un vector de 1024 con un solo uno. Dos con el uno en el mismo lugar son
/// idénticos; en lugares distintos, lo más lejos que se puede estar.
function vector(pos: number): number[] {
  const v = new Array<number>(1024).fill(0)
  v[pos] = 1
  return v
}

async function resumen(dia: string, texto: string, pos: number | null) {
  await pool.query(
    `insert into resumenes_dia (dia, resumen, n_entradas, embedding)
     values ($1, $2, 1, $3::vector)`,
    [dia, texto, pos === null ? null : `[${vector(pos).join(',')}]`])
}

/// Las dos llamadas, falsas y contadas.
function dobles(puntajes: (docs: string[]) => number[]) {
  const visto = { embeber: 0, reordenar: 0, consulta: '', documentos: [] as string[] }
  return {
    visto,
    dep: {
      embeber: async (textos: string[]) => { visto.embeber++; return textos.map(() => vector(0)) },
      reordenar: async (consulta: string, documentos: string[]) => {
        visto.reordenar++
        visto.consulta = consulta
        visto.documentos = documentos
        return puntajes(documentos)
      },
    },
  }
}

const limpiar = () => pool.query(`delete from resumenes_dia where dia between '2001-01-01' and '2001-12-31'`)

beforeEach(limpiar)
after(async () => { await limpiar(); await cerrarPool() })

describe('la memoria larga no gasta cuando no hay de qué acordarse', () => {
  test('sin resúmenes más viejos, no se llama a nadie', async () => {
    const d = dobles(() => [])
    assert.deepEqual(await recordar(HOY, FRASE, [], d.dep), [])
    assert.equal(d.visto.embeber, 0)
    assert.equal(d.visto.reordenar, 0)
  })

  test('un resumen sin vector todavía no cuenta', async () => {
    await resumen('2001-03-01', 'Discutiste con tu hermana.', null)
    const d = dobles(() => [1])
    assert.deepEqual(await recordar(HOY, FRASE, [], d.dep), [])
    assert.equal(d.visto.embeber, 0)
  })

  test('un "sí" no busca nada', async () => {
    await resumen('2001-03-01', 'Discutiste con tu hermana.', 0)
    const d = dobles(() => [1])
    assert.deepEqual(await recordar(HOY, 'sí, eso', [], d.dep), [])
    assert.equal(d.visto.embeber, 0)
  })
})

describe('qué recuerdos llegan', () => {
  test('sólo los que pasan el piso, y ordenados por fecha', async () => {
    await resumen('2001-05-10', 'Discutiste con tu hermana por la casa.', 0)
    await resumen('2001-02-03', 'Tu hermana te llamó y terminaron mal.', 0)
    await resumen('2001-04-01', 'Fuiste a nadar y dormiste bien.', 5)

    const d = dobles(docs => docs.map(t => t.includes('hermana') ? 0.8 : 0.01))
    const r = await recordar(HOY, FRASE, [], d.dep)

    assert.deepEqual(r.map(x => x.dia), ['2001-02-03', '2001-05-10'])
    assert.equal(d.visto.consulta, FRASE)
    assert.equal(d.visto.documentos.length, 3, 'el reordenador ve los candidatos, no la tabla cruda')
  })

  test('como mucho cinco, y son los de mejor puntaje', async () => {
    for (let i = 1; i <= 8; i++) await resumen(`2001-06-0${i}`, `Recuerdo número ${'x'.repeat(i)}.`, 0)
    // El puntaje sube con el largo: los cinco últimos días son los mejores.
    const d = dobles(docs => docs.map(t => 0.3 + t.length / 1000))
    const r = await recordar(HOY, FRASE, [], d.dep)
    assert.deepEqual(r.map(x => x.dia),
      ['2001-06-04', '2001-06-05', '2001-06-06', '2001-06-07', '2001-06-08'])
  })

  test('no repite los días que Bitácora ya tiene, ni mira de hoy para adelante', async () => {
    await resumen('2001-12-30', 'Ayer: discutiste con tu hermana.', 0)
    await resumen('2001-12-31', 'HOY no terminó.', 0)
    await resumen('2001-07-07', 'Hace meses discutiste con tu hermana.', 0)

    const d = dobles(docs => docs.map(() => 0.9))
    const r = await recordar(HOY, FRASE, ['2001-12-30'], d.dep)
    assert.deepEqual(r.map(x => x.dia), ['2001-07-07'])
  })

  test('si el reordenador se cae, el turno sale sin recuerdos y no revienta', async () => {
    await resumen('2001-05-10', 'Discutiste con tu hermana.', 0)
    const r = await recordar(HOY, FRASE, [], {
      embeber: async t => t.map(() => vector(0)),
      reordenar: async () => { throw new Error('Rerank 503') },
    })
    assert.deepEqual(r, [])
  })
})

describe('el índice sigue al resumen', () => {
  test('el latido vectoriza los que faltan, y sólo ésos', async () => {
    await resumen('2001-08-01', 'Dormiste mal.', null)
    await resumen('2001-08-02', 'Ya tenía vector.', 3)

    let pedidos: string[] = []
    const n = await embeberPendientes(async textos => {
      pedidos = pedidos.concat(textos)
      return textos.map(() => vector(7))
    })

    // Puede haber pendientes de otros tests corriendo a la vez: se mira el propio.
    assert.ok(n >= 1)
    assert.ok(pedidos.includes('Dormiste mal.'))
    assert.ok(!pedidos.includes('Ya tenía vector.'))
    const { rows } = await pool.query<{ ok: boolean }>(
      `select embedding is not null as ok from resumenes_dia where dia = '2001-08-01'`)
    assert.equal(rows[0]!.ok, true)
  })

  test('reescribir un resumen le borra el vector viejo', async () => {
    const { rows: [e] } = await pool.query<{ id: number }>(
      `insert into entradas (client_uuid, creado_en, creado_local, fuente, transcripcion)
       values (gen_random_uuid(), now(), '2001-09-09T21:00:00', 'dictado_ios', 'Vos: [test recuerdos] hoy fue largo.')
       returning id::int`)
    try {
      await resumen('2001-09-09', 'El resumen de antes.', 2)
      await resumirDia('2001-09-09', (async () => ({ datos: { resumen: 'El resumen nuevo.' }, crudo: {} })) as never)
      const { rows } = await pool.query<{ resumen: string; sin: boolean }>(
        `select resumen, embedding is null as sin from resumenes_dia where dia = '2001-09-09'`)
      assert.equal(rows[0]!.resumen, 'El resumen nuevo.')
      assert.equal(rows[0]!.sin, true, 'el vector era del texto anterior')
    } finally {
      await pool.query('delete from entradas where id = $1', [e!.id])
    }
  })
})

describe('cómo le llega a Bitácora', () => {
  const vos = (t: string): Turno => ({ de: 'vos', texto: t })
  const bitacora = (t: string): Turno => ({ de: 'bitacora', texto: t })

  function espia() {
    const visto: string[] = []
    const fn = (async (p: { sistema: string }) => { visto.push(p.sistema); return { datos: 'ok', crudo: {} } }) as never
    return { fn, visto }
  }

  test('lo de más atrás va en su propio bloque, con la fecha', async () => {
    const a = espia()
    let buscado = ''
    await siguienteTurno({ turnos: [vos(FRASE)], dia: '2027-06-15' }, a.fn,
      async (_dia, texto) => { buscado = texto; return [{ dia: '2027-01-20', resumen: 'Discutiste con tu hermana por la casa.' }] })

    assert.equal(buscado, FRASE, 'se busca con lo último que dijo')
    assert.match(a.visto[0]!, /De más atrás/)
    assert.match(a.visto[0]!, /2027-01-20: Discutiste con tu hermana por la casa\./)
  })

  test('sin recuerdos, el bloque no aparece', async () => {
    const a = espia()
    await siguienteTurno({ turnos: [vos(FRASE)], dia: '2027-06-15' }, a.fn, async () => [])
    assert.doesNotMatch(a.visto[0]!, /De más atrás/)
  })

  test('si lo último lo dijo Bitácora, no hay con qué buscar', async () => {
    const a = espia()
    let llamadas = 0
    await siguienteTurno({ turnos: [vos('hola'), bitacora('¿Cómo andás?')], dia: '2027-06-15' }, a.fn,
      async () => { llamadas++; return [] })
    assert.equal(llamadas, 0)
  })
})

describe('el registro', () => {
  /// Sin esto el insert rebota contra el CHECK, se traga con un console.error,
  /// y el guard de presupuesto no ve estas llamadas nunca.
  test('la base acepta las dos tareas nuevas', async () => {
    // Nombre propio: `tick.test.ts` borra las filas de 'modelo-de-prueba' y corre a la vez.
    await pool.query(`delete from llm_llamadas where modelo = 'prueba-de-recuerdos'`)
    for (const tarea of ['embedding', 'rerank'] as const) {
      await pool.query(
        `insert into llm_llamadas (tarea, modelo, tokens_in, costo_usd, latencia_ms, ok)
         values ($1, 'prueba-de-recuerdos', 10, 0, 1, true)`, [tarea])
    }
    await registrar({ tarea: 'rerank', modelo: 'prueba-de-recuerdos', refId: null,
                      tokensIn: 5, tokensOut: null, costoUsd: 0.000001, latenciaMs: 3, ok: true })
    const { rows } = await pool.query<{ n: number }>(
      `select count(*)::int as n from llm_llamadas
        where modelo = 'prueba-de-recuerdos' and tarea in ('embedding', 'rerank')`)
    assert.ok(rows[0]!.n >= 3)
  })
})
