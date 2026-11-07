import './_setup.ts'
import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import { pool } from '../src/db.ts'
import { llamarConStream, type Herramienta } from '../src/llm.ts'
import { recordarDias } from '../src/memoria.ts'

after(async () => {
  await pool.query("delete from resumenes_dia where dia between '2020-03-01' and '2020-03-31'")
  await pool.end()
})

/// Un proveedor de mentira que contesta en SSE: primero pide la herramienta,
/// después habla con lo que recibió.
function sse(lineas: unknown[]): Response {
  const cuerpo = lineas.map(l => `data: ${JSON.stringify(l)}\n\n`).join('') + 'data: [DONE]\n\n'
  return new Response(cuerpo, { status: 200, headers: { 'content-type': 'text/event-stream' } })
}

test('la charla pide una herramienta, la usa y sigue hablando', async () => {
  const pedidos: { messages: { role: string; content?: string }[]; tools?: unknown[] }[] = []
  const original = globalThis.fetch
  globalThis.fetch = (async (_u: unknown, init?: { body?: string }) => {
    pedidos.push(JSON.parse(init!.body!))
    if (pedidos.length === 1) return sse([
      { choices: [{ delta: { tool_calls: [{ index: 0, id: 'x1', function: { name: 'recordar_tema', arguments: '' } }] } }] },
      { choices: [{ delta: { tool_calls: [{ index: 0, function: { arguments: '{"tema":"dormir"}' } }] } }] },
      { usage: { prompt_tokens: 10, completion_tokens: 2 } },
    ])
    return sse([{ choices: [{ delta: { content: 'En septiembre te costaba ' } }] },
                { choices: [{ delta: { content: 'dormir.' } }] }, { usage: { prompt_tokens: 20, completion_tokens: 5 } }])
  }) as typeof fetch
  try {
    const recibidos: Record<string, unknown>[] = []
    const h: Herramienta = { nombre: 'recordar_tema', descripcion: '', parametros: {},
                             ejecutar: async (a) => { recibidos.push(a); return 'le cuesta dormir (6 veces)' } }
    const vistos: string[] = []
    const r = await llamarConStream({ tarea: 'charla', refId: null, sistema: 's', usuario: '¿te acuerdas?',
                                      herramientas: [h], sinGuardDePresupuesto: true }, t => vistos.push(t))
    assert.equal(r.datos, 'En septiembre te costaba dormir.')
    assert.deepEqual(recibidos, [{ tema: 'dormir' }])
    assert.equal(pedidos.length, 2)
    const tool = pedidos[1]!.messages.find(m => m.role === 'tool')
    assert.equal(tool?.content, 'le cuesta dormir (6 veces)')
    assert.ok(vistos.at(-1)?.endsWith('dormir.'))
  } finally {
    globalThis.fetch = original
  }
})

test('recordar unos días trae los resúmenes de ese tramo, y no más de un mes', async () => {
  await pool.query(`insert into resumenes_dia (dia, resumen, n_entradas) values
    ('2020-03-02', 'Habló de que le costó dormir.', 1), ('2020-03-20', 'Fue un día tranquilo.', 1)
    on conflict (dia) do nothing`)
  const t = await recordarDias('2020-03-01', '2020-03-10')
  assert.match(t, /2020-03-02: Habló de que le costó dormir/)
  assert.doesNotMatch(t, /tranquilo/)
  assert.match(await recordarDias('2019-01-01', '2019-01-05'), /No hay nada guardado/)
})
