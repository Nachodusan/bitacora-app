import './_setup.ts'
import assert from 'node:assert/strict'
import { after, beforeEach, describe, test } from 'node:test'

const { sintetizar, gastoDeVoz, MAX_CARACTERES } = await import('../src/voz.ts')
const { PresupuestoAgotado } = await import('../src/llm.ts')
const { config } = await import('../src/config.ts')
const { pool, cerrarPool } = await import('../src/db.ts')

after(async () => { await cerrarPool() })

/// Un proveedor de mentira que anota con qué lo llamaron.
function proveedor(audio = Buffer.from('audio de mentira')) {
  const visto: { texto: string; voz: string; modelo: string }[] = []
  return {
    visto,
    fn: async (texto: string, voz: string, modelo: string) => {
      visto.push({ texto, voz, modelo })
      return { audio, tipo: 'audio/aac' }
    },
  }
}

async function llamadasDeVoz() {
  const { rows } = await pool.query(
    `select tarea, modelo, tokens_in, costo_usd, ok from llm_llamadas
      where tarea = 'voz' order by id`)
  return rows
}

beforeEach(async () => {
  await pool.query(`delete from llm_llamadas where tarea = 'voz'`)
})

describe('la voz de Bitácora', () => {
  test('devuelve el audio del proveedor', async () => {
    const p = proveedor(Buffer.from([0xff, 0xfb, 0x90]))
    const r = await sintetizar('Hola, contame.', 'mujer', p.fn)
    assert.deepEqual([...r.audio], [0xff, 0xfb, 0x90])
    assert.equal(r.tipo, 'audio/aac')
    assert.equal(p.visto[0]?.texto, 'Hola, contame.')
  })

  /// La regla 5: toda llamada al modelo queda registrada, salga bien o mal.
  /// Sin esto el guard de presupuesto queda ciego justo para la llamada más
  /// fácil de repetir sin querer.
  test('registra la llamada con su costo', async () => {
    await sintetizar('doce chars', 'mujer', proveedor().fn)
    const [l] = await llamadasDeVoz()
    assert.equal(l!.tarea, 'voz')
    assert.equal(l!.ok, true)
    assert.equal(l!.tokens_in, 'doce chars'.length)
    assert.ok(Number(l!.costo_usd) > 0, 'la voz tiene que costar algo')
  })

  test('registra también la que falló', async () => {
    await assert.rejects(
      sintetizar('hola', 'mujer', async () => { throw new Error('TTS 500: se cayó') }),
      /TTS 500/)
    const [l] = await llamadasDeVoz()
    assert.equal(l!.ok, false)
  })

  /// El CHECK de `llm_llamadas.tarea` tiene que incluir 'voz'. Si no, el insert
  /// rebota, `registrar()` se lo traga con un console.error y la plata no la
  /// cuenta nadie. Esto es lo que verifica que el delta se aplicó.
  test('la base acepta la tarea voz', async () => {
    await sintetizar('hola', 'mujer', proveedor().fn)
    assert.equal((await llamadasDeVoz()).length, 1,
      'no quedó registrada: falta aplicar db/deltas.sql')
  })

  /// Una llamada que rebotó no generó audio, así que no se cobra. La fila
  /// queda igual, con los caracteres que se intentaron.
  test('la que falló no suma costo', async () => {
    await assert.rejects(
      sintetizar('hola que tal', 'mujer', async () => { throw new Error('TTS 503') }))
    const [l] = await llamadasDeVoz()
    assert.equal(Number(l!.costo_usd), 0)
    assert.equal(l!.tokens_in, 'hola que tal'.length)
  })

  /// El techo propio: cuando la voz se comió su parte, se apaga sola y la
  /// charla sigue. Sin esto, unas semanas de charlas largas podían gastar el
  /// mes entero en audio y dejar a la persona sin respuestas.
  test('la voz se apaga sola cuando se come su parte del mes', async () => {
    const techo = config.presupuestoMensualUsd * config.fraccionDeVoz
    // Una fila de voz que ya se pasó del techo propio, pero no del general.
    await pool.query(
      `insert into llm_llamadas (tarea, modelo, costo_usd, ok) values ('voz', 'x', $1, true)`,
      [techo + 0.01])
    await assert.rejects(sintetizar('hola', 'mujer', proveedor().fn), PresupuestoAgotado)
    // Y el general sigue teniendo aire: la charla no se corta.
    assert.ok(await gastoDeVoz() < config.presupuestoMensualUsd)
  })

  test('el techo de caracteres es el del proveedor que menos acepta', () => {
    assert.equal(MAX_CARACTERES, 2000)
  })

  /// La voz cuelga de a dónde apunta `VOZ_BASE_URL`. Un nombre de OpenAI
  /// mandado a Inworld rebota con 400 y Bitácora termina hablando con la de iOS
  /// sin que nadie vea un error.
  test('una sola voz, aunque una app vieja pida la de hombre', async () => {
    const antes = { ...process.env }
    try {
      const p = proveedor()
      await sintetizar('hola', 'mujer', p.fn)
      await sintetizar('hola', 'hombre', p.fn)
      assert.deepEqual(p.visto.map(v => v.voz), ['coral', 'coral'])

      process.env.VOZ_BASE_URL = 'https://api.deepinfra.com/v1/openai'
      const q = proveedor()
      await sintetizar('hola', 'mujer', q.fn)
      await sintetizar('hola', 'hombre', q.fn)
      assert.deepEqual(q.visto.map(v => v.voz), ['Lupita', 'Lupita'])
      assert.deepEqual(q.visto.map(v => v.modelo),
        ['inworld-ai/realtime-tts-2', 'inworld-ai/realtime-tts-2'])
      assert.equal(config.precioVozPorMChar, 35)

      process.env.VOZ_MUJER = 'Luna'
      const r = proveedor()
      await sintetizar('hola', 'hombre', r.fn)
      assert.equal(r.visto[0]!.voz, 'Luna')
    } finally {
      process.env.VOZ_BASE_URL = antes.VOZ_BASE_URL
      process.env.VOZ_MUJER = antes.VOZ_MUJER
    }
  })
})
