import { pool } from './db.ts'
import { llamar } from './llm.ts'
import { haySenal, normalizar } from './riesgo.ts'
import { bloqueDePatrones } from './patrones.ts'

/// La ficha viva del paciente (27/10/2026, etapa 1 del plan «Ficha viva»).
///
/// Bitácora recordaba pero no conocía: tenía resúmenes de días y nada que dijera
/// quién es la persona. La ficha se arma de a poco, una conversación por vez,
/// y entra al prompt de cada charla.
///
/// LOS RELATOS NO SE TOCAN. La ficha se deriva de `entradas` y se puede tirar y
/// reconstruir desde cero. El sistema nunca borra un dato: lo viejo pierde peso
/// (`peso`), y el progreso se registra como filas nuevas que dicen qué cambió.
///
/// EL MODELO NO ESCRIBE LA FICHA. Propone operaciones, cada una con la frase
/// tal cual la dijo la persona, y acá se busca esa frase en la conversación:
/// si no está, la operación no entra. Es la red contra el invento, que es el
/// riesgo real de dejar que un modelo arme un perfil.
///
/// SIN DIAGNÓSTICOS Y SIN RIESGO. Palabras de todos los días, sólo lo que
/// contó. Lo del riesgo va por su carril (`riesgo.ts`) y no entra acá.

export const TIPOS = ['persona', 'problematica', 'desencadenante', 'meta',
                      'le_sirve', 'no_le_sirve', 'dato', 'como_hablarle'] as const
export type Tipo = typeof TIPOS[number]
const DIFERENCIAS = ['primera', 'mejoro', 'empeoro', 'igual', 'cambio_de_foco'] as const
/// Cuándo le sirve (o no) algo. Pocos y de todos los días, para poder contarlos.
export const MOMENTOS = ['al despertar', 'en la mañana', 'en la tarde', 'en la noche', 'de madrugada',
                         'antes de dormir', 'en el trabajo', 'con otras personas', 'estando solo'] as const

/// Sólo para las personas que la activaron: el resto de los clientes todavía
/// no recibió el aviso de que se arma una ficha (principio de transparencia).
export function fichaActiva(): boolean {
  return process.env.FICHA_ACTIVA === 'si'
}

/// Activa, y además la persona ya leyó el aviso desde Mi espacio, y no pidió
/// borrar su cuenta. Sin el aviso, la ficha no se arma ni entra a la charla.
export async function fichaEncendida(): Promise<boolean> {
  if (!fichaActiva()) return false
  // Si falta el delta 11, apagada: la charla no puede romperse por la ficha.
  const { rows } = await pool.query<{ ok: boolean }>(
    `select ficha_avisada_en is not null and cuenta_borrar_en is null as ok from ajustes where id = 1`)
    .catch(() => ({ rows: [] as { ok: boolean }[] }))
  return rows[0]?.ok ?? false
}

const CLINICAS = /depresi|trastorno|ansiedad generalizada|bipolar|tept|\btoc\b|p[aá]nico|disociaci|fobia|burnout|s[ií]ndrome|diagn/i

const SISTEMA = `Armas la ficha de una persona que usa un diario hablado. Te paso la
ficha como está hoy y una conversación nueva. Propones operaciones para
actualizarla. No reescribes la ficha: sólo dices qué agregar o reforzar.

Tipos de dato:
- persona: alguien de su vida (su jefe, sus papás, un amigo). Nombre corto como
  ella lo dice: «su jefe», «sus papás», «Rodrigo».
- problematica: algo que le pasa y le pesa, con palabras de todos los días
  («le cuesta dormir», «se siente sin propósito»).
- desencadenante: lo que lo activa («la plata», «la noche», «compararse»).
- meta: algo que quiere lograr. Si dice POR QUÉ o qué le cambiaría («quiero
  irme de la casa para no depender de mis papás»), agrega una "conexion" desde
  la meta hacia ese problema, con relación «busca resolver». Sólo si lo dijo.
- le_sirve / no_le_sirve: algo que contó que le ayudó o no («salir a caminar»,
  «que le hagan preguntas abstractas»).
- dato: quién es, SÓLO lo que contó él mismo («estudia», «vive con sus papás»).
  Si cuenta por qué empezó a hablar con Bitácora, va como dato con el nombre
  «lo que lo trajo a Bitácora». Va UNA sola vez: lo que trae una charla del día no es eso.
  En "le_sirve" y "no_le_sirve", "momento" dice CUÁNDO le sirvió o no, si lo
  dijo o se entiende por la hora o lo que contaba: al despertar, en la mañana,
  en la tarde, en la noche, de madrugada, antes de dormir, en el trabajo, con
  otras personas, estando solo. Si no se sabe, null. Y si DIJO que le sirvió
  PARA algo concreto («la respiración me calmó y me pude dormir»), agrega una
  "conexion" con relación «le ayuda con» hacia eso, con la cita donde lo dice.
  Si sólo contó que le hizo bien, sin decir para qué, no inventes el para qué.
- como_hablarle: cómo prefiere que le hablen, si lo dijo o se nota en cómo
  reaccionó («le sirven las ideas concretas»).

Operaciones:
- nodo: agrega un dato o lo refuerza si ya está en la ficha (usa el MISMO nombre
  que tiene en la ficha). "descripcion": una línea en palabras de todos los días.
  "apodo": otra forma en que lo nombró, si la hay («el de la oficina»).
  APODOS: si nombra algo que YA está en la ficha con otra palabra («el viejo»
  por «su papá», «la pega» por «el trabajo»), usa el nombre de la ficha y pon la
  palabra nueva en "apodo". Sólo cuando es claro que es lo mismo. Un apodo es
  un NOMBRE corto (una a tres palabras: «el viejo», «la pega»), nunca una frase
  («me sentí presionado» no es un apodo). Sin apodo, null. En la ficha,
  entre paréntesis, ves cómo más le dice a cada cosa.
- conexion: une dos datos («su jefe» desencadena «le cuesta dormir»). Los dos
  tienen que estar en la ficha o en tus operaciones. "relacion" en pocas
  palabras: «desencadena», «le ayuda con», «busca mejorar», «le preocupa».
- progreso: cómo está HOY con una problemática que ya existe, comparado con lo
  último que dice la ficha. "diferencia": primera, mejoro, empeoro, igual o
  cambio_de_foco. "como_estaba" y "cita" hablan de ESA problemática, no de otra
  («le cuesta dormir» lleva una frase sobre dormir). "como_estaba" lo escribes
  tú, con lo de esta conversación: nunca copies el estado anterior.

Reglas:
- "cita": la frase EXACTA que dijo la persona (líneas "Vos:"), copiada letra por
  letra, de cuatro a veinticinco palabras. Lo que dijo Bitácora no cuenta. Sin
  cita exacta, no hay operación.
- Nunca diagnósticos ni palabras clínicas. Nunca supongas: ni edad, ni trabajo,
  ni nada que no haya dicho.
- Nada de riesgo, autolesión ni ganas de no vivir: eso no va en la ficha.
- CONTAR LO QUE VUELVE. Si la conversación vuelve a tocar EXACTAMENTE algo que
  ya está en la ficha, emite un "nodo" con su nombre exacto y una cita de esta
  conversación, aunque no traiga nada nuevo: así se sabe cuántas veces lo
  habló. Hazlo con cada tema que vuelva, empezando por lo que le pasa.
- NO JUNTES TEMAS DISTINTOS. Reforzar es sólo para lo mismo dicho de otra
  forma. Cosas distintas van separadas aunque estén relacionadas: «se siente
  sin propósito», «no tener trabajo a su edad», «le cuesta dormir» y «días
  decepcionantes» son cuatro datos, no uno. Si se relacionan, únelos con una
  "conexion". Si ningún dato de la ficha es ESE tema, abre uno nuevo.
- La "cita" de un nodo habla de ese dato: «No puedo dormir» refuerza «le cuesta
  dormir», no «días decepcionantes».
- Si la conversación no trae nada nuevo ni vuelve sobre nada, devuelve la lista
  vacía.
- Pocas y buenas: como mucho quince operaciones.
- NO REPITAS CON OTRO NOMBRE. Si en la ficha ya hay algo que dice lo mismo
  («no tener un trabajo fijo» y «no estar trabajando a su edad»), refuerza ése
  con su nombre exacto; no abras uno nuevo.
- "dato" es quién es, algo que sigue siendo cierto mañana («estudia
  programación», «vive con sus papás»). Lo que pasó un día («hoy fue un día
  raro», «tuvo una conversación») no es un dato.
- METAS CON SU PARA QUÉ. Cada vez que agregas o refuerzas una meta y la
  conversación dice qué problema le resolvería, la "conexion" meta → «busca
  resolver» → problema es obligatoria. Ejemplo: «quiero juntar plata para irme
  a vivir solo y dejar de depender de mis papás» da la meta «irse a vivir solo»
  y la conexión «irse a vivir solo» → busca resolver → «depender de sus papás».
- La persona misma no va en "persona": su gente son los demás.
- "como_estaba" sin fechas: cómo está, en palabras.`

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['operaciones'],
  properties: {
    operaciones: {
      type: 'array',
      maxItems: 15,
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['accion', 'tipo', 'nombre', 'descripcion', 'apodo', 'momento', 'hacia_tipo', 'hacia_nombre',
                   'relacion', 'como_estaba', 'diferencia', 'cita'],
        properties: {
          accion: { type: 'string', enum: ['nodo', 'conexion', 'progreso'] },
          tipo: { type: 'string', enum: [...TIPOS] },
          nombre: { type: 'string' },
          descripcion: { type: ['string', 'null'] },
          apodo: { type: ['string', 'null'] },
          momento: { type: ['string', 'null'], enum: [...MOMENTOS, null] },
          hacia_tipo: { type: ['string', 'null'], enum: [...TIPOS, null] },
          hacia_nombre: { type: ['string', 'null'] },
          relacion: { type: ['string', 'null'] },
          como_estaba: { type: ['string', 'null'] },
          diferencia: { type: ['string', 'null'], enum: [...DIFERENCIAS, null] },
          cita: { type: 'string' },
        },
      },
    },
  },
} as const

export interface Operacion {
  accion: 'nodo' | 'conexion' | 'progreso'
  tipo: Tipo
  nombre: string
  descripcion: string | null
  apodo: string | null
  momento?: typeof MOMENTOS[number] | null
  hacia_tipo: Tipo | null
  hacia_nombre: string | null
  relacion: string | null
  como_estaba: string | null
  diferencia: typeof DIFERENCIAS[number] | null
  cita: string
}

/// Lo que dijo la persona, sin lo de Bitácora.
export function loQueDijo(transcripcion: string): string {
  return transcripcion.split('\n').filter(l => l.startsWith('Vos:')).map(l => l.slice(4).trim()).join('\n')
}

/// Sin tildes ni signos y en minúscula, para que una coma de más o una tilde
/// que el modelo corrigió no tumbe una cita que es la misma frase.
const TRAJO = 'lo que lo trajo a Bitácora'

function plano(t: string): string {
  return normalizar(t).replace(/[^a-zñ0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim()
}

/// El validador: la cita tiene que estar en lo que dijo la persona.
export function citaValida(cita: string, dicho: string): boolean {
  const c = plano(cita)
  return c.split(' ').length >= 4 && plano(dicho).includes(c)
}

/// Qué operaciones entran. Las que no pasan se descartan en silencio: mejor
/// una ficha corta que una con algo que no dijo.
/// Un apodo es un nombre corto, no una frase, y no es el mismo nombre con
/// otro posesivo («mi primo» para «su primo» no dice nada nuevo).
export function apodoValido(apodo: string | null, nombre: string): string | null {
  const a = apodo?.trim()
  if (!a || a.split(/\s+/).length > 3) return null
  const sinPosesivo = (t: string) => plano(t).replace(/^(mi|mis|su|sus|el|la|los|las) /, '')
  if (sinPosesivo(a) === sinPosesivo(nombre)) return null
  // Con un verbo conjugado en primera persona es una frase, no un nombre.
  if (/\b(me|estoy|tengo|siento|senti|encontre|voy|quiero)\b/.test(plano(a))) return null
  return a
}

export function validar(ops: Operacion[], dicho: string): Operacion[] {
  return ops.filter(o =>
    citaValida(o.cita, dicho)
    && !haySenal(o.cita)
    && !CLINICAS.test(`${o.nombre} ${o.descripcion ?? ''} ${o.como_estaba ?? ''}`)
    && o.nombre.trim().length > 1
    && (o.accion !== 'conexion' || (o.hacia_tipo && o.hacia_nombre && o.relacion))
    && (o.accion !== 'progreso' || (o.tipo === 'problematica' && o.como_estaba && o.diferencia)))
    // Una conexión sólo si la charla habla de aquello a lo que apunta: el modelo
    // unía «salir a caminar» con «le cuesta dormir», o «su papá» con el sueño,
    // en charlas que no nombraban el sueño.
    .filter(o => !(o.accion === 'conexion' && !hablaDe(dicho, o.hacia_nombre ?? '')))
    // El modelo a veces copia la nota de la ficha dentro del nombre («que le
    // cuenten un cuento (también le dice: …)»): se le saca.
    .map(o => ({ ...o, nombre: sinNota(o.nombre), hacia_nombre: o.hacia_nombre && sinNota(o.hacia_nombre) }))
    // Y un apodo tiene que haberlo dicho ella: «ejercicio de respiración» lo
    // dijo Bitácora, y terminó como otro nombre de «que le cuenten un cuento».
    .map(o => ({ ...o, apodo: o.apodo && plano(dicho).includes(plano(o.apodo)) ? apodoValido(o.apodo, o.nombre) : null }))
}

function sinNota(nombre: string): string {
  return nombre.replace(/\s*\((también le dice|le dice también|cómo estaba)[^)]*\)\s*/gi, ' ').trim()
}

const VACIAS = new Set(['esta', 'este', 'como', 'algo', 'para', 'pero', 'todo', 'cosa', 'hace', 'tiene',
                        'tengo', 'estoy', 'siento', 'sentir', 'siente', 'cuando', 'porque', 'mucho', 'poco'])
function raices(t: string): Set<string> {
  return new Set(plano(t).split(' ').filter(p => p.length >= 4 && !VACIAS.has(p)).map(p => p.slice(0, 4)))
}

/// Si una frase comparte alguna palabra (por la raíz) con el nombre de un dato.
export function hablaDe(cita: string, nombre: string): boolean {
  const r = raices(nombre)
  return [...raices(cita)].some(x => r.has(x))
}

/// Revisa una conversación: le pide operaciones al modelo, las valida y las
/// aplica. Devuelve cuántas entraron.
export async function revisarEntrada(id: number, llamada = llamar): Promise<number> {
  const { rows } = await pool.query<{ transcripcion: string; dia: string }>(
    'select transcripcion, dia::text as dia from entradas where id = $1', [id])
  const e = rows[0]
  if (!e) return 0
  const dicho = loQueDijo(e.transcripcion)
  let aplicadas = 0
  if (dicho.length >= 60) {
    const { datos } = await llamada<{ operaciones: Operacion[] }>({
      tarea: 'ficha',
      refId: id,
      sistema: SISTEMA,
      usuario: `La ficha hoy:\n${await fichaParaElModelo()}\n\nLa conversación nueva (${e.dia}):\n${e.transcripcion}`,
      nombreSchema: 'ficha',
      schema: SCHEMA as unknown as Record<string, unknown>,
    })
    aplicadas = await aplicar(validar(datos.operaciones ?? [], dicho), id, e.dia)
  }
  await pool.query('update entradas set ficha_revisada_en = now() where id = $1', [id])
  return aplicadas
}

async function nodo(tipo: Tipo, nombre: string, dia: string, descripcion: string | null,
                    apodo: string | null): Promise<number> {
  const { rows } = await pool.query<{ id: string }>(
    `insert into ficha_nodos (tipo, nombre, descripcion, apodos, primera, ultima)
     values ($1, $2, $3, case when $4::text is null then '{}' else array[$4::text] end, $5, $5)
     on conflict (tipo, lower(nombre)) do update set
       veces = ficha_nodos.veces + 1,
       ultima = greatest(ficha_nodos.ultima, excluded.ultima),
       -- La primera descripción queda: la de otra charla pisaba la buena con
       -- algo de otro tema («recuerdos de su ex» terminó hablando de sus papás).
       descripcion = coalesce(ficha_nodos.descripcion, excluded.descripcion),
       apodos = case when $4::text is null or $4::text = any(ficha_nodos.apodos) then ficha_nodos.apodos
                     else ficha_nodos.apodos || $4::text end
     returning id`,
    [tipo, nombre.trim(), descripcion, apodo?.trim() || null, dia])
  return Number(rows[0]!.id)
}

/// El nombre con que está en la ficha algo que se nombró por su nombre o por
/// un apodo: «el viejo» es «su papá» si ya se anotó así. Si no está, el mismo.
async function canonico(tipo: Tipo | null, nombre: string): Promise<{ id: number; nombre: string } | null> {
  const { rows } = await pool.query<{ id: number; nombre: string }>(
    `select id::int, nombre from ficha_nodos
      where borrado_en is null and ($2::text is null or tipo = $2)
        and (lower(nombre) = lower($1) or lower($1) = any(select lower(a) from unnest(apodos) a))
      order by (lower(nombre) = lower($1)) desc, veces desc limit 1`, [nombre.trim(), tipo])
  return rows[0] ?? null
}

/// Para las conexiones: si ya hay un dato con ese nombre, es ése, aunque el
/// modelo le haya puesto otro tipo. Si no, «días decepcionantes» terminaba en
/// «Su gente» al lado del de «Lo que le pasa».
async function existenteONuevo(tipo: Tipo, nombre: string, dia: string): Promise<number> {
  const c = await canonico(tipo, nombre) ?? await canonico(null, nombre)
  return c ? c.id : nodo(tipo, nombre, dia, null, null)
}

async function aplicar(ops: Operacion[], entrada: number, dia: string): Promise<number> {
  let n = 0
  for (let o of ops) {
    if (o.accion === 'nodo') {
      // Por el apodo también: si dijo «el viejo» y ya está «su papá» con ese
      // apodo, es ése. Y el nombre que usó ahora, si es otro, queda de apodo.
      const c = await canonico(o.tipo, o.nombre)
      if (c && c.nombre.toLowerCase() !== o.nombre.trim().toLowerCase()) {
        o = { ...o, apodo: o.apodo ?? o.nombre, nombre: c.nombre }
      }
      o = { ...o, apodo: apodoValido(o.apodo, o.nombre) }
      // Lo que lo trajo se cuenta una sola vez: el modelo le pegaba lo que
      // traía cada charla del día («no puedo dormir») y llegaba a 9 veces.
      if (o.tipo === 'dato' && plano(o.nombre) === plano(TRAJO) &&
          (await pool.query('select 1 from ficha_nodos where tipo = $1 and lower(nombre) = lower($2)',
                            ['dato', TRAJO])).rowCount) continue
      // Una vez por conversación: si en esta ya se reforzó, sólo suma la frase.
      const { rows: ya } = await pool.query<{ id: string }>(
        `select n.id from ficha_nodos n join ficha_evidencias e on e.nodo_id = n.id
          where n.tipo = $1 and lower(n.nombre) = lower($2) and e.entrada_id = $3 limit 1`,
        [o.tipo, o.nombre.trim(), entrada])
      const id = ya[0] ? Number(ya[0].id) : await nodo(o.tipo, o.nombre, dia, o.descripcion, o.apodo)
      await pool.query('insert into ficha_evidencias (nodo_id, entrada_id, dia, cita) values ($1, $2, $3, $4)',
        [id, entrada, dia, o.cita])
      // Cuándo le sirvió: se cuenta por momento, una vez por conversación.
      if (o.momento && MOMENTOS.includes(o.momento) && (o.tipo === 'le_sirve' || o.tipo === 'no_le_sirve') && !ya[0]) {
        await pool.query(
          `update ficha_nodos set momentos = jsonb_set(momentos, array[$2::text],
             to_jsonb(coalesce((momentos ->> $2)::int, 0) + 1)) where id = $1`, [id, o.momento])
      }
    } else if (o.accion === 'conexion') {
      const a = await existenteONuevo(o.tipo, o.nombre, dia)
      const b = await existenteONuevo(o.hacia_tipo!, o.hacia_nombre!, dia)
      const { rows } = await pool.query<{ id: string }>(
        `insert into ficha_conexiones (desde, hacia, relacion, primera, ultima) values ($1, $2, $3, $4, $4)
         on conflict (desde, hacia, relacion) do update set
           veces = ficha_conexiones.veces + 1, ultima = greatest(ficha_conexiones.ultima, excluded.ultima)
         returning id`, [a, b, o.relacion!.trim(), dia])
      await pool.query('insert into ficha_evidencias (conexion_id, entrada_id, dia, cita) values ($1, $2, $3, $4)',
        [Number(rows[0]!.id), entrada, dia, o.cita])
    } else {
      const { rows } = await pool.query<{ id: string }>(
        `select id from ficha_nodos where tipo = 'problematica' and borrado_en is null
            and (lower(nombre) = lower($1) or lower($1) = any(select lower(a) from unnest(apodos) a))`,
        [o.nombre.trim()])
      if (!rows[0]) continue
      // Un «cómo va» copiado del anterior no dice nada nuevo: pasaba, y
      // quedaba una frase de otro día pegada a la de hoy.
      const { rows: antes } = await pool.query<{ como_estaba: string }>(
        'select como_estaba from ficha_progreso where nodo_id = $1', [Number(rows[0].id)])
      if (antes.some(a => plano(a.como_estaba) === plano(o.como_estaba!))) continue
      // Y la frase tiene que hablar de ese tema: sin ninguna palabra en común
      // con su nombre, es de otro («No puedo dormir» en «días decepcionantes»).
      if (!hablaDe(o.cita, o.nombre)) continue
      await pool.query(
        `insert into ficha_progreso (nodo_id, entrada_id, dia, como_estaba, cita, diferencia)
         values ($1, $2, $3, $4, $5, $6)`, [Number(rows[0].id), entrada, dia, o.como_estaba, o.cita, o.diferencia])
    }
    n++
  }
  return n
}

/// Las conversaciones de días ya cerrados que la ficha todavía no leyó.
export async function pendientes(hoy: string): Promise<number[]> {
  const { rows } = await pool.query<{ id: string }>(
    `select id from entradas where ficha_revisada_en is null and dia < $1 order by creado_local`, [hoy])
  return rows.map(r => Number(r.id))
}

// ---------------------------------------------------------------------------
// Leer la ficha

interface NodoLeido {
  id: number; tipo: Tipo; nombre: string; descripcion: string | null; veces: number; apodos: string[]
  momentos: Record<string, number>
  primera: string; ultima: string; compartir: boolean
}

/// Pesa más lo que aparece seguido y lo reciente: la mitad cada cuarenta y
/// cinco días. Lo viejo no se borra, baja.
export function peso(veces: number, diasDesde: number): number {
  return veces * Math.pow(0.5, diasDesde / 45)
}

async function nodos(): Promise<(NodoLeido & { peso: number })[]> {
  const { rows } = await pool.query<NodoLeido & { dias: number }>(
    `select id::int, tipo, nombre, descripcion, apodos, momentos, veces, primera::text as primera, ultima::text as ultima, compartir,
            (current_date - ultima)::int as dias
     from ficha_nodos where borrado_en is null`)
  return rows.map(r => ({ ...r, peso: peso(r.veces, Math.max(0, r.dias)) })).sort((a, b) => b.peso - a.peso)
}

/// Lo que ve el modelo que arma la ficha: los nombres tal cual, para que los
/// reuse en vez de inventar «el jefe» al lado de «su jefe».
async function fichaParaElModelo(): Promise<string> {
  const ns = await nodos()
  if (ns.length === 0) return '(vacía)'
  const prog = await ultimoProgreso()
  return ns.slice(0, 80).map(n => `${n.tipo}: ${n.nombre}` +
    (n.apodos.length ? ` (también le dice: ${n.apodos.join(', ')})` : '') +
    (prog.get(n.id) ? ` (cómo estaba la última vez, para comparar y no para copiar: ${prog.get(n.id)})` : '')).join('\n')
}

async function ultimoProgreso(): Promise<Map<number, string>> {
  const { rows } = await pool.query<{ nodo_id: number; como_estaba: string; dia: string }>(
    `select distinct on (nodo_id) nodo_id::int, como_estaba, dia::text as dia
     from ficha_progreso order by nodo_id, dia desc, id desc`)
  return new Map(rows.map(r => [r.nodo_id, `${r.como_estaba.replace(/\s*\(\d{4}-\d{2}-\d{2}\)/g, '')} (${r.dia})`]))
}

const SECCIONES: [string, Tipo[]][] = [
  ['Quién es (sólo lo que contó)', ['dato']],
  ['Su gente', ['persona']],
  ['Lo que le pasa', ['problematica']],
  ['Qué lo activa', ['desencadenante']],
  ['Qué le sirve', ['le_sirve']],
  ['Qué no le sirve', ['no_le_sirve']],
  ['Cómo hablarle', ['como_hablarle']],
  ['Metas', ['meta']],
]

/// La ficha para el prompt de la charla, con tope: lo que más pesa primero.
/// Unos tres mil caracteres son unos ochocientos tokens.
export async function fichaParaLaCharla(tope = 3200): Promise<string | null> {
  const ns = await nodos()
  if (ns.length === 0) return null
  const prog = await ultimoProgreso()
  const { rows: con } = await pool.query<{ a: string; b: string; relacion: string; veces: number; ultima: string }>(
    `select na.nombre as a, nb.nombre as b, c.relacion, c.veces, c.ultima::text as ultima
     from ficha_conexiones c join ficha_nodos na on na.id = c.desde join ficha_nodos nb on nb.id = c.hacia
     where na.borrado_en is null and nb.borrado_en is null order by c.veces desc, c.ultima desc limit 8`)

  // Las conexiones van después de «Qué lo activa»: son lo que más dice, y al
  // final quedaban cortadas por el tope.
  const conexiones = con.length === 0 ? [] : ['Lo que se conecta:', ...con.map(c =>
    `- ${c.a} → ${c.relacion} → ${c.b} (${c.veces === 1 ? 'una vez' : `${c.veces} veces`}, la última ${c.ultima})`)]
  const ayuda = await paraQue()
  const lineas: string[] = []
  for (const [titulo, tipos] of SECCIONES) {
    if (titulo === 'Qué le sirve') lineas.push(...conexiones)
    const de = ns.filter(n => tipos.includes(n.tipo)).slice(0, 5)
    if (de.length === 0) continue
    lineas.push(`${titulo}:`)
    for (const n of de) {
      const p = prog.get(n.id)
      lineas.push(`- ${n.nombre}${n.apodos.length ? ` (le dice también «${n.apodos.join('», «')}»)` : ''}` +
        `${n.descripcion ? `: ${n.descripcion}` : ''}` +
        ` (${n.veces === 1 ? 'una vez' : `${n.veces} veces`}, la última ${n.ultima})` +
        cuandoYParaQue(n, ayuda.get(n.id)) +
        (p ? `. Cómo va: ${p}` : ''))
    }
  }

  const patronesDeLaFicha = await bloqueDePatrones()
  let texto = ''
  for (const l of lineas) {
    if (texto.length + l.length > tope) break
    texto += l + '\n'
  }
  return [
    '--- Lo que sabes de esta persona (su ficha) ---',
    'Sale de lo que te contó en otras charlas, con sus palabras. Úsala para hablarle',
    'a ella y no a alguien genérico: no la recites ni le digas que tienes una ficha.',
    'Si ves que algo se repite —lo que lo activa y lo que le pasa—, primero',
    'pregúntalo suave («¿puede ser que cuando pasa esto te cueste más dormir?»). Si',
    'el patrón sigue, puedes mostrarle lo concreto (cuántas veces y desde cuándo)',
    'como un espejo, sin juzgar. Nunca lo conviertas en un diagnóstico.',
    'Si hoy aparece algo de «Lo que le pasa», mira en «Qué le sirve» lo que le',
    'ayuda con eso y a esta hora, y ofrécelo como idea suya, con sus palabras («la',
    'otra vez leer te ayudó a dormir, ¿te tinca?»). No ofrezcas lo de «Qué no le sirve».',
    'Si hoy aparece un problema que una de sus «Metas» busca resolver, puedes recordarle',
    'esa meta como algo suyo y proponer un paso chico hacia ella, sin presionar.',
    texto.trim(),
    ...(patronesDeLaFicha ? [patronesDeLaFicha] : []),
  ].join('\n')
}

/// Para qué es cada cosa: lo que le ayuda con algo («le ayuda con») y lo que
/// una meta busca resolver («busca resolver», «busca mejorar»).
async function paraQue(): Promise<Map<number, string[]>> {
  const { rows } = await pool.query<{ id: number; hacia: string }>(
    `select c.desde::int as id, h.nombre as hacia
       from ficha_conexiones c join ficha_nodos h on h.id = c.hacia join ficha_nodos d on d.id = c.desde
      where h.borrado_en is null
        and ((d.tipo = 'le_sirve' and c.relacion ilike '%ayud%')
             or (d.tipo = 'meta' and (c.relacion ilike '%busca%' or c.relacion ilike '%resolv%' or c.relacion ilike '%mejor%')))
      order by c.veces desc`)
  const m = new Map<number, string[]>()
  for (const r of rows) m.set(r.id, [...(m.get(r.id) ?? []), r.hacia])
  return m
}

/// «; sobre todo en la noche; le ayuda con le cuesta dormir», o nada.
export function cuandoYParaQue(n: { momentos: Record<string, number>; tipo?: string }, para: string[] = []): string {
  const momentos = Object.entries(n.momentos ?? {}).sort((a, b) => b[1] - a[1]).slice(0, 2).map(([m]) => m)
  return (momentos.length ? `; sobre todo ${momentos.join(' y ')}` : '') +
    (para.length ? `; ${n.tipo === 'meta' ? 'busca resolver' : 'le ayuda con'}: ${para.slice(0, 3).join(', ')}` : '')
}

// ---------------------------------------------------------------------------
// Mi espacio: la persona ve su ficha, elige qué le llega a su psicólogo y
// quita lo que no quiere que esté.

export interface CitaDeLaFicha { dia: string; cita: string }
export interface DatoDeLaFicha {
  id: number; nombre: string; descripcion: string | null; veces: number
  primera: string; ultima: string; compartir: boolean; citas: CitaDeLaFicha[]; apodos: string[]
  /// Cuándo le sirve, el más seguido primero, y para qué.
  momentos: string[]; para: string[]
}
export interface SeccionDeLaFicha { tipo: Tipo; titulo: string; datos: DatoDeLaFicha[] }

/// Los títulos para la persona, que lee de sí misma: en segunda persona.
const TITULOS: Record<Tipo, string> = {
  dato: 'Quién eres', persona: 'Tu gente', problematica: 'Lo que te pasa',
  desencadenante: 'Lo que lo activa', le_sirve: 'Lo que te sirve', no_le_sirve: 'Lo que no te sirve',
  como_hablarle: 'Cómo te gusta que te hablen', meta: 'Lo que quieres',
}
const ORDEN: Tipo[] = ['problematica', 'desencadenante', 'le_sirve', 'no_le_sirve', 'meta', 'persona', 'como_hablarle', 'dato']

/// Toda la ficha, sin tope, con las frases de donde salió cada dato. Si
/// `soloCompartido`, lo que la persona eligió para su psicólogo.
export async function fichaParaLeer(soloCompartido = false): Promise<SeccionDeLaFicha[]> {
  const ns = (await nodos()).filter(n => !soloCompartido || n.compartir)
  const ayuda = await paraQue()
  const { rows: citas } = await pool.query<{ nodo_id: number; dia: string; cita: string }>(
    `select nodo_id::int, dia::text as dia, cita from ficha_evidencias
     where nodo_id is not null order by dia desc, id desc`)
  const porNodo = new Map<number, CitaDeLaFicha[]>()
  for (const c of citas) {
    const l = porNodo.get(c.nodo_id) ?? []
    if (l.length < 5) l.push({ dia: c.dia, cita: c.cita })
    porNodo.set(c.nodo_id, l)
  }
  return ORDEN.map(tipo => ({
    tipo, titulo: TITULOS[tipo],
    datos: ns.filter(n => n.tipo === tipo).map(n => ({
      id: n.id, nombre: n.nombre, descripcion: n.descripcion, veces: n.veces,
      primera: n.primera, ultima: n.ultima, compartir: n.compartir, citas: porNodo.get(n.id) ?? [], apodos: n.apodos,
      momentos: Object.entries(n.momentos ?? {}).sort((a, b) => b[1] - a[1]).map(([m]) => m), para: ayuda.get(n.id) ?? [],
    })),
  })).filter(s => s.datos.length > 0)
}

/// Quitar un dato. No vuelve: si el modelo lo propone otra vez, la fila sigue
/// borrada (`nodo()` no toca `borrado_en`).
export async function quitarDato(id: number): Promise<boolean> {
  const r = await pool.query('update ficha_nodos set borrado_en = now() where id = $1 and borrado_en is null', [id])
  return (r.rowCount ?? 0) > 0
}

export async function compartirDato(id: number, compartir: boolean): Promise<boolean> {
  const r = await pool.query('update ficha_nodos set compartir = $2 where id = $1 and borrado_en is null', [id, compartir])
  return (r.rowCount ?? 0) > 0
}

export async function marcarAvisada(): Promise<void> {
  await pool.query('update ajustes set ficha_avisada_en = coalesce(ficha_avisada_en, now()) where id = 1')
}
