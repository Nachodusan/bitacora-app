-- ============================================================
-- Bitácora — esquema base
--
-- Segunda base, 06/09/2026. La primera está archivada en historia/.
--
-- La app es un chat de voz con una compañera (Bitácora) y un calendario con las
-- conversaciones de cada día. Nada más. Esto es todo lo que el servidor
-- necesita guardar para eso:
--
--   entradas       lo que dijiste, crudo. La fuente de verdad.
--   resumenes_dia  dos o tres líneas por día: la memoria de Bitácora.
--   notas_terapia  frases textuales tuyas para llevar a una sesión.
--   llm_llamadas   cada llamada al modelo, con su costo. Regla 5.
--   ajustes        una fila: tu nombre y tu zona horaria.
--
-- Corre tal cual con `psql -d bitacora -f db/schema.sql` sobre una base vacía.
-- Sobre una base que ya lo tiene, falla en la primera línea — a propósito: este
-- archivo no se corre dos veces. Cuando haga falta cambiar el esquema, va un
-- archivo nuevo en db/migraciones/ (crear la carpeta), con su porqué arriba.
-- ============================================================

-- Para `resumenes_dia.embedding`. Viene con `brew install pgvector`.
create extension if not exists vector;

-- ------------------------------------------------------------
-- ENTRADAS
-- ------------------------------------------------------------
create table entradas (
  id            bigserial primary key,

  -- Lo manda el teléfono. Es lo que hace que reintentar una subida después de
  -- un timeout no cree una entrada duplicada: el servidor ya la tenía, y
  -- devuelve el mismo id. Nullable para que una fila metida a mano por SQL no
  -- tenga que inventar un uuid; el UNIQUE de abajo ignora los NULL.
  client_uuid   uuid,

  creado_en     timestamptz not null default now(),   -- el instante absoluto
  creado_local  timestamp   not null,                 -- la hora de pared del iPhone

  -- El día lógico corta a las 4am: lo que hablás a la 1 de la mañana pertenece
  -- al día anterior. Se calcula sobre `creado_local`, que es timestamp SIN
  -- zona, y no con AT TIME ZONE: esa función es STABLE y Postgres no la acepta
  -- en una columna generada. Que sea GENERATED es lo que hace la regla
  -- irrompible desde afuera — ningún INSERT puede mandarle otro valor.
  --
  -- La misma fórmula está en el teléfono (DiaLogico.horaDeCorte) y en
  -- leerReloj(). Si cambia, cambia en los tres lados o el sistema se parte.
  dia           date generated always as ((creado_local - interval '4 hours')::date) stored,

  fuente        text not null check (fuente in ('dictado_ios', 'dictado_android', 'texto')),
  transcripcion text not null check (length(btrim(transcripcion)) > 0),
  duracion_seg  numeric(6,1),

  -- Cuándo se revisó esta conversación para escribirle una nota de terapia.
  -- NULL es "todavía no". No es una máquina de estados: es un hecho con fecha.
  --
  -- Existe porque una nota puede no existir por dos motivos distintos —se
  -- intentó y no había nada que rescatar, o nunca se intentó— y sin esto no se
  -- distinguen: el tick volvía a llamar al modelo por la misma charla corta en
  -- cada latido, para siempre, o peor, dejaba huérfanas las que fallaron una vez.
  nota_revisada_en timestamptz,

  -- Cuándo se buscó en esta conversación una consulta mencionada («el jueves
  -- tengo terapia a las cinco») para proponerla en el calendario. Mismo patrón
  -- que la de arriba: un hecho con fecha, y NULL es "todavía no".
  consultas_revisadas_en timestamptz
);

create index entradas_sin_nota_idx on entradas (dia) where nota_revisada_en is null;

create unique index entradas_client_uuid_key on entradas (client_uuid)
  where client_uuid is not null;

create index entradas_dia_idx on entradas (dia, creado_local);

-- No hay columna `estado`, y es lo más importante que cambió respecto de la
-- base anterior. Antes cada entrada pasaba por pendiente → extraída → error, y
-- ese "error" era terminal: una caída del proveedor o un timeout convertía una
-- charla real en una fila muerta sin ningún camino de vuelta. Acá una entrada
-- es una entrada. Lo que se deriva de ella (resumen, nota) se intenta aparte y,
-- si falla, se vuelve a intentar. Nada le pasa a la entrada.

-- ------------------------------------------------------------
-- RESÚMENES — la memoria de Bitácora
-- ------------------------------------------------------------
create table resumenes_dia (
  dia         date primary key,

  -- Dos o tres líneas en segunda persona, sin una sola cifra. Los dígitos son
  -- donde se cuela el invento: el modelo lee "siete horas y media" de sueño y
  -- escribe "te levantaste a las 7:30". Un resumen con cifras no se guarda.
  --
  -- Nullable, y no por descuido: cuando el modelo devuelve algo que no cumple,
  -- la fila queda con resumen NULL y `intentos` sube. Sin eso, un día que el
  -- modelo no logra resumir se reintentaría en cada tick, para siempre, a una
  -- llamada por vez.
  resumen     text check (resumen is null
                          or (length(btrim(resumen)) > 0 and resumen !~ '\d')),
  intentos    smallint not null default 0,

  -- Cuántas entradas tenía el día cuando se escribió. Cerrar un día no es
  -- definitivo: con la cola offline del teléfono, algo dictado a la 1am sin
  -- señal puede aterrizar a las 9 con el resumen ya escrito. El tick compara
  -- este número contra el real y, si difieren, lo reescribe. Es un estado
  -- derivado de los datos, no una marca que alguien tenga que acordarse de poner.
  n_entradas  integer not null check (n_entradas >= 0),

  modelo      text,
  creado_en   timestamptz not null default now(),

  -- El mismo resumen como vector, para encontrarlo cuando la persona vuelve a
  -- nombrar algo de hace meses. NULL hasta que el latido lo calcula, y vuelve a
  -- NULL cada vez que el resumen se reescribe: es derivado del texto, y uno
  -- viejo apuntaría a un recuerdo que ya no dice eso. 1024 es `BAAI/bge-m3`.
  embedding   vector(1024)
);

-- ------------------------------------------------------------
-- LA GUÍA DE LOS LIBROS
-- ------------------------------------------------------------
-- Fragmentos de manuales de terapia (Beck, Linehan, Barlow, Hayes, Burns...),
-- con su vector. En cada turno se buscan los que vienen al caso y Bitácora los
-- recibe como criterio para contestar, no para citarlos (`guias.ts`).
--
-- Es la única tabla que no sale de la persona: se carga entera desde afuera con
-- `npm run guias`, y volver a cargarla es borrarla y llenarla de nuevo.
create table if not exists guias (
  id         bigserial primary key,
  libro      text not null,
  pagina     integer,
  texto      text not null,
  -- 1024 es `BAAI/bge-m3`, el mismo de los resúmenes.
  embedding  vector(1024) not null
);

-- ------------------------------------------------------------
-- NOTAS PARA TERAPIA
-- ------------------------------------------------------------
-- Lo que dijiste un día, en TUS palabras, para llevarlo a una sesión.
--
-- No es una nota clínica. Son tres cosas y ninguna más: frases literales tuyas,
-- rótulos de qué apareció, y dos líneas para ubicarlas. El material es tuyo;
-- la lectura es del profesional. Cada cita se verifica contra la transcripción
-- antes de guardarse: una frase inventada acá no es un dato flojo, es ponerle
-- en la boca a una persona algo que no dijo, delante de su terapeuta.
create table notas_terapia (
  id          bigserial primary key,
  entrada_id  bigint not null unique references entradas(id) on delete cascade,
  dia         date   not null,
  creado_en   timestamptz not null default now(),
  modelo      text   not null,
  citas       jsonb  not null,
  temas       text[] not null default '{}',
  contexto    text,
  -- Emociones, impulsos, conductas y hábitos que contó, cada uno con su frase
  -- literal. Sólo para el PDF del psicólogo: la app no se lo muestra a la
  -- persona, para que no se autodiagnostique.
  registro    jsonb  not null default '[]' check (jsonb_typeof(registro) = 'array'),

  -- Sin citas no hay nota. Es la razón de ser de la tabla.
  constraint nota_con_citas check (jsonb_typeof(citas) = 'array'
                                   and jsonb_array_length(citas) > 0)
);

create index notas_terapia_dia_idx on notas_terapia (dia);

-- ------------------------------------------------------------
-- LLAMADAS AL MODELO — regla 5
-- ------------------------------------------------------------
-- Toda llamada queda acá, salga bien o mal: una que falló también costó tokens.
-- Es lo que lee el guard de presupuesto para decidir si corta ANTES de llamar.
--
-- Si agregás una tarea en el tipo `Tarea` de llm.ts, agregala también en este
-- CHECK. Si no, el insert del registro rebota, `registrar()` lo traga con un
-- console.error, y esa plata no se cuenta nunca: el guard queda ciego.
create table llm_llamadas (
  id           bigserial primary key,
  creado_en    timestamptz not null default now(),
  tarea        text not null check (tarea in ('charla', 'resumen_dia', 'nota_terapia', 'voz',
                                           'embedding', 'rerank', 'consulta',
                                           'para_llevar', 'evaluacion', 'emociones')),
  modelo       text not null,
  tokens_in    integer,
  tokens_out   integer,
  costo_usd    numeric(10,6),
  latencia_ms  integer,
  ok           boolean not null default true,
  ref_id       bigint
);

create index llm_llamadas_mes_idx on llm_llamadas (creado_en);

-- ------------------------------------------------------------
-- EVENTOS DEL CALENDARIO
-- ------------------------------------------------------------
-- Sobre todo las consultas con su terapeuta: con ellas Bitácora sabe cuándo
-- ayudar a preparar una sesión y cuándo preguntar cómo le fue. Viven acá y no
-- sólo en el teléfono porque Bitácora las tiene que ver, y porque puede
-- proponer una que la persona mencionó en una charla. El teléfono guarda una
-- copia para mostrarlas sin red.
create table eventos (
  id            bigserial primary key,
  -- Idempotencia, como en `entradas`: reintentar el alta no duplica.
  client_uuid   uuid,
  tipo          text not null check (tipo in ('consulta', 'otro')),
  dia           date not null,
  hora          time,
  titulo        text check (titulo is null or length(btrim(titulo)) between 1 and 80),
  -- Quién la puso. Las de Bitácora nacen 'propuesto' y no cuentan para nada
  -- hasta que la persona las confirma; 'descartado' queda para no volver a
  -- proponer la misma.
  origen        text not null check (origen in ('persona', 'bitacora')),
  estado        text not null default 'confirmado'
                check (estado in ('confirmado', 'propuesto', 'descartado')),
  -- La charla de donde salió una propuesta.
  entrada_id    bigint references entradas(id) on delete set null,

  -- Lo que eligió llevar a la consulta, en la charla de antes. Derivado, como
  -- los resúmenes: `para_llevar_n` es de cuántas charlas salió, y si cambia,
  -- se vuelve a escribir.
  para_llevar   jsonb not null default '[]' check (jsonb_typeof(para_llevar) = 'array'),
  para_llevar_n integer not null default 0,

  -- El borrador de la evaluación, escrito con lo que contó después. Se BORRA
  -- apenas la evaluación queda guardada en el teléfono (`evaluada_en`): las
  -- evaluaciones viven allá, no acá.
  borrador      jsonb,
  borrador_n    integer not null default 0,
  evaluada_en   timestamptz,

  creado_en     timestamptz not null default now(),
  constraint otro_con_titulo check (tipo = 'consulta' or titulo is not null)
);

create unique index eventos_client_uuid_key on eventos (client_uuid)
  where client_uuid is not null;
create index eventos_dia_idx on eventos (dia);

-- ------------------------------------------------------------
-- AJUSTES — una sola fila
-- ------------------------------------------------------------
create table ajustes (
  id          smallint primary key default 1 check (id = 1),

  -- Cómo querés que Bitácora te llame. NULL es una respuesta válida: nadie está
  -- obligado a dar su nombre para escribir un diario, y sin nombre la charla
  -- funciona igual — simplemente no te nombra.
  --
  -- El techo de 40 no es cosmético. Esto entra al system prompt de Bitácora, y un
  -- "nombre" de dos mil caracteres es el lugar más obvio para meterle
  -- instrucciones por la puerta de atrás.
  nombre      text,
  constraint ajustes_nombre_razonable
    check (nombre is null or length(btrim(nombre)) between 1 and 40),

  -- Identificador IANA. El tick necesita saber qué hora es en tu muñeca para
  -- decidir qué días ya terminaron; en un VPS el reloj está en UTC.
  zona        text not null,

  actualizado timestamptz not null default now()
);

insert into ajustes (id, zona) values (1, 'America/Argentina/Buenos_Aires');
