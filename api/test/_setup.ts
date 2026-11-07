/// Va PRIMERO en cada archivo de test, antes de cualquier otro import.
///
/// Apunta la base a `bitacora_test`. Hasta septiembre los tests corrían contra
/// la base real: insertaban y limpiaban, y el tick de prueba, con el reloj
/// falso en 2027, cerraba de verdad todos los días del diario. Si cortabas la
/// corrida a la mitad, quedaban cerrados. Nunca más.
///
/// `dotenv` no pisa una variable que ya está seteada, así que esto le gana al
/// .env aunque config.ts lo cargue después.
process.env.DATABASE_URL = process.env.DATABASE_URL_TEST ?? 'postgres://localhost:5432/bitacora_test'

// Lo que hace falta para que config.ts no reviente. Ninguno se usa de verdad:
// las llamadas al modelo van siempre por un stub.
process.env.PRECIO_IN_USD_POR_MTOK ??= '0.40'
process.env.PRECIO_OUT_USD_POR_MTOK ??= '1.60'
process.env.OPENAI_MODEL ??= 'modelo-de-prueba'
process.env.OPENAI_API_KEY ??= 'sk-de-prueba'
process.env.BUDGET_USD_MES ??= '5'
process.env.MAX_LLAMADAS_MES ??= '1000'

// La memoria larga, apagada: con la clave del .env a la vista, el tick de
// prueba salía a internet a vectorizar resúmenes inventados y los pagaba. Los
// tests de `recuerdos` inyectan sus propias llamadas y no la necesitan.
process.env.DEEPINFRA_API_KEY = ''
process.env.LLM_BASE_URL = 'https://api.openai.com/v1'

// Y la voz, fija en un proveedor: de eso cuelgan el modelo, las voces y el
// precio, y no pueden depender de qué diga el .env del día.
process.env.VOZ_BASE_URL = 'https://api.openai.com/v1'
process.env.VOZ_MUJER = ''
process.env.MODELO_DE_VOZ = ''
process.env.MODELO_DE_VOZ_MUJER = ''
process.env.PRECIO_VOZ_USD_POR_MCHAR = ''

// El resumen de cada charla al subirla sale a un modelo: en los tests, no.
process.env.RESUMIR_CHARLAS = 'no'
