import { pool } from './db.ts'

export interface Ajustes {
  /// Identificador IANA, tal cual lo manda el teléfono.
  zona: string
  /// Cómo quiere que Bitácora lo llame. `null` es una respuesta válida: sin nombre
  /// la charla funciona igual, sólo que no te nombra.
  nombre?: string | null
}

/// El "ahora" del usuario, no el del servidor.
///
/// El tick decide qué días ya terminaron mirando qué hora es en la muñeca del
/// usuario, y el servidor no lo sabe: en un VPS el reloj está en UTC.
export interface Reloj {
  ajustes: Ajustes
  /// "YYYY-MM-DD HH:MM:SS", hora de pared del usuario.
  ahoraLocal: string
  /// El día lógico de este instante, con el MISMO corte de 4am que la columna
  /// generada `entradas.dia`. La fórmula está repetida a propósito: si cambia,
  /// cambia en los dos lados o el sistema se parte.
  diaLogico: string
}

/// El AT TIME ZONE de acá no contradice la regla del corte: esa regla prohíbe
/// calcular `entradas.dia` con la zona del servidor. Acá no llega ninguna hora
/// de pared de afuera; se pregunta qué hora es ahora para el usuario.
///
/// Si Postgres no conoce la zona, se calcula acá con la del teléfono. Pasó
/// con el cliente desde el 7 de octubre: su Android mandó
/// `America/Buenos_Aires`, un nombre viejo que el Postgres del VPS ya no trae
/// (el actual es `America/Argentina/Buenos_Aires`) y que Node sí acepta, así
/// que pasaba `zonaValida` y después el tick y `/notas` reventaban cada vez.
export async function leerReloj(): Promise<Reloj> {
  const { rows } = await pool.query<{ zona: string; nombre: string | null; conocida: boolean }>(
    `select a.zona, a.nombre,
            exists (select 1 from pg_timezone_names t where t.name = a.zona) as conocida
       from ajustes a where a.id = 1`,
  )
  const f = rows[0]
  if (!f) throw new Error('No hay fila en `ajustes`. Corré db/schema.sql.')
  const ajustes = { zona: f.zona, nombre: f.nombre }
  if (!f.conocida) return { ajustes, ...relojEn(f.zona) }

  const { rows: r } = await pool.query<{ ahora_local: string; dia_logico: string }>(
    `select to_char(l.ahora, 'YYYY-MM-DD HH24:MI:SS') as ahora_local,
            ((l.ahora) - interval '4 hours')::date::text as dia_logico
       from (select now() at time zone $1::text as ahora) l`,
    [f.zona],
  )
  return { ajustes, ahoraLocal: r[0]!.ahora_local, diaLogico: r[0]!.dia_logico }
}

/// La misma cuenta que la consulta de arriba, hecha con el reloj de Node: la
/// hora de pared en `zona` y el día lógico con el corte de las 4 de la mañana.
/// Node conoce también los nombres viejos de las zonas.
export function relojEn(zona: string, instante = new Date()): { ahoraLocal: string; diaLogico: string } {
  const pared = (d: Date) => {
    const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
      timeZone: zona, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    }).formatToParts(d).map(x => [x.type, x.value]))
    return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}:${p.second}`
  }
  const ahoraLocal = pared(instante)
  // Restar 4 horas a la hora de pared (no al instante): así lo hace Postgres.
  const [fecha, hora] = ahoraLocal.split(' ')
  const comoUtc = new Date(`${fecha}T${hora}Z`)
  const diaLogico = new Date(comoUtc.getTime() - 4 * 3600_000).toISOString().slice(0, 10)
  return { ahoraLocal, diaLogico }
}

/// Upsert pelado, sin efectos secundarios.
export async function guardarAjustes(a: Ajustes): Promise<Ajustes> {
  const { rows } = await pool.query<Ajustes>(
    `insert into ajustes (id, zona, nombre, actualizado)
     values (1, $1, $2, now())
     on conflict (id) do update set
       zona = excluded.zona, nombre = excluded.nombre, actualizado = now()
     returning zona, nombre`,
    // Un nombre en blanco es no tener nombre, no un nombre vacío: sin esto el
    // CHECK rebotaría el upsert y el prompt diría "te llamás  ".
    [a.zona, (a.nombre ?? '').trim() || null],
  )
  return rows[0]!
}

/// Que la zona exista de verdad. Sin esto, un string cualquiera entra a la
/// tabla y el tick revienta en `at time zone` cada diez minutos, para siempre.
export function zonaValida(zona: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zona })
    return true
  } catch {
    return false
  }
}
