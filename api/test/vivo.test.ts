import './_setup.ts'
import assert from 'node:assert/strict'
import { after, describe, test } from 'node:test'

import type { Turno } from '../src/charla.ts'

const { turnoEnVivo, trama } = await import('../src/vivo.ts')
const { MENSAJE_DE_CORTE } = await import('../src/charla.ts')
const { RecorteEnVivo, LectorDeAudioEnVivo, ajustarSilencios, escribirWav, aBytes } = await import('../src/silencios.ts')
const { cerrarPool } = await import('../src/db.ts')

after(async () => { await cerrarPool() })

const HOY = '2027-06-15'
const vos = (t: string): Turno => ({ de: 'vos', texto: t })
const pausa = (ms: number) => new Promise(r => setTimeout(r, ms))

/// Desarma lo que salió por la conexión en sus tramas.
function leer(salida: Buffer[]) {
  const todo = Buffer.concat(salida)
  const tramas: { tipo: string; cuerpo: Buffer }[] = []
  let i = 0
  while (i < todo.length) {
    const largo = todo.readUInt32BE(i + 1)
    tramas.push({ tipo: todo.toString('latin1', i, i + 1), cuerpo: todo.subarray(i + 5, i + 5 + largo) })
    i += 5 + largo
  }
  return tramas
}

/// Un modelo de mentira que escribe el texto de a pedacitos.
const modelo = (texto: string, cada = 7) => (async (_p: never, alLlegar: (t: string) => void) => {
  for (let i = cada; i < texto.length; i += cada) { alLlegar(texto.slice(0, i)); await pausa(1) }
  alLlegar(texto)
  return { datos: texto, crudo: {} }
}) as never

/// Una voz de mentira: el "audio" de una frase es la frase misma, en bytes, para
/// poder leer en qué orden salió. `tarda` y `falla` son por frase.
function voz(opciones: { tarda?: (f: string) => number; falla?: (f: string) => boolean } = {}) {
  const pedidas: string[] = []
  const fn = (async (frase: string, _t: string, alLlegar: (pcm: Buffer, hz: number) => void) => {
    pedidas.push(frase)
    await pausa(opciones.tarda?.(frase) ?? 1)
    if (opciones.falla?.(frase)) throw new Error('TTS 503')
    const b = Buffer.from(`[${frase}]`, 'utf8')
    alLlegar(b.subarray(0, 4), 24000)
    await pausa(1)
    alLlegar(b.subarray(4), 24000)
  }) as never
  return { fn, pedidas }
}

const TEXTO = 'Qué duro lo que me cuentas de tu jefe. Que te regañen en público duele bastante. ¿Qué pasó después?'
const sinRecuerdos = async () => []

async function correr(dep: { llamada: never; sintesis: never }, senal = new AbortController().signal) {
  const salida: Buffer[] = []
  const r = await turnoEnVivo({ turnos: [vos('hola')], dia: HOY }, 'mujer', t => salida.push(t), senal,
                              { ...dep, recordarFn: sinRecuerdos })
  const tramas = leer(salida)
  const audio = Buffer.concat(tramas.filter(t => t.tipo === 'A').map(t => t.cuerpo))
    .toString('utf8').replace(/\0+/g, ' ')
  const fin = tramas.filter(t => t.tipo === 'F').map(t => JSON.parse(t.cuerpo.toString('utf8')))
  return { r, tramas, audio, fin }
}

describe('el turno en vivo', () => {
  test('cada oración se pide por separado, apenas está completa', async () => {
    const v = voz()
    await correr({ llamada: modelo(TEXTO), sintesis: v.fn })
    assert.deepEqual(v.pedidas, [
      'Qué duro lo que me cuentas de tu jefe.',
      'Que te regañen en público duele bastante.',
      '¿Qué pasó después?',
    ])
  })

  /// Los pedidos corren a la vez y el segundo puede llegar antes que el primero.
  test('el audio sale en el orden del texto aunque llegue desordenado', async () => {
    const v = voz({ tarda: f => f.startsWith('Qué duro') ? 40 : 1 })
    const { audio, fin } = await correr({ llamada: modelo(TEXTO), sintesis: v.fn })
    assert.equal(audio,
      '[Qué duro lo que me cuentas de tu jefe.] [Que te regañen en público duele bastante.] [¿Qué pasó después?]')
    assert.deepEqual(fin, [{ ok: true, texto: TEXTO, hablado: TEXTO.length }])
  })

  test('la frecuencia va una sola vez y antes del primer audio', async () => {
    const { tramas } = await correr({ llamada: modelo(TEXTO), sintesis: voz().fn })
    const tipos = tramas.map(t => t.tipo).join('')
    assert.equal(tipos.replace(/[^H]/g, ''), 'H')
    assert.ok(tipos.indexOf('H') < tipos.indexOf('A'))
    assert.equal(tramas.find(t => t.tipo === 'H')!.cuerpo.toString(), '24000')
    assert.equal(tipos.at(-1), 'F', 'la F es lo último')
  })

  test('el texto va llegando, y el último es el definitivo', async () => {
    const { tramas } = await correr({ llamada: modelo(TEXTO), sintesis: voz().fn })
    const textos = tramas.filter(t => t.tipo === 'T').map(t => t.cuerpo.toString('utf8'))
    assert.ok(textos.length > 3)
    assert.equal(textos.at(-1), TEXTO)
    for (const t of textos) assert.ok(TEXTO.startsWith(t))
  })

  /// Si la voz falla a mitad de camino, lo que venía detrás NO sale aunque
  /// haya llegado bien, y `hablado` dice hasta dónde: el teléfono dice el resto
  /// con la voz de iOS. Saltearse una oración no puede pasar.
  test('si una oración falla, la voz se corta ahí y hablado lo dice', async () => {
    const v = voz({ falla: f => f.startsWith('Que te regañen') })
    const { audio, fin } = await correr({ llamada: modelo(TEXTO), sintesis: v.fn })
    assert.equal(audio, '[Qué duro lo que me cuentas de tu jefe.]')
    assert.equal(fin[0].ok, true)
    assert.equal(fin[0].hablado, 'Qué duro lo que me cuentas de tu jefe.'.length)
    assert.equal(TEXTO.slice(fin[0].hablado).trim(), 'Que te regañen en público duele bastante. ¿Qué pasó después?')
  })

  test('sin voz en absoluto, el texto llega igual y hablado es cero', async () => {
    const { audio, fin } = await correr({ llamada: modelo(TEXTO), sintesis: voz({ falla: () => true }).fn })
    assert.equal(audio, '')
    assert.deepEqual(fin, [{ ok: true, texto: TEXTO, hablado: 0 }])
  })

  /// Cuando la persona escribe, Bitácora no habla: el teléfono no manda timbre.
  /// El texto sale igual, y no se pide ni una frase de audio.
  test('sin timbre va sólo el texto, y no se pide voz', async () => {
    const v = voz()
    const salida: Buffer[] = []
    await turnoEnVivo({ turnos: [vos('hola')], dia: HOY }, null, t => salida.push(t),
                      new AbortController().signal,
                      { llamada: modelo(TEXTO), sintesis: v.fn, recordarFn: sinRecuerdos })
    const tramas = leer(salida)
    assert.deepEqual(v.pedidas, [])
    assert.equal(tramas.filter(t => t.tipo === 'A' || t.tipo === 'H').length, 0)
    assert.ok(tramas.filter(t => t.tipo === 'T').length > 3, 'el texto va llegando igual')
    assert.deepEqual(JSON.parse(tramas.at(-1)!.cuerpo.toString('utf8')), { ok: true, texto: TEXTO, hablado: 0 })
  })

  test('si el modelo falla, termina con la despedida fija', async () => {
    const roto = (async () => { throw new Error('LLM 503') }) as never
    const { r, fin } = await correr({ llamada: roto, sintesis: voz().fn })
    assert.equal(r.ok, false)
    assert.deepEqual(fin, [{ ok: false, texto: MENSAJE_DE_CORTE, hablado: 0 }])
  })

  /// La persona interrumpió: el teléfono cerró la conexión. No hay a quién
  /// mandarle una despedida.
  test('si el que cortó fue el teléfono, no se manda nada más', async () => {
    const corte = new AbortController()
    const cortado = (async () => { corte.abort(); throw new Error('aborted') }) as never
    const { fin } = await correr({ llamada: cortado, sintesis: voz().fn }, corte.signal)
    assert.deepEqual(fin, [])
  })

  test('una trama es un byte de tipo, cuatro de largo y el contenido', () => {
    assert.deepEqual([...trama('T', 'hé')], [0x54, 0, 0, 0, 3, 0x68, 0xc3, 0xa9])
  })
})

describe('el recorte de silencios, de a pedazos', () => {
  const HZ = 24000
  const ms = (n: number) => Math.round(HZ * n / 1000)
  function audio(...tramos: [boolean, number][]): Int16Array {
    const pcm = new Int16Array(tramos.reduce((n, [, d]) => n + ms(d), 0))
    let o = 0
    for (const [suena, d] of tramos) { if (suena) pcm.fill(5000, o, o + ms(d)); o += ms(d) }
    return pcm
  }
  const silencios = (pcm: Int16Array) => {
    const r: number[] = []; let n = 0
    for (const v of pcm) { if (v === 0) n++; else if (n) { r.push(Math.round(n / HZ * 1000)); n = 0 } }
    if (n) r.push(Math.round(n / HZ * 1000))
    return r
  }
  const entrada = audio([false, 250], [true, 800], [false, 560], [true, 1200], [false, 90], [true, 400], [false, 400])

  function enPedazos(pcm: Int16Array, tamano: number, techo = 300): Int16Array {
    const r = new RecorteEnVivo(HZ, techo)
    const partes: number[] = []
    for (let i = 0; i < pcm.length; i += tamano) partes.push(...r.pasar(pcm.subarray(i, i + tamano)))
    partes.push(...r.cerrar())
    return Int16Array.from(partes)
  }

  test('saca el principio, le pone techo a las pausas y deja media pausa al final', () => {
    assert.deepEqual(silencios(enPedazos(entrada, 1000)), [20, 300, 90, 150])
  })

  /// Los pedazos de red llegan de cualquier tamaño. El resultado no puede
  /// depender de dónde cayó el corte.
  test('da lo mismo llegue como llegue partido', () => {
    const entero = enPedazos(entrada, entrada.length)
    for (const tamano of [1, 37, 240, 1001, 4096]) {
      assert.deepEqual(enPedazos(entrada, tamano), entero, `partido de a ${tamano}`)
    }
  })

  test('la voz es la misma que deja la versión de audio entero', () => {
    const deVoz = (p: Int16Array) => p.filter(v => v !== 0).length
    assert.equal(deVoz(enPedazos(entrada, 777)), deVoz(ajustarSilencios(entrada, HZ, 300)))
  })

  test('con el techo en cero las pausas del medio pasan enteras', () => {
    assert.deepEqual(silencios(enPedazos(entrada, 1000, 0)).slice(0, 3), [20, 560, 90])
  })
})

describe('el audio en streaming del proveedor', () => {
  /// Así llega: una seguidilla de WAV chicos, cada uno con su encabezado.
  const uno = Int16Array.from([1, 2, 3, 4, 5])
  const dos = Int16Array.from([6, 7, 8])
  const flujo = Buffer.concat([escribirWav({ hz: 24000, pcm: uno }), escribirWav({ hz: 24000, pcm: dos })])

  test('saca los encabezados y deja las muestras seguidas', () => {
    const l = new LectorDeAudioEnVivo()
    assert.deepEqual([...l.pasar(flujo)], [1, 2, 3, 4, 5, 6, 7, 8])
    assert.equal(l.hz, 24000)
  })

  /// Un encabezado partido entre dos pedazos de red, o una muestra de dos
  /// bytes cortada al medio: lo que no puede pasar es que un encabezado
  /// termine sonando.
  test('aunque los pedazos de red corten en cualquier lado', () => {
    for (const tamano of [1, 3, 7, 44, 45, 50]) {
      const l = new LectorDeAudioEnVivo()
      const r: number[] = []
      for (let i = 0; i < flujo.length; i += tamano) r.push(...l.pasar(flujo.subarray(i, i + tamano)))
      assert.deepEqual(r, [1, 2, 3, 4, 5, 6, 7, 8], `partido de a ${tamano}`)
    }
  })

  test('si llegan muestras crudas, sin encabezado, pasan como están', () => {
    const crudo = aBytes(Int16Array.from(Array.from({ length: 40 }, (_, i) => i + 100)))
    const l = new LectorDeAudioEnVivo()
    assert.equal(l.pasar(crudo).length, 40)
    assert.equal(l.hz, 24000)
  })
})
