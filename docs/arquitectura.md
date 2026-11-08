# Arquitectura

Bitácora tiene tres piezas: la app del teléfono (iOS y Android), un servidor en Node
y una base Postgres. El teléfono transcribe la voz y guarda las conversaciones; el
servidor habla con el modelo, recuerda y escribe lo que la persona se lleva a terapia.

```
 Teléfono                         Servidor (api/)                 Proveedor
┌──────────────────┐   HTTPS    ┌─────────────────────────┐     ┌──────────────┐
│ dictado on-device│──────────▶ │ corte de riesgo         │     │ LLM (charla) │
│ chat / llamada   │ ◀──stream──│ techo de gasto          │────▶│ LLM (fondo)  │
│ calendario       │            │ memoria (pgvector)      │     │ embeddings   │
│ outbox offline   │            │ latido cada 10 min      │     │ reranker     │
└──────────────────┘            └──────────┬──────────────┘     │ TTS          │
                                           │                    └──────────────┘
                                     PostgreSQL + pgvector
```

## Teléfono

**iOS** (`ios/Bitacora`). Tres pestañas: calendario, chat y *Mi expediente*.

- *Chat:* `ConversacionView` tiene tres estados (portal, conversación, llamada).
  `Conversacion.swift` es la máquina de estados y la única que decide qué pasa con cada
  turno. `CapturaDeVoz` dicta en el teléfono con cancelación de eco, `VozDeBitacora` y
  `Altavoz` reproducen la voz en vivo, y `SenalDeVoz` dibuja la luz que sigue la voz.
- *Calendario:* `CalendarioView`, con las conversaciones y notas de cada día lógico.
- *Mi expediente:* las sesiones de terapia (`AnotarSesionView`, `SesionView`), el
  resumen del mes (`NotasView`) y las consultas (`Agenda`, `ConsultasView`).
- `Estilo.swift` concentra la paleta y las tipografías.

**Core** (`ios/BitacoraCore`). Foundation puro y testeable: el día lógico, el cliente
del servidor, el corte de riesgo, el fin de turno y el lector del streaming.

**Android** (`android/`). Kotlin y Jetpack Compose, con la misma estructura:
`nucleo/` (lógica pura con tests), `datos/` (almacén local y outbox), `ui/` y `voz/`.

Las conversaciones terminadas pasan por un **outbox**: si no hay red, quedan en el
teléfono y se suben cuando vuelve.

## Servidor

Node 22, TypeScript, Fastify y `pg` sin ORM.

| Ruta | Qué hace |
|---|---|
| `POST /charla/vivo` | El turno de Bitácora en streaming: texto y voz mientras se generan |
| `POST /charla` | El turno entero, de una vez (respaldo) |
| `POST /voz` | El audio de un texto |
| `POST /entradas` | Guarda una conversación terminada |
| `GET/PUT /ajustes` | Nombre y zona horaria |
| `GET /notas` | Las frases para llevar a terapia |
| `GET/POST /eventos`, `PATCH/DELETE /eventos/:id` | Consultas y eventos del calendario |

**Orden de cada turno:** primero el corte de riesgo (`riesgo.ts`; si dispara, no se
llama al modelo y vuelve un mensaje fijo con `cuidado: true`), después el techo de
gasto, y recién ahí el modelo.

**Techo de gasto.** `BUDGET_USD_MES` en dólares y `MAX_LLAMADAS_MES` en llamadas; el
segundo existe porque con un tier gratuito el precio es 0 y el primero nunca cortaría.
La voz tiene su propia fracción del presupuesto (`FRACCION_VOZ`): cuando se agota, el
teléfono pasa a la voz del sistema y la charla sigue.

**El latido** (`latido.ts`, `tick.ts`). Cada 10 minutos, dentro del mismo proceso:
resume los días que terminaron, escribe las notas de terapia, propone las consultas
mencionadas en la charla, prepara los borradores de evaluación e indexa los resúmenes.

**Memoria.** Bitácora recibe los resúmenes de los últimos 7 días. Además, cada resumen
se guarda como vector; en cada turno Postgres trae los veinte más parecidos a lo último
que dijo la persona y el reranker deja hasta cinco. Tiene timeout corto: si falla, el
turno sale sin eso.

**Proveedores.** Todo pasa por una API compatible con OpenAI, así que cambiar de
proveedor es cambiar `LLM_BASE_URL`, el modelo y los precios en `.env`. Un mes típico
de uso escrito cuesta unos USD 0,19 por persona; la voz es lo caro (unos 5 centavos por
minuto de lo que habla Bitácora).

## Base

`db/schema.sql` se aplica entero sobre una base vacía; `db/deltas.sql` se corre sobre
una existente y se puede repetir. Necesita la extensión `pgvector`. Varias reglas del
dominio (por ejemplo, que cada dato extraído tenga su frase textual como evidencia)
están impuestas con `CHECK` en la base, no sólo en el código.

`db/historia/` guarda el esquema de una versión anterior (hábitos, plan del día,
gráficos de progreso) que se sacó para volver a una base más simple.

## Tests

- Servidor: `cd api && npm test` (contra `bitacora_test`).
- iOS: los tests de `BitacoraCore` en Xcode.
- Android: `./gradlew test` (`NucleoTest`).

`api/scripts/simular-mes.ts` genera un mes de conversaciones de una persona ficticia
para probar resúmenes, memoria y costos sin datos reales.
