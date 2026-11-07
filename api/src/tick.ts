import { pool, conCandado } from './db.ts'
import { llamar, PresupuestoAgotado } from './llm.ts'
import { leerReloj, type Reloj } from './ajustes.ts'
import { resumirDia, MAX_INTENTOS } from './resumen.ts'
import { escribirNota, sinRevisar, marcarRevisada } from './notas.ts'
import { embeberPendientes, memoriaLargaActiva } from './recuerdos.ts'
import { proponerConsultas, prepararConsultas } from './consultas.ts'
import { purgarSiVencio, cuentaSeBorraEl } from './cuenta.ts'
import { fichaEncendida, pendientes, revisarEntrada } from './ficha.ts'

/// Cuántos días para atrás se miran. Bitácora sólo lee los últimos siete, así que
/// resumir algo de hace tres semanas es gastar una llamada en un recuerdo que
/// nunca va a aparecer. Catorce deja margen para una semana sin servidor.
///
/// Vale también para las notas, y ahí la razón es otra: acotar cuánto puede
/// costar un tick después de una caída larga. Una conversación de hace más de
/// dos semanas sin nota se puede revisar a mano con `npm run tick` corriendo
/// con VENTANA más grande; no hace falta que el latido lo haga solo.
const VENTANA_DIAS = 14

export interface ResultadoTick {
  reloj: Reloj
  /// Días a los que se les escribió (o reescribió) el resumen.
  resumidos: string[]
  /// Días donde el modelo no logró un resumen guardable.
  sin_resumen: string[]
  /// Días que fallaron por el entorno y se van a reintentar.
  postergados: string[]
  /// Cuántas notas de terapia se escribieron.
  notas: number
  /// Conversaciones cuya nota falló por el entorno y se van a reintentar.
  notas_postergadas: number
  /// Resúmenes que quedaron indexados para la memoria larga.
  indexados: number
  /// Consultas que se propusieron en el calendario porque se mencionaron en una charla.
  consultas_propuestas: number
  /// Consultas a las que se les escribió lo que eligió llevar.
  para_llevar: number
  /// Borradores de evaluación escritos.
  borradores: number
  /// Operaciones que entraron a la ficha viva.
  ficha: number
  presupuesto_agotado: boolean
}

/// Un latido: cierra los días que ya terminaron.
///
/// Cuatro pasadas, independientes entre sí. La de las consultas va entre las
/// notas y la indexación. La tercera indexa los resúmenes para
/// la memoria larga (`recuerdos.ts`). Primero los resúmenes de los días
/// vencidos (la memoria de Bitácora). Después las notas de terapia de cada
/// conversación de esos días que todavía no se revisó. Van separadas a
/// propósito: antes las notas colgaban del loop del resumen, y si una nota
/// fallaba después de que el resumen ya estaba escrito, el día salía de la
/// lista y esa conversación no tenía nota nunca más. Material para terapia
/// perdido en silencio.
///
/// Un fallo en un día o en una conversación NO corta el tick: se anota y se
/// sigue con el siguiente. Lo único que corta todo es el techo del mes.
///
/// `relojFijo` es para correr el latido en otra fecha (la simulación de un mes).
/// Sin él, la hora de verdad del usuario.
export async function tick(llamada = llamar, relojFijo?: Reloj): Promise<ResultadoTick> {
  const reloj = relojFijo ?? await leerReloj()
  const r: ResultadoTick = { reloj, resumidos: [], sin_resumen: [], postergados: [],
                             notas: 0, notas_postergadas: 0, indexados: 0,
                             consultas_propuestas: 0, para_llevar: 0, borradores: 0, ficha: 0,
                             presupuesto_agotado: false }

  // El candado evita que el latido del servidor y un `npm run tick` a mano
  // resuman el mismo día a la vez y paguen dos veces. Si otro lo tiene, este
  // tick no hace nada y no es un error.
  await conCandado('tick', async () => {
    // La cuenta en la papelera: no se procesa nada, y a los treinta días se
    // borra todo (`cuenta.ts`).
    await purgarSiVencio()
    if (await cuentaSeBorraEl()) return
    try {
      for (const dia of await diasPorCerrar(reloj.diaLogico)) {
        try {
          const res = await resumirDia(dia, llamada)
          if (res) (res.resumen ? r.resumidos : r.sin_resumen).push(dia)
        } catch (e) {
          if (e instanceof PresupuestoAgotado) throw e
          // Falla del entorno (resumirDia ya filtró las que son del día). El
          // próximo tick lo vuelve a intentar; los días siguientes no esperan.
          r.postergados.push(dia)
          console.warn(`tick: el resumen de ${dia} se posterga:`, mensaje(e))
        }
      }

      for (const id of await sinRevisar(reloj.diaLogico, VENTANA_DIAS)) {
        try {
          if (await escribirNota(id, llamada)) r.notas++
          // Se marca aunque no haya salido nota: "se revisó y no había nada"
          // también es una respuesta, y sin marcarla se volvería a preguntar
          // cada diez minutos.
          await marcarRevisada(id)
        } catch (e) {
          if (e instanceof PresupuestoAgotado) throw e
          r.notas_postergadas++
          console.warn(`tick: la nota de la entrada ${id} se posterga:`, mensaje(e))
        }
      }

      // Las consultas (`consultas.ts`): proponer las que se mencionaron, y
      // escribir lo que eligió llevar y los borradores de evaluación. Cada una
      // atrapa sus propios fallos y sólo deja pasar el techo del mes.
      r.consultas_propuestas = await proponerConsultas(reloj.diaLogico, VENTANA_DIAS, llamada)
      const prep = await prepararConsultas(reloj, llamada)
      r.para_llevar = prep.para_llevar
      r.borradores = prep.borradores

      // La ficha viva (`ficha.ts`): lee las conversaciones de los días que ya
      // cerraron. Si una falla, el próximo latido la vuelve a intentar.
      if (await fichaEncendida()) {
        for (const id of await pendientes(reloj.diaLogico)) {
          try {
            r.ficha += await revisarEntrada(id, llamada)
          } catch (e) {
            if (e instanceof PresupuestoAgotado) throw e
            console.warn(`tick: la ficha de la entrada ${id} se posterga:`, mensaje(e))
          }
        }
      }

      // Última, y después de los resúmenes a propósito: indexa también los que
      // se acaban de escribir en este mismo latido.
      if (memoriaLargaActiva()) r.indexados = await embeberPendientes()
    } catch (e) {
      // El techo del mes cortó. Lo que ya se hizo queda hecho; lo demás espera
      // a que vuelva el presupuesto — y como nada quedó marcado, se retoma solo.
      if (e instanceof PresupuestoAgotado) { r.presupuesto_agotado = true; return }
      throw e
    }
  })
  return r
}

function mensaje(e: unknown): string {
  return (e instanceof Error ? e.message : String(e)).slice(0, 160)
}

/// Los días que ya terminaron y todavía tienen algo que escribir.
///
/// Tres casos, todos derivados de los datos: nunca hubo resumen; lo hubo pero
/// llegaron más entradas después (la cola offline del teléfono); o el modelo
/// no logró uno guardable y todavía quedan intentos.
async function diasPorCerrar(hoy: string): Promise<string[]> {
  const { rows } = await pool.query<{ dia: string }>(
    `select e.dia::text
       from entradas e
       left join resumenes_dia r on r.dia = e.dia
      where e.dia < $1::date
        and e.dia >= $1::date - $2::int
      group by e.dia, r.dia, r.resumen, r.intentos, r.n_entradas
     having r.dia is null
         or r.n_entradas <> count(*)
         or (r.resumen is null and r.intentos < $3::int)
      order by e.dia`,
    [hoy, VENTANA_DIAS, MAX_INTENTOS],
  )
  return rows.map(x => x.dia)
}
