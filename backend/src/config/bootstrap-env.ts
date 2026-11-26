/**
 * Módulo de efecto secundario: carga el `.env` **al evaluarse**.
 *
 * En ESM todos los `import` se evalúan antes del cuerpo del módulo que los
 * declara, así que llamar a `loadEnvironment()` dentro de `server.ts` habría
 * ocurrido después de evaluar `./app.js` y su grafo de dependencias. Al vivir
 * la carga en un módulo propio e importarlo primero, el entorno queda listo
 * antes que cualquier otro módulo del backend.
 *
 * Solo `server.ts` debe importar este archivo; los tests importan
 * `env-loader.js` directamente para no tocar `process.env`.
 */
import { loadEnvironment } from './env-loader.js';

loadEnvironment();
