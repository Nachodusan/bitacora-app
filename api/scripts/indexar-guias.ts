import { readFileSync } from 'node:fs'
import { pool, cerrarPool } from '../src/db.ts'
import { config } from '../src/config.ts'
import { embeber, memoriaLargaActiva } from '../src/recuerdos.ts'

/// Carga la guía de los libros: lee el JSONL que arma `extraer-libros.py`,
/// vectoriza cada fragmento y deja la tabla `guias` con eso y nada más.
///
/// Borra lo que había, en la misma transacción que la carga nueva: si se corta a
/// la mitad, queda la guía anterior entera y no media de cada una.
///
/// Cuesta centavos: unos 7.000 fragmentos de 300 tokens con bge-m3 son ~2
/// millones de tokens, a 0,01 USD el millón. Cada tanda queda registrada como
/// cualquier otra llamada.
///
///     npm run guias -- ../guias/fragmentos.jsonl

const TANDA = 32

const archivo = process.argv[2]
if (!archivo) throw new Error('Falta el JSONL: npm run guias -- ../guias/fragmentos.jsonl')
if (!memoriaLargaActiva()) throw new Error('Hace falta DEEPINFRA_API_KEY en el .env')

const fragmentos = readFileSync(archivo, 'utf8').split('\n').filter(Boolean)
  .map(l => JSON.parse(l) as { libro: string; pagina: number; texto: string })
  // Algunos PDF traen caracteres nulos, y Postgres no los acepta en un text.
  .map(f => ({ ...f, texto: f.texto.replace(/[\u0000-\u0008\u000b-\u001f\ufffd]/g, '') }))

const cliente = await pool.connect()
try {
  await cliente.query('begin')
  await cliente.query('delete from guias')
  for (let i = 0; i < fragmentos.length; i += TANDA) {
    const tanda = fragmentos.slice(i, i + TANDA)
    const vectores = await embeber(tanda.map(f => f.texto), config.llmTimeoutMs)
    for (const [j, f] of tanda.entries()) {
      await cliente.query(
        'insert into guias (libro, pagina, texto, embedding) values ($1, $2, $3, $4::vector)',
        [f.libro, f.pagina, f.texto, `[${vectores[j]!.join(',')}]`])
    }
    process.stdout.write(`\r${Math.min(i + TANDA, fragmentos.length)} de ${fragmentos.length}`)
  }
  await cliente.query('commit')
  console.log('\nListo.')
} catch (e) {
  await cliente.query('rollback')
  throw e
} finally {
  cliente.release()
  await cerrarPool()
}
