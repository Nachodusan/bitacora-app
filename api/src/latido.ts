import type { FastifyInstance } from 'fastify'
import { tick, type ResultadoTick } from './tick.ts'
import { enCuenta } from './db.ts'
import { basesDeCuentas } from './cuentas.ts'

/// Cada cuánto late. Diez minutos: el resumen de un día que terminó a las 4am
/// no hace falta que esté a las 4:00 en punto, y las consultas de guardia no se
/// notan.
const CADA_MS = Number(process.env.TICK_CADA_MS ?? 10 * 60 * 1000)

/// El tick corriendo dentro del proceso del servidor.
///
/// Es un `setInterval` y no un cron del sistema a propósito: con un solo
/// usuario y un solo VPS, un cron es otro archivo que configurar, que se pierde
/// al migrar de máquina y que falla en silencio. Acá arranca con el servidor y
/// se ve en el mismo log. Si algún día conviene sacarlo afuera, `npm run tick`
/// hace exactamente lo mismo una vez.
export function arrancarLatido(app: FastifyInstance): () => void {
  let corriendo = false

  const latir = async () => {
    // Un tick puede tardar más que el intervalo si hay varios días atrasados
    // que resumir. Sin este guard se solaparían.
    if (corriendo) {
      app.log.warn('tick: el anterior sigue corriendo, salteo este')
      return
    }
    corriendo = true
    try {
      // Una cuenta por vez, cada una con su base. Si una falla, las demás siguen.
      for (const bd of await basesDeCuentas()) {
        try { informar(await enCuenta(bd, () => tick()), bd) } catch (e) { app.log.error({ e, bd }, 'tick falló') }
      }
    } finally {
      corriendo = false
    }
  }

  const informar = (r: ResultadoTick, bd: string | null) => {
    // Sólo se loguea cuando hizo algo. Un log cada diez minutos diciendo que
    // no pasó nada es un log que nadie mira.
    if (r.resumidos.length || r.sin_resumen.length || r.postergados.length
        || r.notas || r.notas_postergadas || r.consultas_propuestas || r.para_llevar
        || r.borradores || r.ficha || r.presupuesto_agotado) {
      app.log.info({ bd: bd ?? 'principal', resumidos: r.resumidos, sin_resumen: r.sin_resumen,
                     postergados: r.postergados, notas: r.notas,
                     notas_postergadas: r.notas_postergadas,
                     consultas_propuestas: r.consultas_propuestas,
                     para_llevar: r.para_llevar, borradores: r.borradores, ficha: r.ficha,
                     presupuesto_agotado: r.presupuesto_agotado }, 'tick')
    }
  }

  const t = setInterval(latir, CADA_MS)
  // Sin `unref`, el proceso no termina nunca aunque le pidan que cierre.
  t.unref()
  // Uno al arrancar, por si el servidor estuvo caído justo en la ventana.
  void latir()

  return () => clearInterval(t)
}
