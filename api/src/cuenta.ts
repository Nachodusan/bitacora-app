import { pool } from './db.ts'

/// Lo que la persona borra desde Mi espacio, además de un dato de la ficha
/// (`ficha.ts`). El sistema nunca borra solo: esto pasa sólo si ella lo pide.

/// Borrar una conversación, con todo lo que salió de ella: las frases de la
/// ficha, su progreso y su nota (en cascada). El resumen de ese día también la
/// tenía adentro: si quedan otras charlas se rehace (el tick ve que no
/// coinciden las cuentas), y si no quedan, se va.
export async function borrarConversacion(uuid: string): Promise<boolean> {
  const cliente = await pool.connect()
  try {
    await cliente.query('begin')
    const { rows } = await cliente.query<{ dia: string }>(
      'delete from entradas where client_uuid = $1 returning dia::text as dia', [uuid])
    const dia = rows[0]?.dia
    if (dia) {
      await cliente.query(
        `update resumenes_dia set resumen = null, embedding = null, intentos = 0 where dia = $1`, [dia])
      await cliente.query(
        `delete from resumenes_dia where dia = $1 and not exists (select 1 from entradas where dia = $1)`, [dia])
      // Los datos de la ficha que sólo salían de esta charla se quedan sin
      // ninguna frase: sin evidencia no hay dato.
      await cliente.query(
        `update ficha_nodos n set borrado_en = now()
          where borrado_en is null and not exists (select 1 from ficha_evidencias e where e.nodo_id = n.id)`)
      await cliente.query(
        `delete from ficha_conexiones c where not exists (select 1 from ficha_evidencias e where e.conexion_id = c.id)`)
    }
    await cliente.query('commit')
    return dia !== undefined
  } catch (e) {
    await cliente.query('rollback')
    throw e
  } finally {
    cliente.release()
  }
}

export const DIAS_DE_PAPELERA = 30

/// La cuenta va a la papelera: durante treinta días no se procesa nada y se
/// puede recuperar. Devuelve el día en que se borra del todo.
export async function pedirBorrarCuenta(): Promise<string> {
  const { rows } = await pool.query<{ hasta: string }>(
    `update ajustes set cuenta_borrar_en = coalesce(cuenta_borrar_en, now()) where id = 1
     returning to_char(cuenta_borrar_en + make_interval(days => $1), 'YYYY-MM-DD') as hasta`, [DIAS_DE_PAPELERA])
  return rows[0]!.hasta
}

export async function recuperarCuenta(): Promise<void> {
  await pool.query('update ajustes set cuenta_borrar_en = null where id = 1')
}

/// `null` si no está en la papelera; si no, el día en que se borra del todo.
export async function cuentaSeBorraEl(): Promise<string | null> {
  const { rows } = await pool.query<{ hasta: string | null }>(
    `select to_char(cuenta_borrar_en + make_interval(days => $1), 'YYYY-MM-DD') as hasta from ajustes where id = 1`,
    [DIAS_DE_PAPELERA]).catch(() => ({ rows: [] as { hasta: string | null }[] }))
  return rows[0]?.hasta ?? null
}

/// Pasados los treinta días, se borra todo lo de la persona. Quedan los
/// costos de las llamadas al modelo (sin nada de lo que dijo) y la zona
/// horaria, para que el servidor siga andando. Lo llama el tick.
export async function purgarSiVencio(): Promise<boolean> {
  const { rows } = await pool.query<{ vencio: boolean }>(
    `select coalesce(cuenta_borrar_en + make_interval(days => $1) <= now(), false) as vencio
       from ajustes where id = 1`, [DIAS_DE_PAPELERA]).catch(() => ({ rows: [] as { vencio: boolean }[] }))
  if (!rows[0]?.vencio) return false
  const cliente = await pool.connect()
  try {
    await cliente.query('begin')
    await cliente.query('delete from ficha_nodos')
    await cliente.query('delete from eventos')
    await cliente.query('delete from resumenes_dia')
    await cliente.query('delete from entradas')
    await cliente.query(
      `update ajustes set nombre = null, ficha_avisada_en = null, cuenta_borrar_en = null where id = 1`)
    await cliente.query('commit')
    return true
  } catch (e) {
    await cliente.query('rollback')
    throw e
  } finally {
    cliente.release()
  }
}
