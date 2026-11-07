import './_setup.ts'
import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import { construirServidor } from '../src/server.ts'
import { pool, poolBase, poolDe, cerrarPool } from '../src/db.ts'

const app = construirServidor()
const creadas: string[] = []

after(async () => {
  await app.close()
  await poolBase.query('delete from cuentas')
  await cerrarPool()
  const pg = (await import('pg')).default
  const c = new pg.Client({ connectionString: process.env.DATABASE_URL })
  await c.connect()
  for (const bd of creadas) await c.query(`drop database if exists ${bd}`)
  await c.end()
})

const json = (r: { body: string }) => JSON.parse(r.body)

test('una cuenta nueva tiene su propia base, con su perfil, y se vuelve a entrar con ID y PIN', async () => {
  const r = await app.inject({ method: 'POST', url: '/cuentas',
    payload: { pin: '482915', zona: 'America/Santiago', nombre: 'Prueba', fecha_nacimiento: '1997-03-14',
               pais: 'Chile', ciudad: 'Santiago', con_quien: null } })
  assert.equal(r.statusCode, 201)
  const { id, token } = json(r)
  assert.match(id, /^[2-9A-Z]{3}-[2-9A-Z]{3}$/)
  const { rows } = await poolBase.query<{ bd: string }>('select bd from cuentas where id = $1', [id])
  creadas.push(rows[0]!.bd)

  const perfil = json(await app.inject({ url: '/perfil', headers: { authorization: `Bearer ${token}` } }))
  assert.deepEqual(perfil, { id, nombre: 'Prueba', fecha_nacimiento: '1997-03-14', pais: 'Chile', ciudad: 'Santiago', con_quien: null })

  // Lo que sube esta cuenta va a su base, no a la principal.
  const e = await app.inject({ method: 'POST', url: '/entradas', headers: { authorization: `Bearer ${token}` },
    payload: { client_uuid: crypto.randomUUID(), creado_en: '2020-02-01T12:00:00-03:00', creado_local: '2020-02-01T12:00:00',
               fuente: 'dictado_ios', transcripcion: 'Vos: hola, prueba-cuentas', duracion_seg: 1 } })
  assert.ok([200, 201].includes(e.statusCode), e.body)
  const enSuBase = await poolDe(rows[0]!.bd).query("select 1 from entradas where transcripcion like '%prueba-cuentas%'")
  const enLaPrincipal = await pool.query("select 1 from entradas where transcripcion like '%prueba-cuentas%'")
  assert.equal(enSuBase.rowCount, 1)
  assert.equal(enLaPrincipal.rowCount, 0)

  const mal = await app.inject({ method: 'POST', url: '/cuentas/entrar', payload: { id, pin: '000000' } })
  assert.equal(mal.statusCode, 401)
  const bien = await app.inject({ method: 'POST', url: '/cuentas/entrar', payload: { id: id.toLowerCase().replace('-', ''), pin: '482915' } })
  assert.equal(bien.statusCode, 200)
  assert.ok(json(bien).token)
})

test('cinco PIN equivocados traban la cuenta, aunque el sexto sea el bueno', async () => {
  const { id } = json(await app.inject({ method: 'POST', url: '/cuentas', payload: { pin: '111222', zona: 'UTC' } }))
  creadas.push((await poolBase.query<{ bd: string }>('select bd from cuentas where id = $1', [id])).rows[0]!.bd)
  for (let i = 0; i < 5; i++) {
    assert.equal((await app.inject({ method: 'POST', url: '/cuentas/entrar', payload: { id, pin: '999999' } })).statusCode, 401)
  }
  const r = await app.inject({ method: 'POST', url: '/cuentas/entrar', payload: { id, pin: '111222' } })
  assert.equal(r.statusCode, 423)
})

test('sin token no se entra, y un token inventado tampoco', async () => {
  assert.equal((await app.inject({ url: '/perfil' })).statusCode, 401)
  assert.equal((await app.inject({ url: '/perfil', headers: { authorization: 'Bearer inventado' } })).statusCode, 401)
})
