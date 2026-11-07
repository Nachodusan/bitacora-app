import { verificarPresupuesto, PresupuestoAgotado } from './llm.ts'
import { pool } from './db.ts'
import { config } from './config.ts'
import { aBytes, ajustarSilencios, escribirWav, leerWav, LectorDeAudioEnVivo, RecorteEnVivo } from './silencios.ts'

/// La voz de Bitácora, sintetizada acá y no en el teléfono.
///
/// POR QUÉ EXISTE. `AVSpeechSynthesizer` es on-device y gratis, y la app lo
/// exprime todo lo que se puede: puntúa las voces instaladas, prefiere las
/// mejoradas, avisa en Ajustes cuando sólo hay una compacta. Aun así Dusan dijo
/// "tiene una voz muy robótica", y tiene razón: las voces de Apple son
/// concatenativas, y ninguna cantidad de parámetros las hace sonar a persona.
///
/// POR QUÉ NO ROMPE LA REGLA DEL AUDIO. La regla es que el audio de la persona
/// no sale del teléfono: se transcribe on-device o falla a la vista. Esto es lo
/// contrario y no la toca. Lo que se manda acá es el texto que Bitácora acaba de
/// decir, que lo escribió el mismo proveedor al que se lo mandamos: ya salió del
/// teléfono, viajó entero, y volver a mandarlo para que lo lea en voz alta no
/// expone nada nuevo.
///
/// CON UN ASTERISCO DESDE EL 01/10/2026. El texto y la voz van los dos por
/// DeepInfra, pero el modelo de voz es de Inworld y figura en el catálogo como
/// modelo de un socio. No está verificado si DeepInfra lo corre en sus máquinas
/// o le pasa el texto a Inworld; si es lo segundo, lo que dice Bitácora lo leen dos
/// empresas. Es texto de Bitácora y no de la persona, pero una respuesta suya dice
/// bastante de lo que le contaron. Queda anotado como pendiente en el docs/arquitectura.md.
///
/// CON UNA EXCEPCIÓN, y está del lado del teléfono. Los textos fijos de la app
/// —el mensaje de cuidado de la regla 6 y la despedida de los cortes— NO pasan
/// por acá nunca: los escribió la app, no el proveedor, y pedir que sinteticen
/// justo el mensaje de riesgo le avisaría a una empresa que el detector se
/// disparó. Ese corte vive en el teléfono para no depender de nadie. `decirSinSalir`
/// en `VozDeBitacora.swift` es la puerta que garantiza que no salgan.
///
/// POR QUÉ SE PUEDE APAGAR. Es lo primero que deja de andar sin internet, y
/// una bitácora tiene que funcionar en un colectivo. Cuando esto falla —sin
/// red, sin presupuesto, un 500 del proveedor— el teléfono no muestra ningún
/// error: usa la voz de iOS y sigue. Que suene peor es infinitamente mejor que
/// que se calle.

/// Lo que pide el teléfono. Desde el 26/10/2026 hay una sola voz y esto se
/// ignora: se sigue aceptando porque las apps ya instaladas (el APK de un
/// cliente, por ejemplo) mandan «hombre» si alguna vez lo eligieron, y un 400
/// las dejaría con la voz de iOS.
export type TimbreVoz = 'mujer' | 'hombre'

/// La voz de Bitácora: una sola, Lupita.
///
/// Hasta el 26/10/2026 Ajustes ofrecía mujer u hombre (Lupita y Diego en
/// DeepInfra, coral y ash en OpenAI). Ese día Lupita pasó a `realtime-tts-2`,
/// Dusan la eligió de oído contra el modelo anterior y contra Diego, y pidió
/// dejar sólo ésa. La historia de cómo se eligieron las dos está en git.
///
/// Un nombre que no existe rebota con 400, así que una voz mal escrita se nota
/// en el momento: Bitácora habla con la de iOS. Se puede pisar con `VOZ_MUJER`,
/// por ejemplo con una voz clonada, que en Inworld se pide por su id.
function vozDe(_timbre: TimbreVoz): string {
  return config.vozDeMujer ?? (config.vozEnDeepInfra ? 'Lupita' : 'coral')
}

/// Con qué modelo se sintetiza: `config.modeloDeVoz`, o `MODELO_DE_VOZ_MUJER`.
function modeloDe(_timbre: TimbreVoz): string {
  return config.modeloDeVozDeMujer ?? config.modeloDeVoz
}

/// Cómo tiene que sonar. Sólo vale para OpenAI.
///
/// El modelo acepta instrucciones de estilo, y sin ellas sale un locutor de
/// audiolibro: entusiasta, redondo, con la entonación de quien lee algo que le
/// pasaron. Lo que hace falta acá es lo contrario, porque del otro lado hay
/// alguien contando el día a las dos de la mañana.
const ESTILO = [
  'Hablas en español latinoamericano neutro, con acento mexicano suave.',
  'Tono cálido y tranquilo, como alguien que está escuchando de verdad.',
  'Ritmo pausado, con pausas naturales entre las frases.',
  'Nada de entusiasmo de locutor ni de asistente virtual: no levantes la voz al',
  'final, no exageres la entonación, no suenes alegre por defecto.',
  'Si el texto es serio, decilo serio.',
].join(' ')

/// El techo del proveedor. Un pedido más largo rebota con 400.
///
/// Es el más bajo de los dos: OpenAI acepta 4000 e Inworld 2000. Uno solo para
/// los dos porque el teléfono nunca manda más de unos trescientos por pedido
/// (`TrozosDeVoz`), así que no hay nada que ganar con el más alto.
export const MAX_CARACTERES = 2000

export interface Audio {
  audio: Buffer
  tipo: string
}

/// La firma de la llamada al proveedor, inyectable para poder testear sin clave,
/// sin red y sin gastar — el mismo patrón que `llamar` en `llm.ts`.
export type LlamadaDeVoz = (texto: string, voz: string, modelo: string) => Promise<Audio>

/// El pedido real al proveedor.
async function pedirAudio(texto: string, voz: string, modelo: string): Promise<Audio> {
  const enDeepInfra = config.vozEnDeepInfra
  const r = await fetch(`${config.vozBaseUrl}/audio/speech`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${config.vozApiKey}`,
      'content-type': 'application/json',
    },
    signal: AbortSignal.timeout(config.vozTimeoutMs),
    body: JSON.stringify({
      model: modelo,
      voice: voz,
      input: texto,
      // Las instrucciones de estilo son de OpenAI. Inworld no las tiene: cómo
      // suena lo decide la voz elegida, y mandarle un campo que no conoce es
      // jugar a ver si lo ignora o lo rebota.
      ...(enDeepInfra ? {} : { instructions: ESTILO }),
      // AAC y no mp3 cuando se puede: `AVAudioPlayer` reproduce los dos —probado
      // con el audio real de este endpoint— y a la misma calidad AAC pesa casi
      // la mitad (72 kbps contra 128). Eso son segundos de espera menos en una
      // charla por datos, que es donde una bitácora se usa de verdad.
      //
      // Inworld no da AAC (rebota con 422). Ahí se pide WAV, sin comprimir, y
      // no mp3: para sacarle los silencios que sobran hay que tener las
      // muestras a la vista, y un mp3 habría que decodificarlo. Pesa el triple
      // —48 KB por segundo de voz— y se paga a propósito: el teléfono lo
      // reproduce igual, y lo que se gana es que la voz deje de trabarse.
      response_format: enDeepInfra ? 'wav' : 'aac',
    }),
  })

  if (!r.ok) {
    // SÓLO el status en el mensaje. El cuerpo de error del proveedor devuelve
    // el `input` que rebotó —o sea, lo que Bitácora iba a decir— y ese mensaje
    // termina en `req.log.error`, que escribe a disco. Material de una charla
    // en un archivo de log es exactamente lo que este proyecto no hace.
    await r.text().catch(() => '')
    throw new Error(`TTS ${r.status}`)
  }

  const audio = Buffer.from(await r.arrayBuffer())
  if (!enDeepInfra) return { audio, tipo: 'audio/aac' }

  // Si por lo que sea no es el WAV que se espera, va como vino: una pausa de
  // más es mejor que un audio roto.
  const wav = leerWav(audio)
  if (!wav) return { audio, tipo: 'audio/wav' }
  const pcm = ajustarSilencios(wav.pcm, wav.hz, config.pausaMaximaDeVozMs)
  return { audio: escribirWav({ hz: wav.hz, pcm }), tipo: 'audio/wav' }
}

/// Cuánto salió, para que el guard de presupuesto siga teniendo dientes.
///
/// El proveedor cobra la voz por audio generado, no por tokens de texto, así
/// que no hay `usage` que leer: se estima por caracteres, que es proporcional a
/// la duración. No es exacto, y no hace falta que lo sea — lo que tiene que
/// hacer es que una charla que sintetiza mil veces mueva el contador.
function costoUsd(caracteres: number): number {
  return caracteres / 1_000_000 * config.precioVozPorMChar
}

/// Cuánto se lleva gastado en voz este mes.
export async function gastoDeVoz(): Promise<number> {
  const { rows } = await pool.query<{ total: string }>(
    `select coalesce(sum(costo_usd), 0)::text as total
       from llm_llamadas
      where tarea = 'voz' and creado_en >= date_trunc('month', now())`,
  )
  return Number(rows[0]?.total ?? 0)
}

/// El techo propio de la voz, que corta antes que el general.
async function verificarTechoDeVoz(): Promise<void> {
  const techo = config.presupuestoMensualUsd * config.fraccionDeVoz
  const gastado = await gastoDeVoz()
  if (gastado >= techo) {
    throw new PresupuestoAgotado(
      `La voz se comió su parte del mes: ${gastado.toFixed(4)} de ${techo.toFixed(2)} USD. ` +
      `Sigue andando con la voz del teléfono. Subí BUDGET_USD_MES o FRACCION_VOZ.`,
    )
  }
}

/// Genera el audio de un turno de Bitácora.
///
/// DOS TECHOS, y el orden importa. Primero el propio de la voz, que es una
/// fracción del general: cuando se pasa, la voz se apaga sola y la charla sigue
/// con la voz del teléfono. Sin eso, unas semanas de charlas largas podían
/// gastar el mes entero en audio y dejar a la persona sin lo único que no tiene
/// reemplazo, que es que Bitácora conteste.
///
/// Y el general corre SIEMPRE acá, a diferencia de la charla, que lo saltea de
/// la segunda respuesta en adelante: una charla empezada no se aborta, pero
/// quedarse sin voz linda no aborta nada. Lo que la regla 5 no puede permitir es
/// que un loop se coma el saldo, y la voz es la llamada más fácil de repetir sin
/// querer y la más cara.
/// Cómo se dice lo que en pantalla se escribe distinto.
///
/// Hoy es una sola cosa: el *4141, la línea de prevención del suicidio de
/// Chile, que el prompt le pide nombrar cuando aparecen señales de riesgo.
/// Escrito así, una voz puede leerlo como «cuatro mil ciento cuarenta y uno» o
/// saltearse el asterisco, y queda un número que no se marca. Se dice como se
/// marca. El texto en pantalla no cambia: esto es sólo lo que se sintetiza.
export function paraDecir(texto: string): string {
  return texto.replace(/\*\s?4141\b/g, 'asterisco cuatro uno cuatro uno')
}

export async function sintetizar(
  texto: string,
  timbre: TimbreVoz,
  llamada: LlamadaDeVoz = pedirAudio,
): Promise<Audio> {
  await verificarTechoDeVoz()
  await verificarPresupuesto()

  const arranque = Date.now()
  let ok = false
  try {
    const r = await llamada(paraDecir(texto), vozDe(timbre), modeloDe(timbre))
    ok = true
    return r
  } finally {
    // La fila queda igual, pero el costo va en cero si falló: acá, a diferencia
    // del texto, una llamada que rebota no generó audio y no se cobra. Los
    // caracteres se registran igual, para saber qué se intentó.
    await registrar(modeloDe(timbre), texto.length, Date.now() - arranque, ok)
  }
}

/// La firma del pedido en vivo, inyectable como la otra.
///
/// `alLlegar` recibe muestras de 16 bits, mono, ya sin los silencios que
/// sobran; `hz` es la frecuencia que informó el proveedor.
export type LlamadaDeVozEnVivo = (
  texto: string,
  voz: string,
  alLlegar: (pcm: Buffer, hz: number) => void,
  senal: AbortSignal | undefined,
  modelo: string,
) => Promise<void>

/// Cuánto puede tardar un pedazo entero, de punta a punta. Holgado: en
/// streaming lo que importa es cuándo llega el primer byte, y eso lo cuida
/// `VOZ_TIMEOUT_MS`.
const TECHO_DE_UN_PEDAZO_MS = 45_000

/// El pedido real, en streaming: el audio se entrega a medida que se genera.
///
/// El primer byte llega en medio segundo, tenga el texto el largo que tenga.
/// Pedido entero, en cambio, el audio tarda en proporción a lo que dura: dos
/// segundos para una frase corta y cuatro para una larga, todos de silencio.
async function pedirAudioEnVivo(
  texto: string,
  voz: string,
  alLlegar: (pcm: Buffer, hz: number) => void,
  senal: AbortSignal | undefined,
  modelo: string,
): Promise<void> {
  // El reloj corto es para el primer byte y se apaga cuando llega.
  const arranque = new AbortController()
  const reloj = setTimeout(() => arranque.abort(), config.vozTimeoutMs)
  const senales = [arranque.signal, AbortSignal.timeout(TECHO_DE_UN_PEDAZO_MS)]
  if (senal) senales.push(senal)

  try {
    const r = await fetch(`${config.vozBaseUrl}/audio/speech`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${config.vozApiKey}`,
        'content-type': 'application/json',
      },
      signal: AbortSignal.any(senales),
      body: JSON.stringify({
        model: modelo,
        voice: voz,
        input: texto,
        response_format: 'pcm',
        stream: true,
      }),
    })
    if (!r.ok || !r.body) {
      // Sólo el status, por lo mismo que en `pedirAudio`.
      await r.text().catch(() => '')
      throw new Error(`TTS ${r.status}`)
    }

    const lector = new LectorDeAudioEnVivo()
    let recorte: RecorteEnVivo | null = null
    const entregar = (pcm: Int16Array) => {
      if (pcm.length > 0) alLlegar(aBytes(pcm), lector.hz)
    }

    const cuerpo = r.body.getReader()
    for (;;) {
      const { done, value } = await cuerpo.read()
      if (done) break
      clearTimeout(reloj)
      const muestras = lector.pasar(Buffer.from(value))
      // El recorte se arma con el primer pedazo: recién ahí se sabe la frecuencia.
      recorte ??= new RecorteEnVivo(lector.hz, config.pausaMaximaDeVozMs)
      entregar(recorte.pasar(muestras))
    }
    if (recorte) entregar(recorte.cerrar())
  } finally {
    clearTimeout(reloj)
  }
}

/// Genera el audio de un pedazo de turno, entregándolo a medida que llega.
///
/// Los mismos dos techos que `sintetizar`, en el mismo orden, y el mismo
/// registro. Lo que cambia es cuándo se cobra: un pedazo que se cortó a la
/// mitad —porque la persona interrumpió, o porque se cayó el proveedor— ya
/// generó audio, así que se registra con su costo si llegó a sonar algo.
export async function sintetizarEnVivo(
  texto: string,
  timbre: TimbreVoz,
  alLlegar: (pcm: Buffer, hz: number) => void,
  senal?: AbortSignal,
  llamada: LlamadaDeVozEnVivo = pedirAudioEnVivo,
): Promise<void> {
  await verificarTechoDeVoz()
  await verificarPresupuesto()

  const arranque = Date.now()
  let ok = false
  let sono = false
  try {
    await llamada(paraDecir(texto), vozDe(timbre), (pcm, hz) => { sono = true; alLlegar(pcm, hz) }, senal, modeloDe(timbre))
    ok = true
  } finally {
    await registrar(modeloDe(timbre), texto.length, Date.now() - arranque, ok, sono)
  }
}

async function registrar(modelo: string, caracteres: number, latenciaMs: number, ok: boolean, cobrar = ok): Promise<void> {
  try {
    await pool.query(
      `insert into llm_llamadas (tarea, modelo, tokens_in, tokens_out, costo_usd, latencia_ms, ok, ref_id)
       values ('voz', $1, $2, null, $3, $4, $5, null)`,
      [modelo, caracteres, costoUsd(cobrar ? caracteres : 0), latenciaMs, ok],
    )
  } catch (e) {
    // Igual que en `llm.ts`: que falle el registro no puede tumbar la llamada,
    // pero tiene que verse. Sin registro, el guard queda ciego.
    console.error('No se pudo registrar la llamada de voz en llm_llamadas:', e)
  }
}
