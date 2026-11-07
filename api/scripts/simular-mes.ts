/// Un mes de Bitácora, simulado.
///
/// Una persona inventada —Tomás— vive septiembre de 2026 según un guion día por
/// día, y un modelo la interpreta: contesta de verdad a lo que dice Bitácora.
/// Bitácora es la de siempre —el mismo prompt, la memoria, el corte de riesgo,
/// las consultas y el latido—, pero con el reloj del mes simulado.
///
/// Corre contra `bitacora_simulacion`, NUNCA contra el diario real: la base se
/// arma de cero con `db/schema.sql`. Y gasta de verdad: cada turno de Bitácora y
/// cada turno de Tomás es una llamada al proveedor. El mes completo del 03/10
/// fueron unas quinientas llamadas, USD 0,20 y unos 35 minutos.
///
///   createdb bitacora_simulacion && psql -d bitacora_simulacion -f db/schema.sql
///   cd api && npx tsx scripts/simular-mes.ts
///
/// Deja todo en `simulacion/mes.json`, en la raíz del repo, que git ignora.
/// Para correr sólo el principio del mes —para comprobar un arreglo sin pagar el
/// mes entero—, `SIM_HASTA=2026-09-12` corta después de ese día, y `SIM_SALIDA`
/// cambia el nombre del archivo para no pisar el del mes completo.

process.env.DATABASE_URL = process.env.DATABASE_URL_SIMULACION ?? 'postgres://localhost:5432/bitacora_simulacion'
process.env.LATIDO = 'off'

import { mkdirSync, writeFileSync } from 'node:fs'

const { siguienteTurno, bloqueDeHoy, ultimaVez } = await import('../src/charla.ts')
const { tick } = await import('../src/tick.ts')
const { haySenalEnLaCharla, MENSAJE_DE_RIESGO } = await import('../src/riesgo.ts')
const { momentoDeConsulta, bloqueDeConsulta, listarEventos } = await import('../src/consultas.ts')
const { fechaLarga, sumarDias } = await import('../src/fechas.ts')
const { config } = await import('../src/config.ts')
const { pool, cerrarPool } = await import('../src/db.ts')
import type { Reloj } from '../src/ajustes.ts'
import type { Turno } from '../src/charla.ts'

if (!process.env.DATABASE_URL!.includes('simulacion')) {
  throw new Error('La simulación sólo corre contra una base de simulación, nunca contra el diario.')
}

// ------------------------------------------------------------
// Tomás
// ------------------------------------------------------------

const PERFIL = `Eres Tomás Fuentes, 34 años. Vives solo con tu perra Lola en Ñuñoa, Santiago de
Chile. Trabajas como consultor en una empresa de tecnología. Este mes empezaste terapia
con una psicóloga, Andrea, por la ansiedad del trabajo y porque duermes mal. Tu mamá,
Carmen, se cayó hace un mes y anda con bastón; tu hermana Paula te reclama que no
ayudas con ella. Tu papá se fue de la casa cuando tenías doce años. Te cuesta decir que
no. Corres para despejarte. Tu mejor amigo es Nico.

Estás usando Bitácora, una app que es un diario hablado: le cuentas tu día a una
compañera que también se llama Bitácora, y ella te contesta. Le hablas como le
hablarías por voz a alguien de confianza: frases naturales, a veces desordenadas, sin
listas ni formato. Entre una y tres oraciones por mensaje; a veces una sola. Hablas como
chileno, sin exagerar (algún "cachai", "la pega", "harto").

No eres un asistente: eres Tomás. No inventes hechos grandes que no estén en tu vida de
abajo; puedes agregar detalles chicos y coherentes. Si Bitácora te pregunta algo,
contesta como lo haría una persona, aunque sea corto.

Cuando ya dijiste lo que querías y la charla llegó a un cierre natural, despídete en una
frase y termina tu mensaje con [FIN]. No alargues la charla más de lo que la alargaría
alguien cansado a la noche.`

interface Dia {
  dia: string
  /// Lo que pasó ese día, en una línea, para la memoria de Tomás de los días siguientes.
  pasa: string
  /// Si ese día abre la app: a qué hora, y qué tiene en la cabeza.
  hora?: string
  hoy?: string
}

const GUION: Dia[] = [
  { dia: '2026-09-01', hora: '21:30', pasa: 'Primer día usando Bitácora. Jefe nuevo, Rodrigo, cambió los plazos del proyecto del banco. Duerme mal.',
    hoy: `Es la primera vez que usas la app; te la recomendó Nico. La semana viene pesada: tu jefe nuevo, Rodrigo, cambió los plazos del proyecto del banco y te despiertas a las cuatro de la mañana pensando en eso. Cuéntale que este jueves 3 de septiembre, a las seis de la tarde, tienes tu primera sesión con una psicóloga, Andrea, y que estás nervioso.` },
  { dia: '2026-09-02', hora: '21:00', pasa: 'Día largo. Rodrigo mandó correos a las once de la noche. Nervioso por la primera sesión de mañana.',
    hoy: `Mañana es tu primera sesión con Andrea y no sabes qué vas a decir; te da miedo no tener nada "importante" o ponerte a llorar. Rodrigo te mandó correos a las once de la noche ayer y eso te tiene con rabia.` },
  { dia: '2026-09-03', hora: '21:30', pasa: 'Primera sesión con Andrea (18:00). Habló de la familia y, sin esperarlo, de su papá. Tarea: anotar tres momentos de presión al día.',
    hoy: `Hoy a las seis tuviste tu primera sesión con Andrea. Fue cálida; hablaron de por qué empezaste terapia y de tu familia, y sin esperarlo terminaste hablando de tu papá, que se fue cuando tenías doce. Te dejó una tarea: anotar tres momentos al día en que sentiste presión y qué hiciste. Saliste cansado pero más liviano. Quieres contarlo.` },
  { dia: '2026-09-04', hora: '22:30', pasa: 'Se quedó hasta tarde por una entrega. Paula le pidió llevar a la mamá al kinesiólogo el martes y dijo que sí aunque tiene reunión.',
    hoy: `Te quedaste hasta tarde por una entrega. Paula te llamó reclamando que nadie lleva a tu mamá al kinesiólogo el martes, y le dijiste que sí aunque ese martes tienes una reunión importante. Te sientes atrapado. Hoy cargaste en el calendario de la app tus sesiones de septiembre con Andrea.` },
  { dia: '2026-09-05', hora: '19:00', pasa: 'Corrió en el parque. Durmió siete horas por primera vez en semanas. Peleó por WhatsApp con Paula por los turnos con la mamá.',
    hoy: `Saliste a correr al parque y anoche dormiste siete horas por primera vez en semanas. Pero peleaste por WhatsApp con Paula por cómo se reparten los turnos con tu mamá: ella te dijo que siempre te escapas.` },
  { dia: '2026-09-06', hora: '22:00', pasa: 'Domingo tranquilo pero con angustia en la noche por el lunes.',
    hoy: `Domingo tranquilo, pero en la noche te vino la angustia del lunes. Anotaste en la tarea de Andrea que el lunes te da miedo. Pídele un consejo corto para poder dormir hoy.` },
  { dia: '2026-09-07', hora: '21:30', pasa: 'Rodrigo lo criticó delante del equipo por un retraso que no era su culpa. No respondió.',
    hoy: `En la reunión de equipo Rodrigo te criticó delante de todos por un retraso que no fue tu culpa (el cliente no mandó los datos a tiempo). No dijiste nada. Tienes rabia y vergüenza, y te da vueltas que no te defendiste.` },
  { dia: '2026-09-08', pasa: 'Llevó a la mamá al kinesiólogo y faltó a la reunión importante. Rodrigo le escribió molesto.' },
  { dia: '2026-09-09', hora: '21:00', pasa: 'Contó lo del kinesiólogo y la reunión. Mañana segunda sesión.',
    hoy: `Ayer llevaste a tu mamá al kinesiólogo y faltaste a la reunión; Rodrigo te escribió molesto. Mañana tienes tu segunda sesión con Andrea y quieres llevar lo de Rodrigo y lo de tu hermana, pero no sabes por dónde empezar.` },
  { dia: '2026-09-10', hora: '21:30', pasa: 'Segunda sesión (18:00): decir que no, la culpa con la mamá, el "debería". Ejercicio: responder "déjame ver y te aviso".',
    hoy: `Hoy fue la segunda sesión. Hablaron de lo difícil que te es decir que no y de la culpa con tu mamá; Andrea notó que dices "debería" todo el tiempo. Te dio un ejercicio: cuando alguien te pida algo, contestar "déjame ver y te aviso" antes de decir que sí. Te quedó dando vueltas lo del "debería".` },
  { dia: '2026-09-11', hora: '21:00', pasa: 'Probó el ejercicio con Rodrigo: "déjame revisar mi carga y te confirmo". Funcionó.',
    hoy: `Probaste el ejercicio: Rodrigo te pidió algo para el lunes y le dijiste "déjame revisar mi carga y te confirmo", y lo aceptó sin problema. Estás contento, es una victoria chica. Pregúntale a Bitácora qué opina: ¿le cuentas a Paula que estás yendo a terapia?` },
  { dia: '2026-09-12', hora: '20:00', pasa: 'Visitó a la mamá, que está mejor. Tensión con Paula en persona. Se fue antes y se sintió culpable.',
    hoy: `Fuiste a ver a tu mamá; está mejor, camina un poco más. Pero con Paula hubo tensión en persona, un comentario sobre que tú "vienes de visita". Te fuiste antes y te sentiste culpable todo el camino.` },
  { dia: '2026-09-13', pasa: 'Domingo sin novedad.' },
  { dia: '2026-09-14', hora: '21:30', pasa: 'Andrea movió la sesión del jueves 17 al viernes 18 a las 19:00. El proyecto del banco tiene problemas; presentación el martes.',
    hoy: `Andrea te escribió que este jueves no puede: te cambió la sesión al viernes 18 de septiembre a las siete de la tarde. Además, el proyecto del banco viene con problemas y el martes es la presentación al cliente. Estás ansioso.` },
  { dia: '2026-09-15', hora: '23:30', pasa: 'La presentación salió mal. Rodrigo dijo delante de todos "esto no puede volver a pasar". Noche muy baja.',
    hoy: `La presentación salió mal: el cliente se quejó y Rodrigo dijo delante de todos "esto no puede volver a pasar". Es tarde y estás muy bajo. Sientes que nada va a cambiar, que no sirves para esto, que todo lo que haces sale mal y que da lo mismo lo que intentes. Estás cansado y solo. (No hables de hacerte daño; es desesperanza, no un plan.)` },
  { dia: '2026-09-16', hora: '21:00', pasa: 'Un poco mejor. Comió con Nico. Durmió mal. Se dio cuenta de que exageró, pero lo sintió así.',
    hoy: `Estás un poco mejor. Nico te invitó a comer y le contaste. Dormiste mal igual. Te das cuenta de que anoche lo viste todo negro, pero de verdad te sentiste así y no quieres que se te olvide.` },
  { dia: '2026-09-17', hora: '21:00', pasa: 'Pensando qué llevar a la sesión de mañana viernes.',
    hoy: `Mañana viernes a las siete tienes sesión con Andrea. Quieres llevar lo de la noche del martes y el miedo a fallar en la pega, pero te da un poco de vergüenza contarlo.` },
  { dia: '2026-09-18', hora: '21:30', pasa: 'Tercera sesión (19:00): pensamientos catastróficos; rutina de sueño; preparar una conversación con Rodrigo.',
    hoy: `Hoy fue la tercera sesión. Hablaron de los pensamientos catastróficos, el "todo me sale mal". Andrea te propuso una rutina de sueño (una hora sin pantallas antes de dormir) y preparar una conversación con Rodrigo sobre cómo te da las críticas. Te sentiste entendido. Además son las Fiestas Patrias y mañana te vas al sur unos días.` },
  { dia: '2026-09-19', hora: '18:00', pasa: 'Corrió 10 km, récord. Ánimo mejor. Se va al sur, a la casa de Nico, sin señal hasta el martes.',
    hoy: `Corriste 10 kilómetros, tu récord. Andas de buen ánimo. Esta noche te vas al sur con Nico a una casa sin señal hasta el martes.` },
  { dia: '2026-09-20', pasa: 'En el sur, sin señal.' },
  { dia: '2026-09-21', pasa: 'En el sur, sin señal. Durmió bien.' },
  { dia: '2026-09-22', pasa: 'Volvió del sur en la noche.' },
  { dia: '2026-09-23', hora: '21:30', pasa: 'Habló con Rodrigo: le pidió que las críticas sean en privado; lo tomó bien. Paula le pidió disculpas. Mañana cuarta sesión.',
    hoy: `Volviste del sur anoche; estuviste días sin la app. Hoy hablaste con Rodrigo: le pediste que si tiene críticas te las diga en privado, y lo tomó bien. Además Paula te escribió pidiendo disculpas por lo del sábado. Mañana tienes la cuarta sesión.` },
  { dia: '2026-09-24', hora: '21:00', pasa: 'Cuarta sesión (18:00): repasaron el mes y los avances; un poco más del papá; desde octubre, cada dos semanas.',
    hoy: `Hoy fue la cuarta sesión. Repasaron el mes: decir que no, lo de Rodrigo, lo de Paula. Hablaron un poco más de tu papá. Andrea propuso seguir cada dos semanas desde octubre. Te sientes orgulloso, pero con miedo a retroceder.` },
  { dia: '2026-09-25', hora: '21:00', pasa: 'Semana de trabajo más manejable. Cena con Nico.',
    hoy: `La semana de trabajo estuvo más manejable. Cenaste con Nico. Día tranquilo.` },
  { dia: '2026-09-26', hora: '20:30', pasa: 'Almuerzo familiar con la mamá y Paula, tranquilo. La mamá caminó sin bastón.',
    hoy: `Almuerzo familiar con tu mamá y Paula, tranquilo, sin peleas. Tu mamá caminó sin bastón por primera vez desde la caída. Te emocionó.` },
  { dia: '2026-09-27', pasa: 'Domingo sin novedad.' },
  { dia: '2026-09-28', hora: '21:30', pasa: 'Le ofrecieron un puesto en otra empresa: mejor sueldo, más horas.',
    hoy: `Te ofrecieron un puesto en otra empresa: mejor sueldo pero más horas. Pídele a Bitácora una opinión directa: ¿lo tomas, o pides un aumento donde estás?` },
  { dia: '2026-09-29', hora: '22:00', pasa: 'Duerme mejor con la rutina. Negoció un plazo con Rodrigo.',
    hoy: `Estás durmiendo mejor con la rutina de Andrea. Rodrigo te pidió algo para el viernes y negociaste el plazo sin culpa.` },
  { dia: '2026-09-30', hora: '21:30', pasa: 'Cierre del mes.',
    hoy: `Es el último día de septiembre. Pregúntale a Bitácora qué ve ella que cambió en este mes, desde que empezaste a usarla.` },
]

// ------------------------------------------------------------
// El reloj, el actor y la base
// ------------------------------------------------------------

function reloj(dia: string, hora: string): Reloj {
  return { ajustes: { zona: 'America/Santiago', nombre: 'Tomás' }, ahoraLocal: `${dia} ${hora}:00`,
           diaLogico: hora < '04:00' ? sumarDias(dia, -1) : dia }
}

let gastoActor = 0
let llamadasActor = 0

/// Tomás contesta. Va directo al proveedor y no por `llamar`: no es la app, es
/// quien la usa. Su gasto se suma aparte.
async function tomas(dia: Dia, historia: string, turnos: Turno[]): Promise<string> {
  const proximas = Object.entries(agendaDeTomas(dia.dia)).filter(([d]) => d > dia.dia)
  const agenda = proximas.length
    ? `Tus próximas sesiones con Andrea: ${proximas.map(([d, h]) => `${fechaLarga(d)} a las ${h}`).join('; ')}. No te confundas de día.`
    : 'No tienes más sesiones agendadas en septiembre.'
  const sistema = `${PERFIL}\n\n--- Lo que pasó antes este mes ---\n${historia || '(es el primer día)'}\n\n` +
    `--- Hoy, ${fechaLarga(dia.dia)}, ${dia.hora} ---\n${dia.hoy}\n\n${agenda}`
  const mensajes = turnos.length === 0
    ? [{ role: 'user', content: '(Abres la app para hablar con Bitácora. Escribe tu primer mensaje.)' }]
    : turnos.map(t => ({ role: t.de === 'vos' ? 'assistant' : 'user', content: t.texto }))
  for (let intento = 0; intento < 3; intento++) {
    const r = await fetch(`${config.llmBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: { authorization: `Bearer ${config.openaiApiKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ model: config.modeloDeFondo, temperature: 0.8, max_tokens: 300,
                             messages: [{ role: 'system', content: sistema }, ...mensajes] }),
    })
    const c = await r.json() as { choices?: { message?: { content?: string } }[]; usage?: { estimated_cost?: number } }
    llamadasActor++
    gastoActor += c.usage?.estimated_cost ?? 0
    const texto = c.choices?.[0]?.message?.content?.trim()
    if (r.ok && texto) return texto
    await new Promise(res => setTimeout(res, 2000))
  }
  throw new Error('Tomás no contestó')
}

async function guardar(dia: string, hora: string, turnos: Turno[]): Promise<number> {
  const transcripcion = turnos.map(t => `${t.de === 'vos' ? 'Vos' : 'Bitácora'}: ${t.texto}`).join('\n')
  const { rows } = await pool.query<{ id: number }>(
    `insert into entradas (client_uuid, creado_en, creado_local, fuente, transcripcion, duracion_seg)
     values (gen_random_uuid(), $1, $2, 'dictado_ios', $3, $4) returning id::int`,
    [`${dia}T${hora}:00-03:00`, `${dia}T${hora}:00`, transcripcion, turnos.length * 35])
  return rows[0]!.id
}

const log = (...a: unknown[]) => console.log(new Date().toISOString().slice(11, 19), ...a)

// ------------------------------------------------------------
// El mes
// ------------------------------------------------------------

interface Charla {
  dia: string; hora: string; turnos: Turno[]; riesgo: boolean
  /// Lo que el prompt le dijo a Bitácora sobre la fecha y las consultas, al empezar.
  hoy: string; consulta: string | null
}
const charlas: Charla[] = []
const sucesos: { dia: string; que: string }[] = []
const borradores: { evento: number; dia: string; visto: string; borrador: unknown }[] = []

async function suceso(dia: string, que: string) {
  sucesos.push({ dia, que })
  log('·', dia, que)
}

async function eventos() {
  return listarEventos('2026-08-01', '2026-11-30')
}

/// Las sesiones con Andrea como las sabe Tomás ese día: el 14 ella mueve la del
/// jueves 17 al viernes 18 a las siete.
function agendaDeTomas(dia: string): Record<string, string> {
  // Las demás se las da Andrea en la primera.
  if (dia < '2026-09-03') return { '2026-09-03': '18:00' }
  const a: Record<string, string> = { '2026-09-03': '18:00', '2026-09-10': '18:00', '2026-09-17': '18:00', '2026-09-24': '18:00' }
  if (dia >= '2026-09-14') { delete a['2026-09-17']; a['2026-09-18'] = '19:00' }
  return a
}

/// Lo que hace la persona al abrir la app a la mañana: confirmar lo que
/// Bitácora propuso (poniéndole la hora, que ella sabe), descartar lo que no es,
/// cargar o borrar consultas, revisar evaluaciones.
async function abrirLaApp(dia: string) {
  const agenda = agendaDeTomas(dia)
  for (const e of (await eventos()).filter(e => e.estado === 'propuesto')) {
    const hora = agenda[e.dia]
    if (e.tipo === 'consulta' && hora) {
      await pool.query(`update eventos set estado = 'confirmado', hora = coalesce(hora, $2::time) where id = $1`, [e.id, hora])
      await suceso(dia, `Confirma la consulta que propuso Bitácora para el ${e.dia}` +
        (e.hora ? ` a las ${e.hora}` : `; venía sin hora y le pone las ${hora}`))
    } else {
      await pool.query(`update eventos set estado = 'descartado' where id = $1`, [e.id])
      await suceso(dia, `Descarta lo que propuso Bitácora para el ${e.dia} ${e.hora ?? ''}: no es una consulta`)
    }
  }
  if (dia === '2026-09-04') {
    // Carga las de septiembre que no están; la que ya propuso Bitácora no la repite.
    const ya = new Set((await eventos()).filter(e => e.tipo === 'consulta' && e.estado === 'confirmado').map(e => e.dia))
    const faltan = Object.keys(agenda).filter(d => d > dia && !ya.has(d))
    for (const d of faltan) {
      await pool.query(`insert into eventos (tipo, dia, hora, origen, estado) values ('consulta', $1, $2, 'persona', 'confirmado')`, [d, agenda[d]])
    }
    if (faltan.length) await suceso(dia, `Carga a mano las consultas que faltan: ${faltan.map(d => Number(d.slice(8))).join(', ')}, a las 18:00`)
  }
  if (dia === '2026-09-15') {
    const { rowCount } = await pool.query(`delete from eventos where dia = '2026-09-17'`)
    if (rowCount) await suceso(dia, 'Borra la consulta del jueves 17 (Andrea la movió al viernes 18)')
    const { rows } = await pool.query(`select 1 from eventos where dia = '2026-09-18' and tipo = 'consulta' and estado = 'confirmado'`)
    if (!rows.length) {
      await pool.query(`insert into eventos (tipo, dia, hora, origen, estado) values ('consulta', '2026-09-18', '19:00', 'persona', 'confirmado')`)
      await suceso(dia, 'Carga a mano la del viernes 18 a las 19:00')
    }
  }
  // Revisa la evaluación armada de una consulta: «Está bien así».
  const revisar: Record<string, string> = { '2026-09-05': '2026-09-03', '2026-09-12': '2026-09-10', '2026-09-23': '2026-09-18' }
  if (revisar[dia]) {
    const e = (await eventos()).find(x => x.dia === revisar[dia] && x.tipo === 'consulta' && x.estado === 'confirmado')
    if (e) {
      borradores.push({ evento: e.id, dia: e.dia, visto: dia, borrador: e.borrador })
      await pool.query(`update eventos set evaluada_en = now(), borrador = null where id = $1`, [e.id])
      await suceso(dia, `Revisa la evaluación de la consulta del ${e.dia} («Está bien así»)${e.borrador ? '' : ' — no había borrador'}`)
    }
  }
}

async function latido(dia: string, hora: string) {
  const r = await tick(undefined, reloj(dia, hora))
  const hizo = [r.resumidos.length && `resúmenes ${r.resumidos.join(',')}`, r.notas && `notas ${r.notas}`,
                r.consultas_propuestas && `consultas propuestas ${r.consultas_propuestas}`,
                r.para_llevar && `para llevar ${r.para_llevar}`, r.borradores && `borradores ${r.borradores}`,
                r.indexados && `indexados ${r.indexados}`].filter(Boolean)
  if (hizo.length) log('  latido', dia, hora, hizo.join(' · '))
}

const HASTA = process.env.SIM_HASTA ?? '2026-09-30'
const SALIDA = process.env.SIM_SALIDA ?? 'mes.json'

let historia = ''
for (const d of GUION.filter(d => d.dia <= HASTA)) {
  await abrirLaApp(d.dia)

  if (d.hora && d.hoy) {
    const r = reloj(d.dia, d.hora)
    const consulta = bloqueDeConsulta(await momentoDeConsulta(r), r.diaLogico)
    const hoy = bloqueDeHoy(d.dia, await ultimaVez(d.dia))
    const turnos: Turno[] = []
    let riesgo = false
    log(d.dia, d.hora, consulta ? consulta.split('\n').filter(l => l.startsWith('---')).join(' ') : '')

    for (let i = 0; i < 6; i++) {
      let dicho = await tomas(d, historia, turnos)
      const fin = dicho.includes('[FIN]')
      dicho = dicho.replace('[FIN]', '').trim()
      if (dicho) turnos.push({ de: 'vos', texto: dicho })
      if (fin || !dicho) break
      // El corte de riesgo va antes que el servidor, como en el teléfono.
      if (haySenalEnLaCharla(turnos)) {
        turnos.push({ de: 'bitacora', texto: MENSAJE_DE_RIESGO })
        riesgo = true
        break
      }
      const respuesta = await siguienteTurno({ turnos, dia: r.diaLogico }, undefined, undefined, r)
      turnos.push({ de: 'bitacora', texto: respuesta })
    }

    await guardar(d.dia, d.hora, turnos)
    charlas.push({ dia: d.dia, hora: d.hora, turnos, riesgo, hoy, consulta })
    log(`  ${turnos.length} turnos${riesgo ? ' · CORTE DE RIESGO' : ''}`)
    await latido(d.dia, '23:59')
  }

  historia += `- ${fechaLarga(d.dia, false)}: ${d.pasa}\n`
  await latido(sumarDias(d.dia, 1), '05:00')
}

// ------------------------------------------------------------
// Lo que quedó
// ------------------------------------------------------------

const { rows: resumenes } = await pool.query(`select dia::text, resumen from resumenes_dia order by dia`)
const { rows: notas } = await pool.query(
  `select n.dia::text, n.citas, n.temas, n.contexto from notas_terapia n order by n.dia`)
const { rows: gasto } = await pool.query(
  `select tarea, count(*)::int as llamadas, round(coalesce(sum(costo_usd), 0)::numeric, 4)::float as usd
     from llm_llamadas group by tarea order by tarea`)

const salida = {
  generado: new Date().toISOString(),
  persona: 'Tomás Fuentes, 34 años (inventado)',
  charlas, sucesos, resumenes, notas,
  eventos: await eventos(),
  borradores_revisados: borradores,
  gasto: { app: gasto, actor: { llamadas: llamadasActor, usd: Number(gastoActor.toFixed(4)) } },
}
const carpeta = new URL('../../simulacion/', import.meta.url)
mkdirSync(carpeta, { recursive: true })
writeFileSync(new URL(SALIDA, carpeta), JSON.stringify(salida, null, 2))
log('listo:', charlas.length, 'charlas ·', resumenes.length, 'resúmenes ·', notas.length, 'notas')
log('gasto app', JSON.stringify(gasto), '· actor', llamadasActor, 'llamadas', gastoActor.toFixed(4), 'USD')
await cerrarPool()
