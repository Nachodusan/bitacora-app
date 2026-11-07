import 'dotenv/config'

/// Todo lo que la app necesita del entorno, validado una sola vez al arrancar.
///
/// Si falta algo, el proceso muere acá y no tres capas más abajo con un error
/// que no dice nada. Mono-usuario: no hay defaults "seguros" que adivinar.
function requerido(nombre: string): string {
  const v = process.env[nombre]
  if (!v || v.trim() === '') {
    throw new Error(`Falta la variable de entorno ${nombre}. Copiá .env.example a .env.`)
  }
  return v.trim()
}

const authToken = requerido('AUTH_TOKEN')

if (authToken === 'cambiame') {
  throw new Error('AUTH_TOKEN quedó con el valor de ejemplo. Generá uno: openssl rand -hex 32')
}

/// Un número que TIENE que estar. Sin precios no hay guard de presupuesto, y
/// sin guard la regla 5 es decorativa: un loop mal escrito te come el saldo sin
/// que lo veas. Prefiero que el worker no arranque a inventar un precio.
function numeroRequerido(nombre: string): number {
  const n = Number(requerido(nombre))
  if (!Number.isFinite(n) || n < 0) {
    throw new Error(`${nombre} tiene que ser un número >= 0.`)
  }
  return n
}

/// Un número que puede faltar, pero que si está tiene que ser un número.
///
/// `Number('gratis')` es `NaN`, y `NaN` se propaga: un precio así entra en
/// `costo_usd`, `sum()` de una columna con un NaN da NaN, y el techo en dólares
/// deja de cortar para TODAS las tareas y para todo el mes. Un typo en el .env
/// apagaba el guard entero sin un solo error a la vista.
function numeroConDefault(nombre: string, porDefecto: number): number {
  const crudo = process.env[nombre]
  if (crudo === undefined || crudo.trim() === '') return porDefecto
  const n = Number(crudo)
  if (!Number.isFinite(n) || n < 0) {
    throw new Error(`${nombre} tiene que ser un número >= 0 (llegó "${crudo}").`)
  }
  return n
}

/// Qué clave va con qué dirección.
function claveDe(baseUrl: string): string {
  return requerido(baseUrl.includes('deepinfra.com') ? 'DEEPINFRA_API_KEY' : 'OPENAI_API_KEY')
}

export const config = {
  databaseUrl: requerido('DATABASE_URL'),
  authToken,
  puerto: Number(process.env.PORT ?? 3000),
  // 0.0.0.0 y no 127.0.0.1: sin esto el iPhone no puede llegar por la red local.
  host: process.env.HOST ?? '0.0.0.0',

  // Sólo hacen falta para hablar con el modelo; el servidor HTTP levanta sin
  // ellas (así corren los tests). Se leen perezosamente por eso — pero el
  // latido las valida TODAS al arrancar con verificarConfigLLM(), porque
  // leerlas tarde fue justo el bug que dejó el registro de gasto en cero sin
  // que nadie se enterara.
  get llmBaseUrl(): string { return (process.env.LLM_BASE_URL ?? 'https://api.openai.com/v1').replace(/\/$/, '') },
  /// Un pedido colgado sin timeout se cuelga para siempre: `fetch` no tiene
  /// uno por defecto. Con latencias de 100 segundos como las de NIM, el techo
  /// tiene que ser holgado pero existir.
  get llmTimeoutMs(): number { return Number(process.env.LLM_TIMEOUT_MS ?? 180_000) },
  /// La clave del texto. Sale de a dónde apunta `LLM_BASE_URL`, y no de una
  /// variable más: así cambiar de proveedor es cambiar la dirección, y la clave
  /// del otro queda en el `.env` sin tocar para poder volver.
  get openaiApiKey(): string { return claveDe(this.llmBaseUrl) },
  /// El modelo de la charla. El nombre de la variable quedó de cuando había un
  /// solo proveedor; acepta cualquiera que sirva `LLM_BASE_URL`.
  get openaiModel(): string { return requerido('OPENAI_MODEL') },
  /// El modelo de lo que corre solo: el resumen del día y las notas de terapia.
  ///
  /// Aparte del de la charla porque no valen lo mismo. La charla es lo único que
  /// la persona escucha y ahí conviene el modelo bueno; esto corre de fondo, sin
  /// apuro, y uno chico alcanza. Si no está, es el mismo de la charla.
  get modeloDeFondo(): string { return process.env.MODELO_DE_FONDO?.trim() || this.openaiModel },
  get presupuestoMensualUsd(): number { return numeroRequerido('BUDGET_USD_MES') },
  get maxLlamadasMes(): number { return numeroRequerido('MAX_LLAMADAS_MES') },
  get precioEntradaPorMTok(): number { return numeroRequerido('PRECIO_IN_USD_POR_MTOK') },
  get precioSalidaPorMTok(): number { return numeroRequerido('PRECIO_OUT_USD_POR_MTOK') },

  // --- La memoria larga: embedding y reordenado ---
  //
  // Siempre DeepInfra, y no configurable como el texto: el reordenado no tiene
  // un formato común entre proveedores, así que `recuerdos.ts` habla el de éste.
  // Sin la clave, la memoria larga queda apagada y Bitácora sigue con los últimos
  // siete días, que es como andaba antes.
  get deepinfraApiKey(): string | null { return process.env.DEEPINFRA_API_KEY?.trim() || null },
  /// Cambiar este modelo obliga a recalcular todos los vectores y a cambiar el
  /// tamaño de la columna: los de dos modelos distintos no se comparan.
  get modeloDeEmbedding(): string { return process.env.MODELO_EMBEDDING?.trim() || 'BAAI/bge-m3' },
  get precioEmbeddingPorMTok(): number { return numeroConDefault('PRECIO_EMBEDDING_USD_POR_MTOK', 0.01) },
  get modeloDeRerank(): string { return process.env.MODELO_RERANK?.trim() || 'Qwen/Qwen3-Reranker-4B' },
  get precioRerankPorMTok(): number { return numeroConDefault('PRECIO_RERANK_USD_POR_MTOK', 0.025) },
  /// Corto, porque esto pasa ANTES de que Bitácora empiece a contestar: cada
  /// milisegundo acá es silencio. Si no llega a tiempo, el turno sale sin
  /// recuerdos viejos y nadie se entera.
  get memoriaTimeoutMs(): number { return numeroConDefault('MEMORIA_TIMEOUT_MS', 1_500) },

  /// De quién es la voz. Por defecto el mismo proveedor del texto, que es como
  /// fue siempre; se separa para poder mover uno sin mover el otro.
  get vozBaseUrl(): string { return (process.env.VOZ_BASE_URL?.trim() || this.llmBaseUrl).replace(/\/$/, '') },
  get vozApiKey(): string { return claveDe(this.vozBaseUrl) },
  /// Si la voz va por DeepInfra. De esto cuelga todo lo que cambia de un
  /// proveedor al otro: el modelo, las voces, el formato y el precio.
  get vozEnDeepInfra(): boolean { return this.vozBaseUrl.includes('deepinfra.com') },
  /// En DeepInfra, Inworld: es el único del catálogo con voces en castellano de
  /// hombre y de mujer. Desde el 26/10/2026, `realtime-tts-2` para los dos:
  /// Dusan dijo que Lupita sonaba «media lenta, desganada», y con la misma frase
  /// en ese modelo habla un 24 % más rápido (16,1 caracteres por segundo contra
  /// 13,0 del `1.5-max`) y la eligió de oído. Además cuesta menos.
  get modeloDeVoz(): string {
    return process.env.MODELO_DE_VOZ?.trim()
      || (this.vozEnDeepInfra ? 'inworld-ai/realtime-tts-2' : 'gpt-4o-mini-tts')
  },
  /// El techo de las pausas de la voz, en milisegundos (`silencios.ts`).
  ///
  /// La voz de Inworld hace pausas de medio segundo largo en cada coma. Con
  /// esto ninguna pausa dura más que el techo. Es para afinar de oído, que es
  /// la única forma: más bajo suena más fluido y, pasado cierto punto, apurado.
  /// En 0 las pausas del medio no se tocan (los silencios del principio y del
  /// final se recortan igual).
  get pausaMaximaDeVozMs(): number { return numeroConDefault('VOZ_PAUSA_MAX_MS', 300) },
  /// El modelo de la voz, si se quiere distinto del general. Vacío, vale lo
  /// que decida `voz.ts`.
  get modeloDeVozDeMujer(): string | null { return process.env.MODELO_DE_VOZ_MUJER?.trim() || null },
  /// La voz, por si se quiere otra del mismo proveedor sin tocar código.
  /// Vacías, valen las de `voz.ts`.
  get vozDeMujer(): string | null { return process.env.VOZ_MUJER?.trim() || null },
  /// Más corto que el del texto, y más corto que el del teléfono.
  ///
  /// El teléfono espera nueve segundos y después habla con la voz de iOS. Si
  /// acá el techo fuera más alto, el servidor seguiría generando —y pagando—
  /// un audio que del otro lado ya no va a escuchar nadie.
  get vozTimeoutMs(): number { return numeroConDefault('VOZ_TIMEOUT_MS', 8_000) },
  /// Dólares por millón de caracteres sintetizados.
  ///
  /// Éste SÍ tiene default, a diferencia de los precios del texto, y no es una
  /// inconsistencia: el proveedor cobra la voz por duración del audio y no
  /// devuelve ningún `usage` que leer, así que hay que estimarla por el texto.
  ///
  /// El número sale de medir, no del tarifario. Los mp3 que generó este mismo
  /// endpoint van a 13 caracteres por segundo con el estilo que les pedimos
  /// —"ritmo pausado"—, o sea que un millón de caracteres son unas 21 horas de
  /// habla y, a 0.015 dólares el minuto, unos 20 dólares. El primer valor que
  /// puse acá fue 15, calculado suponiendo una velocidad de locutor; subestimaba
  /// un 45%, y un guard que subestima es un guard a medias.
  ///
  /// Los textos cortos salen más caros por caracter (hay un silencio fijo al
  /// principio y al final, que en una frase de sesenta caracteres es el 20%),
  /// pero los turnos largos son los que mueven el gasto y son los que este
  /// número estima bien.
  ///
  /// Inworld sí cobra por caracter, y lo dice el tarifario: 35 dólares el millón
  /// el `realtime-tts-2`, 50 el `1.5-max`, 25 el `1.5-mini`. Si se cambia de
  /// modelo, se cambia este número.
  get precioVozPorMChar(): number {
    return numeroConDefault('PRECIO_VOZ_USD_POR_MCHAR', this.vozEnDeepInfra ? 35 : 20)
  },
  /// Cuánto del techo mensual puede comerse la voz, de 0 a 1.
  ///
  /// Existe porque la voz y la charla comparten presupuesto y no valen lo mismo:
  /// un turno de texto sale una fracción de centavo y el mismo turno hablado
  /// sale unas veinte veces más. Sin este tope, unas semanas de charlas largas
  /// podían agotar el techo del mes en audio y dejar a la persona sin lo único
  /// que no tiene reemplazo — que Bitácora conteste. Al revés sí se puede: sin voz
  /// linda, el teléfono habla con la de iOS y la charla sigue igual.
  ///
  /// La mitad, entonces: cuando la voz se comió la mitad del techo, se apaga
  /// sola y la otra mitad queda para hablar.
  get fraccionDeVoz(): number { return Math.min(1, numeroConDefault('FRACCION_VOZ', 0.5)) },
} as const

/// Toca toda la config del LLM de una, para que falte lo que falte se vea al
/// arrancar y no en medio de una tanda.
export function verificarConfigLLM(): void {
  void config.llmBaseUrl
  void config.modeloDeVoz
  void config.vozTimeoutMs
  void config.precioVozPorMChar
  void config.fraccionDeVoz
  void config.vozApiKey
  void config.pausaMaximaDeVozMs
  void config.precioEmbeddingPorMTok
  void config.precioRerankPorMTok
  void config.memoriaTimeoutMs
  void config.openaiApiKey
  void config.openaiModel
  void config.presupuestoMensualUsd
  void config.maxLlamadasMes
  void config.precioEntradaPorMTok
  void config.precioSalidaPorMTok
}
