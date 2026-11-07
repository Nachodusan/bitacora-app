/// Fechas escritas como las diría una persona, para los prompts.
///
/// Todas reciben y devuelven días como texto ("YYYY-MM-DD") y los leen a
/// mediodía UTC: así ninguna zona horaria los corre al día anterior.

function aFecha(dia: string): Date {
  return new Date(`${dia}T12:00:00Z`)
}

/// "jueves 2 de octubre de 2026", o sin el año.
export function fechaLarga(dia: string, conAnio = true): string {
  return new Intl.DateTimeFormat('es', {
    weekday: 'long', day: 'numeric', month: 'long',
    ...(conAnio ? { year: 'numeric' } : {}), timeZone: 'UTC',
  }).format(aFecha(dia)).replace(',', '')
}

/// Cuántos días van de `desde` a `hasta`. Negativo si `hasta` es antes.
export function diasEntre(desde: string, hasta: string): number {
  return Math.round((aFecha(hasta).getTime() - aFecha(desde).getTime()) / 864e5)
}

/// El día `n` días después (o antes, con `n` negativo).
export function sumarDias(dia: string, n: number): string {
  return new Date(aFecha(dia).getTime() + n * 864e5).toISOString().slice(0, 10)
}

/// "hoy", "mañana", "ayer", o la fecha larga sin año, mirado desde `hoy`.
export function cuandoEs(dia: string, hoy: string): string {
  const n = diasEntre(hoy, dia)
  if (n === 0) return 'hoy'
  if (n === 1) return 'mañana'
  if (n === -1) return 'ayer'
  return `el ${fechaLarga(dia, false)}`
}
