/// Le saca a un audio de voz los silencios que sobran.
///
/// POR QUÉ. Dusan dijo que las voces nuevas le encantan pero que «se traban»,
/// con «pausas de alguien que no sabe leer». Medido sobre el audio que devuelve
/// el proveedor, una respuesta de diez segundos trae entre dos y tres de
/// silencio: un cuarto de segundo antes de la primera palabra, otro tanto
/// después de la última, y pausas de medio segundo largo en cada coma y en cada
/// punto. Nadie habla así. El modelo no acepta un parámetro de velocidad —se
/// probaron `speed` y `speaking_rate` y el audio dura lo mismo—, así que lo que
/// no se le puede pedir se corrige después.
///
/// SON TRES COSAS:
///
///   1. El silencio del principio se va. Es espera pura: lo que tarda Bitácora en
///      empezar a hablar, con el audio ya en la mano.
///   2. El del final se acorta. Entre dos pedazos de un mismo turno se sumaban
///      el final de uno y el principio del otro, y eso era casi un segundo
///      entre oración y oración.
///   3. Las pausas del medio tienen techo. No se sacan: una pausa es parte de
///      hablar. Pero una coma no dura más que un punto.
///
/// NO SE TOCA NI UNA MUESTRA DE VOZ. Sólo se quitan tramos que ya eran silencio,
/// y se corta por el medio del tramo, así que lo que queda a cada lado sigue
/// siendo silencio y el empalme no hace ruido.

/// Abajo de esto, un tramo es silencio. Es el 1% de la escala: el audio del
/// proveedor trae silencio digital exacto, así que cualquier umbral bajo sirve,
/// y éste deja afuera las respiraciones, que sí son parte de la voz.
const UMBRAL = 328
/// Se mira de a diez milisegundos.
const TRAMO_MS = 10
/// Lo que queda antes de la primera palabra y después de la última.
const ANTES_MS = 20
const DESPUES_MS = 120
/// Una pausa más corta que esto no se considera pausa: es el hueco natural
/// entre dos palabras o adentro de una consonante.
const PAUSA_MIN_MS = 120

export function ajustarSilencios(pcm: Int16Array, hz: number, pausaMaxMs: number): Int16Array {
  const porTramo = Math.round(hz * TRAMO_MS / 1000)
  const tramos = Math.floor(pcm.length / porTramo)
  if (tramos === 0) return pcm

  const callado = new Array<boolean>(tramos)
  for (let t = 0; t < tramos; t++) {
    let pico = 0
    for (let i = t * porTramo; i < (t + 1) * porTramo; i++) {
      const a = Math.abs(pcm[i]!)
      if (a > pico) pico = a
    }
    callado[t] = pico < UMBRAL
  }

  // Si todo es silencio no hay nada que ajustar: se devuelve como vino.
  const primero = callado.indexOf(false)
  if (primero === -1) return pcm
  const ultimo = callado.lastIndexOf(false)

  const enTramos = (ms: number) => Math.round(ms / TRAMO_MS)
  /// Qué tramos se quedan.
  const queda = new Array<boolean>(tramos).fill(true)

  for (let t = 0; t < primero - enTramos(ANTES_MS); t++) queda[t] = false
  for (let t = ultimo + 1 + enTramos(DESPUES_MS); t < tramos; t++) queda[t] = false

  if (pausaMaxMs > 0) {
    const techo = Math.max(enTramos(pausaMaxMs), enTramos(PAUSA_MIN_MS))
    let t = primero
    while (t <= ultimo) {
      if (!callado[t]) { t++; continue }
      let fin = t
      while (fin <= ultimo && callado[fin]) fin++
      const largo = fin - t
      if (largo > techo) {
        // Se corta el medio: quedan la primera mitad del techo, pegada a la
        // palabra que termina, y la segunda, pegada a la que empieza.
        const adelante = Math.ceil(techo / 2)
        const atras = techo - adelante
        for (let k = t + adelante; k < fin - atras; k++) queda[k] = false
      }
      t = fin
    }
  }

  const cuantos = queda.reduce((n, q) => n + (q ? 1 : 0), 0)
  // Lo que sobra después del último tramo entero (menos de diez milisegundos)
  // sólo se conserva si el final no se recortó.
  const cola = queda[tramos - 1] ? pcm.length - tramos * porTramo : 0
  const salida = new Int16Array(cuantos * porTramo + cola)
  let o = 0
  for (let t = 0; t < tramos; t++) {
    if (!queda[t]) continue
    salida.set(pcm.subarray(t * porTramo, (t + 1) * porTramo), o)
    o += porTramo
  }
  if (cola > 0) salida.set(pcm.subarray(tramos * porTramo), o)
  return salida
}

/// Lo mismo que `ajustarSilencios`, pero de a pedazos, mientras el audio llega.
///
/// La versión de arriba necesita el audio entero para saber dónde empieza y
/// dónde termina cada pausa. Con la voz en streaming no hay audio entero: los
/// pedazos se mandan al teléfono apenas llegan, y esperar al final para
/// recortar sería tirar justo lo que el streaming gana.
///
/// La regla es la misma y se puede decidir sobre la marcha. De un silencio se
/// deja pasar la primera mitad del techo apenas llega. Lo que sigue se retiene,
/// guardando sólo lo último; cuando vuelve la voz se suelta eso, que es la
/// segunda mitad. Lo del medio nunca se manda. Una pausa más corta que el techo
/// sale entera.
///
/// El silencio del final se queda en esa primera mitad: cuando el audio termina
/// lo retenido se descarta.
export class RecorteEnVivo {
  private readonly porTramo: number
  private readonly adelante: number
  private readonly atras: number
  private readonly conTecho: boolean
  /// Lo que todavía no llena un tramo.
  private pendiente: number[] = []
  private empezo = false
  /// Los últimos tramos de silencio antes de la primera palabra.
  private previo: Int16Array[] = []
  /// Cuántos tramos lleva el silencio en curso.
  private racha = 0
  /// Lo retenido de ese silencio: como mucho, la segunda mitad del techo.
  private retenido: Int16Array[] = []

  constructor(hz: number, pausaMaxMs: number) {
    this.porTramo = Math.round(hz * TRAMO_MS / 1000)
    this.conTecho = pausaMaxMs > 0
    const techo = Math.max(Math.round(pausaMaxMs / TRAMO_MS), Math.round(PAUSA_MIN_MS / TRAMO_MS))
    this.adelante = Math.ceil(techo / 2)
    this.atras = techo - this.adelante
  }

  /// Recibe muestras y devuelve las que ya se pueden mandar.
  pasar(pcm: Int16Array): Int16Array {
    const salida: Int16Array[] = []
    for (const m of pcm) {
      this.pendiente.push(m)
      if (this.pendiente.length === this.porTramo) {
        this.tramo(Int16Array.from(this.pendiente), salida)
        this.pendiente = []
      }
    }
    return unir(salida)
  }

  /// El audio terminó. Devuelve lo último que queda por mandar.
  cerrar(): Int16Array {
    // Menos de diez milisegundos sueltos: sólo valen si venían pegados a voz.
    const cola = this.empezo && this.racha === 0 ? Int16Array.from(this.pendiente) : new Int16Array(0)
    this.pendiente = []
    this.retenido = []
    return cola
  }

  private tramo(t: Int16Array, salida: Int16Array[]): void {
    let pico = 0
    for (const m of t) { const a = Math.abs(m); if (a > pico) pico = a }

    if (pico < UMBRAL) {
      if (!this.empezo) {
        this.previo.push(t)
        if (this.previo.length > Math.round(ANTES_MS / TRAMO_MS)) this.previo.shift()
        return
      }
      this.racha++
      if (!this.conTecho || this.racha <= this.adelante) { salida.push(t); return }
      this.retenido.push(t)
      if (this.retenido.length > this.atras) this.retenido.shift()
      return
    }

    if (!this.empezo) {
      this.empezo = true
      salida.push(...this.previo)
      this.previo = []
    }
    salida.push(...this.retenido, t)
    this.retenido = []
    this.racha = 0
  }
}

function unir(partes: Int16Array[]): Int16Array {
  const total = partes.reduce((n, p) => n + p.length, 0)
  const r = new Int16Array(total)
  let o = 0
  for (const p of partes) { r.set(p, o); o += p.length }
  return r
}

/// Separa el audio en streaming del proveedor en sus muestras.
///
/// Pedido como `pcm` en streaming, el proveedor NO manda muestras sueltas:
/// manda una seguidilla de WAV chicos, cada uno con su encabezado de cuarenta
/// y cuatro bytes. Reproducido tal cual, cada encabezado es un chasquido cada
/// medio segundo. Esto los saca, y de paso lee de ahí la frecuencia.
///
/// Los pedazos de red no coinciden con los WAV: un encabezado puede llegar
/// partido en dos, y una muestra de dos bytes también.
///
/// Si lo que llega no arranca con "RIFF", se toma como muestras crudas a 24 kHz
/// y se deja pasar: es lo que el nombre del formato promete, y si el proveedor
/// algún día lo cumple no hay que romperse.
export class LectorDeAudioEnVivo {
  hz = 24000
  private resto: Buffer = Buffer.alloc(0)
  /// Bytes de muestras que faltan del WAV en curso. -1: todo lo que venga.
  private faltan = 0

  pasar(pedazo: Buffer): Int16Array {
    this.resto = this.resto.length ? Buffer.concat([this.resto, pedazo]) : pedazo
    const partes: Buffer[] = []

    for (;;) {
      if (this.faltan === 0) {
        if (this.resto.length < 44) break
        if (this.resto.toString('latin1', 0, 4) === 'RIFF'
            && this.resto.toString('latin1', 36, 40) === 'data') {
          this.hz = this.resto.readUInt32LE(24)
          this.faltan = this.resto.readUInt32LE(40)
          this.resto = this.resto.subarray(44)
          continue
        }
        this.faltan = -1
      }
      if (this.resto.length === 0) break
      if (this.faltan === -1) { partes.push(this.resto); this.resto = Buffer.alloc(0); break }
      const n = Math.min(this.faltan, this.resto.length)
      partes.push(this.resto.subarray(0, n))
      this.resto = this.resto.subarray(n)
      this.faltan -= n
    }

    const bytes = this.sobra.length ? Buffer.concat([this.sobra, ...partes]) : Buffer.concat(partes)
    const pares = bytes.length - (bytes.length % 2)
    this.sobra = bytes.subarray(pares)
    const pcm = new Int16Array(pares / 2)
    for (let k = 0; k < pcm.length; k++) pcm[k] = bytes.readInt16LE(k * 2)
    return pcm
  }

  /// El byte suelto de una muestra que llegó partida.
  private sobra: Buffer = Buffer.alloc(0)
}

/// Muestras a bytes, como viajan.
export function aBytes(pcm: Int16Array): Buffer {
  const b = Buffer.alloc(pcm.length * 2)
  for (let k = 0; k < pcm.length; k++) b.writeInt16LE(pcm[k]!, k * 2)
  return b
}

export interface Wav {
  hz: number
  pcm: Int16Array
}

/// Lee un WAV de 16 bits mono. `null` si es otra cosa, y ahí el audio se manda
/// como vino: mejor una pausa de más que un ruido.
///
/// El proveedor manda el encabezado DOS veces: adentro del bloque de datos del
/// primero hay otro WAV entero. Leído al pie de la letra, esos cuarenta y
/// cuatro bytes de encabezado sonarían como un chasquido al empezar. Por eso,
/// si los datos empiezan con otro "RIFF", se lee ése.
export function leerWav(b: Buffer): Wav | null {
  if (b.length < 44 || b.toString('latin1', 0, 4) !== 'RIFF' || b.toString('latin1', 8, 12) !== 'WAVE') return null

  let hz = 0
  let ok = false
  let i = 12
  while (i + 8 <= b.length) {
    const id = b.toString('latin1', i, i + 4)
    const largo = b.readUInt32LE(i + 4)
    const desde = i + 8
    if (id === 'fmt ') {
      if (desde + 16 > b.length) return null
      const pcm = b.readUInt16LE(desde) === 1
      const mono = b.readUInt16LE(desde + 2) === 1
      const bits = b.readUInt16LE(desde + 14)
      hz = b.readUInt32LE(desde + 4)
      ok = pcm && mono && bits === 16 && hz > 0
    } else if (id === 'data') {
      if (!ok) return null
      // Un tamaño que se pasa del archivo (los WAV generados al vuelo a veces
      // lo traen mal) se recorta a lo que hay.
      const datos = b.subarray(desde, Math.min(b.length, desde + largo))
      if (datos.length >= 12 && datos.toString('latin1', 0, 4) === 'RIFF') {
        return leerWav(Buffer.from(datos))
      }
      const muestras = Math.floor(datos.length / 2)
      const pcm = new Int16Array(muestras)
      for (let k = 0; k < muestras; k++) pcm[k] = datos.readInt16LE(k * 2)
      return { hz, pcm }
    }
    i = desde + largo + (largo % 2)
  }
  return null
}

/// Arma un WAV de 16 bits mono con un solo encabezado.
export function escribirWav({ hz, pcm }: Wav): Buffer {
  const datos = pcm.length * 2
  const b = Buffer.alloc(44 + datos)
  b.write('RIFF', 0, 'latin1')
  b.writeUInt32LE(36 + datos, 4)
  b.write('WAVE', 8, 'latin1')
  b.write('fmt ', 12, 'latin1')
  b.writeUInt32LE(16, 16)
  b.writeUInt16LE(1, 20)          // PCM
  b.writeUInt16LE(1, 22)          // mono
  b.writeUInt32LE(hz, 24)
  b.writeUInt32LE(hz * 2, 28)     // bytes por segundo
  b.writeUInt16LE(2, 32)          // bytes por muestra
  b.writeUInt16LE(16, 34)
  b.write('data', 36, 'latin1')
  b.writeUInt32LE(datos, 40)
  for (let k = 0; k < pcm.length; k++) b.writeInt16LE(pcm[k]!, 44 + k * 2)
  return b
}
