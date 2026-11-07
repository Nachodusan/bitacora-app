import { timingSafeEqual } from 'node:crypto'
import type { FastifyReply, FastifyRequest } from 'fastify'
import { config } from './config.ts'
import { usarCuenta } from './db.ts'
import { baseDeSesion } from './cuentas.ts'

/// Comparación en tiempo constante. Con `===` el tiempo de respuesta filtra
/// cuántos caracteres del token acertaste; con un solo usuario el riesgo es
/// bajo, pero el costo de hacerlo bien es cero.
function iguales(a: string, b: string): boolean {
  const x = Buffer.from(a)
  const y = Buffer.from(b)
  if (x.length !== y.length) return false
  return timingSafeEqual(x, y)
}

declare module 'fastify' {
  interface FastifyRequest {
    /// Entró con el token fijo del servidor (el diario de antes de las cuentas).
    conTokenFijo?: boolean
    tokenDeSesion?: string
  }
}

/// Dos llaves (28/10/2026): el token fijo de siempre, que es la base
/// principal, o una sesión de una cuenta (ID y PIN), que es su base. Desde
/// acá, todo el pedido usa la base de esa cuenta (`db.ts`).
export async function requiereToken(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  const cabecera = req.headers.authorization ?? ''
  const [esquema, token] = cabecera.split(' ')
  if (esquema === 'Bearer' && token && iguales(token, config.authToken)) {
    req.conTokenFijo = true
    usarCuenta(null)
    return
  }
  const bd = esquema === 'Bearer' && token ? await baseDeSesion(token) : undefined
  if (bd === undefined) {
    // Sin detalle de por qué: un 401 que explica es un 401 que ayuda a adivinar.
    return reply.code(401).send({ error: 'no autorizado' })
  }
  req.tokenDeSesion = token
  usarCuenta(bd)
}
