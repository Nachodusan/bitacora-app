-- ============================================================
-- BITÁCORA — esquema base
-- Postgres 17, mono-usuario. Corre tal cual: psql -f bitacora_schema.sql
--
-- Modelo mental:
--   entradas     = lo que dijiste (crudo, inmutable, fuente de verdad)
--   extracciones = lo que el LLM entendió (1 por entrada, con evidencia)
--   eventos      = todo lo demás que apareció, sin ampliar el esquema
--   dias         = rollup diario (lo que consulta el LLM, NO el crudo)
--   planes       = lo que te propuso + si lo cumpliste (el loop cerrado)
-- ============================================================

-- ------------------------------------------------------------
-- 1. ENTRADAS — cada vez que hablás. Nunca se edita ni se borra.
-- ------------------------------------------------------------
create table entradas (
  id            bigserial primary key,
  creado_en     timestamptz not null default now(),  -- instante absoluto
  creado_local  timestamp   not null,                -- hora de pared del iPhone

  -- Día lógico con corte a las 4am: lo que hablás a la 1am cuenta como el día
  -- anterior. Se calcula sobre creado_local (timestamp SIN tz) porque
  -- `AT TIME ZONE` es STABLE y Postgres no la acepta en columnas generadas.
  dia           date generated always as ((creado_local - interval '4 hours')::date) stored,

  fuente        text not null check (fuente in ('dictado_ios','whisper_api','texto')),
  transcripcion text not null,
  audio_uri     text,                       -- opcional; si no guardás audio, null
  duracion_seg  numeric(6,1),

  estado        text not null default 'pendiente'
                check (estado in ('pendiente','extraida','error')),
  error_msg     text
);

create index entradas_dia_idx on entradas (dia);
create index entradas_pendientes_idx on entradas (id) where estado = 'pendiente';

-- ------------------------------------------------------------
-- 2. EXTRACCIONES — salida del LLM, 1:1 con la entrada.
-- ------------------------------------------------------------
create table extracciones (
  id          bigserial primary key,
  entrada_id  bigint not null unique references entradas(id) on delete cascade,
  modelo      text   not null,
  creado_en   timestamptz not null default now(),

  sueno_horas    numeric(3,1) check (sueno_horas between 0 and 24),
  sueno_calidad  smallint     check (sueno_calidad between 1 and 5),

  entreno_hubo   boolean,
  entreno_min    integer      check (entreno_min between 0 and 600),
  entreno_tipo   text,

  animo_valencia smallint     check (animo_valencia between -2 and 2),
  animo_energia  smallint     check (animo_energia between 1 and 5),
  animo_tags     text[],

  evidencias  jsonb not null default '{}'::jsonb,
  crudo       jsonb not null,

  constraint ev_sueno    check (sueno_horas    is null or evidencias ? 'sueno_horas'),
  constraint ev_entreno  check (entreno_min    is null or evidencias ? 'entreno_min'),
  constraint ev_valencia check (animo_valencia is null or evidencias ? 'animo_valencia')
);

create index extracciones_crudo_idx on extracciones using gin (crudo);

-- ------------------------------------------------------------
-- 3. EVENTOS
-- ------------------------------------------------------------
create table eventos (
  id         bigserial primary key,
  entrada_id bigint not null references entradas(id) on delete cascade,
  dia        date   not null,
  tipo       text   not null check (tipo in
             ('habito','sustancia','comida','pantalla','social','trabajo','estudio','sintoma','otro')),
  etiqueta   text   not null,
  valor_num  numeric,
  unidad     text,
  polaridad  smallint check (polaridad in (-1,0,1)),
  evidencia  text not null
);

create index eventos_dia_idx on eventos (dia);
create index eventos_etiqueta_idx on eventos (etiqueta, dia);

-- ------------------------------------------------------------
-- 4. DIAS
-- ------------------------------------------------------------
create table dias (
  dia            date primary key,
  cerrado_en     timestamptz,
  n_entradas     integer not null default 0,
  sueno_horas    numeric(3,1),
  entreno_min    integer,
  animo_valencia numeric(3,2),
  animo_energia  numeric(3,2),
  resumen        text
);

create or replace function cerrar_dia(p_dia date) returns void as $$
begin
  insert into dias (dia, cerrado_en, n_entradas, sueno_horas, entreno_min,
                    animo_valencia, animo_energia)
  select e.dia,
         now(),
         count(*),
         max(x.sueno_horas),
         coalesce(sum(x.entreno_min), 0),
         avg(x.animo_valencia),
         avg(x.animo_energia)
  from entradas e
  join extracciones x on x.entrada_id = e.id
  where e.dia = p_dia
  group by e.dia
  on conflict (dia) do update set
    cerrado_en     = excluded.cerrado_en,
    n_entradas     = excluded.n_entradas,
    sueno_horas    = excluded.sueno_horas,
    entreno_min    = excluded.entreno_min,
    animo_valencia = excluded.animo_valencia,
    animo_energia  = excluded.animo_energia;
end;
$$ language plpgsql;

-- ------------------------------------------------------------
-- 5. PLANES
-- ------------------------------------------------------------
create table planes (
  id           bigserial primary key,
  dia_objetivo date not null unique,
  creado_en    timestamptz not null default now(),
  modelo       text not null,
  ficha        jsonb not null,
  nota         text
);

create table plan_items (
  id         bigserial primary key,
  plan_id    bigint   not null references planes(id) on delete cascade,
  orden      smallint not null,
  categoria  text     not null,
  texto      text     not null,
  cumplido   boolean,
  evidencia  text,
  entrada_id bigint references entradas(id),
  unique (plan_id, orden)
);

-- ------------------------------------------------------------
-- 6. LLM_LLAMADAS
-- ------------------------------------------------------------
create table llm_llamadas (
  id           bigserial primary key,
  creado_en    timestamptz not null default now(),
  tarea        text not null check (tarea in ('extraccion','resumen_dia','plan','consejo')),
  modelo       text not null,
  tokens_in    integer,
  tokens_out   integer,
  costo_usd    numeric(10,6),
  latencia_ms  integer,
  ok           boolean not null default true,
  ref_id       bigint
);

-- ============================================================
-- VISTAS
-- ============================================================

create view v_ventana_7d as
select
  count(*) filter (where sueno_horas is not null)         as dias_con_sueno,
  round(avg(sueno_horas), 1)                              as sueno_prom,
  count(*) filter (where sueno_horas < 6)                 as noches_menos_6h,
  count(*) filter (where entreno_min > 0)                 as dias_entreno,
  coalesce(sum(entreno_min), 0)                           as entreno_total_min,
  round(avg(animo_valencia), 2)                           as animo_prom,
  round(avg(animo_energia), 2)                            as energia_prom
from dias
where dia > current_date - 7;

create view v_adherencia as
select p.dia_objetivo,
       count(*)                              as items,
       count(*) filter (where i.cumplido)    as cumplidos,
       round(100.0 * count(*) filter (where i.cumplido) / nullif(count(*),0)) as pct
from planes p
join plan_items i on i.plan_id = p.id
group by p.dia_objetivo
order by p.dia_objetivo desc;

create view v_racha_entreno as
select count(*) as dias
from (
  select dia, entreno_min,
         dia - (row_number() over (order by dia desc) * interval '1 day')::date as grupo
  from dias
  where entreno_min > 0 and dia <= current_date
) t
where grupo = (
  select dia - interval '1 day' from dias
  where entreno_min > 0 and dia <= current_date
  order by dia desc limit 1
);
