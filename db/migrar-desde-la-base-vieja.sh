#!/usr/bin/env bash
# Pasa de la base anterior (historia/) a schema.sql. Se corre UNA vez.
#
# No borra nada: la base vieja queda renombrada a `bitacora_vieja`, intacta, y
# antes de tocar nada se hace un dump completo a tu home. Lo único que se copia
# a la base nueva son las entradas (la fuente de verdad), las notas de terapia
# y tus ajustes. Extracciones, días, planes y hábitos no tienen dónde ir y no
# hacen falta: la base nueva no los conoce.
#
# El servidor tiene que estar APAGADO: renombrar una base con conexiones
# abiertas falla.
set -euo pipefail
cd "$(dirname "$0")/.."

VIEJA=bitacora_vieja
NUEVA=bitacora
TEST=bitacora_test
RESPALDO="$HOME/bitacora-respaldo-antes-de-base-nueva.sql"
TMP="$(mktemp -d)"

existe() { psql -lqt | cut -d'|' -f1 | tr -d ' ' | grep -qx "$1"; }

if pgrep -f "tsx src/index.ts" >/dev/null; then
  echo "el servidor está corriendo; apagalo primero" >&2; exit 1
fi

if existe "$VIEJA"; then
  echo "ya existe $VIEJA: la migración ya corrió. No hago nada." >&2; exit 1
fi

echo "1. respaldo completo → $RESPALDO"
pg_dump "$NUEVA" > "$RESPALDO"

echo "2. renombro $NUEVA → $VIEJA"
psql -q -d postgres -c "alter database $NUEVA rename to $VIEJA"

echo "3. creo $NUEVA con el esquema nuevo"
createdb "$NUEVA"
psql -q -v ON_ERROR_STOP=1 -d "$NUEVA" -f db/schema.sql

echo "4. copio entradas, notas y ajustes"
psql -q -d "$VIEJA" -c "\copy (select id, client_uuid, creado_en, creado_local, fuente, transcripcion, duracion_seg from entradas where fuente in ('dictado_ios','texto') order by id) to '$TMP/entradas.csv' csv"
psql -q -d "$NUEVA" -c "\copy entradas (id, client_uuid, creado_en, creado_local, fuente, transcripcion, duracion_seg) from '$TMP/entradas.csv' csv"
psql -q -d "$NUEVA" -c "select setval('entradas_id_seq', coalesce((select max(id) from entradas), 0) + 1, false)"

psql -q -d "$VIEJA" -c "\copy (select entrada_id, dia, creado_en, modelo, citas, temas, contexto from notas_terapia order by id) to '$TMP/notas.csv' csv"
psql -q -d "$NUEVA" -c "\copy notas_terapia (entrada_id, dia, creado_en, modelo, citas, temas, contexto) from '$TMP/notas.csv' csv"

psql -q -d "$NUEVA" -c "update ajustes set nombre = (select nombre from dblink('dbname=$VIEJA', 'select nombre from ajustes where id = 1') as t(nombre text)), zona = (select zona from dblink('dbname=$VIEJA', 'select zona from ajustes where id = 1') as t(zona text)) where id = 1" 2>/dev/null \
  || psql -q -d "$NUEVA" -c "update ajustes set zona = '$(psql -At -d "$VIEJA" -c "select zona from ajustes where id = 1")', nombre = nullif('$(psql -At -d "$VIEJA" -c "select coalesce(nombre,'') from ajustes where id = 1")', '') where id = 1"

echo "5. base de tests: $TEST"
existe "$TEST" && dropdb "$TEST"
createdb "$TEST"
psql -q -v ON_ERROR_STOP=1 -d "$TEST" -f db/schema.sql

rm -rf "$TMP"

echo
echo "listo. cómo quedó $NUEVA:"
psql -d "$NUEVA" -c "select 'entradas' t, count(*) from entradas union all select 'notas_terapia', count(*) from notas_terapia union all select 'resumenes_dia', count(*) from resumenes_dia union all select 'llm_llamadas', count(*) from llm_llamadas"
psql -d "$NUEVA" -c "select nombre, zona from ajustes"
