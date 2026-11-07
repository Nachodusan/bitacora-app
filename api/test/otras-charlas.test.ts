import { test } from 'node:test'
import assert from 'node:assert/strict'
import { bloqueDeOtrasCharlas } from '../src/charla.ts'

// La charla del 27/10 a las 3 a. m.: Bitácora no sabía de la de hacía un rato.
test('las charlas de hoy llegan con su resumen', () => {
  const b = bloqueDeOtrasCharlas([{ hora: '03:14', resumen: 'Contaste que te sientes sin propósito.' }])!
  assert.match(b, /Lo que ya hablaron hoy/)
  assert.match(b, /03:14: Contaste que te sientes sin propósito\./)
  assert.doesNotMatch(b, /Conversaciones/)
})

test('una charla de hoy sin resumen todavía: sabe que existe y cómo volver', () => {
  const b = bloqueDeOtrasCharlas([{ hora: '03:14', resumen: null }])!
  assert.match(b, /Conversaciones/)
})

test('retomar una charla de otro día dice de qué día son los primeros turnos', () => {
  const b = bloqueDeOtrasCharlas([], '2026-10-25')!
  assert.match(b, /retoma una anterior/)
  assert.match(b, /domingo 25 de octubre/)
  assert.doesNotMatch(b, /Otras charlas de hoy/)
})

test('sin otras charlas no hay bloque', () => {
  assert.equal(bloqueDeOtrasCharlas([]), null)
})

test('lo del registro entra a la charla, y en la primera se pregunta qué la trajo', async () => {
  const { bloqueDeQuienEs, edadEl } = await import('../src/charla.ts')
  assert.deepEqual(edadEl('1997-03-14', '2026-03-13'), { anios: 28, cumple: false })
  assert.deepEqual(edadEl('1997-03-14', '2026-03-14'), { anios: 29, cumple: true })
  const b = bloqueDeQuienEs({ fecha_nacimiento: '1997-03-14', pais: 'Chile', ciudad: 'Santiago', con_quien: 'Familia' },
                            true, '2026-10-28')!
  assert.match(b, /tiene 29 años; vive en Santiago, Chile; vive con: Familia/)
  assert.doesNotMatch(b, /cumpleaños/)
  assert.match(b, /qué te trajo/)
  assert.equal(bloqueDeQuienEs({ fecha_nacimiento: null, pais: null, ciudad: null, con_quien: null }, false, '2026-10-28'), null)
})
