import './_setup.ts'
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import type { FastifyInstance } from 'fastify'

import type { Turno } from '../src/charla.ts'

const { haySenal, haySenalEnLaCharla, normalizar, SENALES_DIRECTAS, SENALES_DE_DESESPERANZA,
        MENSAJE_DE_RIESGO } = await import('../src/riesgo.ts')
const { turnoEnVivo } = await import('../src/vivo.ts')
const { paraDecir } = await import('../src/voz.ts')
const { construirServidor } = await import('../src/server.ts')
const { config } = await import('../src/config.ts')
const { pool, cerrarPool } = await import('../src/db.ts')

const HOY = '2027-06-15'
const vos = (t: string): Turno => ({ de: 'vos', texto: t })
const bitacora = (t: string): Turno => ({ de: 'bitacora', texto: t })

/// Un modelo que no se puede llamar: si el corte funciona, nadie lo toca.
const prohibido = (async () => { throw new Error('el modelo no se tenía que llamar') }) as never

let app: FastifyInstance
const auth = { authorization: `Bearer ${config.authToken}` }
before(async () => { app = construirServidor(); await app.ready() })
after(async () => {
  await pool.query(`delete from entradas where transcripcion like '%[test rótulo viejo]%'`)
  await app.close()
  await cerrarPool()
})


describe('qué dispara', () => {
  /// Pedido del 02/10.
  test('las frases nuevas', () => {
    for (const f of ['Me quiero matar.', 'Quiero desaparecer'])
      assert.ok(haySenal(f), f)
  })

  /// Estuvieron en la lista y se sacaron: se dicen como exageración, y cortar
  /// la charla por eso es lo mismo que cortarla por «recortarme el pelo».
  test('las exageraciones de todos los días no cortan', () => {
    for (const f of ['me quiero morir de la vergüenza', 'no aguanto más el calor',
                     'me quiero morir de risa', 'ya no aguanto más esta fila'])
      assert.equal(haySenal(f), false, f)
  })

  test('sin importar mayúsculas, acentos ni puntuación', () => {
    assert.ok(haySenal('¡NO QUIERO VIVIR!'))
    assert.ok(haySenal('estaría mejor muerta, la verdad'))
    assert.ok(haySenal('tengo ganas de hacerme daño'))
    assert.equal(normalizar('Ojalá, no despertarme MÁS.'), ' ojala no despertarme mas ')
  })

  /// El falso positivo que terminaba la charla, en `Riesgo.swift`.
  test('palabra completa: recortarme el pelo no es cortarme', () => {
    assert.equal(haySenal('mañana quiero recortarme el pelo'), false)
  })

  test('mira sólo lo que dijo la persona, y todo lo que dijo', () => {
    assert.equal(haySenalEnLaCharla([bitacora('¿Alguna vez pensaste en quitarte la vida?'), vos('no, nunca')]), false)
    assert.ok(haySenalEnLaCharla([vos('no le veo sentido a nada'), bitacora('Te escucho.'), vos('bueno')]))
  })
})

describe('cuando dispara, el modelo no se llama', () => {
  test('en vivo: sólo el final, con cuidado, sin audio y con todo por decir', async () => {
    const salida: Buffer[] = []
    const r = await turnoEnVivo({ turnos: [vos('me quiero matar')], dia: HOY }, 'mujer',
                                t => salida.push(t), new AbortController().signal,
                                { llamada: prohibido, sintesis: prohibido, recordarFn: async () => [] })
    assert.equal(r.ok, true)
    const todo = Buffer.concat(salida)
    assert.equal(todo.toString('latin1', 0, 1), 'F', 'una sola trama, la final')
    assert.equal(todo.length, 5 + todo.readUInt32BE(1))
    const fin = JSON.parse(todo.subarray(5).toString('utf8'))
    assert.deepEqual(fin, { ok: true, texto: MENSAJE_DE_RIESGO, hablado: 0, cuidado: true })
  })

  test('POST /charla: el mensaje fijo con cuidado, y sin audio aunque pida voz', async () => {
    const r = await app.inject({
      method: 'POST', url: '/charla', headers: auth,
      payload: { turnos: [vos('quiero desaparecer')], dia: HOY, timbre: 'mujer' },
    })
    assert.equal(r.statusCode, 200)
    assert.deepEqual(r.json(), { ok: true, texto: MENSAJE_DE_RIESGO, cuidado: true })
  })
})

describe('la app instalada antes del cambio de nombre', () => {
  /// Un teléfono sin reinstalar todavía manda el rol viejo. Con el corte de
  /// riesgo se puede probar sin llamar al modelo: si el schema lo rechazara,
  /// esto sería un 400.
  test('el rol `laya` todavía se acepta', async () => {
    const r = await app.inject({
      method: 'POST', url: '/charla', headers: auth,
      payload: { turnos: [{ de: 'laya', texto: '¿Cómo estás?' }, vos('me quiero matar')], dia: HOY },
    })
    assert.equal(r.statusCode, 200)
    assert.equal(r.json().cuidado, true)
  })

  test('una entrada con el rótulo `Laya:` se guarda con el nuevo', async () => {
    const r = await app.inject({
      method: 'POST', url: '/entradas', headers: auth,
      payload: {
        client_uuid: crypto.randomUUID(),
        creado_en: '2027-06-15T21:00:00-03:00',
        creado_local: '2027-06-15T21:00:00',
        fuente: 'dictado_ios',
        transcripcion: 'Vos: [test rótulo viejo] hola\nLaya: ¿Cómo estás?\nVos: bien, Laya',
      },
    })
    assert.equal(r.statusCode, 201)
    const { rows } = await pool.query<{ transcripcion: string }>(
      'select transcripcion from entradas where id = $1', [r.json().id])
    // Sólo el rótulo al principio de la línea: lo que dijo la persona no se toca.
    assert.equal(rows[0]!.transcripcion,
                 'Vos: [test rótulo viejo] hola\nBitácora: ¿Cómo estás?\nVos: bien, Laya')
  })
})

describe('la voz dice el número como se marca', () => {
  test('*4141, con o sin espacio', () => {
    assert.equal(paraDecir('Llama al *4141.'), 'Llama al asterisco cuatro uno cuatro uno.')
    assert.equal(paraDecir('al * 4141 ya'), 'al asterisco cuatro uno cuatro uno ya')
    assert.equal(paraDecir('son 41410 pesos'), 'son 41410 pesos', 'sin asterisco no es el número')
  })
})
