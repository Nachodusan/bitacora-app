import { construirServidor } from './server.ts'
import { config, verificarConfigLLM } from './config.ts'
import { cerrarPool } from './db.ts'
import { arrancarLatido } from './latido.ts'

const app = construirServidor()

try {
  await app.listen({ port: config.puerto, host: config.host })
} catch (e) {
  app.log.error(e)
  process.exit(1)
}

/// El latido corre dentro de este proceso salvo que se lo apague.
///
/// Se apaga con LATIDO=off cuando el tick se dispara desde afuera (un cron del
/// sistema llamando a `npm run tick`), o para levantar el servidor sin config
/// del LLM — que es lo que hacen los tests: sin esto tendrían que tener clave.
if (process.env.LATIDO !== 'off') {
  try {
    // Que falte una variable se vea acá al arrancar, y no dentro del primer
    // tick diez minutos después, con el servidor ya en pie y aparentemente bien.
    verificarConfigLLM()
    arrancarLatido(app)
    app.log.info('latido cada 10 min: resumen y notas de los días que terminaron')
  } catch (e) {
    app.log.error(e, 'el latido no arranca; el servidor sigue recibiendo entradas')
  }
}

for (const senal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(senal, async () => {
    await app.close()
    await cerrarPool()
    process.exit(0)
  })
}
