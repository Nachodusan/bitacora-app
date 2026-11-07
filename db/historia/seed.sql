-- ============================================================
-- SEED — ~10 días falsos, para poder probar sin esperar dos semanas.
--
-- Idempotente: borra lo que sembró antes (por client_uuid) y vuelve a poner.
-- No toca entradas reales, que no tienen el prefijo de siembra.
--
-- Cada valor no-null de las extracciones lleva su evidencia, que es la frase
-- literal de la transcripción. Si faltara, los CHECK de la regla 1 rebotarían
-- el insert — es a propósito que el seed también tenga que cumplirla.
-- ============================================================

begin;

delete from entradas
where client_uuid in (select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
                      from generate_series(1, 40) n);

with guion(n, atras, hora, texto, sueno, sueno_ev, entreno, entreno_ev, valencia, valencia_ev) as (values
  (1,  9, '09:10', 'Dormí siete horas y media, me levanté bien. Después fui al gimnasio, una hora de pesas.',
       7.5, 'Dormí siete horas y media', 60, 'una hora de pesas', 1, 'me levanté bien'),
  (2,  8, '08:40', 'Dormí como seis horas, me levanté hecho percha. No llegué a entrenar.',
       6.0, 'Dormí como seis horas', 0, 'No llegué a entrenar', -1, 'me levanté hecho percha'),
  (3,  8, '22:15', 'Tomé tres cafés después del mediodía y ahora no me duermo.',
       null, null, null, null, -1, 'ahora no me duermo'),
  (4,  7, '09:00', 'Ocho horas redondas, dormí de una. Muy bien.',
       8.0, 'Ocho horas redondas', null, null, 2, 'Muy bien'),
  (5,  7, '19:30', 'Corrí media hora tranquilo.',
       null, null, 30, 'Corrí media hora', 1, 'tranquilo'),
  (6,  6, '09:20', 'No pude dormir en toda la noche, estuve con el celular hasta cualquier hora.',
       4.0, 'No pude dormir en toda la noche', null, null, -2, 'No pude dormir en toda la noche'),
  (7,  5, '10:00', 'Discusión con mi hermana, quedé de mal humor todo el día.',
       null, null, null, null, -2, 'quedé de mal humor todo el día'),
  (8,  4, '09:05', 'Dormí siete horas. Entrené cuarenta minutos.',
       7.0, 'Dormí siete horas', 40, 'Entrené cuarenta minutos', 1, 'Entrené cuarenta minutos'),
  (9,  3, '09:30', 'Dormí mal otra vez, unas cinco horas. Día raro, mucha pantalla y poca calle.',
       5.0, 'unas cinco horas', 0, 'poca calle', -1, 'Día raro'),
  (10, 2, '09:15', 'Dormí ocho horas y entrené una hora. Buen día.',
       8.0, 'Dormí ocho horas', 60, 'entrené una hora', 2, 'Buen día'),
  (11, 1, '09:00', 'Siete horas y media. Fui a nadar cuarenta y cinco minutos.',
       7.5, 'Siete horas y media', 45, 'nadar cuarenta y cinco minutos', 1, 'Fui a nadar')
)
insert into entradas (client_uuid, creado_en, creado_local, fuente, transcripcion,
                      duracion_seg, estado)
select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
       now() - (atras || ' days')::interval,
       (current_date - atras) + hora::time,
       'dictado_ios',
       texto,
       round(length(texto) / 14.0, 1),
       'extraida'
from guion;

-- Extracciones: se enganchan por transcripción, que es única en el seed.
with guion(texto, sueno, sueno_ev, entreno, entreno_ev, valencia, valencia_ev) as (values
  ('Dormí siete horas y media, me levanté bien. Después fui al gimnasio, una hora de pesas.',
   7.5, 'Dormí siete horas y media', 60, 'una hora de pesas', 1, 'me levanté bien'),
  ('Dormí como seis horas, me levanté hecho percha. No llegué a entrenar.',
   6.0, 'Dormí como seis horas', 0, 'No llegué a entrenar', -1, 'me levanté hecho percha'),
  ('Tomé tres cafés después del mediodía y ahora no me duermo.',
   null, null, null, null, -1, 'ahora no me duermo'),
  ('Ocho horas redondas, dormí de una. Muy bien.',
   8.0, 'Ocho horas redondas', null, null, 2, 'Muy bien'),
  ('Corrí media hora tranquilo.',
   null, null, 30, 'Corrí media hora', 1, 'tranquilo'),
  ('No pude dormir en toda la noche, estuve con el celular hasta cualquier hora.',
   4.0, 'No pude dormir en toda la noche', null, null, -2, 'No pude dormir en toda la noche'),
  ('Discusión con mi hermana, quedé de mal humor todo el día.',
   null, null, null, null, -2, 'quedé de mal humor todo el día'),
  ('Dormí siete horas. Entrené cuarenta minutos.',
   7.0, 'Dormí siete horas', 40, 'Entrené cuarenta minutos', 1, 'Entrené cuarenta minutos'),
  ('Dormí mal otra vez, unas cinco horas. Día raro, mucha pantalla y poca calle.',
   5.0, 'unas cinco horas', 0, 'poca calle', -1, 'Día raro'),
  ('Dormí ocho horas y entrené una hora. Buen día.',
   8.0, 'Dormí ocho horas', 60, 'entrené una hora', 2, 'Buen día'),
  ('Siete horas y media. Fui a nadar cuarenta y cinco minutos.',
   7.5, 'Siete horas y media', 45, 'nadar cuarenta y cinco minutos', 1, 'Fui a nadar')
)
insert into extracciones (entrada_id, modelo, sueno_horas, entreno_min, entreno_hubo,
                          animo_valencia, evidencias, crudo)
select e.id,
       'seed',
       g.sueno,
       g.entreno,
       case when g.entreno is null then null else g.entreno > 0 end,
       g.valencia,
       -- Sólo las claves de los valores no-null: un CHECK rebota lo contrario.
       (case when g.sueno is null then '{}'::jsonb
             else jsonb_build_object('sueno_horas', g.sueno_ev) end
        -- entreno_hubo se deriva de los minutos, pero igual necesita SU propia
        -- evidencia: el CHECK mira cada columna por separado, y con razón.
        || case when g.entreno is null then '{}'::jsonb
                else jsonb_build_object('entreno_min', g.entreno_ev,
                                        'entreno_hubo', g.entreno_ev) end
        || case when g.valencia is null then '{}'::jsonb
                else jsonb_build_object('animo_valencia', g.valencia_ev) end),
       jsonb_build_object('seed', true)
from guion g
join entradas e on e.transcripcion = g.texto;

-- Unos eventos sueltos, para que las etiquetas negativas tengan de dónde salir.
insert into eventos (entrada_id, dia, tipo, etiqueta, valor_num, unidad, polaridad, evidencia)
select e.id, e.dia, v.tipo, v.etiqueta, v.valor, v.unidad, v.polaridad, v.evidencia
from (values
  ('Tomé tres cafés después del mediodía y ahora no me duermo.',
   'sustancia', 'cafe', 3, 'tazas', -1, 'Tomé tres cafés después del mediodía'),
  ('No pude dormir en toda la noche, estuve con el celular hasta cualquier hora.',
   'pantalla', 'scroll_nocturno', null, null, -1, 'estuve con el celular hasta cualquier hora'),
  ('Discusión con mi hermana, quedé de mal humor todo el día.',
   'social', 'discusion', null, null, -1, 'Discusión con mi hermana'),
  ('Dormí mal otra vez, unas cinco horas. Día raro, mucha pantalla y poca calle.',
   'pantalla', 'mucha_pantalla', null, null, -1, 'mucha pantalla y poca calle')
) as v(texto, tipo, etiqueta, valor, unidad, polaridad, evidencia)
join entradas e on e.transcripcion = v.texto;

-- El delete de arriba se lleva las entradas de la siembra anterior, pero no
-- sus filas en `dias`. Como las fechas son relativas a `current_date`, correr
-- el seed otro día deja rollups colgados de fechas sin ninguna entrada detrás,
-- y `v_ventana_7d` los promedia igual. Se limpian acá: es dato derivado.
delete from dias d
 where not exists (select 1 from entradas e where e.dia = d.dia)
   and not exists (select 1 from extracciones x where x.sueno_dia = d.dia);

-- Cerrar todos los días que quedaron con datos.
do $$
declare d date;
begin
  for d in select distinct dia from entradas order by dia loop
    perform cerrar_dia(d);
  end loop;
end $$;

commit;
