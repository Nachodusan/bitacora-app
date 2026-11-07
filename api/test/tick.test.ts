import './_setup.ts'
import assert from 'node:assert/strict'
import { after, before, beforeEach, describe, test } from 'node:test'

const { tick } = await import('../src/tick.ts')
const { resumirDia, memoria, MAX_INTENTOS, esFallaDelEntorno } = await import('../src/resumen.ts')
const { sinRevisar } = await import('../src/notas.ts')
const { leerReloj } = await import('../src/ajustes.ts')
const { pool, cerrarPool } = await import('../src/db.ts')

const MARCA = '[test tick]'

/// Una charla con suficiente contenido tuyo para que la nota valga la pena.
const CHARLA = [
  `Vos: ${MARCA} Hoy me peleé con mi hermana otra vez por lo mismo de siempre.`,
  'Bitácora: ¿Y cómo quedaste después?',
  'Vos: Siento que soy un desastre para poner límites. Me deja agotado y sin ganas.',
].join('\n')

function diaMenos(dia: string, n: number): string {
  return new Date(Date.parse(`${dia}T00:00:00Z`) - n * 864e5).toISOString().slice(0, 10)
}

let HOY: string
let AYER: string
let ANTEAYER: string

async function entrada(dia: string, texto = CHARLA, hora = '21:00:00') {
  const { rows } = await pool.query<{ id: number }>(
    `insert into entradas (client_uuid, creado_en, creado_local, fuente, transcripcion)
     values (gen_random_uuid(), now(), $1, 'dictado_ios', $2) returning id::int`,
    [`${dia}T${hora}`, texto])
  return rows[0]!.id
}

const resumen = (texto: string) => (async (p: { tarea: string }) => ({
  datos: p.tarea === 'resumen_dia'
    ? { resumen: texto }
    : { citas: [{ texto: 'Siento que soy un desastre para poner límites', sobre: 'límites' }],
        temas: ['discusión familiar'], contexto: 'Contó que se peleó con su hermana.' },
  crudo: {},
})) as never

async function limpiar() {
  await pool.query(`delete from entradas where transcripcion like $1`, [`%${MARCA}%`])
  // Con techo: sin él, esto borraba también los resúmenes de 2027 que usa
  // `charla.test.ts`, que corre a la vez, y ese test fallaba una de cada tantas.
  await pool.query(`delete from resumenes_dia where dia between $1 and $2`,
                   [diaMenos(HOY, 14), diaMenos(HOY, -1)])
  await pool.query(`delete from llm_llamadas where modelo = 'modelo-de-prueba'`)
}

before(async () => {
  HOY = (await leerReloj()).diaLogico
  AYER = diaMenos(HOY, 1)
  ANTEAYER = diaMenos(HOY, 2)
})
// Cada test arranca con los días limpios: si no, el resumen que dejó uno hace
// que el siguiente vea un día "para reescribir" que no es el suyo.
beforeEach(limpiar)
after(async () => { await limpiar(); await cerrarPool() })

describe('el tick cierra los días que terminaron', () => {
  test('a un día vencido le escribe el resumen y una nota por conversación', async () => {
    await entrada(AYER)
    await entrada(AYER, CHARLA.replace('hermana', 'madre'), '23:10:00')

    const r = await tick(resumen('Te peleaste con tu familia y quedaste agotado.'))
    assert.deepEqual(r.resumidos, [AYER])
    assert.equal(r.notas, 2)

    const { rows } = await pool.query<{ resumen: string; n_entradas: number; intentos: number }>(
      'select resumen, n_entradas, intentos from resumenes_dia where dia = $1', [AYER])
    assert.equal(rows[0]!.resumen, 'Te peleaste con tu familia y quedaste agotado.')
    assert.equal(rows[0]!.n_entradas, 2)
    assert.equal(rows[0]!.intentos, 0)
  })

  /// La cola offline del teléfono: algo dictado a la 1am sin señal aterriza a
  /// las 9 con el resumen ya escrito. Se detecta por los datos, no por una marca.
  ///
  /// La entrada tardía va a la 01:30 del día CALENDARIO siguiente: por el corte
  /// de las 4am pertenece a ANTEAYER. (La primera versión de este test la ponía
  /// a la 01:30 del mismo día calendario y el tick la resumió como el día
  /// anterior — que era lo correcto. El que estaba mal era el test.)
  test('si llega una entrada después, el resumen se reescribe', async () => {
    await entrada(ANTEAYER)
    await tick(resumen('Un día tranquilo.'))
    await entrada(diaMenos(ANTEAYER, -1), CHARLA.replace('hermana', 'jefe'), '01:30:00')

    const r = await tick(resumen('Un día tranquilo hasta la noche.'))
    assert.deepEqual(r.resumidos, [ANTEAYER])
    const { rows } = await pool.query<{ n_entradas: number }>(
      'select n_entradas from resumenes_dia where dia = $1', [ANTEAYER])
    assert.equal(rows[0]!.n_entradas, 2)
  })

  test('hoy no se toca: todavía no terminó', async () => {
    await entrada(HOY)
    const r = await tick(resumen('No debería escribirse.'))
    assert.equal(r.resumidos.includes(HOY), false)
    const { rows } = await pool.query('select 1 from resumenes_dia where dia = $1', [HOY])
    assert.equal(rows.length, 0)
  })

  test('un tick sin nada que hacer no hace nada, y dos seguidos tampoco', async () => {
    const a = await tick(resumen('x'))
    const b = await tick(resumen('x'))
    assert.deepEqual(a.resumidos, [])
    assert.deepEqual(b.resumidos, [])
    assert.equal(a.notas + b.notas, 0)
  })
})

describe('un resumen con cifras no se guarda', () => {
  /// Los dígitos son donde se cuela el invento: "siete horas y media" de sueño
  /// se vuelve "te levantaste a las 7:30". Mejor un hueco que una mentira.
  test('queda la fila con resumen nulo y un intento', async () => {
    await entrada(AYER)
    const r = await resumirDia(AYER, resumen('Dormiste 7 horas y fuiste al gym.'))
    assert.equal(r!.resumen, null)
    const { rows } = await pool.query<{ resumen: string | null; intentos: number }>(
      'select resumen, intentos from resumenes_dia where dia = $1', [AYER])
    assert.equal(rows[0]!.resumen, null)
    assert.equal(rows[0]!.intentos, 1)
  })

  test('después de MAX_INTENTOS el tick deja de intentarlo', async () => {
    await entrada(AYER)
    let llamadas = 0
    const conta = (async (p: { tarea: string }) => {
      if (p.tarea === 'resumen_dia') llamadas++
      return { datos: { resumen: 'Cifra 1.' }, crudo: {} }
    }) as never
    for (let i = 0; i < MAX_INTENTOS + 2; i++) await tick(conta)
    assert.equal(llamadas, MAX_INTENTOS, 'ni una llamada más que el tope')
  })

  test('la base tampoco acepta uno con cifras por otro camino', async () => {
    await assert.rejects(
      pool.query(`insert into resumenes_dia (dia, resumen, n_entradas)
                  values ('2020-01-01', 'Dormiste 8 horas.', 1)`),
      /resumenes_dia_resumen_check/)
  })
})

describe('la memoria de Bitácora', () => {
  test('son los últimos siete días con resumen, antes del día pedido, del más viejo al más nuevo', async () => {
    for (let i = 1; i <= 9; i++) {
      await pool.query(
        `insert into resumenes_dia (dia, resumen, n_entradas) values ($1, $2, 1)
         on conflict (dia) do update set resumen = excluded.resumen`,
        [diaMenos(HOY, i), `Día menos ${'x'.repeat(i)}.`])
    }
    const m = await memoria(HOY)
    assert.equal(m.length, 7)
    assert.equal(m[0]!.dia, diaMenos(HOY, 7), 'arranca en el más viejo de los siete')
    assert.equal(m[6]!.dia, diaMenos(HOY, 1), 'termina en ayer')
  })

  test('un día sin resumen guardable no aparece', async () => {
    await pool.query(
      `insert into resumenes_dia (dia, resumen, intentos, n_entradas) values ($1, null, 3, 1)
       on conflict (dia) do update set resumen = null, intentos = 3`, [AYER])
    const m = await memoria(HOY)
    assert.equal(m.some(x => x.dia === AYER), false)
  })
})

describe('lo que es del entorno y lo que es del día', () => {
  test('red, 5xx, rate limit y config son del entorno; contenido y respuesta vacía son del día', () => {
    for (const m of ['LLM 503: Service Unavailable', 'LLM 429: Rate limit reached',
                     'LLM 401: bad key', 'LLM 404: model not found',
                     'The operation was aborted due to timeout', 'fetch failed']) {
      assert.equal(esFallaDelEntorno(new Error(m)), true, m)
    }
    for (const m of ['LLM 400: invalid content', 'El modelo devolvió una respuesta sin contenido',
                     'Unexpected end of JSON input']) {
      assert.equal(esFallaDelEntorno(new Error(m)), false, m)
    }
  })

  /// Tres ticks de rate limit dejaban el día sin resumen para siempre.
  test('un 429 no quema un intento', async () => {
    await entrada(AYER)
    const r = await tick((async () => { throw new Error('LLM 429: Rate limit reached') }) as never)
    assert.deepEqual(r.postergados, [AYER])
    const { rows } = await pool.query('select 1 from resumenes_dia where dia = $1', [AYER])
    assert.equal(rows.length, 0, 'sin fila: no cuenta como intento')
  })

  /// Una respuesta sin texto se reintentaba sin tope y bloqueaba los días
  /// posteriores. Ahora cuenta como intento y no frena a nadie.
  test('un día que el modelo no puede contestar no bloquea a los que siguen', async () => {
    await entrada(ANTEAYER)
    await entrada(AYER)
    const r = await tick((async (p: { tarea: string; usuario: string }) => {
      if (p.tarea === 'resumen_dia' && p.usuario.includes('hermana')) {
        throw new Error('El modelo devolvió una respuesta sin contenido')
      }
      return { datos: p.tarea === 'resumen_dia' ? { resumen: 'Un día común.' }
                                                : { citas: [], temas: [], contexto: '' }, crudo: {} }
    }) as never)
    // Las dos entradas tienen "hermana", así que las dos fallan — y las dos
    // quedan con intento contado, ninguna postergada, y el tick terminó.
    assert.deepEqual(r.sin_resumen, [ANTEAYER, AYER])
    assert.deepEqual(r.postergados, [])
  })
})

describe('las notas no dependen del resumen', () => {
  /// Antes, si la nota fallaba después de escrito el resumen, el día salía de la
  /// lista y esa conversación no tenía nota nunca más.
  test('una nota que falla por el entorno se reintenta en el tick siguiente', async () => {
    const id = await entrada(AYER)
    let vez = 0
    const primero = (async (p: { tarea: string }) => {
      if (p.tarea === 'nota_terapia') { vez++; throw new Error('LLM 503: down') }
      return { datos: { resumen: 'Un día.' }, crudo: {} }
    }) as never
    const a = await tick(primero)
    assert.deepEqual(a.resumidos, [AYER])
    assert.equal(a.notas_postergadas, 1)
    assert.equal((await sinRevisar(HOY, 14)).includes(id), true, 'sigue pendiente')

    const b = await tick(resumen('Un día.'))
    assert.equal(b.notas, 1)
    assert.equal((await sinRevisar(HOY, 14)).includes(id), false, 'ya se revisó')
  })

  test('una charla corta se marca revisada sin gastar una llamada, y no se vuelve a mirar', async () => {
    const id = await entrada(AYER, `Vos: ${MARCA} Hola.`)
    let llamadas = 0
    const conta = (async (p: { tarea: string }) => {
      if (p.tarea === 'nota_terapia') llamadas++
      return { datos: { resumen: 'Saludaste.' }, crudo: {} }
    }) as never
    await tick(conta); await tick(conta)
    assert.equal(llamadas, 0)
    assert.equal((await sinRevisar(HOY, 14)).includes(id), false)
  })
})
