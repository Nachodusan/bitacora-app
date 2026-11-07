# La base anterior (agosto 2026)

Estos tres archivos son la primera versión del esquema, con las 17 deltas que
la fueron cambiando. Se archivan el 06/09/2026, cuando la app se recorta a chat
más calendario y el esquema arranca de nuevo en `../schema.sql`.

No corren contra la base nueva y no hace falta que corran. Están para poder
leer *por qué* se decidió cada cosa: los comentarios de los deltas son la única
documentación de varias decisiones que la base nueva hereda (el corte de las
4am, la evidencia obligatoria, el candado del tick).

- `bitacora_schema.sql` — el original, que nunca se tocó.
- `deltas.sql` — los 17 cambios, idempotentes.
- `seed.sql` — datos de prueba. Quedó roto contra el delta 3 y nunca se arregló.

La base vieja sigue existiendo en Postgres como `bitacora_vieja`, intacta, por
si hay que volver a mirar algo. Y hay un respaldo completo en
`~/bitacora-respaldo-antes-de-base-nueva.sql`.
