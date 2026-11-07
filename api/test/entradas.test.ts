import './_setup.ts'
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { randomUUID } from 'node:crypto'
import type { FastifyInstance } from 'fastify'
import { construirServidor } from '../src/server.ts'
import { config } from '../src/config.ts'
import { pool, cerrarPool } from '../src/db.ts'

let app: FastifyInstance
const auth = { authorization: `Bearer ${config.authToken}` }

function cuerpo(extra: Record<string, unknown> = {}) {
  return {
    client_uuid: randomUUID(),
    creado_en: '2026-08-10T01:30:00-03:00',
    creado_local: '2026-08-10T01:30:00',
    fuente: 'dictado_ios',
    transcripcion: 'Vos: dormí como seis horas',
    duracion_seg: 4.2,
    ...extra,
  }
}

before(async () => {
  app = construirServidor()
  await app.ready()
})

after(async () => {
  await pool.query("delete from entradas where transcripcion like 'Vos: dormí como seis horas%'")
  await app.close()
  await cerrarPool()
})

describe('salud', () => {
  test('responde 200 con la base viva y no pide token', async () => {
    const r = await app.inject({ method: 'GET', url: '/health' })
    assert.equal(r.statusCode, 200)
    assert.deepEqual(r.json(), { ok: true, db: true })
  })
})

describe('de dónde viene', () => {
  /// Desde el 03/10/2026 también la app de Android.
  test('una charla dictada en Android se acepta', async () => {
    const r = await app.inject({ method: 'POST', url: '/entradas', headers: auth,
                                 payload: cuerpo({ fuente: 'dictado_android' }) })
    assert.equal(r.statusCode, 201)
  })
})

describe('auth', () => {
  test('sin token es 401', async () => {
    const r = await app.inject({ method: 'POST', url: '/entradas', payload: cuerpo() })
    assert.equal(r.statusCode, 401)
  })

  test('con token equivocado es 401', async () => {
    const r = await app.inject({
      method: 'POST', url: '/entradas',
      headers: { authorization: 'Bearer no-es-este' }, payload: cuerpo(),
    })
    assert.equal(r.statusCode, 401)
  })

  test('sin el esquema Bearer es 401', async () => {
    const r = await app.inject({
      method: 'POST', url: '/entradas',
      headers: { authorization: config.authToken }, payload: cuerpo(),
    })
    assert.equal(r.statusCode, 401)
  })
})

describe('POST /entradas', () => {
  test('crea y devuelve el día lógico con el corte de las 4am', async () => {
    const r = await app.inject({ method: 'POST', url: '/entradas', headers: auth, payload: cuerpo() })
    assert.equal(r.statusCode, 201)
    const { id, dia } = r.json()
    assert.ok(id > 0)
    // Habló a la 01:30 del 10: pertenece al 9. Lo calcula la columna generada,
    // no el servidor.
    assert.equal(dia.slice(0, 10), '2026-08-09')
  })

  test('el mismo client_uuid dos veces no duplica', async () => {
    const b = cuerpo()
    const a1 = await app.inject({ method: 'POST', url: '/entradas', headers: auth, payload: b })
    const a2 = await app.inject({ method: 'POST', url: '/entradas', headers: auth, payload: b })

    assert.equal(a1.statusCode, 201, 'la primera crea')
    assert.equal(a2.statusCode, 200, 'la segunda reconoce que ya existía')
    assert.equal(a1.json().id, a2.json().id, 'y devuelve el mismo id')

    const { rows } = await pool.query(
      'select count(*)::int as n from entradas where client_uuid = $1', [b.client_uuid])
    assert.equal(rows[0].n, 1)
  })

  /// La conversación del día se manda varias veces a medida que crece.
  test('la misma charla, más larga, se actualiza', async () => {
    const b = cuerpo()
    const a1 = await app.inject({ method: 'POST', url: '/entradas', headers: auth, payload: b })
    const largo = { ...b, transcripcion: b.transcripcion + '\nBitácora: ¿Y cómo te levantaste?\nVos: cansado', duracion_seg: 90 }
    const a2 = await app.inject({ method: 'POST', url: '/entradas', headers: auth, payload: largo })
    assert.equal(a2.statusCode, 200)
    assert.equal(a1.json().id, a2.json().id)
    const { rows } = await pool.query<{ transcripcion: string; duracion_seg: number }>(
      'select transcripcion, duracion_seg::float as duracion_seg from entradas where client_uuid = $1', [b.client_uuid])
    assert.ok(rows[0]!.transcripcion.endsWith('Vos: cansado'))
    assert.equal(rows[0]!.duracion_seg, 90)
  })

  test('una versión más corta que llega tarde no pisa la larga', async () => {
    const b = cuerpo({ transcripcion: 'Vos: dormí como seis horas, y me desperté dos veces' })
    await app.inject({ method: 'POST', url: '/entradas', headers: auth, payload: b })
    await app.inject({ method: 'POST', url: '/entradas', headers: auth, payload: { ...b, transcripcion: 'Vos: dormí como seis horas' } })
    const { rows } = await pool.query<{ transcripcion: string }>(
      'select transcripcion from entradas where client_uuid = $1', [b.client_uuid])
    assert.ok(rows[0]!.transcripcion.endsWith('dos veces'))
  })

  test('con la nota ya escrita (el día cerrado) no se toca', async () => {
    const b = cuerpo()
    await app.inject({ method: 'POST', url: '/entradas', headers: auth, payload: b })
    await pool.query('update entradas set nota_revisada_en = now() where client_uuid = $1', [b.client_uuid])
    const r = await app.inject({ method: 'POST', url: '/entradas', headers: auth,
      payload: { ...b, transcripcion: b.transcripcion + '\nVos: algo más' } })
    assert.equal(r.statusCode, 200)
    const { rows } = await pool.query<{ transcripcion: string }>(
      'select transcripcion from entradas where client_uuid = $1', [b.client_uuid])
    assert.equal(rows[0]!.transcripcion, b.transcripcion)
  })

  /// El guard más importante del endpoint: creado_local es hora de pared. Con
  /// zona, Postgres la interpretaría y el corte de las 4am se calcularía sobre
  /// la hora equivocada.
  test('rechaza creado_local con zona horaria', async () => {
    for (const malo of ['2026-08-10T01:30:00Z', '2026-08-10T01:30:00-03:00', '2026-08-10 01:30:00']) {
      const r = await app.inject({
        method: 'POST', url: '/entradas', headers: auth,
        payload: cuerpo({ creado_local: malo }),
      })
      assert.equal(r.statusCode, 400, `debería rebotar: ${malo}`)
    }
  })

  test('rechaza transcripción vacía y fuente inventada', async () => {
    const vacia = await app.inject({
      method: 'POST', url: '/entradas', headers: auth, payload: cuerpo({ transcripcion: '' }),
    })
    assert.equal(vacia.statusCode, 400)

    const fuente = await app.inject({
      method: 'POST', url: '/entradas', headers: auth, payload: cuerpo({ fuente: 'telepatia' }),
    })
    assert.equal(fuente.statusCode, 400)
  })

  test('rechaza campos de más', async () => {
    const r = await app.inject({
      method: 'POST', url: '/entradas', headers: auth, payload: cuerpo({ animo: 5 }),
    })
    assert.equal(r.statusCode, 400)
  })
})
