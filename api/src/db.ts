import { AsyncLocalStorage } from 'node:async_hooks'
import pg from 'pg'
import { config } from './config.ts'

/// Sin ORM: las consultas son la lógica de negocio y se leen mejor en SQL que
/// envueltas en tres capas de abstracción.
///
/// UNA BASE POR CUENTA (28/10/2026). Cada persona tiene su propia base, igual
/// que cuando cada diario era un servidor aparte: lo de una nunca está en una
/// tabla con lo de otra. `poolBase` es la de `DATABASE_URL`: el diario que ya
/// existía, la tabla de cuentas y los libros (`guias`). `pool` es la de la
/// cuenta del pedido o del tick que está corriendo (`enCuenta`); fuera de una
/// cuenta, la base.
export const poolBase = nuevoPool(config.databaseUrl)

function nuevoPool(url: string): pg.Pool {
  return new pg.Pool({ connectionString: url, max: 5, idleTimeoutMillis: 30_000 })
}

interface Contexto { pool: pg.Pool }
const contexto = new AsyncLocalStorage<Contexto>()
const pools = new Map<string, pg.Pool>()

/// El pool de una base de cuenta, por nombre. `null` es la base.
export function poolDe(bd: string | null): pg.Pool {
  if (!bd) return poolBase
  let p = pools.get(bd)
  if (!p) {
    const u = new URL(config.databaseUrl)
    u.pathname = '/' + bd
    p = nuevoPool(u.toString())
    pools.set(bd, p)
  }
  return p
}

/// Corre `fn` con la base de esa cuenta como `pool`.
export function enCuenta<T>(bd: string | null, fn: () => T): T {
  return contexto.run({ pool: poolDe(bd) }, fn)
}

/// Para los pedidos: abre un contexto vacío que `requiereToken` completa.
export function abrirContexto(fn: () => void): void {
  contexto.run({ pool: poolBase }, fn)
}
export function usarCuenta(bd: string | null): void {
  const c = contexto.getStore()
  if (c) c.pool = poolDe(bd)
}

/// Se usa como un `pg.Pool` de siempre; detrás, el de la cuenta actual.
export const pool: pg.Pool = new Proxy({} as pg.Pool, {
  get(_, prop) {
    const p = contexto.getStore()?.pool ?? poolBase
    const v = Reflect.get(p, prop, p)
    return typeof v === 'function' ? v.bind(p) : v
  },
})

export async function cerrarPool(): Promise<void> {
  await Promise.all([poolBase.end(), ...[...pools.values()].map(p => p.end())])
}

/// Corre `fn` con un candado exclusivo, o devuelve `null` si ya lo tiene otro.
///
/// Existe por una razón concreta: hay dos caminos que pueden pedir el mismo
/// trabajo caro al mismo tiempo. El latido del servidor y un `npm run tick` a
/// mano pueden arrancar con segundos de diferencia, y sin candado los dos
/// llaman al modelo por el mismo día para que uno pise al otro. La clave
/// primaria de `resumenes_dia` impide la fila duplicada, pero recién en el
/// insert: para entonces ya se pagó dos veces.
///
/// Advisory lock y no una columna `generando`: el candado se suelta solo si el
/// proceso se muere. Una columna se queda pegada después de un kill -9 y hay
/// que ir a destrabarla a mano justo cuando nadie se acuerda de que existe.
///
/// El lock vive en la CONEXIÓN, así que tiene que tomarse y soltarse en el
/// mismo cliente — de ahí el `connect()` en vez de usar el pool suelto.
export async function conCandado<T>(
  clave: string,
  fn: () => Promise<T>,
): Promise<T | null> {
  const cliente = await pool.connect()
  try {
    const { rows } = await cliente.query<{ ok: boolean }>(
      'select pg_try_advisory_lock(hashtext($1)) as ok', [clave])
    if (!rows[0]!.ok) return null

    try {
      return await fn()
    } finally {
      await cliente.query('select pg_advisory_unlock(hashtext($1))', [clave])
    }
  } finally {
    cliente.release()
  }
}
