/// Corre un tick y sale. Para un cron, o para mirarlo a mano:
///
///   npm run tick
import { tick } from './tick.ts'
import { gastoDelMes } from './llm.ts'
import { cerrarPool } from './db.ts'
import { config, verificarConfigLLM } from './config.ts'

verificarConfigLLM()

const r = await tick()

console.log(`ahora (${r.reloj.ajustes.zona}): ${r.reloj.ahoraLocal}  ·  día lógico: ${r.reloj.diaLogico}`)
if (r.resumidos.length) console.log(`resumidos: ${r.resumidos.join(', ')}`)
if (r.sin_resumen.length) console.log(`sin resumen guardable: ${r.sin_resumen.join(', ')}`)
if (r.postergados.length) console.log(`postergados por el entorno: ${r.postergados.join(', ')}`)
console.log(`notas escritas: ${r.notas}${r.notas_postergadas ? `  ·  postergadas: ${r.notas_postergadas}` : ''}`)
if (r.presupuesto_agotado) console.log('PRESUPUESTO AGOTADO: el tick cortó')

const gastado = await gastoDelMes()
console.log(`gasto del mes: ${gastado.toFixed(4)} de ${config.presupuestoMensualUsd} USD`)

await cerrarPool()
process.exit(r.presupuesto_agotado ? 1 : 0)
