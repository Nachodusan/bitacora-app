import type { Turno } from './charla.ts'

/// El corte de riesgo, del lado del servidor.
///
/// Es el mismo que vive en el teléfono (`Riesgo.swift`): la misma lista de
/// frases, la misma forma de compararlas y el mismo mensaje. Está en los dos
/// lados a propósito, y cada lado cubre un caso que el otro no:
///
///   · EN EL TELÉFONO funciona sin red. El motivo número uno de «no llego al
///     servidor» es que cambió la IP de la Mac, y en ese momento el único que
///     puede mostrar el mensaje de cuidado es el teléfono.
///   · EN EL SERVIDOR cubre a cualquier cliente que no lo tenga: la versión de
///     Android, o una app vieja con la lista desactualizada.
///
/// Las dos listas tienen que ser idénticas. `riesgo.test.ts` lee
/// `Riesgo.swift` y las compara, junto con el mensaje: si alguien agrega una
/// frase de un lado y no del otro, el test lo dice.
///
/// LO QUE ESTO ES: un piso. Coincidencia de frases, sin costo, que corre antes
/// de llamar al modelo. LO QUE NO ES: suficiente. Una lista se pierde todo lo
/// que se dice de otra manera; la segunda capa es el párrafo de riesgo del
/// prompt (`charla.ts`), que lee el sentido.
///
/// Cuando dispara, el modelo no se llama: el turno de la persona no viaja al
/// proveedor y el mensaje es fijo. El mensaje tampoco se manda a sintetizar —lo
/// dice la voz del teléfono—, porque pedir el audio de justo ese texto sería
/// avisarle a una empresa que el detector se disparó.

/// Autolesión y suicidio. Normalizadas: minúsculas, sin acentos ni puntuación.
export const SENALES_DIRECTAS = [
  'matarme', 'suicidarme', 'suicidio', 'quitarme la vida', 'terminar con todo',
  'no quiero vivir', 'no quiero seguir viviendo', 'dejar de existir',
  'estaria mejor muerto', 'estaria mejor muerta', 'ojala no despertarme',
  'lastimarme', 'hacerme dano', 'cortarme', 'no despertarme mas',
  'me quiero matar', 'quiero desaparecer',
]

/// Desesperanza. Se tratan igual que las anteriores.
///
/// Sin «me quiero morir» ni «no aguanto más», a propósito: el porqué está en
/// `Riesgo.swift`, junto a esta misma lista.
export const SENALES_DE_DESESPERANZA = [
  'no le veo sentido a nada', 'nada tiene sentido', 'no tiene sentido nada',
  'no hay salida', 'no puedo mas con nada', 'soy una carga',
  'estarian mejor sin mi', 'todo me da igual ya', 'no vale la pena nada',
  'estoy vacio por dentro', 'estoy vacia por dentro',
]

/// Lo que se dice cuando dispara. Es el mismo texto que `Riesgo.mensaje`.
///
/// Corto a propósito. No da consejos, no propone un plan, no analiza, no
/// pregunta nada más. Sugiere hablar con una persona y sale del medio. El
/// *4141 es la línea de prevención del suicidio de Chile (Ministerio de Salud):
/// gratis desde el celular, todos los días, a toda hora, y atiende un psicólogo.
export const MENSAJE_DE_RIESGO =
  'Gracias por decirlo aquí.\n\n' +
  'Con esto no te puedo ayudar yo, y no quiero hacerte más preguntas ahora. ' +
  'Busca a alguien de confianza y cuéntaselo hoy — o a un profesional, si puedes.\n\n' +
  'Si estás en Chile, puedes llamar gratis al *4141 desde el celular, a cualquier hora: ' +
  'atiende un psicólogo.\n\n' +
  'Lo que dijiste queda guardado. Nada más.'

/// Minúsculas, sin acentos, sin puntuación, y entre espacios.
///
/// Es `Riesgo.normalizar` del teléfono: sin esto "matarme" y "MATARME." no
/// coinciden, y en español los acentos se comen la mitad de las coincidencias.
/// La ñ queda como n ("hacerme dano"), igual que allá.
export function normalizar(texto: string): string {
  const plano = texto.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
  const palabras = plano.replace(/[^\p{L}\p{N}]+/gu, ' ').split(' ').filter(Boolean)
  return ` ${palabras.join(' ')} `
}

/// Palabra completa, con espacios a los dos lados: "recortarme el pelo" no
/// tiene que disparar "cortarme". El porqué completo está en `Riesgo.swift`.
export function haySenal(texto: string): boolean {
  const n = normalizar(texto)
  return [...SENALES_DIRECTAS, ...SENALES_DE_DESESPERANZA].some(s => n.includes(` ${s} `))
}

/// Si en lo que dijo la persona en esta charla hay una señal.
///
/// Mira TODOS sus turnos y sólo los suyos, como el teléfono: una pregunta de
/// Bitácora no puede disparar el corte, y una señal de hace tres turnos sigue
/// siendo una señal.
export function haySenalEnLaCharla(turnos: Turno[]): boolean {
  return haySenal(turnos.filter(t => t.de === 'vos').map(t => t.texto).join(' '))
}
