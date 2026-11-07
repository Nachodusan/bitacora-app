import 'dotenv/config'
import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

/// Genera la misma frase de Bitácora con cada voz candidata, para elegir de oído.
///
/// No hay otra forma de elegir una voz: las fichas dicen "español" y ninguna
/// dice cómo suena de verdad. Corre con `npm run voces` y deja los mp3 en
/// `pruebas-de-voz/`, numerados, más los tiempos de cada uno.
///
/// La frase es inventada y fija. NUNCA pasar por acá texto de una charla real:
/// esto le habla a proveedores que la app todavía no usa.

const FRASE =
  'Qué momento tan feo. Que te regañen delante de todos duele, y quedarte callado ' +
  'después deja un enojo que cuesta sacarse. ¿Quieres contarme qué te dijo?'

const BASE = 'https://api.deepinfra.com/v1/openai'

/// modelo → voces a probar. `extra` son parámetros propios de cada modelo.
const CANDIDATAS: { modelo: string; voces: string[]; extra?: Record<string, unknown> }[] = [
  { modelo: 'inworld-ai/realtime-tts-1.5-max', voces: ['Diego', 'Lupita', 'Miguel', 'Rafael', 'Luna', 'Ashley'] },
  { modelo: 'inworld-ai/realtime-tts-1.5-mini', voces: ['Diego', 'Lupita'] },
  { modelo: 'Qwen/Qwen3-TTS', voces: ['Vivian', 'Serena', 'Ryan', 'Aiden', 'Sohee'], extra: { language: 'Spanish' } },
  { modelo: 'ResembleAI/chatterbox-multilingual', voces: [''], extra: { language_id: 'es' } },
]

const clave = process.env.DEEPINFRA_API_KEY?.trim()
if (!clave) throw new Error('Falta DEEPINFRA_API_KEY en api/.env')

const carpeta = join(import.meta.dirname, '..', '..', 'pruebas-de-voz')
await mkdir(carpeta, { recursive: true })

let n = 0
for (const c of CANDIDATAS) {
  for (const voz of c.voces) {
    const arranque = Date.now()
    const r = await fetch(`${BASE}/audio/speech`, {
      method: 'POST',
      headers: { authorization: `Bearer ${clave}`, 'content-type': 'application/json' },
      signal: AbortSignal.timeout(60_000),
      body: JSON.stringify({ model: c.modelo, input: FRASE, response_format: 'mp3',
                             ...(voz ? { voice: voz } : {}), ...c.extra }),
    })
    const etiqueta = `${c.modelo.split('/')[1]} · ${voz || 'voz por defecto'}`
    if (!r.ok || !r.body) {
      console.log(`  —  ${etiqueta}: rebotó con ${r.status}`)
      continue
    }
    // El primer pedazo es lo que importa para la charla: es cuándo podría
    // empezar a sonar si el teléfono reprodujera mientras llega.
    const lector = r.body.getReader()
    const pedazos: Uint8Array[] = []
    let primero = 0
    for (;;) {
      const { done, value } = await lector.read()
      if (done) break
      if (!primero) primero = Date.now() - arranque
      pedazos.push(value)
    }
    n++
    const nombre = `${String(n).padStart(2, '0')} ${etiqueta.replace(' · ', ' - ')}.mp3`
    await writeFile(join(carpeta, nombre), Buffer.concat(pedazos))
    console.log(`  ${String(n).padStart(2, '0')}  ${etiqueta}: primer audio ${primero} ms, completo ${Date.now() - arranque} ms`)
  }
}
console.log(`\n${n} audios en ${carpeta}`)
