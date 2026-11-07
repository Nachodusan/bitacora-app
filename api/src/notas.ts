import { pool } from './db.ts'
import { llamar } from './llm.ts'
import { config } from './config.ts'

/// Las notas para llevar a terapia.
///
/// Lo que dijo un día, en SUS palabras, para poder llevarlo a una sesión.
///
/// NO es una nota clínica, y esa distinción es la que gobierna todo lo de
/// abajo. Un texto escrito por un modelo que le llega a un profesional con
/// forma de informe carga una autoridad que no se ganó: si interpreta de más,
/// la sesión arranca desde algo que dijo una máquina sobre alguien a quien no
/// escuchó nunca, y el terapeuta —que sí lo escuchó— tiene que remar contra eso.
///
/// Entonces la nota es tres cosas y ninguna más: frases literales de él,
/// etiquetas de qué apareció, y dos líneas para ubicar las citas. El material
/// es suyo; la lectura es del profesional.
///
/// Desde el 14 de octubre lleva además un REGISTRO: emociones, impulsos,
/// conductas y hábitos que la persona contó, cada uno con la frase suya que lo
/// respalda. Es para el psicólogo y SÓLO para él: la app no se lo muestra a la
/// persona en ninguna pantalla, va únicamente en el PDF. Lo pidió Dusan, para
/// que nadie se autodiagnostique leyendo sus días rotulados.

const SISTEMA = `Preparás material para que una persona pueda llevar a su sesión de
terapia lo que contó un día en su bitácora hablada.

NO SOS UN CLÍNICO Y ESTO NO ES UN INFORME. Quien lo va a leer conoce a esta
persona y vos no. Tu único trabajo es rescatar lo que dijo para que no se pierda
entre una sesión y otra.

DEVOLVÉS CUATRO COSAS:

1. \`citas\`: entre una y cinco frases LITERALES suyas, copiadas carácter por
   carácter del texto. Las que tengan más peso: lo que le dolió, lo que se
   repite, lo que dijo sobre sí mismo. Cada una con \`sobre\`, dos o tres
   palabras que digan de qué es esa cita ("la pelea con su hermana", "el sueño").

   Se citan ÚNICAMENTE las líneas que empiezan con "Vos:". Nunca una línea
   "Bitácora:": eso lo dijo la asistente, no él, y una cita mal atribuida en este
   documento es peor que no tener el documento.

2. \`temas\`: de uno a cuatro rótulos cortos, en minúscula, descriptivos y NO
   clínicos. "discusión familiar", "cansancio", "exigencia con uno mismo" sirven.
   "ansiedad", "depresión", "codependencia", "trauma" NO: son categorías que le
   corresponde poner a quien lo atiende, y ponerlas vos las instala antes de que
   nadie las evalúe.

3. \`contexto\`: dos o tres líneas para ubicar las citas. Qué pasó ese día, en
   tercera persona y descriptivo, en español neutro y sin modismos de un país. "Contó que se peleó con su hermana y que
   durmió poco pensando en eso."

4. \`registro\`: lo que la persona CONTÓ de sí misma en cuatro tipos, para que su
   psicólogo lo tenga ordenado. Cada elemento lleva:
   · \`tipo\`: "emocion", "impulso", "conducta" o "habito".
   · \`que\`: de una a cuatro palabras cotidianas que lo nombren ("bronca",
     "ganas de renunciar", "comer sin hambre", "dormir tarde").
   · \`cita\`: la frase LITERAL suya que lo respalda, copiada carácter por
     carácter de una línea "Vos:". Puede ser un fragmento de la línea.

   Qué es cada tipo:
   · emocion: lo que dijo que sintió ("me dio mucha bronca", "estaba triste").
   · impulso: ganas que tuvo de hacer algo, lo haya hecho o no ("me dieron
     ganas de irme", "quería mandarle un mensaje").
   · conducta: algo que hizo ("le corté el teléfono", "me fui a caminar").
   · habito: algo que dijo que hace seguido o siempre ("todas las noches me
     quedo con el celular", "como siempre, comí sin hambre"). Sólo si ÉL dice
     que se repite; que aparezca un día no lo vuelve hábito.

   Registrás únicamente lo que dijo de forma explícita. Si no lo nombró, no
   existe: no deducís emociones del tono ni impulsos de lo que hizo. Para
   \`que\` usás palabras de todos los días, nunca un término clínico: "nervios",
   "angustia", "miedo", "tristeza", "culpa" sirven; si él dijo "ansiedad", eso
   queda en su cita y en \`que\` ponés otra palabra ("nervios"). Entre cero y diez
   elementos. Un día sin nada de esto devuelve \`registro\` vacío.

PROHIBIDO EN \`contexto\`, EN \`temas\` Y EN EL \`que\` DEL REGISTRO:
· Diagnosticar o nombrar cuadros.
· Interpretar. Nada de "parece haber un patrón de", "esto sugiere", "se observa
  una tendencia a". Vos no observás nada: transcribís.
· Sacar conclusiones sobre su carácter o su historia.
· Recomendar qué trabajar en la sesión. Eso lo deciden ellos dos.
· Suavizar o dramatizar. Si dijo algo duro, va tal cual.

Si en la conversación no hay nada que valga la pena rescatar —charla corta, sin
contenido personal— devolvé \`citas\` vacío. Un día liviano es un día liviano.`

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['citas', 'temas', 'contexto', 'registro'],
  properties: {
    citas: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['texto', 'sobre'],
        properties: {
          texto: { type: 'string' },
          sobre: { type: 'string' },
        },
      },
    },
    temas: { type: 'array', items: { type: 'string' } },
    contexto: { type: 'string' },
    registro: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['tipo', 'que', 'cita'],
        properties: {
          tipo: { type: 'string', enum: ['emocion', 'impulso', 'conducta', 'habito'] },
          que: { type: 'string' },
          cita: { type: 'string' },
        },
      },
    },
  },
} as const

export type TipoDeRegistro = 'emocion' | 'impulso' | 'conducta' | 'habito'
export interface Registro { tipo: TipoDeRegistro; que: string; cita: string }
const TIPOS: TipoDeRegistro[] = ['emocion', 'impulso', 'conducta', 'habito']
const MAX_REGISTRO = 10

interface NotaGenerada {
  citas: { texto: string; sobre: string }[]
  temas: string[]
  contexto: string
  registro?: Registro[]
}

/// Rótulos que le tocan a quien atiende, no a esta app.
///
/// El prompt ya los prohíbe; esto es la red. Se aplica SÓLO a `contexto` y
/// `temas` —la prosa del modelo— y nunca a las citas: si la palabra "ansiedad"
/// la dijo él, tiene que poder aparecer entre comillas. Censurar sus propias
/// palabras sería el otro error.
/// La lista está acotada A PROPÓSITO, y la acotó un falso positivo.
///
/// La primera versión incluía "límite", y rebotó una nota perfectamente buena
/// porque la persona había dicho "me cuesta poner límites" — que no tiene nada
/// que ver con un trastorno límite y que es EXACTAMENTE el vocabulario que
/// alguien usa acá. Lo mismo pasaba con "trauma" ("fue un trauma ese viaje"),
/// "obsesivo" ("estoy obsesionado con esto") y "pánico".
///
/// Una lista que rebota notas buenas es peor que no tener lista: la nota no
/// aparece y nadie se entera de por qué. Así que quedan sólo los términos que
/// nadie usa en una charla, más las fórmulas con las que un modelo empieza a
/// diagnosticar.
const ROTULOS_CLINICOS = [
  'ansiedad', 'ansioso', 'ansiosa', 'depresión', 'depresion', 'depresivo',
  'depresiva', 'trastorno', 'patológico', 'patologico', 'patológica',
  'tept', 'bipolar', 'borderline', 'codependencia', 'codependiente',
  'psicótico', 'psicotico', 'diagnóstico', 'diagnostico',
  'cuadro de', 'rasgos de', 'síntomas de', 'sintomas de', 'se observa',
]

/// Palabra completa, no subcadena. Sin esto "límites" activaba "límite" y
/// "trastorno" activaría "trastornado". Las fórmulas de varias palabras se
/// buscan tal cual.
export function rotuloClinico(texto: string): string | null {
  const n = texto.toLowerCase()
  return ROTULOS_CLINICOS.find(r =>
    r.includes(' ')
      ? n.includes(r)
      : new RegExp(`(^|[^a-záéíóúñ])${r}([^a-záéíóúñ]|$)`, 'i').test(n),
  ) ?? null
}

/// Para comparar una cita contra el texto sin que la puntuación dé un falso
/// negativo. Sólo para BUSCARLA: se guarda la cita tal cual la devolvió.
export function normalizar(s: string): string {
  return s.toLowerCase().replace(/\s+/g, ' ').replace(/[.,;:!¡?¿"'()—–-]/g, '').trim()
}

/// Sólo lo que dijo él. Las preguntas de Bitácora no son material de nadie.
export function soloVos(transcripcion: string): string {
  return transcripcion
    .split('\n')
    .filter(l => l.trimStart().startsWith('Vos:'))
    .map(l => l.replace(/^\s*Vos:\s*/, ''))
    .join('\n')
}

export interface ResultadoNota {
  entrada_id: number
  citas: number
  descartadas: number
  /// Elementos del registro guardados, y los que se tiraron (cita que no está,
  /// tipo desconocido o rótulo clínico).
  registro: number
  registro_descartado: number
  /// Si hubo que tirar la prosa del modelo por diagnosticar.
  rotulo_descartado?: string
}

/// Escribe la nota de una conversación. `null` si no había nada que rescatar.
///
/// Las citas se VERIFICAN contra la transcripción antes de guardarse, y por una
/// razón fuerte: este texto está pensado para que lo lea alguien que le va a
/// creer. Una frase inventada acá no es un
/// dato flojo, es ponerle en la boca a una persona algo que no dijo, delante de
/// su terapeuta.
export async function escribirNota(
  entradaId: number,
  llamada = llamar,
): Promise<ResultadoNota | null> {
  const { rows } = await pool.query<{ dia: string; transcripcion: string }>(
    `select dia::text, transcripcion from entradas
      where id = $1`,
    [entradaId],
  )
  const entrada = rows[0]
  if (!entrada) return null

  const dicho = soloVos(entrada.transcripcion)
  if (dicho.trim().length < 40) return null   // no hubo conversación

  const { datos } = await llamada<NotaGenerada>({
    tarea: 'nota_terapia',
    refId: entradaId,
    sistema: SISTEMA,
    usuario: entrada.transcripcion,
    nombreSchema: 'nota_terapia',
    schema: SCHEMA as unknown as Record<string, unknown>,
  })

  const fuente = normalizar(dicho)
  const buenas = (datos.citas ?? []).filter(c => {
    const aguja = normalizar(c.texto ?? '')
    return aguja.length > 0 && fuente.includes(aguja)
  })
  const descartadas = (datos.citas ?? []).length - buenas.length

  // Sin citas verificadas no se guarda nada. Lo único que quedaría sería la
  // prosa del modelo, que es exactamente lo que no queremos que alguien lea
  // como si describiera a una persona.
  if (buenas.length === 0) return null

  // Si el modelo se puso a diagnosticar, se cae SU prosa — no la nota. Las
  // citas son lo que esto es; el contexto es una comodidad. Tirar cinco frases
  // suyas porque el modelo escribió "se observa" sería cambiar un problema por
  // uno peor: la nota no aparecería y nadie sabría por qué.
  let contexto: string | null = (datos.contexto ?? '').trim() || null
  const temasLimpios = (datos.temas ?? []).filter(t => !rotuloClinico(t))
  const rotulo = (contexto && rotuloClinico(contexto))
    || (datos.temas ?? []).map(rotuloClinico).find(Boolean)
    || undefined
  if (contexto && rotuloClinico(contexto)) contexto = null

  const registro = filtrarRegistro(datos.registro ?? [], fuente)
  const registroDescartado = (datos.registro ?? []).length - registro.length

  await pool.query(
    `insert into notas_terapia (entrada_id, dia, modelo, citas, temas, contexto, registro)
     values ($1, $2, $3, $4, $5, $6, $7)
     on conflict (entrada_id) do update set
       citas = excluded.citas, temas = excluded.temas,
       contexto = excluded.contexto, registro = excluded.registro, creado_en = now()`,
    [entradaId, entrada.dia, config.modeloDeFondo,
     JSON.stringify(buenas), temasLimpios, contexto, JSON.stringify(registro)],
  )

  return { entrada_id: entradaId, citas: buenas.length, descartadas,
           registro: registro.length, registro_descartado: registroDescartado,
           ...(rotulo ? { rotulo_descartado: rotulo } : {}) }
}

/// El registro que se guarda: con las mismas reglas que las citas, porque es lo
/// mismo —algo que va a leer su terapeuta como dicho por él—. Se tira el
/// elemento cuya cita no está en lo que dijo, el de un tipo que no existe, y el
/// que el modelo rotuló con un término clínico: en esos casos no hay forma de
/// salvarlo sin inventar. Sin duplicados (mismo tipo y mismo rótulo).
export function filtrarRegistro(crudo: Partial<Registro>[], fuenteNormalizada: string): Registro[] {
  const vistos = new Set<string>()
  const buenos: Registro[] = []
  for (const r of crudo) {
    const tipo = r.tipo as TipoDeRegistro
    const que = (r.que ?? '').trim()
    const cita = (r.cita ?? '').trim()
    const aguja = normalizar(cita)
    if (!TIPOS.includes(tipo) || !que || !aguja) continue
    if (!fuenteNormalizada.includes(aguja)) continue
    if (rotuloClinico(que)) continue
    const clave = `${tipo}|${que.toLowerCase()}`
    if (vistos.has(clave)) continue
    vistos.add(clave)
    buenos.push({ tipo, que, cita })
    if (buenos.length === MAX_REGISTRO) break
  }
  return buenos
}

/// Las conversaciones de días ya terminados que todavía no se revisaron.
///
/// Se mira `nota_revisada_en` y no si existe la nota: una charla corta no deja
/// nota y está bien, pero sin la marca se volvería a mandar al modelo en cada
/// tick. Y una que falló por el proveedor queda sin marca, así que se reintenta
/// — que es lo que tiene que pasar con material para terapia.
export async function sinRevisar(hoy: string, ventanaDias: number): Promise<number[]> {
  const { rows } = await pool.query<{ id: number }>(
    `select id::int from entradas
      where nota_revisada_en is null
        and dia < $1::date and dia >= $1::date - $2::int
      order by dia, creado_local`,
    [hoy, ventanaDias],
  )
  return rows.map(r => r.id)
}

/// Se intentó, haya salido nota o no. Sólo después de un intento que NO tiró.
export async function marcarRevisada(entradaId: number): Promise<void> {
  await pool.query('update entradas set nota_revisada_en = now() where id = $1', [entradaId])
}

export interface NotaDelDia {
  dia: string
  hora: string
  temas: string[]
  contexto: string | null
  citas: { texto: string; sobre: string }[]
  /// Sólo para el PDF del psicólogo. Las apps no lo muestran en pantalla.
  registro: Registro[]
}

/// Lo que se lee para llevar a la sesión. Ordenado del día más reciente para
/// atrás, que es como se repasa "qué me pasó desde la última vez".
export async function notas(desde: string, hasta: string): Promise<NotaDelDia[]> {
  const { rows } = await pool.query<NotaDelDia>(
    `select n.dia::text,
            to_char(e.creado_local, 'HH24:MI') as hora,
            n.temas, n.contexto, n.citas, n.registro
       from notas_terapia n
       join entradas e on e.id = n.entrada_id
      where n.dia between $1 and $2
      order by n.dia desc, e.creado_local desc`,
    [desde, hasta],
  )
  return rows
}
