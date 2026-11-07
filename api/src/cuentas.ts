import { createHash, randomBytes, randomInt, scrypt, timingSafeEqual } from 'node:crypto'
import { promisify } from 'node:util'
import type pg from 'pg'
import { pool, poolBase, poolDe } from './db.ts'
import { zonaValida } from './ajustes.ts'

/// Las cuentas (28/10/2026): un ID que da el servidor y un PIN de seis dígitos
/// que elige la persona. Cada cuenta tiene su propia base, copiada de la
/// plantilla. La tabla vive en la base principal.
///
/// Seis dígitos se adivinan en un millón de intentos: por eso, después de
/// cinco errores la cuenta se traba, primero quince minutos y cada vez más.
/// El PIN se guarda con scrypt; las sesiones, con su hash.

const scryptAsync = promisify(scrypt) as (pin: string, sal: Buffer, largo: number) => Promise<Buffer>
const PLANTILLA = process.env.PLANTILLA_BD ?? 'bitacora_plantilla'
/// Sin letras que se confunden (0/O, 1/I/L).
const LETRAS = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'

export const PIN = /^\d{6}$/

export interface Perfil {
  nombre?: string | null
  /// YYYY-MM-DD. La edad se calcula: no hay que volver a preguntarla.
  fecha_nacimiento?: string | null
  pais?: string | null
  ciudad?: string | null
  con_quien?: string | null
}

async function hashPin(pin: string): Promise<string> {
  const sal = randomBytes(16)
  return `${sal.toString('hex')}:${(await scryptAsync(pin, sal, 32)).toString('hex')}`
}

async function pinCorrecto(pin: string, guardado: string): Promise<boolean> {
  const [sal, hash] = guardado.split(':')
  const h = await scryptAsync(pin, Buffer.from(sal!, 'hex'), 32)
  return timingSafeEqual(h, Buffer.from(hash!, 'hex'))
}

const hashToken = (t: string) => createHash('sha256').update(t).digest('hex')

function nuevoId(): string {
  const parte = () => Array.from({ length: 3 }, () => LETRAS[randomInt(LETRAS.length)]).join('')
  return `${parte()}-${parte()}`
}

async function nuevaSesion(cuenta: string): Promise<string> {
  const token = randomBytes(32).toString('base64url')
  await poolBase.query('insert into sesiones (token_hash, cuenta_id) values ($1, $2)', [hashToken(token), cuenta])
  return token
}

/// La base de una sesión, o `undefined` si el token no es de nadie.
export async function baseDeSesion(token: string): Promise<string | null | undefined> {
  const { rows } = await poolBase.query<{ bd: string | null }>(
    'select c.bd from sesiones s join cuentas c on c.id = s.cuenta_id where s.token_hash = $1', [hashToken(token)])
    .catch(() => ({ rows: [] as { bd: string | null }[] }))
  return rows[0] ? rows[0].bd : undefined
}

function limpio(t: string | null | undefined): string | null {
  const s = (t ?? '').trim()
  return s ? s.slice(0, 80) : null
}

/// En la base de la cuenta actual, salvo que se diga otra.
export async function guardarPerfil(p: Perfil, base: pg.Pool = pool): Promise<void> {
  await base.query(
    `update ajustes set nombre = coalesce($1, nombre), fecha_nacimiento = $2::date, pais = $3, ciudad = $4,
            con_quien = $5, actualizado = now() where id = 1`,
    [limpio(p.nombre)?.slice(0, 40) ?? null, p.fecha_nacimiento ?? null, limpio(p.pais)?.slice(0, 60) ?? null,
     limpio(p.ciudad)?.slice(0, 60) ?? null, limpio(p.con_quien)])
}

/// Una cuenta nueva: su base copiada de la plantilla, el perfil y la zona.
export async function crearCuenta(pin: string, perfil: Perfil, zona: string): Promise<{ id: string; token: string }> {
  let id = nuevoId()
  while ((await poolBase.query('select 1 from cuentas where id = $1', [id])).rowCount) id = nuevoId()
  const bd = 'bitacora_c_' + id.replace('-', '').toLowerCase()
  // CREATE DATABASE no acepta parámetros: el nombre sale sólo de LETRAS.
  await poolBase.query(`create database ${bd} template ${PLANTILLA}`)
  await poolDe(bd).query('update ajustes set zona = $1 where id = 1', [zonaValida(zona) ? zona : 'UTC'])
  await guardarPerfil(perfil, poolDe(bd))
  await poolBase.query('insert into cuentas (id, pin_hash, bd) values ($1, $2, $3)', [id, await hashPin(pin), bd])
  return { id, token: await nuevaSesion(id) }
}

/// El diario que ya existía (la base principal) pasa a tener ID y PIN. Sólo
/// una vez: si ya tiene, devuelve el mismo ID y cambia el PIN.
export async function cuentaParaLaBase(pin: string): Promise<{ id: string; token: string }> {
  const hash = await hashPin(pin)
  const { rows } = await poolBase.query<{ id: string }>('select id from cuentas where bd is null')
  let id = rows[0]?.id
  if (id) await poolBase.query('update cuentas set pin_hash = $2 where id = $1', [id, hash])
  else {
    id = nuevoId()
    await poolBase.query('insert into cuentas (id, pin_hash, bd) values ($1, $2, null)', [id, hash])
  }
  return { id, token: await nuevaSesion(id) }
}

export type Entrada = { ok: true; token: string } | { ok: false; trabada_hasta?: string }

/// Entrar con ID y PIN. Lo mismo si el ID no existe o el PIN está mal: no se
/// dice cuál de los dos falló.
export async function entrar(idCrudo: string, pin: string): Promise<Entrada> {
  const id = idCrudo.trim().toUpperCase().replace(/[^0-9A-Z]/g, '').replace(/^(.{3})(.{3})$/, '$1-$2')
  const { rows } = await poolBase.query<{ pin_hash: string; intentos: number; trabada: string | null }>(
    `select pin_hash, intentos,
            case when bloqueada_hasta > now() then to_char(bloqueada_hasta at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') end as trabada
       from cuentas where id = $1`, [id])
  const c = rows[0]
  if (!c) return { ok: false }
  if (c.trabada) return { ok: false, trabada_hasta: c.trabada }
  if (!PIN.test(pin) || !(await pinCorrecto(pin, c.pin_hash))) {
    // Cada cinco errores, una traba: 15 min, 30, 60… hasta un día.
    const n = c.intentos + 1
    const minutos = n % 5 === 0 ? Math.min(15 * 2 ** (n / 5 - 1), 1440) : 0
    await poolBase.query(
      `update cuentas set intentos = $2,
              bloqueada_hasta = case when $3::int > 0 then now() + make_interval(mins => $3::int) else bloqueada_hasta end
        where id = $1`, [id, n, minutos])
    return { ok: false }
  }
  await poolBase.query('update cuentas set intentos = 0, bloqueada_hasta = null where id = $1', [id])
  return { ok: true, token: await nuevaSesion(id) }
}

/// Todas las bases que tiene que recorrer el latido: la principal y las de
/// las cuentas.
export async function basesDeCuentas(): Promise<(string | null)[]> {
  const { rows } = await poolBase.query<{ bd: string }>('select bd from cuentas where bd is not null order by creada_en')
    .catch(() => ({ rows: [] as { bd: string }[] }))
  return [null, ...rows.map(r => r.bd)]
}

/// El ID de la cuenta de un token de sesión.
export async function idDeSesion(token: string): Promise<string | null> {
  const { rows } = await poolBase.query<{ cuenta_id: string }>(
    'select cuenta_id from sesiones where token_hash = $1', [hashToken(token)])
  return rows[0]?.cuenta_id ?? null
}

/// El ID de la base principal, si ya eligió PIN.
export async function idDeLaBase(): Promise<string | null> {
  const { rows } = await poolBase.query<{ id: string }>('select id from cuentas where bd is null')
    .catch(() => ({ rows: [] as { id: string }[] }))
  return rows[0]?.id ?? null
}
