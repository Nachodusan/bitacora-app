import './_setup.ts'
import assert from 'node:assert/strict'
import { after, describe, test } from 'node:test'

const { relojEn, leerReloj } = await import('../src/ajustes.ts')
const { pool, cerrarPool } = await import('../src/db.ts')

after(cerrarPool)

describe('el reloj del usuario', () => {
  /// Las dos cuentas tienen que dar lo mismo: si no, el día lógico cambia
  /// según qué camino tome el servidor.
  test('el cálculo en Node coincide con el de Postgres', async () => {
    for (const zona of ['America/Santiago', 'America/Argentina/Buenos_Aires', 'Europe/Madrid']) {
      for (const iso of ['2026-10-14T06:30:00Z', '2026-10-14T08:10:00Z', '2026-03-01T03:59:00Z']) {
        const { rows } = await pool.query<{ a: string; d: string }>(
          `select to_char($1::timestamptz at time zone $2, 'YYYY-MM-DD HH24:MI:SS') as a,
                  (($1::timestamptz at time zone $2) - interval '4 hours')::date::text as d`, [iso, zona])
        const js = relojEn(zona, new Date(iso))
        assert.deepEqual(js, { ahoraLocal: rows[0]!.a, diaLogico: rows[0]!.d }, `${zona} ${iso}`)
      }
    }
  })

  test('un nombre viejo de zona funciona igual que el actual', () => {
    const t = new Date('2026-10-14T03:30:00Z')
    assert.deepEqual(relojEn('America/Buenos_Aires', t), relojEn('America/Argentina/Buenos_Aires', t))
    assert.equal(relojEn('America/Buenos_Aires', t).diaLogico, '2026-10-13', '00:30 en Buenos Aires es todavía el día anterior')
  })

  test('leerReloj anda aunque Postgres no conozca la zona guardada', async () => {
    const { rows } = await pool.query<{ zona: string }>('select zona from ajustes where id = 1')
    const antes = rows[0]?.zona
    // Una zona que Node acepta y que este Postgres no trae, como le pasa al del
    // VPS con America/Buenos_Aires.
    try {
      await pool.query(`update ajustes set zona = $1 where id = 1`, ['US/Pacific-New'])
      const r = await leerReloj()
      assert.equal(r.ajustes.zona, 'US/Pacific-New')
      assert.match(r.ahoraLocal, /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d$/)
    } finally {
      if (antes) await pool.query('update ajustes set zona = $1 where id = 1', [antes])
    }
  })
})
