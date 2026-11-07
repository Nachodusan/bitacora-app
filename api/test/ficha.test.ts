import './_setup.ts'
// Un día de 2020: lejos de la ventana del tick, que corre en paralelo.
import { test, after, beforeEach } from 'node:test'
import assert from 'node:assert/strict'
import { pool } from '../src/db.ts'
import { apodoValido, citaValida, hablaDe, validar, revisarEntrada, fichaParaLaCharla, fichaParaLeer, quitarDato, compartirDato, peso,
         type Operacion } from '../src/ficha.ts'
import { borrarConversacion } from '../src/cuenta.ts'

const RELATO = 'Vos: Últimamente me siento sin propósito, sobre todo de noche.\n' +
  'Bitácora: Eso pesa. ¿Qué te da más vueltas?\n' +
  'Vos: Depender de mis papás, pedirles plata a mi edad me frustra mucho.'

const op = (o: Partial<Operacion>): Operacion => ({
  accion: 'nodo', tipo: 'problematica', nombre: 'se siente sin propósito', descripcion: null, apodo: null, momento: null,
  hacia_tipo: null, hacia_nombre: null, relacion: null, como_estaba: null, diferencia: null,
  cita: 'me siento sin propósito, sobre todo de noche', ...o })

beforeEach(async () => {
  await pool.query("delete from ficha_nodos; delete from entradas where transcripcion like '%prueba-ficha%'")
})
after(async () => {
  await pool.query("delete from ficha_nodos; delete from entradas where transcripcion like '%prueba-ficha%'")
  await pool.end()
})

test('la cita tiene que estar en lo que dijo la persona, no en lo de Bitácora', () => {
  const dicho = RELATO.split('\n').filter(l => l.startsWith('Vos:')).join('\n')
  assert.ok(citaValida('pedirles plata a mi edad', dicho))
  assert.ok(citaValida('Pedirles plata, a mi edad', dicho), 'una coma de más no la tumba')
  assert.ok(!citaValida('qué te da más vueltas', dicho), 'lo de Bitácora no cuenta')
  assert.ok(!citaValida('me siento solo y triste', dicho), 'lo inventado no entra')
})

test('se descartan los diagnósticos y lo incompleto', () => {
  const dicho = 'me siento sin propósito, sobre todo de noche'
  assert.equal(validar([op({ nombre: 'depresión' })], dicho).length, 0)
  assert.equal(validar([op({ accion: 'conexion' })], dicho).length, 0)
  assert.equal(validar([op({})], dicho).length, 1)
})

test('lo viejo pesa menos pero no desaparece', () => {
  assert.equal(peso(2, 0), 2)
  assert.equal(peso(2, 45), 1)
  assert.ok(peso(10, 365) > 0)
})

test('revisar una conversación arma la ficha con evidencia, y reforzar suma', async () => {
  const { rows } = await pool.query<{ id: string }>(
    "insert into entradas (creado_local, fuente, transcripcion) values ('2020-01-15 12:00', 'texto', $1) returning id",
    [RELATO + '\nVos: prueba-ficha'])
  const id = Number(rows[0]!.id)
  const llamada = async () => ({ datos: { operaciones: [
    op({}),
    op({ tipo: 'persona', nombre: 'sus papás', cita: 'Depender de mis papás' }),
    op({ accion: 'conexion', tipo: 'persona', nombre: 'sus papás', hacia_tipo: 'problematica',
         hacia_nombre: 'se siente sin propósito', relacion: 'le preocupa', cita: 'pedirles plata a mi edad me frustra' }),
    op({ nombre: 'algo inventado', cita: 'esto nunca lo dijo nadie aquí' }),
  ] } }) as never
  assert.equal(await revisarEntrada(id, llamada), 3)
  const f = (await fichaParaLaCharla())!
  assert.match(f, /se siente sin propósito/)
  assert.match(f, /sus papás → le preocupa → se siente sin propósito/)
  assert.doesNotMatch(f, /algo inventado/)
  const { rows: ev } = await pool.query('select count(*)::int as n from ficha_evidencias where entrada_id = $1', [id])
  assert.equal(ev[0].n, 3)
  const { rows: r } = await pool.query('select ficha_revisada_en from entradas where id = $1', [id])
  assert.ok(r[0].ficha_revisada_en)
})

async function fichaDePrueba(): Promise<{ id: number; uuid: string }> {
  const { rows } = await pool.query<{ id: string; uuid: string }>(
    `insert into entradas (creado_local, fuente, transcripcion, client_uuid)
     values ('2020-01-16 12:00', 'texto', $1, gen_random_uuid())
     returning id, client_uuid::text as uuid`, [RELATO + '\nVos: prueba-ficha'])
  const id = Number(rows[0]!.id)
  await revisarEntrada(id, (async () => ({ datos: { operaciones: [
    op({}), op({ tipo: 'persona', nombre: 'sus papás', cita: 'Depender de mis papás' }),
  ] } })) as never)
  return { id, uuid: rows[0]!.uuid }
}

test('Mi espacio: la ficha se lee con sus frases, y lo que se quita no vuelve', async () => {
  const { id } = await fichaDePrueba()
  const secciones = await fichaParaLeer()
  const pasa = secciones.find(s => s.tipo === 'problematica')!
  assert.equal(pasa.titulo, 'Lo que te pasa')
  const dato = pasa.datos[0]!
  assert.equal(dato.citas[0]!.cita, 'me siento sin propósito, sobre todo de noche')

  assert.ok(await compartirDato(dato.id, true))
  assert.deepEqual((await fichaParaLeer(true)).flatMap(s => s.datos.map(d => d.nombre)), ['se siente sin propósito'])

  assert.ok(await quitarDato(dato.id))
  await revisarEntrada(id, (async () => ({ datos: { operaciones: [op({})] } })) as never)
  assert.ok(!(await fichaParaLeer()).some(s => s.tipo === 'problematica'), 'el modelo no lo resucita')
  assert.doesNotMatch((await fichaParaLaCharla()) ?? '', /sin propósito/)
})

test('borrar una conversación se lleva lo que salió de ella', async () => {
  const { uuid } = await fichaDePrueba()
  assert.ok(await borrarConversacion(uuid))
  assert.equal((await fichaParaLeer()).length, 0, 'sin frases, no queda ningún dato')
  assert.equal(await borrarConversacion(uuid), false)
})

test('lo que vuelve en otra charla suma una vez por charla, y un «cómo va» copiado no entra', async () => {
  const nueva = async (dia: string) => Number((await pool.query<{ id: string }>(
    "insert into entradas (creado_local, fuente, transcripcion) values ($1, 'texto', $2) returning id",
    [`${dia} 12:00`, RELATO + '\nVos: prueba-ficha'])).rows[0]!.id)
  const repetido = async () => ({ datos: { operaciones: [op({}), op({ cita: 'Últimamente me siento sin propósito' })] } }) as never
  await revisarEntrada(await nueva('2020-01-17'), repetido)
  await revisarEntrada(await nueva('2020-01-18'), repetido)
  const { rows } = await pool.query<{ veces: number }>("select veces from ficha_nodos where nombre = 'se siente sin propósito'")
  assert.equal(rows[0]!.veces, 2, 'dos charlas, dos veces, aunque en cada una salga dos veces')

  const progreso = (como: string) => async () => ({ datos: { operaciones: [
    op({ accion: 'progreso', como_estaba: como, diferencia: 'igual', cita: 'Últimamente me siento sin propósito' })] } }) as never
  await revisarEntrada(await nueva('2020-01-19'), progreso('sigue sintiéndose sin rumbo'))
  await revisarEntrada(await nueva('2020-01-20'), progreso('Sigue sintiéndose sin rumbo.'))
  const p = await pool.query('select 1 from ficha_progreso')
  assert.equal(p.rowCount, 1)
})

test('«cómo va» sólo con una frase de ese tema', () => {
  assert.ok(hablaDe('No, no puedo dormir', 'le cuesta dormir'))
  assert.ok(!hablaDe('No, no puedo dormir', 'días decepcionantes'))
  assert.ok(hablaDe('Últimamente me siento sin propósito', 'se siente sin propósito'))
})

test('la descripción de un dato no la pisa otra charla', async () => {
  const nueva = async (dia: string) => Number((await pool.query<{ id: string }>(
    "insert into entradas (creado_local, fuente, transcripcion) values ($1, 'texto', $2) returning id",
    [`${dia} 12:00`, RELATO + '\nVos: prueba-ficha'])).rows[0]!.id)
  await revisarEntrada(await nueva('2020-01-21'), (async () => ({ datos: { operaciones: [op({ descripcion: 'la primera' })] } })) as never)
  await revisarEntrada(await nueva('2020-01-22'), (async () => ({ datos: { operaciones: [op({ descripcion: 'otra cosa' })] } })) as never)
  const { rows } = await pool.query<{ descripcion: string }>("select descripcion from ficha_nodos where nombre = 'se siente sin propósito'")
  assert.equal(rows[0]!.descripcion, 'la primera')
})

test('apodos: «el viejo» suma en «su papá», también en las conexiones', async () => {
  const RELATO_PAPA = 'Vos: Mi papá me volvió a preguntar por el trabajo y me agobia.\n' +
    'Vos: El viejo no entiende que estoy buscando, me pone nervioso.\nVos: prueba-ficha'
  const nueva = async (dia: string) => Number((await pool.query<{ id: string }>(
    "insert into entradas (creado_local, fuente, transcripcion) values ($1, 'texto', $2) returning id",
    [`${dia} 12:00`, RELATO_PAPA])).rows[0]!.id)
  const persona = (o: Partial<Operacion>) => op({ tipo: 'persona', nombre: 'su papá', cita: 'Mi papá me volvió a preguntar por el trabajo', ...o })
  await revisarEntrada(await nueva('2020-02-01'), (async () => ({ datos: { operaciones: [persona({})] } })) as never)
  await revisarEntrada(await nueva('2020-02-02'), (async () => ({ datos: { operaciones: [persona({ apodo: 'el viejo' })] } })) as never)
  await revisarEntrada(await nueva('2020-02-03'), (async () => ({ datos: { operaciones: [
    persona({ nombre: 'el viejo', cita: 'El viejo no entiende que estoy buscando' }),
    op({ accion: 'conexion', tipo: 'persona', nombre: 'el viejo', hacia_tipo: 'problematica',
         hacia_nombre: 'no tener trabajo', relacion: 'le agobia', cita: 'El viejo no entiende que estoy buscando' }),
  ] } })) as never)
  const { rows } = await pool.query<{ nombre: string; veces: number; apodos: string[] }>(
    "select nombre, veces, apodos from ficha_nodos where tipo = 'persona'")
  assert.deepEqual(rows, [{ nombre: 'su papá', veces: 3, apodos: ['el viejo'] }])
  const c = await pool.query("select 1 from ficha_conexiones c join ficha_nodos n on n.id = c.desde where n.nombre = 'su papá'")
  assert.equal(c.rowCount, 1)
  assert.match((await fichaParaLaCharla())!, /su papá \(le dice también «el viejo»\)/)
})

test('un apodo es un nombre corto, no una frase', () => {
  assert.equal(apodoValido('el viejo', 'su papá'), 'el viejo')
  assert.equal(apodoValido('me sentí muy presionado', 'se siente presionado'), null)
  assert.equal(apodoValido('si ya encontré trabajo', 'no tener trabajo'), null)
  assert.equal(apodoValido('mi primo', 'su primo'), null)
})

test('lo que le sirve guarda cuándo y para qué, y la charla lo ve', async () => {
  const T = 'Vos: Anoche no podía dormir y leer un rato me ayudó un montón a calmarme.\nVos: prueba-ficha'
  const nueva = async (dia: string) => Number((await pool.query<{ id: string }>(
    "insert into entradas (creado_local, fuente, transcripcion) values ($1, 'texto', $2) returning id", [`${dia} 23:00`, T])).rows[0]!.id)
  const ops = async () => ({ datos: { operaciones: [
    op({ tipo: 'problematica', nombre: 'le cuesta dormir', cita: 'Anoche no podía dormir' }),
    op({ tipo: 'le_sirve', nombre: 'leer', momento: 'en la noche', cita: 'leer un rato me ayudó un montón' }),
    op({ accion: 'conexion', tipo: 'le_sirve', nombre: 'leer', hacia_tipo: 'problematica', hacia_nombre: 'le cuesta dormir',
         relacion: 'le ayuda con', cita: 'leer un rato me ayudó un montón' }),
  ] } }) as never
  await revisarEntrada(await nueva('2020-05-01'), ops)
  await revisarEntrada(await nueva('2020-05-02'), ops)
  const { rows } = await pool.query<{ momentos: Record<string, number> }>("select momentos from ficha_nodos where nombre = 'leer'")
  assert.deepEqual(rows[0]!.momentos, { 'en la noche': 2 })
  assert.match((await fichaParaLaCharla())!, /- leer .*; sobre todo en la noche; le ayuda con: le cuesta dormir/)
  const leer = (await fichaParaLeer()).find(s => s.tipo === 'le_sirve')!.datos[0]!
  assert.deepEqual([leer.momentos, leer.para], [['en la noche'], ['le cuesta dormir']])
})

test('una conexión no entra si la charla no habla de aquello a lo que apunta', () => {
  const dicho = 'Hoy en la mañana salí a caminar y me hizo bien, llegué con más ánimo.'
  const c = (hacia: string) => op({ accion: 'conexion', tipo: 'le_sirve', nombre: 'salir a caminar', hacia_tipo: 'problematica',
                                    hacia_nombre: hacia, relacion: 'le ayuda con', cita: 'salí a caminar y me hizo bien' })
  assert.equal(validar([c('le cuesta dormir')], dicho).length, 0)
  assert.equal(validar([c('ánimo bajo')], dicho).length, 1)
})

test('patrones: qué día, a qué hora, y qué viene después de qué', async () => {
  const { patrones } = await import('../src/patrones.ts')
  const nodo = async (tipo: string, nombre: string) => Number((await pool.query<{ id: string }>(
    "insert into ficha_nodos (tipo, nombre, primera, ultima) values ($1, $2, '2020-01-01', '2020-01-01') returning id", [tipo, nombre])).rows[0]!.id)
  const dormir = await nodo('problematica', 'le cuesta dormir')
  const papa = await nodo('persona', 'su papá')
  const animo = await nodo('problematica', 'ánimo bajo')
  const evidencia = async (n: number, local: string) => {
    const e = Number((await pool.query<{ id: string }>(
      "insert into entradas (creado_local, fuente, transcripcion) values ($1, 'texto', 'Vos: prueba-ficha') returning id", [local])).rows[0]!.id)
    await pool.query("insert into ficha_evidencias (nodo_id, entrada_id, dia, cita) values ($1, $2, (select dia from entradas where id = $2), 'x')", [n, e])
  }
  // Cuatro domingos de madrugada (a las 3, el día lógico es el sábado) y un martes.
  for (const d of ['2020-07-05', '2020-07-12', '2020-07-19', '2020-07-26']) await evidencia(dormir, `${d} 23:30`)
  await evidencia(dormir, '2020-07-14 23:30')
  // Su papá tres veces; el ánimo bajo, al día siguiente de cada una.
  for (const [p, a] of [['2020-08-03', '2020-08-04'], ['2020-08-10', '2020-08-11'], ['2020-08-17', '2020-08-18']]) {
    await evidencia(papa, `${p} 13:00`); await evidencia(animo, `${a} 10:00`)
  }
  for (const d of ['2020-08-05', '2020-08-06', '2020-08-07', '2020-08-08']) await evidencia(dormir, `${d} 23:00`)
  const t = (await patrones()).map(p => p.texto)
  assert.ok(t.includes('«le cuesta dormir» lo cuenta casi siempre en la noche (9 de 9 veces)'), t.join('\n'))
  assert.ok(t.includes('«le cuesta dormir» aparece sobre todo los domingos (4 de 9 días)'), t.join('\n'))
  assert.ok(!t.some(x => x.includes('«ánimo bajo» aparece sobre todo')), 'tres días no alcanzan para un día de la semana')
  assert.ok(t.includes('cuando aparece «su papá», ese día o el siguiente suele aparecer «ánimo bajo» (3 de 3 veces)'), t.join('\n'))
})

test('una meta queda unida al problema que busca resolver, y la charla lo ve', async () => {
  const T = 'Vos: Quiero irme de la casa, independizarme, para no tener que depender de mis papás.\nVos: prueba-ficha'
  const id = Number((await pool.query<{ id: string }>(
    "insert into entradas (creado_local, fuente, transcripcion) values ('2020-09-01 21:00', 'texto', $1) returning id", [T])).rows[0]!.id)
  await revisarEntrada(id, (async () => ({ datos: { operaciones: [
    op({ tipo: 'problematica', nombre: 'depender de sus papás', cita: 'para no tener que depender de mis papás' }),
    op({ tipo: 'meta', nombre: 'independizarse', cita: 'Quiero irme de la casa, independizarme' }),
    op({ accion: 'conexion', tipo: 'meta', nombre: 'independizarse', hacia_tipo: 'problematica', hacia_nombre: 'depender de sus papás',
         relacion: 'busca resolver', cita: 'para no tener que depender de mis papás' }),
  ] } })) as never)
  assert.match((await fichaParaLaCharla())!, /- independizarse.*; busca resolver: depender de sus papás/)
  const meta = (await fichaParaLeer()).find(s => s.tipo === 'meta')!.datos[0]!
  assert.deepEqual(meta.para, ['depender de sus papás'])
})

test('el nombre sin la nota de la ficha, y el apodo sólo si lo dijo ella', () => {
  const dicho = 'Me ayudó que me contaran un cuento para dormir.'
  const [o] = validar([op({ tipo: 'le_sirve', nombre: 'que le cuenten un cuento (también le dice: ejercicio de respiración)',
                            apodo: 'ejercicio de respiración', cita: 'Me ayudó que me contaran un cuento' })], dicho)
  assert.equal(o!.nombre, 'que le cuenten un cuento')
  assert.equal(o!.apodo, null)
})
