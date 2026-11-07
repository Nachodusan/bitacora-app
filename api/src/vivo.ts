import { llamarConStream, verificarPresupuesto } from './llm.ts'
import { armarPedido, finDeFrase, sinMarkdown, MENSAJE_DE_CORTE, type PedidoDeCharla } from './charla.ts'
import { sintetizarEnVivo, type TimbreVoz } from './voz.ts'
import { recordar } from './recuerdos.ts'
import { haySenalEnLaCharla, MENSAJE_DE_RIESGO } from './riesgo.ts'

/// El turno de Bitácora, en vivo: el texto y la voz salen mientras se generan.
///
/// POR QUÉ. Hasta acá el turno era un pedido y una respuesta: el teléfono
/// esperaba el texto entero y el audio de la primera oración, y recién ahí
/// sonaba algo. Con una primera oración larga eran cinco o seis segundos de
/// silencio. Y el resto del turno se pedía después, por pedazos.
///
/// Acá es una sola conexión que no se cierra hasta que el turno termina. Apenas
/// el modelo completa una oración, esa oración se manda a sintetizar en
/// streaming y el audio empieza a salir medio segundo después, mientras el
/// modelo sigue escribiendo la que sigue. El teléfono reproduce lo que va
/// llegando. Bitácora empieza a hablar cuando tiene la primera oración, no cuando
/// tiene todo.
///
/// LO QUE VIAJA son tramas: un byte que dice qué es, cuatro con el largo, y el
/// contenido.
///
///   T  el texto de Bitácora hasta ahora, entero (el teléfono reemplaza, no suma)
///   H  la frecuencia del audio, en hertz, como texto. Una vez, antes del audio
///   A  audio: muestras de 16 bits, mono, little-endian
///   F  el final, en JSON: `ok`, el `texto` definitivo y `hablado`. Con
///      `cuidado: true` el texto es el mensaje fijo de riesgo y la charla se
///      cierra (ver `riesgo.ts`)
///
/// `hablado` es hasta qué caracter del texto llegó el audio. Si la voz falló a
/// mitad de camino —sin presupuesto, el proveedor caído— es menor que el largo
/// del texto, y el teléfono dice lo que falta con la voz de iOS. Es la misma
/// regla de siempre: que suene peor es mejor que que se calle.
///
/// Si el turno entero falla, la F viene con `ok: false` y la despedida fija,
/// igual que en `/charla`.

export type Tipo = 'T' | 'H' | 'A' | 'F'

export function trama(tipo: Tipo, contenido: Buffer | string): Buffer {
  const cuerpo = typeof contenido === 'string' ? Buffer.from(contenido, 'utf8') : contenido
  const cabeza = Buffer.alloc(5)
  cabeza.write(tipo, 0, 'latin1')
  cabeza.writeUInt32BE(cuerpo.length, 1)
  return Buffer.concat([cabeza, cuerpo])
}

/// Lo que se deja entre el audio de una oración y el de la siguiente. Cada
/// audio ya trae su parte de silencio al final y al principio; con esto la
/// pausa entre oraciones queda parecida a la que el modelo hace adentro de un
/// mismo audio, que es el techo de `VOZ_PAUSA_MAX_MS`.
const ENTRE_ORACIONES_MS = 130

type Sintesis = typeof sintetizarEnVivo

interface Pieza {
  /// Hasta qué caracter del texto llega esta pieza.
  hasta: number
  /// El audio que llegó antes de que le tocara salir.
  guardado: Buffer[]
  lista: boolean
  fallo: boolean
}

/// Convierte el texto que va llegando en audio que sale EN ORDEN.
///
/// Cada oración se pide apenas está completa, así que hay varios pedidos al
/// proveedor corriendo a la vez. El audio de la segunda puede empezar a llegar
/// antes de que termine el de la primera; se guarda y sale cuando le toca.
class ColaDeVoz {
  /// El texto ya mandado a sintetizar. Siempre es el comienzo exacto del texto.
  private pedido = ''
  private piezas: Pieza[] = []
  private pendientes: Promise<void>[] = []
  /// La pieza cuyo audio está saliendo.
  private actual = 0
  private cortada = false
  private hz: number | null = null
  private salioAudio = false
  /// Hay que dejar un silencio antes del próximo audio que salga: terminó una
  /// oración y la que sigue todavía no empezó a llegar.
  private pausaPendiente = false
  hablado = 0

  constructor(
    private readonly timbre: TimbreVoz,
    private readonly emitir: (t: Buffer) => void,
    private readonly senal: AbortSignal,
    private readonly sintesis: Sintesis,
  ) {}

  /// Llega más texto. Manda a sintetizar las oraciones que ya estén completas;
  /// con `final`, también lo que quede.
  avanzar(texto: string, final: boolean): void {
    // `sinMarkdown` puede cambiar algo que ya se pidió (un asterisco que se
    // cierra más tarde). Es raro, y si pasa no se pide más audio: mandar voz
    // que no coincide con el texto es peor que terminar con la de iOS.
    if (!texto.startsWith(this.pedido)) return

    for (;;) {
      const resto = texto.slice(this.pedido.length)
      const n = finDeFrase(resto)
      if (n !== null) { this.pedir(resto.slice(0, n)); continue }
      if (final && resto.trim()) this.pedir(resto)
      return
    }
  }

  private pedir(fragmento: string): void {
    this.pedido += fragmento
    const i = this.piezas.length
    const pieza: Pieza = { hasta: this.pedido.length, guardado: [], lista: false, fallo: false }
    this.piezas.push(pieza)

    this.pendientes.push(
      this.sintesis(fragmento.trim(), this.timbre, (pcm, hz) => this.llego(i, pcm, hz), this.senal)
        .then(() => { pieza.lista = true }, () => { pieza.fallo = true })
        .then(() => this.seguir()),
    )
  }

  private llego(i: number, pcm: Buffer, hz: number): void {
    if (this.cortada) return
    if (this.hz === null) { this.hz = hz; this.emitir(trama('H', String(hz))) }
    if (i === this.actual) this.sacar(pcm)
    else this.piezas[i]!.guardado.push(pcm)
  }

  private sacar(pcm: Buffer): void {
    if (this.pausaPendiente && this.hz) {
      this.emitir(trama('A', Buffer.alloc(Math.round(this.hz * ENTRE_ORACIONES_MS / 1000) * 2)))
    }
    this.pausaPendiente = false
    this.emitir(trama('A', pcm))
    this.salioAudio = true
  }

  /// Terminó una pieza: si era la que estaba saliendo, pasa a la siguiente.
  private seguir(): void {
    while (!this.cortada && this.actual < this.piezas.length) {
      const p = this.piezas[this.actual]!
      // Una pieza que falló corta la voz ahí. Lo que venía detrás no sale
      // aunque haya llegado bien: saltearse una oración es peor que cambiar de
      // voz, y el teléfono retoma desde `hablado` con la de iOS.
      if (p.fallo) { this.cortada = true; return }
      if (!p.lista) return

      this.hablado = p.hasta
      this.actual++
      // La pausa no se manda acá sino con el primer audio de lo que sigue: la
      // oración siguiente puede no haberse pedido todavía, y si era la última
      // del turno no hay nada que separar.
      this.pausaPendiente = this.salioAudio
      const sigue = this.piezas[this.actual]
      if (!sigue) return
      for (const pcm of sigue.guardado) this.sacar(pcm)
      sigue.guardado = []
    }
  }

  /// Espera a que termine todo lo pedido. Devuelve hasta dónde llegó la voz.
  async terminar(): Promise<number> {
    await Promise.all(this.pendientes)
    return this.hablado
  }
}

/// Genera el turno y lo va emitiendo. No tira: si algo falla, lo dice con una F.
///
/// `senal` se dispara cuando el teléfono cierra la conexión —la persona
/// interrumpió a Bitácora, o cortó la charla—. Con eso se cortan el texto y los
/// audios que estén en camino: nadie los va a escuchar.
///
/// SIN TIMBRE NO HAY VOZ. Es lo que manda el teléfono cuando la persona
/// escribe en vez de hablar: Dusan pidió que Bitácora sólo hable en llamada. El
/// texto sale igual, mientras se escribe, y no se pide —ni se paga— audio.
export async function turnoEnVivo(
  p: PedidoDeCharla,
  timbre: TimbreVoz | null,
  emitir: (t: Buffer) => void,
  senal: AbortSignal,
  dep: { llamada?: typeof llamarConStream; sintesis?: Sintesis; recordarFn?: typeof recordar } = {},
): Promise<{ ok: boolean; error?: unknown }> {
  const llamada = dep.llamada ?? llamarConStream

  // El corte de riesgo, antes del presupuesto y antes del modelo: el turno de
  // la persona no viaja al proveedor. Llega sólo la F, con `cuidado` y
  // `hablado: 0`, y sin audio aunque haya timbre: el mensaje lo dice la voz
  // del teléfono. Un teléfono que no conozca `cuidado` igual lo muestra y lo
  // dice con la voz de iOS, como cualquier final con voz pendiente.
  if (haySenalEnLaCharla(p.turnos)) {
    emitir(trama('F', JSON.stringify({ ok: true, texto: MENSAJE_DE_RIESGO, hablado: 0, cuidado: true })))
    return { ok: true }
  }

  try {
    // El guard corre sólo al abrir la charla, igual que en `siguienteTurno`.
    const arranque = !p.turnos.some(t => t.de === 'bitacora')
    if (arranque) await verificarPresupuesto()

    const cola = timbre ? new ColaDeVoz(timbre, emitir, senal, dep.sintesis ?? sintetizarEnVivo) : null
    const { datos } = await llamada({
      tarea: 'charla',
      refId: null,
      ...await armarPedido(p, dep.recordarFn ?? recordar, undefined, undefined, true),
      temperatura: 0.6,
      sinGuardDePresupuesto: !arranque,
      senal,
    }, (acumulado) => {
      const hastaAhora = sinMarkdown(acumulado)
      emitir(trama('T', hastaAhora))
      cola?.avanzar(hastaAhora, false)
    })

    const texto = sinMarkdown(String(datos))
    emitir(trama('T', texto))
    cola?.avanzar(texto, true)
    const hablado = cola ? await cola.terminar() : 0
    emitir(trama('F', JSON.stringify({ ok: true, texto, hablado })))
    return { ok: true }
  } catch (e) {
    // Si el que cortó fue el teléfono, no hay a quién decirle nada.
    if (!senal.aborted) {
      emitir(trama('F', JSON.stringify({ ok: false, texto: MENSAJE_DE_CORTE, hablado: 0 })))
    }
    return { ok: false, error: e }
  }
}
