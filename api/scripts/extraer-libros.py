"""Los libros de la carpeta, partidos en fragmentos para la guía de Bitácora.

Saca el texto de cada PDF y EPUB y lo corta en pedazos de unos 1200 caracteres,
cortando en párrafos, con un poco de solape para que una idea partida al medio
aparezca entera en alguno de los dos. Escribe un JSONL por línea un fragmento:
{"libro", "pagina", "texto"}. Ese archivo es lo que `indexar-guias.ts` sube.

Un PDF escaneado (sin capa de texto) va por OCR con tesseract en español.
Es lento —un par de minutos por cada cien páginas— y sólo pasa la primera vez.

El texto de los libros NO va al repo: `guias/` está en .gitignore. Se arma en la
Mac y se sube al VPS con scp (ver docs/arquitectura.md, «La guía de los libros»).

    python3 -m venv /tmp/v && /tmp/v/bin/pip install pymupdf
    /tmp/v/bin/python api/scripts/extraer-libros.py "/ruta/a/los libros" guias/fragmentos.jsonl
"""
import json
import re
import sys
import unicodedata
from pathlib import Path

import pymupdf

LARGO = 1200
SOLAPE = 200
MINIMO = 350

# El nombre del archivo trae la editorial pirata y los autores; para el prompt
# alcanza con el título y el autor principal.
TITULOS = {
    'Manual de Entrenamiento en Habilidades DBT': 'Linehan, Manual de habilidades DBT',
    'Manual para el tratamiento cognitivo-conductual': 'Caballo, Manual cognitivo-conductual',
    'Protocolo unificado': 'Barlow, Protocolo unificado',
    'Razón y emoción': 'Ellis, Razón y emoción en psicoterapia',
    'Sal de tu mente': 'Hayes, Sal de tu mente, entra en tu vida',
    'Sentirse bien': 'Burns, Sentirse bien',
    'Terapia cognitiva de la depresión': 'Beck, Terapia cognitiva de la depresión',
    'Terapia cognitiva (Judith': 'J. Beck, Terapia cognitiva',
    'Vivir con plenitud las crisis': 'Kabat-Zinn, Vivir con plenitud las crisis',
}


def titulo(archivo: Path) -> str:
    # macOS guarda los nombres con las tildes descompuestas.
    nombre = unicodedata.normalize('NFC', archivo.name)
    for clave, t in TITULOS.items():
        if nombre.startswith(clave):
            return t
    return archivo.stem.split(' (')[0]


def paginas(archivo: Path):
    doc = pymupdf.open(archivo)
    escaneado = archivo.suffix == '.pdf' and \
        sum(len(p.get_text()) for p in doc) < 50 * len(doc)
    for i, p in enumerate(doc):
        if escaneado:
            texto = p.get_textpage_ocr(language='spa', dpi=200, full=True).extractText()
        else:
            texto = p.get_text()
        yield i + 1, texto


def limpiar(t: str) -> str:
    t = re.sub(r'[\x00-\x08\x0b-\x1f\ufffd]', '', t)
    t = re.sub(r'-\n(?=[a-záéíóúñ])', '', t)      # palabras cortadas por guion
    t = re.sub(r'[ \t]+', ' ', t)
    t = re.sub(r'(?<![.:?!»”])\n(?!\n)', ' ', t)   # renglones dentro del párrafo
    return re.sub(r'\n{2,}', '\n\n', t).strip()


def parece_relleno(t: str) -> bool:
    """Índices, bibliografía, créditos: muchos números y pocas palabras."""
    letras = sum(c.isalpha() for c in t)
    digitos = sum(c.isdigit() for c in t)
    if letras < 0.6 * len(t) or digitos > 0.08 * len(t):
        return True
    return len(re.findall(r'\(\d{4}\)|pp\.|Ed\.|ISBN|Copyright', t)) > 3


def fragmentos(libro: str, archivo: Path):
    actual, desde = '', 1
    for pagina, crudo in paginas(archivo):
        for parrafo in limpiar(crudo).split('\n\n'):
            parrafo = parrafo.strip()
            if not parrafo:
                continue
            if not actual:
                desde = pagina
            actual = f'{actual}\n{parrafo}' if actual else parrafo
            if len(actual) >= LARGO:
                if not parece_relleno(actual):
                    yield {'libro': libro, 'pagina': desde, 'texto': actual}
                actual = actual[-SOLAPE:].split(' ', 1)[-1]
                desde = pagina
    if len(actual) >= MINIMO and not parece_relleno(actual):
        yield {'libro': libro, 'pagina': desde, 'texto': actual}


def main():
    carpeta, salida = Path(sys.argv[1]), Path(sys.argv[2])
    salida.parent.mkdir(parents=True, exist_ok=True)
    with salida.open('w', encoding='utf-8') as f:
        for archivo in sorted(carpeta.iterdir()):
            if archivo.suffix not in ('.pdf', '.epub'):
                continue
            libro, n = titulo(archivo), 0
            for frag in fragmentos(libro, archivo):
                f.write(json.dumps(frag, ensure_ascii=False) + '\n')
                n += 1
            print(f'{n:6} fragmentos  {libro}', flush=True)


if __name__ == '__main__':
    main()
