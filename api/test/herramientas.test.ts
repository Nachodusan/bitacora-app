import './_setup.ts'
import assert from 'node:assert/strict'
import { after, describe, test } from 'node:test'

const { emocionesSugeridas, EMOCIONES_DE_SIEMPRE } = await import('../src/herramientas.ts')
const { cerrarPool } = await import('../src/db.ts')

const vos = (texto: string) => ({ de: 'vos' as const, texto })
const devuelve = (emociones: string[]) => (async () => ({ datos: { emociones }, crudo: null })) as never

describe('las emociones de «Ponerle nombre»', () => {
  after(cerrarPool)

  test('se limpian, sin repetidas ni términos clínicos', async () => {
    const r = await emocionesSugeridas([vos('No sé qué me pasa, estoy raro desde lo de mi jefe')],
      devuelve(['Frustración', 'frustración', 'Depresión', 'vergüenza.', 'trastorno de ansiedad', 'cansancio', 'rabia']))
    assert.deepEqual(r, ['frustración', 'vergüenza', 'cansancio', 'rabia'])
  })

  test('si el modelo falla, van las de siempre', async () => {
    const r = await emocionesSugeridas([vos('No sé cómo me siento con todo esto')],
      (async () => { throw new Error('500') }) as never)
    assert.deepEqual(r, EMOCIONES_DE_SIEMPRE.slice(0, 6))
  })

  test('sin nada dicho no se llama al modelo', async () => {
    let llamadas = 0
    await emocionesSugeridas([], (async () => { llamadas++; return { datos: { emociones: [] }, crudo: null } }) as never)
    assert.equal(llamadas, 0)
  })
})
