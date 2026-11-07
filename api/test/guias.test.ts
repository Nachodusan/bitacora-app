import './_setup.ts'
import assert from 'node:assert/strict'
import { after, beforeEach, describe, test } from 'node:test'

const { guiar, bloqueDeGuia, bloqueDeNoche } = await import('../src/guias.ts')
const { pool, cerrarPool } = await import('../src/db.ts')

function vector(pos: number): string {
  const v = new Array<number>(1024).fill(0)
  v[pos] = 1
  return `[${v.join(',')}]`
}

const dep = (puntajes: number[]) => ({
  embeber: async (t: string[]) => t.map(() => vector(0).slice(1, -1).split(',').map(Number)),
  reordenar: async () => puntajes,
})

describe('la guía de los libros', () => {
  beforeEach(async () => { await pool.query('delete from guias') })
  after(async () => { await pool.query('delete from guias'); await cerrarPool() })

  test('sin libros cargados no llama a nadie', async () => {
    let llamadas = 0
    const r = await guiar('No puedo dejar de pensar en lo que pasó', {
      embeber: async () => { llamadas++; return [] }, reordenar: async () => [],
    })
    assert.deepEqual(r, [])
    assert.equal(llamadas, 0)
  })

  test('quedan los que pasan el piso, mejor puntaje primero', async () => {
    for (const [i, t] of ['rumiación', 'respiración', 'receta de cocina'].entries()) {
      await pool.query('insert into guias (libro, pagina, texto, embedding) values ($1, 1, $2, $3::vector)',
                       ['Libro', t, vector(i)])
    }
    // Postgres los devuelve por cercanía: el 0 primero, después los otros.
    const r = await guiar('No puedo dejar de pensar en lo que pasó', dep([0.6, 0.9, 0.44]))
    assert.equal(r.length, 2)
    assert.ok(!r.some(g => g.texto === 'receta de cocina'))
  })

  test('una falla no rompe el turno', async () => {
    await pool.query('insert into guias (libro, texto, embedding) values ($1, $2, $3::vector)',
                     ['Libro', 'algo', vector(0)])
    const r = await guiar('No puedo dejar de pensar en lo que pasó', {
      embeber: async () => { throw new Error('500') }, reordenar: async () => [],
    })
    assert.deepEqual(r, [])
  })

  test('sin guías no hay bloque', () => {
    assert.equal(bloqueDeGuia([]), null)
  })

  test('la noche va de 23 a 5', () => {
    assert.ok(bloqueDeNoche('2026-10-26 23:10:00'))
    assert.ok(bloqueDeNoche('2026-10-26 03:40:00'))
    assert.equal(bloqueDeNoche('2026-10-26 05:00:00'), null)
    assert.equal(bloqueDeNoche('2026-10-26 18:00:00'), null)
  })
})
