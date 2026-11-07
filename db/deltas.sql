-- ============================================================
-- DELTAS DEL ESQUEMA NUEVO
-- ============================================================
-- `schema.sql` es la verdad y se aplica entero en una base vacía. Esto es para
-- la base que YA está corriendo: cada bloque es lo que hay que ejecutar para
-- ponerla al día, en orden, y todos son idempotentes.
--
-- Los deltas del esquema viejo (los diecisiete anteriores al 06/09/2026) están
-- archivados en `historia/deltas.sql` y no se aplican a esta base.

-- ------------------------------------------------------------
-- DELTA 1 — la voz de Bitácora también es una llamada al modelo.
--
-- Hasta ahora las tres tareas registradas eran de texto. La voz se sintetiza
-- con el mismo proveedor y la misma clave, así que también cuesta, y la regla 5
-- dice que toda llamada queda registrada: sin esto el insert de `registrar()`
-- rebota contra el CHECK, `voz.ts` lo traga con un console.error, y esa plata
-- no la cuenta nadie — el guard de presupuesto queda ciego justo para la
-- llamada más fácil de repetir sin querer.
--
-- La restricción ya no se pone acá: la lista definitiva de tareas está en el
-- último delta que la cambia (hoy, el 4). Cuando cada delta reponía la lista de
-- su día, volver a correr el archivo sobre una base con registros de tareas
-- más nuevas fallaba acá —borraba la restricción y no la podía volver a poner—
-- y la tabla quedaba sin ella. Pasó dos veces, contra `bitacora_test`.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- DELTA 2 — Bitácora se acuerda de más atrás que una semana.
--
-- Cada resumen de día se guarda también como vector, y en cada turno se buscan
-- los que se parecen a lo que la persona acaba de decir. Se indexan los
-- RESÚMENES y nada más: la regla de que Bitácora no ve la historia cruda sigue
-- intacta, lo único que cambia es cuántos resúmenes puede llegar a ver.
--
-- Sin índice a propósito: es una fila por día, y con cientos de filas el
-- recorrido exacto tarda menos que lo que se ganaría con uno aproximado.
--
-- 1024 es el tamaño de `BAAI/bge-m3`. Cambiar de modelo de embedding es cambiar
-- este número y volver a calcular todos: vectores de dos modelos no se comparan.
--
-- Y dos tareas nuevas en el registro, por lo mismo que el delta 1: el embedding
-- y el reordenado también son llamadas a un modelo.
-- ------------------------------------------------------------
create extension if not exists vector;
alter table resumenes_dia add column if not exists embedding vector(1024);
-- Las dos tareas nuevas entran en la restricción del delta 4, que tiene la
-- lista completa (ver el delta 1).

-- ------------------------------------------------------------
-- DELTA 3 — Laya pasa a llamarse Bitácora (02/10/2026).
--
-- La compañera se llama como la app. Las transcripciones guardadas tienen sus
-- líneas rotuladas "Laya:", y ese rótulo no es decorado: lo leen el resumen del
-- día y la verificación de las citas para terapia. Se renombra sólo el
-- rótulo, al principio de cada línea (la `n` hace que `^` sea principio de
-- línea): si la persona dijo «Laya» en lo suyo, eso queda como lo dijo.
--
-- Y el único resumen que la nombraba en el texto. Su vector se borra porque
-- era de las palabras viejas; el latido lo vuelve a calcular.
--
-- Respaldo de antes de correrlo: ~/bitacora-respaldo-antes-de-renombrar-2026-10-02.sql
-- Las entradas que lleguen de un teléfono sin reinstalar se traducen al
-- entrar (`ROTULO_VIEJO`, en server.ts).
-- ------------------------------------------------------------
update entradas
   set transcripcion = regexp_replace(transcripcion, '^Laya:', 'Bitácora:', 'gn')
 where transcripcion ~ '(^|\n)Laya:';

update resumenes_dia
   set resumen = replace(resumen, 'Laya', 'Bitácora'), embedding = null
 where resumen like '%Laya%';

-- ------------------------------------------------------------
-- DELTA 4 — consultas en el calendario (03/10/2026).
--
-- Los eventos del calendario, sobre todo las consultas con su terapeuta. Con
-- ellos Bitácora ayuda a preparar una sesión el día anterior, pregunta cómo le
-- fue después, y deja un borrador de la evaluación. El porqué de cada columna
-- está en `schema.sql`.
--
-- Y tres tareas nuevas en el registro, por lo mismo que los deltas 1 y 2: buscar
-- consultas en una charla, anotar lo que eligió llevar y escribir el borrador
-- son llamadas a un modelo.
-- ------------------------------------------------------------
create table if not exists eventos (
  id            bigserial primary key,
  client_uuid   uuid,
  tipo          text not null check (tipo in ('consulta', 'otro')),
  dia           date not null,
  hora          time,
  titulo        text check (titulo is null or length(btrim(titulo)) between 1 and 80),
  origen        text not null check (origen in ('persona', 'bitacora')),
  estado        text not null default 'confirmado'
                check (estado in ('confirmado', 'propuesto', 'descartado')),
  entrada_id    bigint references entradas(id) on delete set null,
  para_llevar   jsonb not null default '[]' check (jsonb_typeof(para_llevar) = 'array'),
  para_llevar_n integer not null default 0,
  borrador      jsonb,
  borrador_n    integer not null default 0,
  evaluada_en   timestamptz,
  creado_en     timestamptz not null default now(),
  constraint otro_con_titulo check (tipo = 'consulta' or titulo is not null)
);
create unique index if not exists eventos_client_uuid_key on eventos (client_uuid)
  where client_uuid is not null;
create index if not exists eventos_dia_idx on eventos (dia);

alter table entradas add column if not exists consultas_revisadas_en timestamptz;

alter table llm_llamadas drop constraint if exists llm_llamadas_tarea_check;
alter table llm_llamadas
  add constraint llm_llamadas_tarea_check
  check (tarea in ('charla', 'resumen_dia', 'nota_terapia', 'voz', 'embedding', 'rerank',
                   'consulta', 'para_llevar', 'evaluacion'));

-- ------------------------------------------------------------
-- DELTA 5 — la app de Android (03/10/2026).
--
-- Una charla dictada en Android dice que viene de ahí. El valor sólo informa:
-- nada del servidor hace algo distinto según de dónde venga.
-- ------------------------------------------------------------
alter table entradas drop constraint if exists entradas_fuente_check;
alter table entradas
  add constraint entradas_fuente_check
  check (fuente in ('dictado_ios', 'dictado_android', 'texto'));

-- ------------------------------------------------------------
-- DELTA 6 — el registro para el psicólogo (14/10/2026).
--
-- Emociones, impulsos, conductas y hábitos que la persona contó un día, cada
-- uno con la frase suya que lo respalda. Va sólo en el PDF: la app no se lo
-- muestra a la persona.
-- ------------------------------------------------------------
alter table notas_terapia
  add column if not exists registro jsonb not null default '[]'
  check (jsonb_typeof(registro) = 'array');

-- ------------------------------------------------------------
-- DELTA 7 — la guía de los libros (26/10/2026).
--
-- Fragmentos de manuales de terapia con su vector, para que Bitácora conteste
-- con más criterio cuando la persona está mal o es tarde de noche. Se llena con
-- `npm run guias` (ver docs/arquitectura.md, «La guía de los libros»).
-- ------------------------------------------------------------
create table if not exists guias (
  id         bigserial primary key,
  libro      text not null,
  pagina     integer,
  texto      text not null,
  embedding  vector(1024) not null
);

-- ------------------------------------------------------------
-- DELTA 8 — las emociones de «Ponerle nombre» (26/10/2026).
--
-- Una tarea nueva en el registro: proponer emociones a partir de lo que la
-- persona contó también es una llamada al modelo (regla 5).
-- ------------------------------------------------------------
alter table llm_llamadas drop constraint if exists llm_llamadas_tarea_check;
alter table llm_llamadas
  add constraint llm_llamadas_tarea_check
  check (tarea in ('charla', 'resumen_dia', 'nota_terapia', 'voz', 'embedding', 'rerank',
                   'consulta', 'para_llevar', 'evaluacion', 'emociones'));

-- ------------------------------------------------------------
-- DELTA 9 — el resumen de cada charla (27/10/2026).
--
-- Bitácora no ve la historia cruda, sólo resúmenes (regla 2), y el del día se
-- escribe cuando el día termina. Esa noche, a las 3, no sabía nada de la charla
-- de hacía cinco minutos. Ahora cada charla tiene su resumen apenas se guarda,
-- y `resumen_largo` dice de qué largo era la transcripción cuando se escribió:
-- si la charla siguió creciendo, se vuelve a resumir.
-- ------------------------------------------------------------
alter table entradas add column if not exists resumen text;
alter table entradas add column if not exists resumen_largo integer;
alter table llm_llamadas drop constraint if exists llm_llamadas_tarea_check;
alter table llm_llamadas
  add constraint llm_llamadas_tarea_check
  check (tarea in ('charla', 'resumen_dia', 'nota_terapia', 'voz', 'embedding', 'rerank',
                   'consulta', 'para_llevar', 'evaluacion', 'emociones', 'resumen_charla'));

-- ------------------------------------------------------------
-- DELTA 10 — la ficha viva del paciente (27/10/2026, etapa 1).
--
-- Los relatos son `entradas`, intactos: la ficha se deriva de ahí y se puede
-- reconstruir desde cero. Nada de esto lo borra el sistema: los datos viejos
-- pierden peso con el tiempo, no se pisan. Lo único que borra es la persona
-- (`borrado_en`, desde Mi espacio). Ver `ficha.ts`.
-- ------------------------------------------------------------
create table if not exists ficha_nodos (
  id          bigserial primary key,
  -- persona: su gente. problematica: lo que le pasa. desencadenante: lo que lo
  -- activa. meta. le_sirve / no_le_sirve. dato: quién es, sólo lo que contó.
  -- como_hablarle: cómo prefiere que le hablen.
  tipo        text not null check (tipo in ('persona', 'problematica', 'desencadenante', 'meta',
                                            'le_sirve', 'no_le_sirve', 'dato', 'como_hablarle')),
  nombre      text not null,
  descripcion text,
  apodos      text[] not null default '{}',
  primera     date not null,
  ultima      date not null,
  veces       integer not null default 1,
  borrado_en  timestamptz
);
create unique index if not exists ficha_nodos_nombre on ficha_nodos (tipo, lower(nombre));

create table if not exists ficha_conexiones (
  id        bigserial primary key,
  desde     bigint not null references ficha_nodos(id) on delete cascade,
  hacia     bigint not null references ficha_nodos(id) on delete cascade,
  relacion  text not null,
  primera   date not null,
  ultima    date not null,
  veces     integer not null default 1,
  unique (desde, hacia, relacion)
);

-- La frase tal cual la dijo, y de dónde salió. Si se borra la conversación, se
-- va con ella.
create table if not exists ficha_evidencias (
  id          bigserial primary key,
  nodo_id     bigint references ficha_nodos(id) on delete cascade,
  conexion_id bigint references ficha_conexiones(id) on delete cascade,
  entrada_id  bigint not null references entradas(id) on delete cascade,
  dia         date not null,
  cita        text not null,
  creado_en   timestamptz not null default now(),
  check (nodo_id is not null or conexion_id is not null)
);

-- Una fila por momento y por problemática. Nunca se borra ni se pisa.
create table if not exists ficha_progreso (
  id          bigserial primary key,
  nodo_id     bigint not null references ficha_nodos(id) on delete cascade,
  entrada_id  bigint not null references entradas(id) on delete cascade,
  dia         date not null,
  como_estaba text not null,
  cita        text not null,
  diferencia  text not null check (diferencia in ('primera', 'mejoro', 'empeoro', 'igual', 'cambio_de_foco'))
);

alter table entradas add column if not exists ficha_revisada_en timestamptz;

alter table llm_llamadas drop constraint if exists llm_llamadas_tarea_check;
alter table llm_llamadas
  add constraint llm_llamadas_tarea_check
  check (tarea in ('charla', 'resumen_dia', 'nota_terapia', 'voz', 'embedding', 'rerank',
                   'consulta', 'para_llevar', 'evaluacion', 'emociones', 'resumen_charla', 'ficha'));

-- DELTA 11 — la ficha en Mi espacio (27/10/2026, etapa 1).
--
-- La persona ve su ficha, elige qué le llega a su psicólogo (`compartir`) y
-- borra en tres niveles: un dato (`ficha_nodos.borrado_en`), una conversación
-- (la fila de `entradas`, con todo lo que salió de ella) o la cuenta entera,
-- que espera treinta días en la papelera (`ajustes.cuenta_borrar_en`).
-- La ficha no se arma hasta que la persona leyó el aviso (`ficha_avisada_en`).
-- ------------------------------------------------------------
alter table ficha_nodos add column if not exists compartir boolean not null default false;
alter table ajustes add column if not exists ficha_avisada_en timestamptz;
alter table ajustes add column if not exists cuenta_borrar_en timestamptz;

-- DELTA 12 — cuentas con ID y PIN (28/10/2026).
--
-- Una base por persona, como cuando cada diario era un servidor aparte. La
-- tabla de cuentas vive en la base principal (`DATABASE_URL`) y dice qué base
-- es de quién; en las demás queda vacía. Las bases nuevas se copian de
-- `bitacora_plantilla` (ver docs/arquitectura.md), que hay que tener al día con estos deltas.
--
-- Sin correo ni teléfono todavía: si se olvida el PIN, se crea otra cuenta.
-- ------------------------------------------------------------
create table if not exists cuentas (
  id              text primary key,
  pin_hash        text not null,
  -- null: la base principal, el diario que ya existía.
  bd              text unique,
  creada_en       timestamptz not null default now(),
  intentos        integer not null default 0,
  bloqueada_hasta timestamptz
);
create unique index if not exists cuentas_una_principal on cuentas ((bd is null)) where bd is null;

create table if not exists sesiones (
  token_hash  text primary key,
  cuenta_id   text not null references cuentas(id) on delete cascade,
  creada_en   timestamptz not null default now()
);

-- Lo que la persona da al registrarse. Todo opcional.
alter table ajustes add column if not exists edad smallint check (edad is null or edad between 10 and 110);
alter table ajustes add column if not exists vive_en text check (vive_en is null or length(vive_en) <= 80);
alter table ajustes add column if not exists de_donde text check (de_donde is null or length(de_donde) <= 80);
alter table ajustes add column if not exists con_quien text check (con_quien is null or length(con_quien) <= 80);

-- DELTA 13 — el registro pide la fecha de nacimiento (la edad se calcula y se
-- mantiene al día sola) y un solo lugar: país y ciudad (28/10/2026). `edad`,
-- `vive_en` y `de_donde` quedan sin usar.
-- ------------------------------------------------------------
alter table ajustes add column if not exists fecha_nacimiento date
  check (fecha_nacimiento is null or fecha_nacimiento between '1900-01-01' and current_date);
alter table ajustes add column if not exists pais text check (pais is null or length(pais) <= 60);
alter table ajustes add column if not exists ciudad text check (ciudad is null or length(ciudad) <= 60);

-- DELTA 14 — cuándo le sirve cada cosa (28/10/2026, etapa 2). Para «Qué le
-- sirve» y «Qué no le sirve»: en qué momento lo contó, contado por momento
-- ({"en la noche": 3}). El «con qué» son las conexiones «le ayuda con».
-- ------------------------------------------------------------
alter table ficha_nodos add column if not exists momentos jsonb not null default '{}';
