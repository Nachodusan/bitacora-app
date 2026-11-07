import { llamar } from './llm.ts'
import type { Turno } from './charla.ts'

/// Las herramientas: momentos guiados dentro de la charla (26/10/2026).
///
/// Son pantallas del teléfono —ponerle nombre a lo que se siente, respirar— y
/// casi todo vive allá. Lo único que necesita al servidor es «Ponerle nombre»:
/// las emociones que se ofrecen salen de lo que la persona contó, no de una
/// lista fija, porque «escuché algo como esto» tiene que ser verdad.
///
/// SUSTANTIVOS Y NO ADJETIVOS. «Frustración», no «frustrada»: la app no sabe
/// con qué género se nombra cada persona, y un adjetivo le pone uno.
///
/// NO SON DIAGNÓSTICOS. Ni «depresión» ni «ansiedad generalizada»: palabras de
/// todos los días. Si el modelo trae una clínica, se filtra acá.

/// Si el modelo falla o no hay de qué sacar, el teléfono ofrece éstas.
export const EMOCIONES_DE_SIEMPRE = [
  'tristeza', 'rabia', 'miedo', 'cansancio', 'frustración', 'soledad', 'angustia', 'culpa',
]

const CLINICAS = /depresi|trastorno|ansiedad generalizada|bipolar|tept|toc\b|p[aá]nico|disociaci|fobia|burnout|s[ií]ndrome/i

const SISTEMA = `Eres parte de una app de diario emocional. La persona dijo que no sabe
cómo ponerle nombre a lo que siente. A partir de lo que contó, propone las seis
emociones que más probablemente esté sintiendo, de la más a la menos probable.

Reglas:
- Sustantivos de emoción, en español neutro y en minúscula: «frustración»,
  «cansancio», «vergüenza», «soledad». Nunca adjetivos («frustrada»).
- Una o dos palabras cada una. Sin explicaciones.
- Palabras de todos los días, nunca un diagnóstico ni un término clínico.
- Distintas entre sí: no dos variantes de lo mismo.`

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['emociones'],
  properties: {
    emociones: { type: 'array', items: { type: 'string' }, minItems: 3, maxItems: 8 },
  },
}

export async function emocionesSugeridas(
  turnos: Turno[],
  llamada = llamar,
): Promise<string[]> {
  // Lo que dijo la persona, lo más reciente al final. Bitácora no hace falta:
  // lo que se busca es cómo lo dijo ella.
  const dicho = turnos.filter(t => t.de === 'vos').map(t => t.texto).slice(-6).join('\n')
  if (dicho.trim().length < 10) return EMOCIONES_DE_SIEMPRE.slice(0, 6)

  try {
    const { datos } = await llamada<{ emociones: string[] }>({
      tarea: 'emociones',
      refId: null,
      sistema: SISTEMA,
      usuario: dicho,
      nombreSchema: 'emociones',
      schema: SCHEMA,
    })
    const vistas = new Set<string>()
    const limpias = (datos.emociones ?? [])
      .map(e => e.trim().toLowerCase().replace(/[.«»"]/g, ''))
      .filter(e => e.length > 1 && e.length <= 24 && !CLINICAS.test(e))
      .filter(e => !vistas.has(e) && vistas.add(e))
      .slice(0, 6)
    if (limpias.length >= 3) return limpias
  } catch (e) {
    console.warn('emocionesSugeridas: van las de siempre:', e instanceof Error ? e.message.slice(0, 120) : e)
  }
  return EMOCIONES_DE_SIEMPRE.slice(0, 6)
}
