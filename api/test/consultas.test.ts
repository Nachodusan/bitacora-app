import './_setup.ts'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { after, before, beforeEach, describe, test } from 'node:test'
import type { FastifyInstance } from 'fastify'

import type { Reloj } from '../src/ajustes.ts'

const { momentoDeConsulta, bloqueDeConsulta, proponerConsultas, prepararConsultas, leerEvento } =
  await import('../src/consultas.ts')
const { siguienteTurno } = await import('../src/charla.ts')
const { leerReloj } = await import('../src/ajustes.ts')
const { sumarDias } = await import('../src/fechas.ts')
const { construirServidor } = await import('../src/server.ts')
const { config } = await import('../src/config.ts')
const { pool, cerrarPool } = await import('../src/db.ts')

/// Todo en 2033, lejos de los días que usan los otros archivos de test, que
/// corren a la vez contra la misma base.
// Sin ninguna palabra de consulta adentro: si no, la marca sola despierta la
// búsqueda de consultas mencionadas.
const MARCA = '[prueba de agenda]'
const auth = { authorization: `Bearer ${config.authToken}` }
let app: FastifyInstance

const reloj = (ahora: string): Reloj => ({
  ajustes: { zona: 'America/Santiago', nombre: null },
  ahoraLocal: ahora,
  diaLogico: sumarDias(ahora.slice(0, 10), ahora.slice(11, 13) < '04' ? -1 : 0),
})

async function consulta(dia: string, hora: string | null, extra: Record<string, unknown> = {}) {
  const { rows } = await pool.query<{ id: number }>(
    `insert into eventos (tipo, dia, hora, origen, estado, para_llevar)
     values ('consulta', $1, $2, $3, $4, $5) returning id::int`,
    [dia, hora, extra.origen ?? 'persona', extra.estado ?? 'confirmado',
     JSON.stringify(extra.para_llevar ?? [])])
  return rows[0]!.id
}

async function entrada(cuando: string, texto: string) {
  const { rows } = await pool.query<{ id: number }>(
    `insert into entradas (client_uuid, creado_en, creado_local, fuente, transcripcion)
     values (gen_random_uuid(), now(), $1, 'dictado_ios', $2) returning id::int`,
    [cuando, `Vos: ${MARCA} ${texto}`])
  return rows[0]!.id
}

async function limpiar() {
  await pool.query(`delete from eventos where dia between '2033-01-01' and '2033-12-31'`)
  await pool.query(`delete from entradas where transcripcion like $1`, [`%${MARCA}%`])
  await pool.query(`delete from llm_llamadas where modelo = 'modelo-de-prueba'`)
}

before(async () => { app = construirServidor(); await app.ready() })
beforeEach(limpiar)
after(async () => { await limpiar(); await app.close(); await cerrarPool() })

/// Un modelo de mentira que contesta según la tarea, y anota qué le pidieron.
function modelo(respuestas: Record<string, unknown>) {
  const pedidos: { tarea: string; usuario: string }[] = []
  const fn = (async (p: { tarea: string; usuario: string }) => {
    pedidos.push(p)
    if (!(p.tarea in respuestas)) throw new Error(`no esperaba la tarea ${p.tarea}`)
    return { datos: respuestas[p.tarea], crudo: {} }
  }) as never
  return { fn, pedidos }
}

describe('las rutas de eventos', () => {
  test('alta idempotente, lista, cambio y baja', async () => {
    const uuid = randomUUID()
    const cuerpo = { client_uuid: uuid, tipo: 'consulta', dia: '2033-05-10', hora: '17:30' }
    const a = await app.inject({ method: 'POST', url: '/eventos', headers: auth, payload: cuerpo })
    assert.equal(a.statusCode, 201)
    const ev = a.json().evento
    assert.deepEqual({ tipo: ev.tipo, dia: ev.dia, hora: ev.hora, origen: ev.origen, estado: ev.estado },
                     { tipo: 'consulta', dia: '2033-05-10', hora: '17:30', origen: 'persona', estado: 'confirmado' })

    const otra = await app.inject({ method: 'POST', url: '/eventos', headers: auth, payload: cuerpo })
    assert.equal(otra.statusCode, 200, 'reintentar no duplica')
    assert.equal(otra.json().evento.id, ev.id)

    const lista = await app.inject({ method: 'GET', url: '/eventos?desde=2033-05-01&hasta=2033-05-31', headers: auth })
    assert.deepEqual(lista.json().eventos.map((e: { id: number }) => e.id), [ev.id])

    const sinHora = await app.inject({ method: 'PATCH', url: `/eventos/${ev.id}`, headers: auth,
                                       payload: { hora: null } })
    assert.equal(sinHora.json().evento.hora, null)

    const baja = await app.inject({ method: 'DELETE', url: `/eventos/${ev.id}`, headers: auth })
    assert.equal(baja.statusCode, 204)
    const otraVez = await app.inject({ method: 'DELETE', url: `/eventos/${ev.id}`, headers: auth })
    assert.equal(otraVez.statusCode, 404)
  })

  test('un evento que no es consulta necesita título', async () => {
    const r = await app.inject({ method: 'POST', url: '/eventos', headers: auth,
                                 payload: { client_uuid: randomUUID(), tipo: 'otro', dia: '2033-05-11' } })
    assert.equal(r.statusCode, 400)
  })

  test('una hora mal escrita es un 400, no un 500', async () => {
    const r = await app.inject({ method: 'POST', url: '/eventos', headers: auth,
                                 payload: { client_uuid: randomUUID(), tipo: 'consulta', dia: '2033-05-12', hora: '25:00' } })
    assert.equal(r.statusCode, 400)
  })

  test('una propuesta descartada no se ve más', async () => {
    const id = await consulta('2033-05-13', null, { origen: 'bitacora', estado: 'propuesto' })
    await app.inject({ method: 'PATCH', url: `/eventos/${id}`, headers: auth, payload: { estado: 'descartado' } })
    const lista = await app.inject({ method: 'GET', url: '/eventos?desde=2033-05-01&hasta=2033-05-31', headers: auth })
    assert.deepEqual(lista.json().eventos, [])
  })

  /// La promesa de que las evaluaciones viven en el teléfono.
  test('marcarla evaluada borra el borrador del servidor', async () => {
    const id = await consulta('2033-05-14', '10:00')
    await pool.query(`update eventos set borrador = '{"entendi":"algo"}' where id = $1`, [id])
    const r = await app.inject({ method: 'PATCH', url: `/eventos/${id}`, headers: auth, payload: { evaluada: true } })
    assert.equal(r.json().evento.evaluada, true)
    assert.equal(r.json().evento.borrador, null)
  })

  test('cambiar la fecha borra lo que se había sacado de la fecha vieja', async () => {
    const id = await consulta('2033-05-15', '10:00', { para_llevar: ['lo de mi hermana'] })
    await app.inject({ method: 'PATCH', url: `/eventos/${id}`, headers: auth, payload: { dia: '2033-05-16' } })
    assert.deepEqual((await leerEvento(id))!.para_llevar, [])
  })
})

describe('antes y después de la consulta', () => {
  test('desde las 4 de la mañana del día anterior, toca prepararla', async () => {
    await consulta('2033-03-10', '17:00')
    assert.equal((await momentoDeConsulta(reloj('2033-03-09 03:59:00'))).antes, null)
    const m = await momentoDeConsulta(reloj('2033-03-09 10:00:00'))
    assert.equal(m.antes?.evento.dia, '2033-03-10')
    assert.equal(m.despues, null)
    const b = bloqueDeConsulta(m, '2033-03-09')!
    assert.match(b, /Tiene consulta con su terapeuta mañana, jueves 10 de marzo, a las 17:00\./)
    assert.match(b, /dos o tres cosas/)
  })

  test('con «Preparar», toca aunque falten días, y sólo si no pasó', async () => {
    const id = await consulta('2033-03-10', '17:00')
    assert.equal((await momentoDeConsulta(reloj('2033-03-07 10:00:00'))).antes, null, 'sin pedirla, faltan días')
    const m = await momentoDeConsulta(reloj('2033-03-07 10:00:00'), id)
    assert.equal(m.antes?.evento.id, id)
    assert.equal(m.antes?.pedida, true)
    const b = bloqueDeConsulta(m, '2033-03-07')!
    assert.match(b, /tocó «Preparar» en la app/)
    assert.doesNotMatch(b, /cuando\nbaje/)
    assert.equal((await momentoDeConsulta(reloj('2033-03-10 17:30:00'), id)).antes, null, 'ya pasó')
    const propuesta = await consulta('2033-03-12', '17:00', { estado: 'propuesto' })
    assert.equal((await momentoDeConsulta(reloj('2033-03-07 10:00:00'), propuesta)).antes, null, 'sin confirmar')
    // Dentro de la ventana de siempre, sin «Preparar», no dice que la pidió.
    const sola = bloqueDeConsulta(await momentoDeConsulta(reloj('2033-03-09 10:00:00')), '2033-03-09')!
    assert.doesNotMatch(sola, /Preparar/)
  })

  test('el material son sus frases desde la consulta anterior', async () => {
    await consulta('2033-03-03', '17:00')
    await consulta('2033-03-10', '17:00')
    const vieja = await entrada('2033-03-01T21:00:00', 'esto fue antes de la consulta anterior')
    const nueva = await entrada('2033-03-06T21:00:00', 'me peleé con mi hermana')
    for (const [id, dia, texto] of [[vieja, '2033-03-01', 'ANTES DE LA ANTERIOR'],
                                    [nueva, '2033-03-06', 'me peleé con mi hermana']] as const) {
      await pool.query(
        `insert into notas_terapia (entrada_id, dia, modelo, citas) values ($1, $2, 'x', $3)`,
        [id, dia, JSON.stringify([{ texto, sobre: 'algo' }])])
    }
    const b = bloqueDeConsulta(await momentoDeConsulta(reloj('2033-03-09 10:00:00')), '2033-03-09')!
    assert.match(b, /«me peleé con mi hermana» \(domingo 6 de marzo\)/)
    assert.doesNotMatch(b, /ANTES DE LA ANTERIOR/)
  })

  test('desde la hora de la consulta y por siete días, toca preguntar cómo le fue', async () => {
    await consulta('2033-03-10', '17:00', { para_llevar: ['que no duermo'] })
    const m = await momentoDeConsulta(reloj('2033-03-10 18:00:00'))
    assert.equal(m.antes, null)
    const b = bloqueDeConsulta(m, '2033-03-10')!
    assert.match(b, /Tuvo consulta con su terapeuta hoy, jueves 10 de marzo, a las 17:00\./)
    assert.match(b, /Antes de ir eligió llevar: que no duermo\./)
    assert.match(b, /cómo le fue en la consulta/)
    assert.equal((await momentoDeConsulta(reloj('2033-03-17 17:01:00'))).despues, null, 'pasaron siete días')
  })

  test('una sola vez: si ya hablaron después de la consulta, tampoco pregunta otro día', async () => {
    await consulta('2033-03-10', '17:00')
    await entrada('2033-03-10T10:00:00', 'esto fue antes de ir')
    const antes = bloqueDeConsulta(await momentoDeConsulta(reloj('2033-03-10 20:00:00')), '2033-03-10')!
    assert.match(antes, /cómo le fue en la consulta/, 'una charla de antes de la hora no cuenta')

    await entrada('2033-03-10T21:00:00', 'hoy fui y me fue bien')
    const mismoDia = bloqueDeConsulta(await momentoDeConsulta(reloj('2033-03-10 23:00:00')), '2033-03-10')!
    assert.match(mismoDia, /Ya hablaron después de la consulta, hoy: no le vuelvas a\npreguntar cómo le fue\./)

    const m = await momentoDeConsulta(reloj('2033-03-12 21:00:00'))
    assert.equal(m.despues?.hablaronEl, '2033-03-10')
    const otroDia = bloqueDeConsulta(m, '2033-03-12')!
    assert.match(otroDia, /Ya hablaron después de la consulta, el jueves 10 de marzo:/)
    assert.doesNotMatch(otroDia, /cómo le fue en la consulta/)
  })

  test('una charla que todavía no pasó no cuenta como que ya hablaron', async () => {
    await consulta('2033-03-10', '17:00')
    await entrada('2033-03-11T21:00:00', 'mañana a la noche')
    assert.equal((await momentoDeConsulta(reloj('2033-03-10 20:00:00'))).despues?.hablaronEl, null)
  })

  test('con la evaluación guardada, no hay después', async () => {
    const id = await consulta('2033-03-10', '17:00')
    await pool.query('update eventos set evaluada_en = now() where id = $1', [id])
    assert.equal((await momentoDeConsulta(reloj('2033-03-11 10:00:00'))).despues, null)
  })

  test('una propuesta sin confirmar no cuenta', async () => {
    await consulta('2033-03-10', '17:00', { origen: 'bitacora', estado: 'propuesto' })
    const m = await momentoDeConsulta(reloj('2033-03-09 10:00:00'))
    assert.equal(m.antes, null)
  })

  /// Con el reloj de verdad: una consulta hoy a última hora tiene que llegar al
  /// prompt. Hoy y no mañana: antes de las 4 de la mañana, la ventana de una
  /// consulta de mañana todavía no empezó.
  test('el bloque llega al prompt de la charla', async () => {
    const r = await leerReloj()
    const id = await consulta(r.ahoraLocal.slice(0, 10), '23:59')
    try {
      const visto: string[] = []
      await siguienteTurno({ turnos: [{ de: 'vos', texto: 'hola' }], dia: r.diaLogico },
        (async (p: { sistema: string }) => { visto.push(p.sistema); return { datos: 'ok', crudo: {} } }) as never,
        async () => [])
      assert.match(visto[0]!, /--- Antes de la consulta ---/)
      assert.ok(visto[0]!.trimEnd().endsWith('todos van en tú.'), 'el idioma sigue al final')
    } finally {
      await pool.query('delete from eventos where id = $1', [id])
    }
  })
})

describe('proponer consultas mencionadas', () => {
  test('la propone, con la frase verificada', async () => {
    const id = await entrada('2033-04-04T21:00:00', 'el jueves tengo terapia a las cinco')
    const m = modelo({ consulta: { consultas: [
      { dia: '2033-04-07', hora: '17:00', cita: 'el jueves tengo terapia a las cinco' },
      { dia: '2033-04-08', hora: '', cita: 'el viernes voy al psiquiatra' },  // no lo dijo
    ] } })
    assert.equal(await proponerConsultas('2033-04-04', 14, m.fn), 1)
    const { rows } = await pool.query(
      `select dia::text, to_char(hora, 'HH24:MI') as hora, origen, estado, entrada_id::int
         from eventos where dia between '2033-04-01' and '2033-04-30'`)
    assert.deepEqual(rows, [{ dia: '2033-04-07', hora: '17:00', origen: 'bitacora',
                              estado: 'propuesto', entrada_id: id }])
    assert.equal(await proponerConsultas('2033-04-04', 14, m.fn), 0, 'ya está revisada')
    assert.equal(m.pedidos.length, 1)
  })

  test('sin palabras de consulta no se llama al modelo, y queda revisada', async () => {
    await entrada('2033-04-04T21:00:00', 'hoy dormí poco y fui a nadar')
    const m = modelo({})
    assert.equal(await proponerConsultas('2033-04-04', 14, m.fn), 0)
    assert.equal(m.pedidos.length, 0)
    const { rows } = await pool.query(
      `select count(*)::int as n from entradas where transcripcion like $1 and consultas_revisadas_en is null`,
      [`%${MARCA}%`])
    assert.equal(rows[0].n, 0)
  })

  test('no propone un día que ya pasó, ni uno que ya tiene consulta o una descartada', async () => {
    await consulta('2033-04-07', null, { origen: 'bitacora', estado: 'descartado' })
    await entrada('2033-04-04T21:00:00', 'el lunes tuve consulta y el jueves tengo terapia')
    const m = modelo({ consulta: { consultas: [
      { dia: '2033-04-03', hora: '', cita: 'el lunes tuve consulta' },
      { dia: '2033-04-07', hora: '', cita: 'el jueves tengo terapia' },
    ] } })
    assert.equal(await proponerConsultas('2033-04-04', 14, m.fn), 0)
  })
})

describe('lo que eligió llevar y el borrador', () => {
  test('lo que eligió llevar queda en la consulta', async () => {
    const id = await consulta('2033-06-10', '17:00')
    await entrada('2033-06-09T20:00:00', 'quiero llevar lo de mi hermana')
    const m = modelo({ para_llevar: { para_llevar: ['lo de mi hermana', '', 'que no duermo', 'uno', 'dos'] } })
    const r = await prepararConsultas(reloj('2033-06-09 22:00:00'), m.fn)
    assert.equal(r.para_llevar, 1)
    assert.deepEqual((await leerEvento(id))!.para_llevar, ['lo de mi hermana', 'que no duermo', 'uno'])
    // Sin charlas nuevas, no se vuelve a llamar.
    await prepararConsultas(reloj('2033-06-09 23:00:00'), m.fn)
    assert.equal(m.pedidos.length, 1)
  })

  test('el borrador sale de lo que habló después, y un cuadro que ella no nombró se cae', async () => {
    const id = await consulta('2033-06-10', '17:00')
    await entrada('2033-06-10T20:00:00', 'entendí que me cuesta poner límites y salí tranquila')
    const m = modelo({ evaluacion: {
      entendi: 'Entendí que me cuesta poner límites.',
      aporte: '',
      sentir: 'Salí tranquila, aunque con rasgos de ansiedad.',  // eso no lo dijo
      temas: ['límites', ''],
      avance: '',
    } })
    const r = await prepararConsultas(reloj('2033-06-11 10:00:00'), m.fn)
    assert.equal(r.borradores, 1)
    assert.deepEqual((await leerEvento(id))!.borrador, {
      entendi: 'Entendí que me cuesta poner límites.', aporte: '', sentir: '',
      temas: ['límites'], avance: '',
    })
  })

  test('el borrador lee la primera charla de después y el día siguiente, y después no se toca más', async () => {
    const id = await consulta('2033-06-10', '17:00')
    await entrada('2033-06-09T21:00:00', 'ANTES DE LA CONSULTA')
    await entrada('2033-06-11T22:00:00', 'hoy te cuento la sesión de ayer')   // la primera de después
    await entrada('2033-06-12T21:00:00', 'me quedé pensando en la sesión')  // el día siguiente
    await entrada('2033-06-13T21:00:00', 'ALMUERZO DE OTRO DÍA')
    const m = modelo({ evaluacion: { entendi: 'Algo.', aporte: '', sentir: '', temas: [], avance: '' } })

    assert.equal((await prepararConsultas(reloj('2033-06-14 10:00:00'), m.fn)).borradores, 1)
    const leido = m.pedidos[0]!.usuario
    assert.match(leido, /hoy te cuento la sesión de ayer/)
    assert.match(leido, /me quedé pensando en la sesión/)
    assert.doesNotMatch(leido, /ANTES DE LA CONSULTA|ALMUERZO DE OTRO DÍA/)

    await entrada('2033-06-14T21:00:00', 'otra charla')
    await prepararConsultas(reloj('2033-06-15 10:00:00'), m.fn)
    assert.equal(m.pedidos.length, 1, 'con la ventana cerrada, una charla nueva no lo reescribe')
    assert.equal((await leerEvento(id))!.borrador?.entendi, 'Algo.')
  })

  test('sin nada de la sesión, no hay borrador', async () => {
    const id = await consulta('2033-06-10', '17:00')
    await entrada('2033-06-11T09:00:00', 'hoy llovió')
    const m = modelo({ evaluacion: { entendi: '', aporte: '', sentir: '', temas: [], avance: '' } })
    assert.equal((await prepararConsultas(reloj('2033-06-11 10:00:00'), m.fn)).borradores, 0)
    assert.equal((await leerEvento(id))!.borrador, null)
  })
})
