import './_setup.ts'
import assert from 'node:assert/strict'
import { after, before, describe, test } from 'node:test'
import { randomUUID } from 'node:crypto'


const { escribirNota, notas, sinRevisar, marcarRevisada, rotuloClinico } = await import('../src/notas.ts')
const { pool, cerrarPool } = await import('../src/db.ts')

const MARCA = 'Vos: [test notas]'
const DIA = '2027-07-04'

const CHARLA = [
  `${MARCA} Me peleé con mi hermana otra vez por lo mismo de siempre.`,
  'Bitácora: ¿Y cómo quedaste después?',
  'Vos: Siento que soy un desastre para poner límites. Me deja agotado.',
].join('\n')

const respuesta = (extra: Record<string, unknown> = {}) => ({
  citas: [{ texto: 'Siento que soy un desastre para poner límites', sobre: 'límites' }],
  temas: ['discusión familiar'],
  contexto: 'Contó que se peleó con su hermana y que le cuesta poner límites.',
  ...extra,
})
const stub = (d: unknown) => (async () => ({ datos: d, crudo: {} })) as never

async function entrada(texto = CHARLA) {
  const { rows } = await pool.query<{ id: number }>(
    `insert into entradas (client_uuid, creado_en, creado_local, fuente, transcripcion)
     values ($1, now(), $2, 'dictado_ios', $3) returning id::int`,
    [randomUUID(), `${DIA}T20:00:00`, texto])
  return rows[0]!.id
}

async function limpiar() {
  await pool.query(`delete from entradas where transcripcion like $1`, [`%[test notas]%`])
}

before(limpiar)
after(async () => {
  await limpiar()
  await pool.query(`delete from llm_llamadas where modelo = 'modelo-de-prueba'`)
  await cerrarPool()
})

describe('la nota es material suyo, no un informe', () => {
  test('guarda las citas verificadas, los temas y el contexto', async () => {
    const id = await entrada()
    const r = await escribirNota(id, stub(respuesta()))
    assert.deepEqual(r, { entrada_id: id, citas: 1, descartadas: 0, registro: 0, registro_descartado: 0 })

    const { rows } = await pool.query<{ temas: string[]; citas: { texto: string }[] }>(
      'select temas, citas from notas_terapia where entrada_id = $1', [id])
    assert.deepEqual(rows[0]!.temas, ['discusión familiar'])
    assert.equal(rows[0]!.citas[0]!.texto, 'Siento que soy un desastre para poner límites')
  })

  /// Lo más importante del archivo. Este texto está pensado para que lo lea
  /// alguien que le va a creer: una frase inventada acá no es un dato flojo, es
  /// ponerle en la boca a una persona algo que no dijo, delante de su terapeuta.
  test('una cita que no está en el texto se descarta', async () => {
    const id = await entrada()
    const r = await escribirNota(id, stub(respuesta({
      citas: [{ texto: 'Siento que soy un desastre para poner límites', sobre: 'límites' },
              { texto: 'Pensé en no volver a hablarle nunca más', sobre: 'la pelea' }],
    })))
    assert.equal(r!.citas, 1)
    assert.equal(r!.descartadas, 1)
  })

  test('sin ninguna cita verificable no se guarda nada', async () => {
    const id = await entrada()
    const r = await escribirNota(id, stub(respuesta({
      citas: [{ texto: 'algo que nunca dijo', sobre: 'x' }],
    })))
    assert.equal(r, null, 'sin sus palabras sólo quedaría la prosa del modelo')

    const { rows } = await pool.query('select 1 from notas_terapia where entrada_id = $1', [id])
    assert.equal(rows.length, 0)
  })

  /// Una cita mal atribuida en ESTE documento es peor que no tener el documento.
  test('no se puede citar una línea de Bitácora', async () => {
    const id = await entrada()
    const r = await escribirNota(id, stub(respuesta({
      citas: [{ texto: '¿Y cómo quedaste después?', sobre: 'la pregunta' }],
    })))
    assert.equal(r, null, 'eso lo dijo la asistente, no él')
  })
})

describe('nada de diagnóstico', () => {
  /// El vocabulario clínico le toca a quien atiende. Ponerlo la app lo instala
  /// antes de que nadie lo evalúe, y encima con la autoridad de venir escrito.
  /// Se cae SU prosa, no la nota: las citas son lo que esto es.
  test('si diagnostica en el contexto, se pierde el contexto y quedan las citas', async () => {
    const id = await entrada()
    const r = await escribirNota(id, stub(respuesta({
      contexto: 'Se observa un cuadro de ansiedad con rasgos de codependencia.',
    })))
    assert.equal(r!.citas, 1, 'las citas sobreviven')
    assert.equal(r!.rotulo_descartado !== undefined, true)

    const { rows } = await pool.query<{ contexto: string | null }>(
      'select contexto from notas_terapia where entrada_id = $1', [id])
    assert.equal(rows[0]!.contexto, null)
  })

  test('un tema clínico se filtra y los demás quedan', async () => {
    const id = await entrada()
    const r = await escribirNota(id, stub(respuesta({
      temas: ['ansiedad', 'discusión familiar'],
    })))
    assert.equal(r!.rotulo_descartado, 'ansiedad')

    const { rows } = await pool.query<{ temas: string[] }>(
      'select temas from notas_terapia where entrada_id = $1', [id])
    assert.deepEqual(rows[0]!.temas, ['discusión familiar'])
  })

  /// El falso positivo que encontró este test la primera vez: "límite" pegaba
  /// dentro de "poner límites", que es lo más común del mundo y justo el
  /// vocabulario de esta app. Una lista que rebota notas buenas es peor que no
  /// tener lista.
  test('las palabras comunes no son diagnósticos', async () => {
    for (const t of ['poner límites', 'fue un trauma ese viaje',
                     'estoy obsesionado con el gimnasio', 'me agarró pánico']) {
      assert.equal(rotuloClinico(t), null, `"${t}" no es un diagnóstico`)
    }
    assert.equal(rotuloClinico('se observa un trastorno'), 'trastorno')
  })

  /// La otra mitad de la regla: si la palabra la dijo ÉL, tiene que poder
  /// aparecer entre comillas. Censurarle sus propias palabras sería el error
  /// simétrico, y en este documento el más grave de los dos.
  test('pero si la palabra es suya, la cita se respeta', async () => {
    const texto = `${MARCA} Estoy con una ansiedad que no me deja dormir.`
    const id = await entrada(texto)
    const r = await escribirNota(id, stub(respuesta({
      citas: [{ texto: 'Estoy con una ansiedad que no me deja dormir', sobre: 'el sueño' }],
      temas: ['sueño'],
      contexto: 'Contó que le cuesta dormir.',
    })))
    assert.equal(r!.citas, 1)
  })
})

describe('lectura', () => {
  test('una charla sin contenido no genera nota ni gasta una llamada', async () => {
    let llamado = false
    const id = await entrada(`${MARCA} Hola.`)
    const r = await escribirNota(id, (async () => {
      llamado = true
      return { datos: respuesta(), crudo: {} }
    }) as never)
    assert.equal(r, null)
    assert.equal(llamado, false, 'un día liviano es un día liviano')
  })

  /// Lo que decide si una conversación se vuelve a mirar es la MARCA, no si
  /// existe la nota: una charla corta no deja nota y aun así no hay que volver
  /// a mandarla al modelo cada diez minutos.
  test('sinRevisar lista lo que nunca se miró; marcarRevisada lo saca aunque no haya nota', async () => {
    const MANANA = '2027-07-05'
    const id = await entrada()
    assert.equal((await sinRevisar(MANANA, 14)).includes(id), true)
    await marcarRevisada(id)
    assert.equal((await sinRevisar(MANANA, 14)).includes(id), false)
  })

  test('se leen del día más reciente para atrás', async () => {
    const id = await entrada()
    await escribirNota(id, stub(respuesta()))
    const lista = await notas(DIA, DIA)
    assert.equal(lista.length >= 1, true)
    assert.equal(lista[0]!.dia, DIA)
    assert.equal(lista[0]!.citas.length >= 1, true)
  })
})

describe('el registro es para el psicólogo y se respalda con sus palabras', () => {
  const REGISTRO = [
    `${MARCA} Me peleé con mi jefe y me dio mucha bronca.`,
    'Bitácora: ¿Y qué hiciste?',
    'Vos: Me dieron ganas de renunciar en ese momento. Me fui a casa y comí sin hambre, como todas las noches.',
  ].join('\n')

  test('guarda emociones, impulsos, conductas y hábitos con su cita', async () => {
    const id = await entrada(REGISTRO)
    const r = await escribirNota(id, stub(respuesta({
      citas: [{ texto: 'Me dieron ganas de renunciar en ese momento', sobre: 'el jefe' }],
      registro: [
        { tipo: 'emocion', que: 'bronca', cita: 'me dio mucha bronca' },
        { tipo: 'impulso', que: 'ganas de renunciar', cita: 'Me dieron ganas de renunciar' },
        { tipo: 'conducta', que: 'comer sin hambre', cita: 'comí sin hambre' },
        { tipo: 'habito', que: 'comer de noche', cita: 'como todas las noches' },
      ],
    })))
    assert.equal(r!.registro, 4)
    assert.equal(r!.registro_descartado, 0)
    const { rows } = await pool.query<{ registro: { tipo: string }[] }>(
      'select registro from notas_terapia where entrada_id = $1', [id])
    assert.deepEqual(rows[0]!.registro.map(x => x.tipo), ['emocion', 'impulso', 'conducta', 'habito'])
    const leidas = await notas(DIA, DIA)
    assert.ok(leidas.every(n => Array.isArray(n.registro)), '/notas lo devuelve en cada nota')
  })

  /// La misma regla que las citas: si no lo dijo, no se le atribuye.
  test('se tira lo que no tiene una frase suya, lo de Bitácora y lo de tipo inventado', async () => {
    const id = await entrada(REGISTRO)
    const r = await escribirNota(id, stub(respuesta({
      citas: [{ texto: 'Me dieron ganas de renunciar en ese momento', sobre: 'el jefe' }],
      registro: [
        { tipo: 'emocion', que: 'tristeza', cita: 'estaba muy triste' },
        { tipo: 'conducta', que: 'contar', cita: 'Y qué hiciste' },
        { tipo: 'diagnostico', que: 'algo', cita: 'me dio mucha bronca' },
        { tipo: 'emocion', que: 'bronca', cita: 'me dio mucha bronca' },
      ],
    })))
    assert.equal(r!.registro, 1)
    assert.equal(r!.registro_descartado, 3)
  })

  test('un rótulo clínico se tira aunque la cita sea suya', async () => {
    const id = await entrada(`${MARCA} Tuve un ataque de ansiedad en el colectivo.`)
    const r = await escribirNota(id, stub(respuesta({
      citas: [{ texto: 'Tuve un ataque de ansiedad en el colectivo', sobre: 'el colectivo' }],
      registro: [{ tipo: 'emocion', que: 'ansiedad', cita: 'Tuve un ataque de ansiedad' },
                 { tipo: 'emocion', que: 'nervios', cita: 'Tuve un ataque de ansiedad' }],
    })))
    assert.equal(r!.registro, 1, 'queda «nervios», con su frase textual')
  })

  test('sin registro la nota se guarda igual, con el registro vacío', async () => {
    const id = await entrada()
    await escribirNota(id, stub(respuesta()))
    const { rows } = await pool.query<{ registro: unknown[] }>(
      'select registro from notas_terapia where entrada_id = $1', [id])
    assert.deepEqual(rows[0]!.registro, [])
  })
})
