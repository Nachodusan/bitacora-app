import { pool } from './db.ts'
import { config } from './config.ts'

/// Las mismas que acepta el CHECK de `llm_llamadas.tarea`. Si se agrega una acá
/// hay que agregarla allá, o el insert del registro rebota y la llamada queda
/// sin loguear — que es la regla 5 rota en silencio.
export type Tarea = 'charla' | 'resumen_dia' | 'nota_terapia' | 'voz' | 'embedding' | 'rerank'
  | 'consulta' | 'para_llevar' | 'evaluacion' | 'emociones' | 'resumen_charla' | 'ficha'

export class PresupuestoAgotado extends Error {}

/// Cuánto se gastó este mes, según lo que quedó registrado.
export async function gastoDelMes(): Promise<number> {
  const { rows } = await pool.query<{ total: string }>(
    `select coalesce(sum(costo_usd), 0)::text as total
       from llm_llamadas
      where creado_en >= date_trunc('month', now())`,
  )
  return Number(rows[0]?.total ?? 0)
}

export async function llamadasDelMes(): Promise<number> {
  const { rows } = await pool.query<{ n: string }>(
    `select count(*)::text as n from llm_llamadas
      where creado_en >= date_trunc('month', now())`,
  )
  return Number(rows[0]?.n ?? 0)
}

/// El guard de la regla 5. Corre ANTES del request: si el techo ya se pasó, la
/// llamada no se hace. Después sería contar el daño.
///
/// Son DOS techos, y el segundo no es redundante. Hay proveedores donde el
/// precio por token es cero —una cuenta de prueba, una tarifa plana— y ahí el
/// techo en dólares no corta nunca, por más que el loop llame mil veces. El
/// tope por cantidad de llamadas es el que sigue teniendo dientes.
export async function verificarPresupuesto(): Promise<void> {
  const gastado = await gastoDelMes()
  if (gastado >= config.presupuestoMensualUsd) {
    throw new PresupuestoAgotado(
      `Techo mensual alcanzado: ${gastado.toFixed(4)} de ${config.presupuestoMensualUsd} USD. ` +
      `Subí BUDGET_USD_MES si querés seguir.`,
    )
  }
  const llamadas = await llamadasDelMes()
  if (llamadas >= config.maxLlamadasMes) {
    throw new PresupuestoAgotado(
      `Tope de llamadas del mes alcanzado: ${llamadas} de ${config.maxLlamadasMes}. ` +
      `Subí MAX_LLAMADAS_MES si querés seguir.`,
    )
  }
}

interface Uso {
  prompt_tokens?: number
  completion_tokens?: number
  /// Lo que el proveedor dice que salió, cuando lo dice. No es estándar:
  /// DeepInfra lo manda, OpenAI no.
  estimated_cost?: number
}

/// Con qué modelo se hace cada tarea de texto. La charla con el bueno; lo que
/// corre solo, con el de fondo.
export function modeloDe(tarea: Tarea): string {
  return tarea === 'charla' ? config.openaiModel : config.modeloDeFondo
}

/// Si el proveedor informa el costo, vale ése: es el que cobra, y sabe cosas que
/// acá no se ven —qué modelo fue, cuánto de la entrada estaba en caché—. Los
/// precios del `.env` quedan para los que no lo informan.
function costoUsd(uso: Uso): number {
  if (typeof uso.estimated_cost === 'number' && Number.isFinite(uso.estimated_cost)
      && uso.estimated_cost >= 0) {
    return uso.estimated_cost
  }
  const entrada = (uso.prompt_tokens ?? 0) / 1_000_000 * config.precioEntradaPorMTok
  const salida = (uso.completion_tokens ?? 0) / 1_000_000 * config.precioSalidaPorMTok
  return entrada + salida
}

export interface Respuesta<T> {
  datos: T
  crudo: unknown
}

export interface Pedido {
  tarea: Tarea
  refId: number | null
  sistema: string
  usuario: string
  /// Turnos anteriores, para las tareas conversacionales. El resto de las
  /// tareas mandan un solo mensaje y no lo usan.
  historial?: { role: 'user' | 'assistant'; content: string }[]
  /// Sin schema no se pide Structured Outputs y la respuesta viene en texto
  /// plano. La charla es el único caso: pedirle un JSON a un compañero es
  /// pedirle que hable como formulario.
  nombreSchema?: string
  schema?: Record<string, unknown>
  /// Temperatura. Resumir no es conversar: por defecto 0, para que el mismo
  /// día dé el mismo resumen dos veces. La charla la sube.
  temperatura?: number
  /// Saltea el guard de presupuesto para ESTA llamada.
  ///
  /// Existe por un solo caso y no debería crecer: los turnos de una charla ya
  /// empezada. El guard corre al abrir la conversación; si volviera a correr en
  /// cada turno, sería lo único en todo el sistema capaz de cortarle la charla
  /// a alguien en la mitad de un desahogo, y lo haría por el motivo menos
  /// importante que existe. Una charla que arrancó no se aborta.
  ///
  /// La llamada se sigue registrando igual: la regla 5 no se saltea, lo único
  /// que se saltea es el corte previo.
  sinGuardDePresupuesto?: boolean
  /// Para cortar la llamada desde afuera. La usa el turno en vivo: si la
  /// persona interrumpe a Bitácora, el teléfono cierra la conexión y no tiene
  /// sentido seguir generando —y pagando— un texto que nadie va a leer.
  senal?: AbortSignal
  /// Herramientas que el modelo puede pedir en medio de la respuesta (sólo
  /// `llamarConStream`). Las ejecuta el servidor y el modelo sigue hablando.
  herramientas?: Herramienta[]
}

/// Una herramienta para el modelo: qué hace, qué recibe y cómo se ejecuta.
export interface Herramienta {
  nombre: string
  descripcion: string
  parametros: Record<string, unknown>
  ejecutar: (args: Record<string, unknown>) => Promise<string>
}

/// Como mucho tantas vueltas de herramientas por turno: si el modelo se
/// engancha pidiendo, la última vuelta va sin herramientas y tiene que contestar.
const VUELTAS_DE_HERRAMIENTAS = 2

/// El timeout de siempre, más el corte de afuera si lo hay.
function senalDe(opciones: Pedido): AbortSignal {
  const techo = AbortSignal.timeout(config.llmTimeoutMs)
  return opciones.senal ? AbortSignal.any([techo, opciones.senal]) : techo
}

/// La firma de `llamar`. Las funciones que llaman al modelo la reciben como
/// parámetro con `llamar` de default, para que los tests puedan pasar un stub y
/// correr sin clave, sin red y sin gastar.
export type Llamada = <T>(p: Pedido) => Promise<Respuesta<T>>

/// Una llamada al modelo, con Structured Outputs si viene schema.
///
/// `strict: true` hace que el modelo no pueda devolver algo fuera del schema.
/// Eso no garantiza que el contenido sea cierto —para eso las citas se verifican
/// contra el texto y los resúmenes con cifras se descartan— pero sí que el JSON
/// siempre parsee.
///
/// Toda llamada, salga bien o mal, queda registrada en `llm_llamadas`. Una que
/// falló también costó tokens.
export async function llamar<T>(opciones: Pedido): Promise<Respuesta<T>> {
  if (!opciones.sinGuardDePresupuesto) await verificarPresupuesto()

  const arranque = Date.now()
  let uso: Uso = {}
  let ok = false

  try {
    const r = await fetch(`${config.llmBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${config.openaiApiKey}`,
        'content-type': 'application/json',
      },
      signal: senalDe(opciones),
      body: JSON.stringify({
        model: modeloDe(opciones.tarea),
        temperature: opciones.temperatura ?? 0,
        messages: [
          { role: 'system', content: opciones.sistema },
          ...(opciones.historial ?? []),
          { role: 'user', content: opciones.usuario },
        ],
        ...(opciones.schema
          ? { response_format: {
                type: 'json_schema',
                json_schema: { name: opciones.nombreSchema!, strict: true,
                               schema: opciones.schema },
              } }
          : {}),
      }),
    })

    const cuerpo = await r.json() as {
      choices?: { message?: { content?: string } }[]
      usage?: Uso
      error?: { message?: string }
    }
    uso = cuerpo.usage ?? {}

    if (!r.ok) throw new Error(`LLM ${r.status}: ${cuerpo.error?.message ?? JSON.stringify(cuerpo).slice(0, 300)}`)

    const contenido = cuerpo.choices?.[0]?.message?.content
    if (!contenido) throw new Error('El modelo devolvió una respuesta sin contenido')

    // Sin schema la respuesta ES el texto; con schema, hay que parsearla.
    const datos = (opciones.schema ? JSON.parse(contenido) : contenido) as T
    ok = true
    return { datos, crudo: cuerpo }
  } finally {
    await registrar({
      tarea: opciones.tarea,
      modelo: modeloDe(opciones.tarea),
      refId: opciones.refId,
      tokensIn: uso.prompt_tokens ?? null,
      tokensOut: uso.completion_tokens ?? null,
      costoUsd: costoUsd(uso),
      latenciaMs: Date.now() - arranque,
      ok,
    })
  }
}

/// Una llamada al modelo que va entregando el texto a medida que llega.
///
/// POR QUÉ EXISTE. Sin esto, el turno de Bitácora se pedía entero —un segundo y
/// medio— y recién ahí empezaba a generarse el audio —dos segundos más—. Las
/// dos etapas, una atrás de la otra, son casi cuatro segundos de silencio
/// mirando la pantalla. Con el texto en streaming, la primera frase está lista
/// a los cuatrocientos milisegundos y el audio puede arrancar ahí, mientras el
/// resto del texto sigue llegando: las dos etapas se pisan en vez de sumarse.
///
/// `alLlegarTexto` se llama con lo acumulado hasta ese momento, en cada pedazo
/// que manda el proveedor. Quien llama decide cuándo ya tiene una frase.
///
/// Se registra igual que `llamar`, con una diferencia: el `usage` de una
/// respuesta en streaming sólo viene si se pide, así que se pide.
export async function llamarConStream(
  opciones: Pedido,
  alLlegarTexto: (acumulado: string) => void,
): Promise<Respuesta<string>> {
  if (!opciones.sinGuardDePresupuesto) await verificarPresupuesto()

  const arranque = Date.now()
  const uso: Uso = { prompt_tokens: 0, completion_tokens: 0 }
  let ok = false
  let texto = ''
  type Mensaje = Record<string, unknown>
  const mensajes: Mensaje[] = [
    { role: 'system', content: opciones.sistema },
    ...(opciones.historial ?? []),
    { role: 'user', content: opciones.usuario },
  ]
  const herramientas = opciones.herramientas ?? []

  try {
    for (let vuelta = 0; ; vuelta++) {
      const conHerramientas = herramientas.length > 0 && vuelta < VUELTAS_DE_HERRAMIENTAS
      const r = await fetch(`${config.llmBaseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${config.openaiApiKey}`,
          'content-type': 'application/json',
        },
        signal: senalDe(opciones),
        body: JSON.stringify({
          model: modeloDe(opciones.tarea),
          temperature: opciones.temperatura ?? 0,
          stream: true,
          stream_options: { include_usage: true },
          messages: mensajes,
          ...(conHerramientas ? { tools: herramientas.map(h => ({ type: 'function',
            function: { name: h.nombre, description: h.descripcion, parameters: h.parametros } })) } : {}),
        }),
      })

      if (!r.ok || !r.body) {
        const detalle = await r.text().catch(() => '')
        throw new Error(`LLM ${r.status}: ${detalle.slice(0, 300)}`)
      }

      // El formato es SSE: líneas "data: {json}", separadas por línea en blanco,
      // y un "data: [DONE]" al final. Puede llegar cortado a la mitad de una
      // línea, así que se guarda lo que sobra para el pedazo siguiente. Los
      // pedidos de herramienta también llegan en pedazos, por índice.
      const lector = r.body.getReader()
      const decodificador = new TextDecoder()
      let resto = ''
      let deEstaVuelta = ''
      const pedidos: { id: string; nombre: string; args: string }[] = []

      for (;;) {
        const { done, value } = await lector.read()
        if (done) break
        resto += decodificador.decode(value, { stream: true })
        const lineas = resto.split('\n')
        resto = lineas.pop() ?? ''

        for (const linea of lineas) {
          const l = linea.trim()
          if (!l.startsWith('data:')) continue
          const cuerpo = l.slice(5).trim()
          if (cuerpo === '[DONE]') continue
          try {
            const d = JSON.parse(cuerpo) as {
              choices?: { delta?: { content?: string; tool_calls?: { index: number; id?: string | null;
                function?: { name?: string | null; arguments?: string } }[] } }[]
              usage?: Uso
            }
            if (d.usage) {
              uso.prompt_tokens! += d.usage.prompt_tokens ?? 0
              uso.completion_tokens! += d.usage.completion_tokens ?? 0
              if (typeof d.usage.estimated_cost === 'number') uso.estimated_cost = (uso.estimated_cost ?? 0) + d.usage.estimated_cost
            }
            const delta = d.choices?.[0]?.delta
            for (const t of delta?.tool_calls ?? []) {
              const p = pedidos[t.index] ??= { id: '', nombre: '', args: '' }
              if (t.id) p.id = t.id
              if (t.function?.name) p.nombre += t.function.name
              if (t.function?.arguments) p.args += t.function.arguments
            }
            const pedazo = delta?.content
            if (pedazo) {
              texto += pedazo
              deEstaVuelta += pedazo
              alLlegarTexto(texto)
            }
          } catch {
            // Una línea que no parsea no tumba el turno: el proveedor manda
            // keep-alives y comentarios, y perder uno no cambia nada.
          }
        }
      }

      const validos = pedidos.filter(p => p && p.nombre)
      if (!conHerramientas || validos.length === 0) break

      // Se ejecutan y el modelo sigue. Una herramienta que falla no corta el
      // turno: el modelo recibe que no se pudo y contesta igual.
      mensajes.push({ role: 'assistant', content: deEstaVuelta || null,
        tool_calls: validos.map((p, i) => ({ id: p.id || `h${vuelta}_${i}`, type: 'function',
                                             function: { name: p.nombre, arguments: p.args || '{}' } })) })
      for (const [i, p] of validos.entries()) {
        const h = herramientas.find(x => x.nombre === p.nombre)
        let resultado: string
        try {
          resultado = h ? await h.ejecutar(JSON.parse(p.args || '{}') as Record<string, unknown>)
                        : `No existe la herramienta ${p.nombre}.`
        } catch {
          resultado = 'No se pudo consultar ahora.'
        }
        mensajes.push({ role: 'tool', tool_call_id: p.id || `h${vuelta}_${i}`, content: resultado })
      }
      // Si ya había dicho algo, lo que sigue va pegado con un espacio.
      if (texto && !/\s$/.test(texto)) texto += ' '
    }

    if (!texto.trim()) throw new Error('El modelo devolvió una respuesta sin contenido')
    texto = texto.trim()
    ok = true
    return { datos: texto, crudo: {} }
  } finally {
    await registrar({
      tarea: opciones.tarea,
      modelo: modeloDe(opciones.tarea),
      refId: opciones.refId,
      tokensIn: uso.prompt_tokens || null,
      tokensOut: uso.completion_tokens || null,
      costoUsd: costoUsd(uso),
      latenciaMs: Date.now() - arranque,
      ok,
    })
  }
}

/// La fila de `llm_llamadas`. Exportada porque no todas las llamadas son de
/// chat: el embedding y el reordenado tienen otro formato de pedido y de costo,
/// pero el registro es uno solo — es lo que lee el guard.
export async function registrar(d: {
  tarea: Tarea
  modelo: string
  refId: number | null
  tokensIn: number | null
  tokensOut: number | null
  costoUsd: number
  latenciaMs: number
  ok: boolean
}): Promise<void> {
  try {
    await pool.query(
      `insert into llm_llamadas (tarea, modelo, tokens_in, tokens_out, costo_usd, latencia_ms, ok, ref_id)
       values ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [d.tarea, d.modelo, d.tokensIn, d.tokensOut, d.costoUsd, d.latenciaMs, d.ok, d.refId],
    )
  } catch (e) {
    // Que falle el registro no puede tumbar la llamada, pero sí tiene que
    // verse: sin registro, el guard de presupuesto queda ciego.
    console.error('No se pudo registrar la llamada en llm_llamadas:', e)
  }
}
