-- ============================================================
-- DELTAS al esquema — se corre DESPUÉS de bitacora_schema.sql
--
-- El esquema original queda intacto. Acá van sólo los cambios que hacen falta,
-- cada uno con la razón. De los nueve deltas que encontré, ESTE ARCHIVO APLICA
-- SÓLO DOS: los que bloquean que la app funcione hoy. Los otros siete siguen
-- sin aplicar, esperando decisión.
-- ============================================================


-- ------------------------------------------------------------
-- DELTA 1 — v_racha_entreno no se creaba.
--
--   ERROR: cannot cast type interval to date
--
-- No existe cast interval → date en Postgres, así que el archivo original
-- termina con esa vista sin crear. Aparte del cast, la lógica de islas tampoco
-- cerraba: comparaba un id de isla contra una fecha.
--
-- Testeada: 3 días seguidos → 3; si corta ayer → 2; si la única racha es vieja
-- → 0.
-- ------------------------------------------------------------
drop view if exists v_racha_entreno;

create view v_racha_entreno as
with d as (
  select dia, dia - (row_number() over (order by dia))::int as grupo
  from dias
  where entreno_min > 0 and dia <= current_date
)
select coalesce((select count(*) from d
                 where grupo = (select grupo from d order by dia desc limit 1)
                   and (select max(dia) from d) >= current_date - 1), 0) as dias;


-- ------------------------------------------------------------
-- DELTA 5 — falta entradas.client_uuid.
--
-- F1 pide idempotencia por client_uuid con UNIQUE, y POST /entradas lo recibe,
-- pero la columna no existía. Sin esto, un reintento después de un timeout
-- crea una entrada duplicada — que es justo lo que la cola offline garantiza
-- que no pasa.
--
-- Nullable a propósito: si alguna vez se inserta una entrada a mano por SQL,
-- no tiene por qué inventar un uuid. El UNIQUE ignora los NULL.
-- ------------------------------------------------------------
alter table entradas
  add column if not exists client_uuid uuid;

create unique index if not exists entradas_client_uuid_key
  on entradas (client_uuid)
  where client_uuid is not null;


-- ============================================================
-- LO QUE NO SE APLICÓ — siete deltas esperando decisión.
--
-- 2. Los CHECK de evidencia cubren 3 de 7 columnas. Faltan sueno_calidad,
--    entreno_hubo, entreno_tipo y animo_energia; además `evidencias ? 'k'`
--    acepta string vacío. La regla 1 está enforced a medias.
--
-- 3. Falta extracciones.sueno_dia. Sin eso, el sueño contado entre medianoche
--    y las 4am se guarda en el día anterior, y la regla 3 es inimplementable.
--
-- 4. cerrar_dia hace join con extracciones, así que ignora las entradas
--    pendientes y n_entradas queda corto.
--
-- 6. Regla 6: no hay dónde guardar la señal de riesgo, y el JSON Schema tiene
--    additionalProperties:false. El teléfono ya corta la conversación, pero el
--    servidor no se entera y va a generar plan igual. BLOQUEANTE PARA F3.
--
-- 7. La transcripción ahora es un diálogo con prefijos "Vos:" / "Laya:". El
--    system prompt de extracción tiene que decir explícito que la evidencia se
--    cita SÓLO de las líneas "Vos:".
--
-- 8. Falta una tabla `habitos`. Un hábito no es un plan_item: el plan se vence
--    a la noche, el hábito se sostiene.
--
-- 9. Faltan `compromisos` y `compromiso_dias`, con cumplido boolean NULLABLE.
--    Hoy viven sólo en el teléfono.
-- ============================================================


-- ============================================================
-- SEGUNDA TANDA — los que F2 necesita para ser correcta.
-- Se agregaron al aprobar la extracción; el esquema original sigue intacto.
-- ============================================================


-- ------------------------------------------------------------
-- DELTA 2 — la regla 1 estaba enforced a medias.
--
-- Los CHECK originales cubren sueno_horas, entreno_min y animo_valencia.
-- Faltaban cuatro columnas, así que un valor podía entrar sin evidencia y la
-- regla de oro se cumplía sólo en 3 de 7 casos.
--
-- Y `evidencias ? 'k'` sólo comprueba que la CLAVE exista: {"sueno_horas": ""}
-- pasaba. Ahora la evidencia tiene que ser un string con contenido, porque una
-- cita vacía no justifica nada.
-- ------------------------------------------------------------
-- OJO con el coalesce: sin él, una clave AUSENTE hace que `ev -> clave` sea
-- NULL, `jsonb_typeof(NULL)` sea NULL y toda la expresión sea NULL. Y un CHECK
-- que evalúa a NULL en SQL **pasa**. O sea: sin esta línea, el caso principal
-- —que el modelo directamente no cite nada— entraría sin control, que es
-- exactamente lo que la regla 1 existe para impedir.
create or replace function tiene_evidencia(ev jsonb, clave text) returns boolean as $$
  select coalesce(jsonb_typeof(ev -> clave) = 'string'
                  and length(btrim(ev ->> clave)) > 0, false)
$$ language sql immutable;

-- Se borran los viejos y también los nuevos, para que el archivo se pueda
-- volver a correr sin explotar.
alter table extracciones drop constraint if exists ev_sueno;
alter table extracciones drop constraint if exists ev_entreno;
alter table extracciones drop constraint if exists ev_valencia;
alter table extracciones drop constraint if exists ev_sueno_horas;
alter table extracciones drop constraint if exists ev_sueno_calidad;
alter table extracciones drop constraint if exists ev_entreno_min;
alter table extracciones drop constraint if exists ev_entreno_hubo;
alter table extracciones drop constraint if exists ev_entreno_tipo;
alter table extracciones drop constraint if exists ev_valencia;
alter table extracciones drop constraint if exists ev_energia;

alter table extracciones
  add constraint ev_sueno_horas   check (sueno_horas    is null or tiene_evidencia(evidencias, 'sueno_horas')),
  add constraint ev_sueno_calidad check (sueno_calidad  is null or tiene_evidencia(evidencias, 'sueno_calidad')),
  add constraint ev_entreno_min   check (entreno_min    is null or tiene_evidencia(evidencias, 'entreno_min')),
  add constraint ev_entreno_hubo  check (entreno_hubo   is null or tiene_evidencia(evidencias, 'entreno_hubo')),
  add constraint ev_entreno_tipo  check (entreno_tipo   is null or tiene_evidencia(evidencias, 'entreno_tipo')),
  add constraint ev_valencia      check (animo_valencia is null or tiene_evidencia(evidencias, 'animo_valencia')),
  add constraint ev_energia       check (animo_energia  is null or tiene_evidencia(evidencias, 'animo_energia'));


-- `eventos.evidencia` es `not null`, pero un string VACÍO cumple not null. Un
-- evento podía entrar con una cita de cero caracteres, que es tanta evidencia
-- como no tener ninguna.
alter table eventos drop constraint if exists evento_con_evidencia;
alter table eventos
  add constraint evento_con_evidencia check (length(btrim(evidencia)) > 0);


-- ------------------------------------------------------------
-- DELTA 3 — el sueño pertenece a la mañana en que TERMINÓ.
--
-- `extracciones` es 1:1 con la entrada, y la entrada cae en su día lógico. Si
-- contás a la 01:30 del lunes que dormiste seis horas, la entrada es del
-- domingo (corte 4am) pero ese sueño terminó el lunes. Sin esta columna la
-- regla 3 es inimplementable, y la consulta que motivó el proyecto —"cuando
-- duermo mal, ¿al otro día entreno menos?"— lee desfasada un día.
--
-- Se completa para las filas que ya estaban con el día de su entrada, que es
-- correcto para todo lo dictado después de las 4am.
-- ------------------------------------------------------------
alter table extracciones add column if not exists sueno_dia date;

update extracciones x
   set sueno_dia = e.dia
  from entradas e
 where e.id = x.entrada_id and x.sueno_horas is not null and x.sueno_dia is null;

alter table extracciones
  drop constraint if exists sueno_con_dia;
alter table extracciones
  add constraint sueno_con_dia check (sueno_horas is null or sueno_dia is not null);


-- ------------------------------------------------------------
-- DELTA 6 — el camino de escape necesita llegar al servidor.
--
-- El teléfono ya corta la conversación ante una señal de riesgo, pero eso vive
-- sólo en el teléfono: sin esta columna, el job de la mañana arma el plan igual
-- que cualquier otro día. Con el foco psicológico de la app, esto es lo que
-- separa "acompaña" de "te empuja en el peor momento".
--
-- `riesgo` no es nullable: o el modelo lo evaluó y dijo que no, o la fila no
-- debería existir. Y si es true, la evidencia es obligatoria — la misma regla
-- que todo lo demás.
-- ------------------------------------------------------------
alter table extracciones
  add column if not exists riesgo boolean not null default false,
  add column if not exists riesgo_evidencia text;

alter table extracciones drop constraint if exists riesgo_con_evidencia;
alter table extracciones
  add constraint riesgo_con_evidencia
  check (riesgo = false or (riesgo_evidencia is not null and length(btrim(riesgo_evidencia)) > 0));

-- Para que el job del plan pueda preguntar rápido "¿hubo señal hoy?".
create index if not exists extracciones_riesgo_idx on extracciones (riesgo) where riesgo;


-- ------------------------------------------------------------
-- DELTA 7 — no es SQL, es el prompt.
--
-- `entradas.transcripcion` ahora guarda el diálogo completo, con prefijos
-- "Vos:" y "Laya:", porque sin la pregunta muchas respuestas no significan
-- nada ("como a las tres"). La consecuencia es que el system prompt de
-- extracción TIENE que decir explícito que la evidencia se cita sólo de las
-- líneas "Vos:". Sin esa aclaración el modelo puede citar una pregunta de Laya
-- como si la hubieras dicho vos, y la regla 1 se rompe por la puerta de atrás.
--
-- Implementado en api/src/extraccion.ts, no acá.
-- ------------------------------------------------------------

-- ============================================================
-- TERCERA TANDA — lo que F3 necesita.
--
-- F3 son tres momentos: repaso al acostarse (sólo el teléfono), cierre a las
-- 4am, y plan 45 minutos antes de despertarse. Estos deltas son lo que hace
-- falta en la base para sostenerlos.
-- ============================================================


-- ------------------------------------------------------------
-- DELTA 10 — tabla `ajustes`: a qué hora se levanta y a qué hora se acuesta.
--
-- Una sola fila, forzada por `check (id = 1)`: mono-usuario, y una tabla de
-- config que puede tener dos filas es una tabla de config que algún día va a
-- tener dos filas y nadie va a saber cuál gana.
--
-- Columnas tipadas y no jsonb a propósito: son dos horas, tienen tipo `time`,
-- y el tick las compara con `>=`. En jsonb serían dos strings que hay que
-- parsear en cada tick y que aceptan cualquier basura.
--
-- La ZONA no es un capricho. El tick corre en el servidor, y en un VPS el
-- reloj está en UTC. `despierta_a` es hora de pared: sin saber en qué zona,
-- "las 8" no significa nada del lado del servidor. Esto NO contradice la
-- regla 2 —que prohíbe calcular `dia` con AT TIME ZONE— porque ahí el evento
-- lo origina el teléfono y manda su `creado_local`; acá el que actúa es el
-- servidor y no hay ningún reloj de pared que le llegue de afuera.
--
-- La fila arranca con defaults. No es una comodidad: el tick necesita una fila
-- SIEMPRE, y el teléfono puede estar sin señal, sin instalar o sin haber hecho
-- el onboarding todavía. Que el usuario los elija en la app es una capa arriba
-- de esto, no un reemplazo.
-- ------------------------------------------------------------
create table if not exists ajustes (
  id          smallint primary key default 1 check (id = 1),
  despierta_a time not null,
  duerme_a    time not null,
  zona        text not null,
  actualizado timestamptz not null default now()
);

insert into ajustes (id, despierta_a, duerme_a, zona)
values (1, '08:00', '00:00', 'America/Argentina/Buenos_Aires')
on conflict (id) do nothing;


-- ------------------------------------------------------------
-- DELTA 11 — cerrar un día no es definitivo.
--
-- Con la cola offline, una entrada dictada a la 1am sin señal puede aterrizar
-- a las 9 de la mañana, con el día ya cerrado y el resumen escrito. El rollup
-- quedaría viejo y nadie se enteraría.
--
-- Dos columnas, y las dos hacen falta:
--
--   necesita_recalculo  lo marca POST /entradas cuando una entrada cae en un
--                       día que ya está cerrado. Es la señal inmediata.
--
--   entradas_procesadas cuántas entradas del día estaban resueltas (extraída o
--                       en error, o sea NO pendientes) en el último cierre.
--                       Tapa el agujero que la marca de POST no ve: una
--                       entrada que ya estaba cargada pero seguía pendiente
--                       cuando se cerró, y que se extrae recién después. El
--                       POST no puede marcarla —llegó antes del cierre— pero
--                       el conteo cambia y el día queda sucio igual.
--
-- La regla de fondo: el rollup SQL se recalcula sin preguntar porque es gratis
-- y `cerrar_dia()` es idempotente. Las dos llamadas al modelo —resumen y
-- adherencia— sólo se rehacen si el conteo cambió.
-- ------------------------------------------------------------
alter table dias
  add column if not exists necesita_recalculo  boolean not null default false,
  add column if not exists entradas_procesadas integer not null default 0;

-- Los días que ya estaban cerrados no nacen sucios: se los pone al día con lo
-- que hay ahora. Sin esto el primer tick los reprocesaría todos, que son 14
-- llamadas al modelo por nada.
update dias d
   set entradas_procesadas = (select count(*) from entradas e
                               where e.dia = d.dia and e.estado <> 'pendiente')
 where d.cerrado_en is not null and d.entradas_procesadas = 0;

create index if not exists dias_sucios_idx on dias (dia) where necesita_recalculo;


-- ------------------------------------------------------------
-- DELTA 4 — `cerrar_dia` contaba mal, y encima tiraba el delta 3 a la basura.
--
-- Dos fallos distintos en la misma función:
--
-- 1. El `join extracciones` deja afuera las entradas pendientes o en error, así
--    que `n_entradas` da corto. Un día con 2 entradas de las cuales una falló
--    reportaba 1, y el rollup decía que ese día hablaste una sola vez.
--
-- 2. Más grave: el sueño se agrupaba por `entradas.dia`. El delta 3 existe
--    justamente porque el sueño pertenece a la mañana en que TERMINÓ y no al
--    día lógico de la entrada — y acá se descartaba esa columna. O sea que la
--    corrección se perdía exactamente donde importa: `dias.sueno_horas`
--    alimenta `v_ventana_7d`, que alimenta la ficha, que es lo único que ve el
--    modelo. La pregunta que motivó el proyecto —"cuando duermo mal, ¿al otro
--    día entreno menos?"— seguía leyendo desfasada un día.
--
-- Ahora cada agregado se calcula sobre su propia clave: el sueño por
-- `sueno_dia`, el resto por el día lógico de la entrada.
--
-- Un día sin NINGÚN dato no genera fila. No hablar no es un dato del día, y una
-- fila en `dias` con todo en null ensucia los promedios de la ventana.
--
-- Pero "sin datos" no es lo mismo que "sin entradas", y confundirlos rompe la
-- regla 3. Si a la 01:30 del martes contás que dormiste seis horas, esa entrada
-- pertenece al lunes por el corte de las 4am — y si después no volvés a hablar
-- en todo el martes, el martes no tiene entradas propias. Pero SÍ tiene un dato:
-- ese sueño, que terminó esa mañana. Con la condición mirando sólo `entradas`,
-- las seis horas no se guardaban en ninguna parte y `v_ventana_7d` nunca las
-- veía: la corrección del delta 3 se perdía en el único caso para el que existe.
-- ------------------------------------------------------------
create or replace function cerrar_dia(p_dia date) returns void as $$
begin
  if not exists (select 1 from entradas where dia = p_dia)
     and not exists (select 1 from extracciones where sueno_dia = p_dia) then
    return;
  end if;

  insert into dias (dia, cerrado_en, n_entradas, sueno_horas, entreno_min,
                    animo_valencia, animo_energia, entradas_procesadas)
  values (
    p_dia,
    now(),
    (select count(*) from entradas where dia = p_dia),
    -- Agrupado por sueno_dia (delta 3), no por el día de la entrada.
    (select max(x.sueno_horas) from extracciones x where x.sueno_dia = p_dia),
    (select coalesce(sum(x.entreno_min), 0)
       from extracciones x join entradas e on e.id = x.entrada_id
      where e.dia = p_dia),
    (select avg(x.animo_valencia)
       from extracciones x join entradas e on e.id = x.entrada_id
      where e.dia = p_dia),
    (select avg(x.animo_energia)
       from extracciones x join entradas e on e.id = x.entrada_id
      where e.dia = p_dia),
    (select count(*) from entradas where dia = p_dia and estado <> 'pendiente')
  )
  on conflict (dia) do update set
    cerrado_en          = excluded.cerrado_en,
    n_entradas          = excluded.n_entradas,
    sueno_horas         = excluded.sueno_horas,
    entreno_min         = excluded.entreno_min,
    animo_valencia      = excluded.animo_valencia,
    animo_energia       = excluded.animo_energia,
    entradas_procesadas = excluded.entradas_procesadas;
end;
$$ language plpgsql;

-- Días fantasma. El seed usa `current_date - N`, así que al correrlo un día
-- distinto siembra fechas corridas y borra las entradas viejas — pero no las
-- filas de `dias` que había dejado. Quedaron cinco rollups sin ninguna entrada
-- detrás, y `v_ventana_7d` los promedia como si fueran días reales: el modelo
-- vería un sueño que nadie contó nunca.
--
-- Se borra sólo el rollup, que es dato derivado y se reconstruye con
-- `cerrar_dia()`. Las entradas —lo único irreemplazable— no se tocan.
delete from dias d
 where not exists (select 1 from entradas e where e.dia = d.dia)
   and not exists (select 1 from extracciones x where x.sueno_dia = d.dia);

-- Los días que sí tienen datos se recalculan con la función arreglada, para
-- que el sueño quede colgado del día correcto desde ahora.
do $$
declare d date;
begin
  for d in select dia from dias loop
    perform cerrar_dia(d);
  end loop;
end $$;


-- ------------------------------------------------------------
-- DELTA 12 — un plan que no se generó también es un hecho.
--
-- Si hubo señal de riesgo, la regla 6 dice que el sistema NO propone plan y
-- devuelve el mensaje de cuidado. Sin una forma de registrar eso, `planes` no
-- tiene fila para hoy, y el fallback perezoso de GET /plan/hoy volvería a
-- intentar generar el plan en cada request — gastando llamadas para volver a
-- decidir lo mismo.
--
-- Con `tipo` la decisión queda escrita: la fila existe, con su ficha y sin
-- ítems, y nadie la vuelve a calcular.
--
--   'plan'     el plan normal, con 3 a 5 ítems.
--   'cuidado'  hubo riesgo; `nota` lleva el mensaje y no hay ítems.
--   'sin_datos' todavía no hay historial del que sacar nada. Un plan armado
--               sobre una ficha vacía es exactamente el generador de frases
--               motivacionales que la regla 4 existe para evitar.
-- ------------------------------------------------------------
alter table planes
  add column if not exists tipo text not null default 'plan';

alter table planes drop constraint if exists plan_tipo_valido;
alter table planes
  add constraint plan_tipo_valido check (tipo in ('plan', 'cuidado', 'sin_datos'));


-- La regla 1 también rige la adherencia, que es el punto 4 del proyecto.
--
-- `cumplido` tiene TRES estados y eso es deliberado:
--   true   lo cumplió, y hay una frase que lo dice.
--   false  NO lo cumplió, y hay una frase que lo dice ("hoy no fui al gym").
--   null   no habló del tema. Ausencia de dato, NUNCA incumplimiento.
--
-- Los dos primeros son afirmaciones sobre lo que pasó, así que los dos exigen
-- evidencia. Marcar `false` sin que él lo haya dicho es inventar un fracaso y
-- después reprochárselo, que en una app con foco psicológico es el peor error
-- posible.
alter table plan_items drop constraint if exists item_cumplido_con_evidencia;
alter table plan_items
  add constraint item_cumplido_con_evidencia
  check (cumplido is null or (evidencia is not null and length(btrim(evidencia)) > 0));


-- Evaluar la adherencia es una llamada al modelo, y la regla 5 dice que TODO
-- lo que sale a la API se loguea. Sin esa tarea en el CHECK de `llm_llamadas`,
-- el insert rebota y la llamada queda sin registrar.
--
-- El CHECK se declara UNA sola vez, en el delta 13, con la lista completa.
-- Antes lo declaraban tres deltas, cada uno con la lista que necesitaba, y cada
-- lista más corta que la siguiente. Al volver a correr el archivo, el primero se
-- topaba con las filas que los otros habían hecho posibles, reventaba, y con
-- ON_ERROR_STOP se llevaba puesto todo lo que venía después — que fue justo
-- cómo se descubrió: un delta nuevo al final que nunca llegaba a aplicarse.


-- ------------------------------------------------------------
-- DELTA 13 — la charla también es una llamada al modelo.
--
-- Sin esto el insert de `registrar()` rebota por el CHECK, el catch de
-- api/src/llm.ts se lo come con un console.error, y la llamada NO queda
-- registrada. Hoy perder el registro de cuatro llamadas de fondo por día sería
-- feo pero acotado; con la charla —una llamada POR TURNO, y sin tope de turnos
-- porque la conversación la termina la persona— sería la mayor parte del gasto
-- del sistema desapareciendo del libro.
--
-- Y el agujero es invisible: el servidor sigue contestando bien, la charla
-- funciona, y lo único que pasa es que `gastoDelMes()` mira para otro lado. La
-- regla 5 rota en silencio, justo en el único camino sin límite de arriba.
--
-- Va acá Y en el tipo `Tarea` de api/src/llm.ts. Las dos o ninguna.
-- ------------------------------------------------------------
-- La lista va COMPLETA de una. Antes este delta declaraba una lista y un delta
-- posterior la ampliaba, y al volver a correr el archivo este de acá se topaba
-- con las filas que el otro había hecho posibles, reventaba, y con
-- ON_ERROR_STOP se llevaba puesto todo lo que venía después.
alter table llm_llamadas drop constraint if exists llm_llamadas_tarea_check;
alter table llm_llamadas
  add constraint llm_llamadas_tarea_check
  check (tarea in ('extraccion', 'resumen_dia', 'adherencia', 'plan', 'consejo',
                   'charla', 'nota_terapia'));


-- ------------------------------------------------------------
-- DELTA 14 — notas para llevar a terapia.
--
-- QUÉ ES: lo que la persona dijo un día, en SUS palabras, para poder llevarlo a
-- una sesión. "El martes pasó esto y lo contaste así."
--
-- QUÉ NO ES, y esto es lo que decide todo el diseño: NO es una nota clínica. Un
-- texto escrito por un modelo que le llega a un profesional con forma de informe
-- carga una autoridad que no se ganó — si interpreta de más, la sesión arranca
-- desde algo que dijo una máquina sobre alguien a quien no escuchó nunca. Por
-- eso:
--
--   citas     Frases LITERALES suyas, verificadas contra la transcripción antes
--             de guardarse. Es la regla 1 aplicada acá, y con más razón: el
--             destinatario le va a creer.
--   temas     Etiquetas cortas de lo que apareció. Descriptivas, no clínicas.
--   contexto  Dos o tres líneas para ubicar las citas. Sin diagnóstico, sin
--             interpretación, sin "parece haber un patrón de".
--
-- Una nota sin ninguna cita no se guarda: sin las palabras de él, lo único que
-- quedaría es la prosa del modelo, que es exactamente lo que no queremos que
-- alguien lea como si describiera a una persona.
--
-- Una por conversación, porque es la unidad en que se dijo. Agruparlas por día
-- es una consulta, no un dato distinto.
-- ------------------------------------------------------------
create table if not exists notas_terapia (
  id          bigserial primary key,
  entrada_id  bigint not null unique references entradas(id) on delete cascade,
  dia         date   not null,
  creado_en   timestamptz not null default now(),
  modelo      text   not null,
  citas       jsonb  not null,
  temas       text[] not null default '{}',
  contexto    text,

  -- Sin citas no hay nota. Ver arriba: es la razón de ser de la tabla.
  constraint nota_con_citas check (jsonb_typeof(citas) = 'array'
                                   and jsonb_array_length(citas) > 0)
);

create index if not exists notas_terapia_dia_idx on notas_terapia (dia);


-- ------------------------------------------------------------
-- DELTA 15 — el extractor también detecta cuándo pedís un hábito.
--
-- En el teléfono ya hay un detector por frases (`IntencionDeHabito`), que corre
-- al instante, sin red y sin costo. Pero una lista de gatillos tiene falsos
-- negativos por definición: "quiero empezar a caminar" la agarra, y "estaría
-- bueno arrancar a caminar a la mañana" no.
--
-- Esta es la segunda capa, la misma estructura que la señal de riesgo: el
-- teléfono pone el piso y el modelo entiende lo que una lista no. Y como todo
-- lo que sale del modelo, va con su evidencia — si no puede citar la frase, no
-- hay pedido.
-- ------------------------------------------------------------
alter table extracciones add column if not exists habito_pedido text;

alter table extracciones drop constraint if exists ev_habito_pedido;
alter table extracciones
  add constraint ev_habito_pedido
  check (habito_pedido is null or tiene_evidencia(evidencias, 'habito_pedido'));

create index if not exists extracciones_habito_pedido_idx
  on extracciones (habito_pedido) where habito_pedido is not null;

-- ------------------------------------------------------------
-- DELTA 16 — una charla puede pedir más de un hábito.
--
-- `habito_pedido` era UN campo, y de una conversación real del 10/08 salieron
-- tres: meditar a la mañana, correr a la noche y dejar el gimnasio anotado. El
-- extractor podía verlos a los tres y sólo tenía dónde poner uno.
--
-- La regla 1 vale igual para una lista, y por eso cada elemento lleva su propia
-- frase: un array de `{sistema, evidencia}` donde ninguno de los dos puede
-- venir vacío. Sin la frase, el hábito no entra — igual que cualquier otro dato
-- del sistema.
--
-- El CHECK no puede llevar una subconsulta, así que la validación va en una
-- función inmutable.
-- ------------------------------------------------------------
create or replace function habitos_pedidos_validos(p jsonb) returns boolean as $$
  select jsonb_typeof(p) = 'array'
     and coalesce(bool_and(length(btrim(coalesce(e ->> 'sistema', ''))) > 0
                       and length(btrim(coalesce(e ->> 'evidencia', ''))) > 0),
                  true)
    from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p
                                   else '[]'::jsonb end) e
$$ language sql immutable;

alter table extracciones
  add column if not exists habitos_pedidos jsonb not null default '[]'::jsonb;

-- Lo que ya estaba anotado en el campo viejo se muda con su evidencia intacta.
-- Guardado por la existencia de la columna, para que el archivo siga siendo
-- re-corrible: la segunda vez que corra, no hay de dónde mudar.
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_name = 'extracciones' and column_name = 'habito_pedido') then
    update extracciones
       set habitos_pedidos = jsonb_build_array(
             jsonb_build_object('sistema', habito_pedido,
                                'evidencia', evidencias ->> 'habito_pedido'))
     where habito_pedido is not null
       and tiene_evidencia(evidencias, 'habito_pedido')
       and habitos_pedidos = '[]'::jsonb;

    alter table extracciones drop constraint if exists ev_habito_pedido;
    drop index if exists extracciones_habito_pedido_idx;
    alter table extracciones drop column habito_pedido;
  end if;
end $$;

alter table extracciones drop constraint if exists ev_habitos_pedidos;
alter table extracciones
  add constraint ev_habitos_pedidos check (habitos_pedidos_validos(habitos_pedidos));

-- ------------------------------------------------------------
-- DELTA 17 — cómo querés que te llame.
--
-- El nombre estaba escrito a mano adentro del system prompt de Laya, que es lo
-- último que debería tener un dato de la persona: para cambiarlo había que
-- editar código y desplegar.
--
-- Nullable a propósito. Nadie está obligado a dar su nombre para usar una
-- bitácora personal, y sin nombre Laya habla igual — simplemente no te nombra.
-- Un default tipo 'Usuario' sería peor que nada: hace que te hable un formulario.
-- ------------------------------------------------------------
alter table ajustes add column if not exists nombre text;

-- Ni vacío ni un párrafo. Lo segundo importa: esto entra al system prompt, y un
-- "nombre" de dos mil caracteres es el lugar más obvio para meterle
-- instrucciones a Laya por la puerta de atrás.
alter table ajustes drop constraint if exists ajustes_nombre_razonable;
alter table ajustes
  add constraint ajustes_nombre_razonable
  check (nombre is null or (length(btrim(nombre)) between 1 and 40));
