import { poolBase as pool } from './db.ts'
import { embeber, reordenar, memoriaLargaActiva, type Embeber, type Reordenar } from './recuerdos.ts'

/// La guía de los libros.
///
/// Manuales de terapia —Beck, Linehan, Barlow, Hayes, Burns, Kabat-Zinn, Ellis,
/// Caballo— partidos en fragmentos con su vector, en la tabla `guias`. En cada
/// turno se buscan los que tienen que ver con lo que la persona acaba de decir,
/// y Bitácora los recibe como criterio: qué conviene hacer con una emoción que
/// desborda, con una rumiación de madrugada, con un pensamiento todo-o-nada.
///
/// NO ES PARA CITAR NI PARA HACER DE TERAPEUTA. El prompt se lo dice: lo usa
/// para elegir mejor qué decir, con palabras de todos los días, y la regla de no
/// diagnosticar y la del riesgo siguen mandando por encima.
///
/// Los mismos tres pasos que `recordar()` en recuerdos.ts —vector, los veinte
/// más parecidos, el reordenador elige— y la misma regla: nada de esto puede
/// romper un turno. Cualquier falla devuelve una lista vacía y Bitácora contesta
/// como antes de que existiera.

const CANDIDATOS = 20
/// Pocos y recortados: es criterio, no lectura. Tres fragmentos de 900
/// caracteres son unos 800 tokens más por turno.
const MAXIMO = 3
const RECORTE = 900
/// Mucho más alto que el de los recuerdos, y es lo que hace que la guía entre
/// sólo cuando la persona está mal. Medido el 26/10/2026 con los 4.046
/// fragmentos: frases con angustia, rabia o insomnio dan 0,58 a 0,93; «ayer me
/// fue bien en el trabajo», 0,44; un almuerzo o pedir una película, menos de
/// 0,2. Un párrafo de manual que no viene al caso empuja a Bitácora a dar una
/// técnica que nadie pidió.
///
/// Bajó de 0,55 a 0,5 tras la primera charla real (26/10/2026, 02:20): «me lo
/// tragué todo el camino de vuelta», la vergüenza, dio 0,53 y quedó afuera justo
/// donde un fragmento sumaba. Lo neutro más alto medido sigue abajo, en 0,44.
const PISO = 0.5
const MIN_CONSULTA = 12
/// Más largo que el de la memoria (1,5 s). Con 1,5 s, en la simulación del
/// 26/10/2026 la guía no llegó en uno de cada cuatro turnos con angustia, justo
/// donde hacía falta. Sólo pesa cuando hay algo que buscar: corre a la par de la
/// memoria larga, así que como mucho suma un segundo de silencio.
const TIEMPO = 2_500

export interface Guia {
  libro: string
  texto: string
}

export async function guiar(
  loQueDijo: string,
  dep: { embeber: Embeber; reordenar: Reordenar } | null = null,
): Promise<Guia[]> {
  if (!dep && !memoriaLargaActiva()) return []
  const emb = dep?.embeber ?? ((t: string[]) => embeber(t, TIEMPO))
  const reo = dep?.reordenar ?? ((c: string, d: string[]) => reordenar(c, d, TIEMPO))

  const consulta = loQueDijo.trim()
  if (consulta.length < MIN_CONSULTA) return []

  try {
    // Sin libros cargados no se gasta nada.
    const hay = await pool.query('select 1 from guias limit 1')
    if (hay.rowCount === 0) return []

    const [vector] = await emb([consulta])
    const { rows } = await pool.query<Guia>(
      `select libro, texto from guias order by embedding <=> $1::vector limit $2`,
      [`[${vector!.join(',')}]`, CANDIDATOS],
    )
    if (rows.length === 0) return []

    const puntajes = await reo(consulta, rows.map(r => r.texto))
    return rows
      .map((r, i) => ({ r, puntaje: puntajes[i] ?? 0 }))
      .filter(x => x.puntaje >= PISO)
      .sort((a, b) => b.puntaje - a.puntaje)
      .slice(0, MAXIMO)
      .map(({ r }) => ({ libro: r.libro, texto: recortar(r.texto) }))
  } catch (e) {
    console.warn('guiar: este turno sale sin la guía:',
                 (e instanceof Error ? e.message : String(e)).slice(0, 120))
    return []
  }
}

function recortar(t: string): string {
  if (t.length <= RECORTE) return t
  const corte = t.lastIndexOf('. ', RECORTE)
  return t.slice(0, corte > RECORTE / 2 ? corte + 1 : RECORTE).trim() + ' […]'
}

export function bloqueDeGuia(guias: Guia[]): string | null {
  if (guias.length === 0) return null
  return [
    '--- Lo que dicen los manuales, por si te sirve ---',
    'Fragmentos de libros de terapia cognitiva, DBT, aceptación y compromiso y',
    'mindfulness, elegidos porque tienen que ver con lo que acaba de decir. Son',
    'criterio para ti, no texto para la persona: no los cites, no nombres el libro',
    'ni la técnica, no le des una lista de ejercicios. Pero úsalos: si de acá sale',
    'algo que le sirva en este mismo momento —que el miedo agranda lo que se siente',
    'en el cuerpo, soltar el aire despacio, que la mente cansada exagera, esperar',
    'antes de actuar con rabia—, dilo con tus palabras en una o dos oraciones, antes',
    'de preguntar. Si sólo está contándote algo tranquilo, sigues en modo escucha.',
    'No diagnosticas, y lo del riesgo de arriba manda por encima de esto.',
    ...guias.map(g => `«${g.libro}»: ${g.texto}`),
  ].join('\n')
}

/// Tarde de noche, con el reloj de la persona. De 23 a 5: después de eso ya es
/// alguien que madrugó, no alguien que no se pudo dormir.
export function esDeNoche(ahoraLocal: string): boolean {
  const hora = Number(ahoraLocal.slice(11, 13))
  return hora >= 23 || hora < 5
}

export function bloqueDeNoche(ahoraLocal: string): string | null {
  if (!esDeNoche(ahoraLocal)) return null
  return [
    '--- Es tarde de noche ---',
    `Son las ${ahoraLocal.slice(11, 16)} para la persona. De noche todo pesa más: el cansancio`,
    'agranda lo que se siente y las vueltas en la cabeza cuestan más de cortar. Habla',
    'más despacio y más corto, con calma: dos o tres oraciones, un solo párrafo,',
    'porque esto se escucha en voz alta de madrugada. No abras temas grandes ni le pidas que',
    'analice su vida ahora: ayúdale a bajar un cambio y a quedarse en lo de este',
    'momento. Si está dando vueltas a algo, puedes decirle que a esta hora la cabeza',
    'exagera y que mañana se ve distinto, sin quitarle importancia a lo que siente.',
    'Si quiere hacer algo que no tiene vuelta atrás —mandar un mensaje, renunciar,',
    'terminar una relación—, dile claro, en la primera oración, que lo deje para',
    'mañana: de noche y con la emoción arriba no es el momento. Si quiere seguir',
    'hablando, la acompañas: no la mandes a dormir. Aunque al principio haya dicho',
    'que se iba a acostar, si sigue contando o te dice «no sé», sigues con ella.',
  ].join('\n')
}
