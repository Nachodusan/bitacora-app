import assert from 'node:assert/strict'
import { describe, test } from 'node:test'

import { ajustarSilencios, escribirWav, leerWav } from '../src/silencios.ts'

const HZ = 24000
const ms = (n: number) => Math.round(HZ * n / 1000)

/// Arma un audio con tramos de voz (un valor fijo y alto) y de silencio.
/// Cada tramo de voz lleva un valor distinto, para poder reconocerlo después.
function audio(...tramos: [tipo: 'voz' | 'silencio', duracionMs: number][]): Int16Array {
  const total = tramos.reduce((n, [, d]) => n + ms(d), 0)
  const pcm = new Int16Array(total)
  let o = 0, nVoz = 0
  for (const [tipo, d] of tramos) {
    if (tipo === 'voz') { nVoz++; pcm.fill(1000 * nVoz, o, o + ms(d)) }
    o += ms(d)
  }
  return pcm
}

const duracion = (pcm: Int16Array) => Math.round(pcm.length / HZ * 1000)
/// Cuánto dura cada silencio que quedó, en orden.
function silencios(pcm: Int16Array): number[] {
  const r: number[] = []
  let n = 0
  for (const v of pcm) {
    if (v === 0) n++
    else if (n > 0) { r.push(Math.round(n / HZ * 1000)); n = 0 }
  }
  if (n > 0) r.push(Math.round(n / HZ * 1000))
  return r
}
const deVoz = (pcm: Int16Array) => pcm.filter(v => v !== 0).length

describe('los silencios que sobran', () => {
  const entrada = audio(['silencio', 250], ['voz', 800], ['silencio', 560], ['voz', 1200],
                        ['silencio', 90], ['voz', 400], ['silencio', 400])

  test('el del principio se va, el del final se acorta y las pausas tienen techo', () => {
    const r = ajustarSilencios(entrada, HZ, 300)
    assert.deepEqual(silencios(r), [20, 300, 90, 120])
    assert.equal(duracion(r), 20 + 800 + 300 + 1200 + 90 + 400 + 120)
  })

  test('no se pierde ni una muestra de voz, y queda en el mismo orden', () => {
    const r = ajustarSilencios(entrada, HZ, 300)
    assert.equal(deVoz(r), deVoz(entrada))
    assert.deepEqual([...new Set(r)].filter(v => v !== 0), [1000, 2000, 3000])
  })

  test('una pausa más corta que el techo no se toca', () => {
    const r = ajustarSilencios(audio(['voz', 500], ['silencio', 200], ['voz', 500]), HZ, 300)
    assert.deepEqual(silencios(r), [200])
  })

  test('con el techo en cero las pausas del medio quedan como vinieron', () => {
    const r = ajustarSilencios(entrada, HZ, 0)
    assert.deepEqual(silencios(r), [20, 560, 90, 120])
  })

  test('un audio que es todo silencio, o vacío, vuelve igual', () => {
    const mudo = audio(['silencio', 500])
    assert.equal(ajustarSilencios(mudo, HZ, 300), mudo)
    assert.equal(ajustarSilencios(new Int16Array(0), HZ, 300).length, 0)
  })

  /// Una respiración es voz: suena bajito, pero no es silencio digital.
  test('lo que suena bajo no es silencio', () => {
    const pcm = audio(['voz', 300], ['silencio', 600], ['voz', 300])
    pcm.fill(600, ms(300), ms(900))   // la "pausa" tiene una respiración encima
    assert.equal(ajustarSilencios(pcm, HZ, 300).length, pcm.length)
  })
})

describe('el WAV', () => {
  const pcm = audio(['voz', 100], ['silencio', 50])

  test('lo que se escribe se vuelve a leer igual', () => {
    const w = leerWav(escribirWav({ hz: HZ, pcm }))
    assert.equal(w?.hz, HZ)
    assert.deepEqual(w?.pcm, pcm)
  })

  /// El proveedor manda un WAV adentro de otro. Leído literal, el encabezado
  /// de adentro sonaría como un chasquido al empezar.
  test('si viene con el encabezado repetido, se lee el de adentro', () => {
    const adentro = escribirWav({ hz: HZ, pcm })
    const afuera = Buffer.concat([escribirWav({ hz: HZ, pcm: new Int16Array(0) }), adentro])
    afuera.writeUInt32LE(36 + adentro.length, 4)
    afuera.writeUInt32LE(adentro.length, 40)
    assert.deepEqual(leerWav(afuera)?.pcm, pcm)
  })

  test('lo que no es un WAV de 16 bits mono no se toca', () => {
    assert.equal(leerWav(Buffer.from('esto no es audio, es un error del proveedor en texto')), null)
    const estereo = escribirWav({ hz: HZ, pcm })
    estereo.writeUInt16LE(2, 22)
    assert.equal(leerWav(estereo), null)
  })
})
