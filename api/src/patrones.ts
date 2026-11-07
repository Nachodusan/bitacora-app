import { pool } from './db.ts'

/// PATRONES EN EL TIEMPO (etapa 2, 28/10/2026). Lo que la ficha dice que se
/// repite, mirado en el calendario: qué día de la semana aparece algo, a qué
/// hora del día, y qué suele venir después de qué.
///
/// Se CUENTA, no lo inventa un modelo: sale de las fechas y horas de las frases
/// de la ficha. Por eso tiene pisos (pocas veces no es un patrón) y se le pasa
/// a Bitácora como «puede ser casualidad»: primero lo pregunta, nunca lo afirma.

export interface Patron {
  /// El texto para la charla, en tercera persona y con los números.
  texto: string
  /// El dato de la ficha del que habla, para buscarlo por tema.
  nombre: string
}

const DIAS = ['domingos', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados']

/// La franja de una hora de pared.
export function franja(hora: number): string {
  if (hora < 6) return 'de madrugada'
  if (hora < 12) return 'en la mañana'
  if (hora < 19) return 'en la tarde'
  return 'en la noche'
}

interface Aparicion { nodo: number; nombre: string; tipo: string; dia: string; hora: number }

async function apariciones(): Promise<Aparicion[]> {
  // Una por dato y por día: tres frases de la misma charla son un día, no tres.
  const { rows } = await pool.query<Aparicion>(
    `select distinct on (n.id, e.dia) n.id::int as nodo, n.nombre, n.tipo, e.dia::text as dia,
            extract(hour from en.creado_local)::int as hora
       from ficha_evidencias e
       join ficha_nodos n on n.id = e.nodo_id
       join entradas en on en.id = e.entrada_id
      where n.borrado_en is null
      order by n.id, e.dia, en.creado_local`)
  return rows
}

const sumarDia = (dia: string, n: number) => new Date(Date.parse(`${dia}T00:00:00Z`) + n * 864e5).toISOString().slice(0, 10)

export async function patrones(): Promise<Patron[]> {
  const ap = await apariciones()
  const porNodo = new Map<number, Aparicion[]>()
  for (const a of ap) porNodo.set(a.nodo, [...(porNodo.get(a.nodo) ?? []), a])
  const encontrados: Patron[] = []

  for (const lista of porNodo.values()) {
    const { nombre, tipo } = lista[0]!
    if (tipo !== 'problematica' && tipo !== 'desencadenante') continue

    // Día de la semana: al menos cinco días distintos, y uno que se lleve
    // tres o más y el 40 % (lo esperable al azar es un 14 %).
    if (lista.length >= 5) {
      const cuenta = new Array(7).fill(0) as number[]
      for (const a of lista) cuenta[new Date(`${a.dia}T12:00:00Z`).getUTCDay()]!++
      const max = Math.max(...cuenta)
      const d = cuenta.indexOf(max)
      if (max >= 3 && max / lista.length >= 0.4) {
        encontrados.push({ nombre, texto: `«${nombre}» aparece sobre todo los ${DIAS[d]} (${max} de ${lista.length} días)` })
      }
    }

    // Hora: al menos cuatro días, y tres o más en la misma franja con el 60 %.
    if (lista.length >= 4) {
      const cuenta = new Map<string, number>()
      for (const a of lista) cuenta.set(franja(a.hora), (cuenta.get(franja(a.hora)) ?? 0) + 1)
      const [f, max] = [...cuenta.entries()].sort((a, b) => b[1] - a[1])[0]!
      if (max >= 3 && max / lista.length >= 0.6) {
        encontrados.push({ nombre, texto: `«${nombre}» lo cuenta casi siempre ${f} (${max} de ${lista.length} veces)` })
      }
    }
  }

  // Lo que viene después: cuando aparece X (alguien, algo que lo activa o algo
  // que le pasa), Y aparece ese día o el siguiente. Al menos tres veces, en el
  // 60 % de los días de X, y bastante más seguido que en un día cualquiera.
  const diasConCharla = new Set(ap.map(a => a.dia)).size
  const diasDe = new Map<number, Set<string>>()
  for (const a of ap) diasDe.set(a.nodo, (diasDe.get(a.nodo) ?? new Set()).add(a.dia))
  for (const [x, dx] of diasDe) {
    const ax = porNodo.get(x)![0]!
    if (dx.size < 3 || ax.tipo === 'le_sirve' || ax.tipo === 'meta' || ax.tipo === 'dato') continue
    for (const [y, dy] of diasDe) {
      const ay = porNodo.get(y)![0]!
      if (x === y || ay.tipo !== 'problematica') continue
      const juntos = [...dx].filter(d => dy.has(d) || dy.has(sumarDia(d, 1))).length
      const base = dy.size / Math.max(1, diasConCharla)
      if (juntos >= 3 && juntos / dx.size >= 0.6 && juntos / dx.size >= base + 0.25) {
        encontrados.push({ nombre: ay.nombre,
          texto: `cuando aparece «${ax.nombre}», ese día o el siguiente suele aparecer «${ay.nombre}» (${juntos} de ${dx.size} veces)` })
      }
    }
  }
  return encontrados
}

/// El bloque para la charla. Con cuidado: son cuentas, pueden ser casualidad.
export async function bloqueDePatrones(): Promise<string | null> {
  const ps = await patrones().catch(() => [] as Patron[])
  if (ps.length === 0) return null
  return [
    'Lo que se repite en el tiempo (sale de contar fechas y horas; puede ser casualidad):',
    ...ps.slice(0, 6).map(p => `- ${p.texto}`),
    'Si viene al caso, pregúntalo como curiosidad («¿te has fijado que…?»), nunca como',
    'una verdad sobre ella.',
  ].join('\n')
}
