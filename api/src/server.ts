import Fastify, { type FastifyInstance } from 'fastify'
import { pool, abrirContexto } from './db.ts'
import { crearCuenta, cuentaParaLaBase, entrar, guardarPerfil, idDeSesion, idDeLaBase, PIN, type Perfil } from './cuentas.ts'
import { resumirCharla } from './resumen.ts'
import { requiereToken } from './auth.ts'
import { leerReloj, guardarAjustes, zonaValida, type Ajustes } from './ajustes.ts'
import { siguienteTurno, siguienteTurnoConVoz, MENSAJE_DE_CORTE, type Turno } from './charla.ts'
import { notas } from './notas.ts'
import { sintetizar, MAX_CARACTERES, type TimbreVoz } from './voz.ts'
import { emocionesSugeridas } from './herramientas.ts'
import { turnoEnVivo } from './vivo.ts'
import { haySenalEnLaCharla, MENSAJE_DE_RIESGO } from './riesgo.ts'
import { listarEventos, crearEvento, cambiarEvento, borrarEvento,
         type EventoNuevo, type CambioDeEvento } from './consultas.ts'
import { sumarDias } from './fechas.ts'
import { fichaActiva, fichaParaLeer, quitarDato, compartirDato, marcarAvisada } from './ficha.ts'
import { borrarConversacion, pedirBorrarCuenta, recuperarCuenta, cuentaSeBorraEl } from './cuenta.ts'

/// Lo que manda una app instalada antes del 02/10/2026, cuando Bitácora se
/// llamaba Laya: el rol `laya` en los turnos y el rótulo `Laya:` en las
/// transcripciones. Se acepta y se traduce al entrar, para que reiniciar el
/// servidor no deje sin charla a un teléfono que todavía no se reinstaló, y
/// para que una entrada que quedó en su cola llegue con el rótulo nuevo, igual
/// que las que ya estaban en la base. Cuando no quede ninguna app vieja, esto
/// y el `'laya'` del schema de abajo se borran.
const ROL_VIEJO = 'laya'
const ROTULO_VIEJO = /^Laya:/gm

function turnosDe(turnos: CuerpoCharla['turnos']): Turno[] {
  return turnos.map(t => ({ de: t.de === ROL_VIEJO ? 'bitacora' : t.de, texto: t.texto }))
}

/// Formato de `creado_local`: hora de pared, SIN zona ni offset.
///
/// El regex es un guard del corte de las 4am, no una formalidad. La columna
/// `creado_local` es timestamp sin zona: si el teléfono mandara
/// "2026-08-10T04:30:00Z" para la 1:30 de Buenos Aires, Postgres descartaría
/// la Z en silencio y guardaría las 4:30 como hora de pared — y el día lógico
/// saldría uno más tarde. Mejor un 400 acá que descubrirlo en el calendario.
const HORA_DE_PARED = '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$'

const cuerpoEntrada = {
  type: 'object',
  required: ['client_uuid', 'creado_en', 'creado_local', 'fuente', 'transcripcion'],
  additionalProperties: false,
  properties: {
    client_uuid: { type: 'string', format: 'uuid' },
    creado_en: { type: 'string', minLength: 20 },
    creado_local: { type: 'string', pattern: HORA_DE_PARED },
    // 'dictado_android' desde el 03/10/2026, con la app de Android.
    fuente: { type: 'string', enum: ['dictado_ios', 'dictado_android', 'texto'] },
    transcripcion: { type: 'string', minLength: 1 },
    // El techo es el de numeric(6,1) en la base. Sin él, un valor absurdo
    // pasaba el schema y rebotaba con 500 — y un 500 traba la cola entera.
    duracion_seg: { type: 'number', minimum: 0, maximum: 99999 },
  },
} as const

interface CuerpoEntrada {
  client_uuid: string
  creado_en: string
  creado_local: string
  fuente: string
  transcripcion: string
  duracion_seg?: number
}

const DIA = '^\\d{4}-\\d{2}-\\d{2}$'

/// El techo de caracteres es el del proveedor, no una preferencia: más largo
/// que eso rebota con un 400 que no dice nada útil. Un turno de Bitácora nunca se
/// acerca — cuatro mil caracteres son unos cuatro minutos hablando.
const cuerpoVoz = {
  type: 'object',
  required: ['texto', 'timbre'],
  additionalProperties: false,
  properties: {
    texto: { type: 'string', minLength: 1, maxLength: MAX_CARACTERES },
    timbre: { type: 'string', enum: ['mujer', 'hombre'] },
  },
} as const

interface CuerpoVoz {
  texto: string
  timbre: string
}

const cuerpoCharla = {
  type: 'object',
  required: ['turnos', 'dia'],
  additionalProperties: false,
  properties: {
    turnos: {
      type: 'array',
      // Sin techo a propósito: la charla la termina la persona. El límite real
      // lo pone el tamaño del request, no una política.
      items: {
        type: 'object',
        required: ['de', 'texto'],
        additionalProperties: false,
        properties: {
          // 'laya' es de las apps viejas: ver `ROL_VIEJO`.
          de: { type: 'string', enum: ['vos', 'bitacora', 'laya'] },
          texto: { type: 'string', minLength: 1 },
        },
      },
    },
    dia: { type: 'string', pattern: DIA },
    // Si viene, el servidor adelanta el audio de la primera frase mientras
    // todavía está generando el texto, y lo devuelve en la misma respuesta.
    // Sin esto el teléfono tiene que esperar el texto entero y recién ahí
    // pedir la voz: dos etapas que se suman en vez de pisarse.
    timbre: { type: 'string', enum: ['mujer', 'hombre'] },
    // La consulta que se está preparando, si la charla se abrió con «Preparar».
    preparar: { type: 'integer', minimum: 1 },
    // El día de la charla anterior que se retomó desde el historial, si vino
    // de ahí: sus turnos van primero en `turnos` (27/10/2026).
    retoma: { type: 'string', pattern: DIA },
  },
} as const

interface CuerpoCharla {
  turnos: { de: Turno['de'] | typeof ROL_VIEJO; texto: string }[]
  dia: string
  timbre?: 'mujer' | 'hombre'
  preparar?: number
  retoma?: string
}

const cuerpoAjustes = {
  type: 'object',
  required: ['zona'],
  additionalProperties: false,
  properties: {
    zona: { type: 'string', minLength: 1, maxLength: 64 },
    // El techo no es cosmético: esto se pega dentro del system prompt de Bitácora,
    // y un campo largo y libre ahí es la puerta más obvia para meterle
    // instrucciones. Un nombre no necesita más de cuarenta caracteres.
    nombre: { type: ['string', 'null'], maxLength: 40 },
  },
} as const

const HORA = '^([01]\\d|2[0-3]):[0-5]\\d$'

const cuerpoEvento = {
  type: 'object',
  required: ['client_uuid', 'tipo', 'dia'],
  additionalProperties: false,
  properties: {
    client_uuid: { type: 'string', format: 'uuid' },
    tipo: { type: 'string', enum: ['consulta', 'otro'] },
    dia: { type: 'string', pattern: DIA },
    hora: { anyOf: [{ type: 'string', pattern: HORA }, { type: 'null' }] },
    titulo: { type: ['string', 'null'], maxLength: 80 },
  },
} as const

const cuerpoCambioDeEvento = {
  type: 'object',
  additionalProperties: false,
  minProperties: 1,
  properties: {
    dia: { type: 'string', pattern: DIA },
    hora: { anyOf: [{ type: 'string', pattern: HORA }, { type: 'null' }] },
    titulo: { type: ['string', 'null'], maxLength: 80 },
    estado: { type: 'string', enum: ['confirmado', 'descartado'] },
    evaluada: { type: 'boolean' },
  },
} as const

const paramsId = {
  type: 'object',
  required: ['id'],
  properties: { id: { type: 'integer', minimum: 1 } },
} as const

/// El resumen de cada charla se escribe un rato después de que deja de
/// crecer: la de hoy sube varias veces mientras dura, y resumirla en cada
/// subida sería pagar varias veces lo mismo. Los tests lo apagan
/// (`RESUMIR_CHARLAS=no`): no tienen que salir a ningún modelo.
/// Por base y por id: cada cuenta numera sus entradas desde uno.
const esperas = new Map<string, ReturnType<typeof setTimeout>>()
function resumirPronto(id: number) {
  if (process.env.RESUMIR_CHARLAS === 'no') return
  const clave = `${pool.options.connectionString}#${id}`
  clearTimeout(esperas.get(clave))
  esperas.set(clave, setTimeout(() => {
    esperas.delete(clave)
    resumirCharla(id).catch(e => console.warn('resumirCharla:', e instanceof Error ? e.message : e))
  }, 15_000))
}

export function construirServidor(): FastifyInstance {
  const app = Fastify({
    logger: { level: process.env.LOG_LEVEL ?? 'info' },
    // Fastify por defecto BORRA los campos que no están en el schema en vez de
    // rechazarlos. Acá el cliente y el servidor viajan juntos: un campo que el
    // servidor no conoce es un bug del cliente, y descartarlo en silencio sería
    // perder datos sin que el teléfono se entere. Mejor un 400 ruidoso.
    ajv: { customOptions: { removeAdditional: false } },
  })

  // Cada pedido con su contexto: `requiereToken` le pone la base de la cuenta.
  app.addHook('onRequest', (_req, _reply, listo) => abrirContexto(listo))

  /// Sin token a propósito: sirve para saber si el proceso está vivo desde
  /// afuera. No dice nada de la base más que si contesta.
  app.get('/health', async (_req, reply) => {
    try {
      await pool.query('select 1')
      return { ok: true, db: true }
    } catch {
      return reply.code(503).send({ ok: false, db: false })
    }
  })

  /// Guarda una conversación. Es lo único que escribe el teléfono.
  ///
  /// Idempotente por `client_uuid`: reenviar una entrada que el servidor ya
  /// recibió —el caso del timeout, donde el teléfono nunca vio la respuesta—
  /// devuelve el id que ya tenía en vez de crear un duplicado. Es lo que hace
  /// seguro que la cola offline reintente sin pensar.
  ///
  /// Desde el 19 de octubre hay UNA conversación por día que no se cierra al
  /// salir (lo pidió Dusan, para mantener el hilo), y el teléfono la manda
  /// varias veces a medida que crece. Si llega más larga que la guardada, se
  /// ACTUALIZA, y la búsqueda de consultas la vuelve a mirar. No se toca si ya
  /// se escribió su nota (el día se cerró) ni si llega más corta: un reintento
  /// viejo que llega tarde no puede pisar lo que ya había.
  app.post<{ Body: CuerpoEntrada }>(
    '/entradas',
    { preHandler: requiereToken, schema: { body: cuerpoEntrada } },
    async (req, reply) => {
      const b = req.body
      const { rows } = await pool.query<{ id: string; dia: string; creada: boolean; cambio: boolean }>(
        `
        with nueva as (
          insert into entradas (client_uuid, creado_en, creado_local, fuente,
                                transcripcion, duracion_seg)
          values ($1, $2, $3, $4, $5, $6)
          on conflict (client_uuid) where client_uuid is not null do update
            set transcripcion = excluded.transcripcion,
                duracion_seg = excluded.duracion_seg,
                consultas_revisadas_en = null
            where entradas.nota_revisada_en is null
              and length(excluded.transcripcion) > length(entradas.transcripcion)
          -- ::text a propósito. Sin el cast, el driver convierte el date a un
          -- Date de JS y sale como 2026-08-09T04:00:00.000Z, que parece un
          -- instante y no lo es. El día lógico es una fecha, y así viaja.
          -- xmax = 0 distingue la fila recién creada de la actualizada.
          returning id, dia::text as dia, (xmax = 0) as creada
        )
        select id, dia, creada, true as cambio from nueva
        union all
        select id, dia::text as dia, false, false from entradas
        where client_uuid = $1 and not exists (select 1 from nueva)
        `,
        [b.client_uuid, b.creado_en, b.creado_local, b.fuente,
         b.transcripcion.replace(ROTULO_VIEJO, 'Bitácora:'), b.duracion_seg ?? null],
      )
      const fila = rows[0]
      if (!fila) return reply.code(500).send({ error: 'no se pudo guardar' })
      if (fila.cambio) resumirPronto(Number(fila.id))
      return reply.code(fila.creada ? 201 : 200).send({ id: Number(fila.id), dia: fila.dia })
    },
  )

  app.get('/ajustes', { preHandler: requiereToken }, async () => {
    const reloj = await leerReloj()
    return { ...reloj.ajustes, dia_logico: reloj.diaLogico }
  })

  app.put<{ Body: Ajustes }>(
    '/ajustes',
    { preHandler: requiereToken, schema: { body: cuerpoAjustes } },
    async (req, reply) => {
      if (!zonaValida(req.body.zona)) {
        return reply.code(400).send({ error: `zona horaria desconocida: ${req.body.zona}` })
      }
      return guardarAjustes(req.body)
    },
  )

  /// Un turno de Bitácora.
  ///
  /// El teléfono manda el diálogo entero cada vez y el servidor no guarda
  /// sesión. Es más tráfico, pero no hay estado que expirar ni que perder si el
  /// proceso se reinicia en medio de una charla — y con una conversación que
  /// sólo termina cuando la persona quiere, "en medio" puede ser dentro de
  /// cuarenta minutos.
  ///
  /// Si el turno falla —presupuesto, timeout, un 429— NO se devuelve un error:
  /// se devuelve la despedida fija con `ok: false`. Del lado de la persona un
  /// 500 y un techo agotado son la misma cosa, y lo único que importa es que no
  /// se quede mirando una pantalla colgada mientras contaba algo pesado.
  app.post<{ Body: CuerpoCharla }>(
    '/charla',
    { preHandler: requiereToken, schema: { body: cuerpoCharla } },
    async (req) => {
      const pedido = { turnos: turnosDe(req.body.turnos), dia: req.body.dia, preparar: req.body.preparar, retoma: req.body.retoma }
      // El corte de riesgo va antes que todo, también antes del presupuesto:
      // con el techo agotado, lo que corresponde decir es esto y no «se me
      // cortó». Sin audio, aunque venga timbre: lo dice la voz del teléfono.
      if (haySenalEnLaCharla(pedido.turnos)) {
        return { ok: true, texto: MENSAJE_DE_RIESGO, cuidado: true }
      }
      try {
        // Con timbre, el audio de la primera frase viene en la misma respuesta,
        // generado mientras se escribía el texto. Sin timbre —un cliente viejo,
        // o la voz natural apagada— es el camino de siempre.
        if (req.body.timbre) {
          const { texto, audio, frase } = await siguienteTurnoConVoz(pedido, req.body.timbre)
          return {
            ok: true,
            texto,
            audio: audio ? audio.toString('base64') : null,
            // Qué parte del texto es ese audio, para que el teléfono sepa desde
            // dónde seguir pidiendo el resto.
            frase,
          }
        }
        const texto = await siguienteTurno(pedido)
        return { ok: true, texto }
      } catch (e) {
        req.log.error(e, 'falló un turno de charla')
        return { ok: false, texto: MENSAJE_DE_CORTE }
      }
    },
  )

  /// Las emociones para «Ponerle nombre», sacadas de lo que la persona contó
  /// (`herramientas.ts`). Con señales de riesgo no hay herramienta: el teléfono
  /// recibe `cuidado` y muestra lo de siempre. Nunca falla: sin modelo van las
  /// de siempre.
  app.post<{ Body: CuerpoCharla }>(
    '/herramientas/emociones',
    { preHandler: requiereToken, schema: { body: cuerpoCharla } },
    async (req) => {
      const turnos = turnosDe(req.body.turnos)
      if (haySenalEnLaCharla(turnos)) return { emociones: [], cuidado: true }
      return { emociones: await emocionesSugeridas(turnos) }
    },
  )

  /// El turno de Bitácora en vivo: texto y voz, a medida que se generan.
  ///
  /// No es JSON ni un pedido común: la respuesta queda abierta y por ella van
  /// saliendo tramas hasta que el turno termina (el formato está en `vivo.ts`).
  /// Por eso se le saca la respuesta a Fastify y se escribe a mano.
  ///
  /// Si el teléfono cierra la conexión —la persona interrumpió a Bitácora— se corta
  /// todo lo que estaba en camino. Era un pendiente viejo: antes el servidor
  /// seguía generando, y pagando, audio que ya nadie iba a escuchar.
  app.post<{ Body: CuerpoCharla }>(
    '/charla/vivo',
    { preHandler: requiereToken, schema: { body: cuerpoCharla } },
    async (req, reply) => {
      reply.hijack()
      const res = reply.raw
      res.writeHead(200, {
        'content-type': 'application/octet-stream',
        'cache-control': 'no-store',
        // Por si algún día hay un proxy adelante: que no junte la respuesta.
        'x-accel-buffering': 'no',
      })

      const corte = new AbortController()
      res.on('close', () => { if (!res.writableFinished) corte.abort() })

      const r = await turnoEnVivo(
        { turnos: turnosDe(req.body.turnos), dia: req.body.dia, preparar: req.body.preparar, retoma: req.body.retoma },
        // Sin timbre va sólo el texto: es lo que pide el teléfono cuando la
        // persona escribe, que es cuando Bitácora no habla.
        req.body.timbre ?? null,
        t => { if (!corte.signal.aborted && !res.writableEnded) res.write(t) },
        corte.signal,
      )
      if (!r.ok && !corte.signal.aborted) req.log.error(r.error, 'falló un turno de charla en vivo')
      res.end()
    },
  )

  /// El audio de un turno de Bitácora.
  ///
  /// Devuelve AAC crudo, no JSON: es lo único de toda la API que no es texto.
  ///
  /// FALLAR ACÁ NO ES GRAVE, y por eso este endpoint sí devuelve un error de
  /// verdad en vez de la despedida fija que devuelve `/charla`. Son casos
  /// distintos: si falla la charla, la persona se queda sin respuesta y hay que
  /// decirle algo; si falla la voz, el teléfono usa la de iOS y la conversación
  /// sigue sin que nadie se entere. Un 503 acá es una instrucción para el
  /// teléfono, no un mensaje para la persona.
  app.post<{ Body: CuerpoVoz }>(
    '/voz',
    { preHandler: requiereToken, schema: { body: cuerpoVoz } },
    async (req, reply) => {
      try {
        const { audio, tipo } = await sintetizar(req.body.texto, req.body.timbre as TimbreVoz)
        return reply.type(tipo).send(audio)
      } catch (e) {
        req.log.error(e, 'falló la síntesis de voz')
        // 503 y no 500: es temporal y el teléfono sabe qué hacer con esto.
        return reply.code(503).send({ ok: false })
      }
    },
  )

  /// Lo que dijiste, en tus palabras, para llevar a una sesión.
  ///
  /// Lectura pura: las notas las escribe el tick al cerrar cada día. Por
  /// defecto las dos últimas semanas — lo que suele haber entre sesión y sesión.
  app.get<{ Querystring: { desde?: string; hasta?: string } }>(
    '/notas',
    { preHandler: requiereToken,
      schema: { querystring: { type: 'object', additionalProperties: false, properties: {
        desde: { type: 'string', pattern: DIA }, hasta: { type: 'string', pattern: DIA } } } } },
    async (req) => {
      const reloj = await leerReloj()
      const hasta = req.query.hasta ?? reloj.diaLogico
      const desde = req.query.desde ?? new Date(
        Date.parse(`${hasta}T00:00:00Z`) - 13 * 864e5).toISOString().slice(0, 10)
      return { desde, hasta, notas: await notas(desde, hasta) }
    })

  /// Los eventos del calendario (`consultas.ts`). Por defecto, de dos meses
  /// atrás a seis adelante: el teléfono los pide todos juntos y guarda la copia.
  app.get<{ Querystring: { desde?: string; hasta?: string } }>(
    '/eventos',
    { preHandler: requiereToken,
      schema: { querystring: { type: 'object', additionalProperties: false, properties: {
        desde: { type: 'string', pattern: DIA }, hasta: { type: 'string', pattern: DIA } } } } },
    async (req) => {
      const hoy = (await leerReloj()).diaLogico
      const desde = req.query.desde ?? sumarDias(hoy, -60)
      const hasta = req.query.hasta ?? sumarDias(hoy, 180)
      return { desde, hasta, eventos: await listarEventos(desde, hasta) }
    })

  /// Una consulta, u otro evento, que carga la persona. Idempotente por
  /// `client_uuid`, como las entradas.
  app.post<{ Body: EventoNuevo }>(
    '/eventos',
    { preHandler: requiereToken, schema: { body: cuerpoEvento } },
    async (req, reply) => {
      if (req.body.tipo === 'otro' && !req.body.titulo?.trim()) {
        return reply.code(400).send({ error: 'un evento que no es consulta necesita un título' })
      }
      const { evento, creado } = await crearEvento(req.body)
      return reply.code(creado ? 201 : 200).send({ evento })
    })

  /// Cambiar un evento: la fecha, la hora o el título; confirmar o descartar
  /// una propuesta; o avisar que su evaluación ya está guardada en el teléfono,
  /// que es lo que borra el borrador de acá.
  app.patch<{ Params: { id: number }; Body: CambioDeEvento }>(
    '/eventos/:id',
    { preHandler: requiereToken,
      schema: { params: paramsId, body: cuerpoCambioDeEvento } },
    async (req, reply) => {
      const evento = await cambiarEvento(req.params.id, req.body)
      return evento ? { evento } : reply.code(404).send({ error: 'no existe' })
    })

  app.delete<{ Params: { id: number } }>(
    '/eventos/:id',
    { preHandler: requiereToken, schema: { params: paramsId } },
    async (req, reply) => {
      return (await borrarEvento(req.params.id)) ? reply.code(204).send()
                                                 : reply.code(404).send({ error: 'no existe' })
    })

  /// Mi espacio: la ficha entera, para que la persona vea qué sabe Bitácora
  /// de ella. `activa` es si este diario la tiene; `avisada`, si ya leyó el
  /// aviso (sin eso no se arma).
  app.get('/ficha', { preHandler: requiereToken }, async () => {
    const { rows } = await pool.query<{ avisada: boolean }>(
      'select ficha_avisada_en is not null as avisada from ajustes where id = 1')
    return { activa: fichaActiva(), avisada: rows[0]?.avisada ?? false,
             cuenta_se_borra_el: await cuentaSeBorraEl(), secciones: await fichaParaLeer() }
  })

  /// Lo que eligió llevarle a su psicólogo, para el PDF.
  app.get('/ficha/compartida', { preHandler: requiereToken }, async () =>
    ({ secciones: await fichaParaLeer(true) }))

  app.post('/ficha/aviso', { preHandler: requiereToken }, async () => {
    await marcarAvisada()
    return { ok: true }
  })

  app.patch<{ Params: { id: number }; Body: { compartir: boolean } }>(
    '/ficha/:id',
    { preHandler: requiereToken,
      schema: { params: paramsId, body: { type: 'object', additionalProperties: false, required: ['compartir'],
                                          properties: { compartir: { type: 'boolean' } } } } },
    async (req, reply) => (await compartirDato(req.params.id, req.body.compartir))
      ? { ok: true } : reply.code(404).send({ error: 'no existe' }))

  app.delete<{ Params: { id: number } }>(
    '/ficha/:id',
    { preHandler: requiereToken, schema: { params: paramsId } },
    async (req, reply) => (await quitarDato(req.params.id))
      ? reply.code(204).send() : reply.code(404).send({ error: 'no existe' }))

  /// Borrar una conversación, por el `client_uuid` que tiene el teléfono.
  /// 204 también si ya no estaba: lo que se pidió, ya pasó.
  app.delete<{ Params: { uuid: string } }>(
    '/entradas/:uuid',
    { preHandler: requiereToken,
      schema: { params: { type: 'object', required: ['uuid'],
                          properties: { uuid: { type: 'string', format: 'uuid' } } } } },
    async (req, reply) => {
      await borrarConversacion(req.params.uuid)
      return reply.code(204).send()
    })

  app.post('/cuenta/borrar', { preHandler: requiereToken }, async () =>
    ({ se_borra_el: await pedirBorrarCuenta() }))

  app.post('/cuenta/recuperar', { preHandler: requiereToken }, async () => {
    await recuperarCuenta()
    return { ok: true }
  })

  // ---- Cuentas (28/10/2026) ----------------------------------------------

  const texto = (n: number) => ({ type: ['string', 'null'], maxLength: n })
  const perfil = {
    nombre: texto(40), fecha_nacimiento: { type: ['string', 'null'], pattern: DIA },
    pais: texto(60), ciudad: texto(60), con_quien: texto(80),
  }
  const pin = { type: 'string', pattern: PIN.source }

  /// Sin token: es como se entra la primera vez. Con techo por hora, porque
  /// cada cuenta es una base nueva.
  let creadas: number[] = []
  app.post<{ Body: Perfil & { pin: string; zona: string } }>(
    '/cuentas',
    { schema: { body: { type: 'object', additionalProperties: false, required: ['pin', 'zona'],
                        properties: { ...perfil, pin, zona: { type: 'string', maxLength: 64 } } } } },
    async (req, reply) => {
      creadas = creadas.filter(t => t > Date.now() - 3600_000)
      if (creadas.length >= 10) return reply.code(429).send({ error: 'demasiadas cuentas nuevas, prueba en un rato' })
      creadas.push(Date.now())
      const { pin: p, zona, ...datos } = req.body
      return reply.code(201).send(await crearCuenta(p, datos, zona))
    })

  app.post<{ Body: { id: string; pin: string } }>(
    '/cuentas/entrar',
    { schema: { body: { type: 'object', additionalProperties: false, required: ['id', 'pin'],
                        properties: { id: { type: 'string', maxLength: 12 }, pin: { type: 'string', maxLength: 6 } } } } },
    async (req, reply) => {
      const r = await entrar(req.body.id, req.body.pin)
      if (r.ok) return { token: r.token }
      return reply.code(r.trabada_hasta ? 423 : 401).send(
        r.trabada_hasta ? { error: 'trabada', trabada_hasta: r.trabada_hasta } : { error: 'ID o PIN incorrectos' })
    })

  /// El diario de antes (token fijo) elige su PIN y recibe su ID.
  app.post<{ Body: { pin: string } }>(
    '/cuenta/pin',
    { preHandler: requiereToken,
      schema: { body: { type: 'object', additionalProperties: false, required: ['pin'], properties: { pin } } } },
    async (req, reply) => {
      if (!req.conTokenFijo) return reply.code(409).send({ error: 'esta cuenta ya tiene PIN' })
      return cuentaParaLaBase(req.body.pin)
    })

  /// Quién es la cuenta: su ID (si tiene) y lo que dio al registrarse.
  app.get('/perfil', { preHandler: requiereToken }, async (req) => {
    const { rows } = await pool.query<Perfil>(
      'select nombre, fecha_nacimiento::text as fecha_nacimiento, pais, ciudad, con_quien from ajustes where id = 1')
    const id = req.tokenDeSesion ? await idDeSesion(req.tokenDeSesion) : await idDeLaBase()
    return { id, ...rows[0] }
  })

  app.put<{ Body: Perfil }>(
    '/perfil',
    { preHandler: requiereToken,
      schema: { body: { type: 'object', additionalProperties: false, properties: perfil } } },
    async (req) => {
      await guardarPerfil(req.body)
      return { ok: true }
    })

  return app
}
