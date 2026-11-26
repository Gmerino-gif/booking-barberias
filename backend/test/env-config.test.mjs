import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { validateRuntimeEnvironment } from '../dist/config/env.js';
import { applyEnvFile, ENV_FILE_PATH } from '../dist/config/env-loader.js';

test('la configuración de desarrollo admite SMTP y CORS opcionales', () => {
  const original = new Map(
    ['NODE_ENV', 'MONGODB_URI', 'JWT_SECRET', 'PORT', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM', 'CORS_ORIGINS']
      .map((key) => [key, process.env[key]]),
  );
  try {
    process.env.NODE_ENV = 'development';
    process.env.MONGODB_URI = 'mongodb://127.0.0.1:27017/booking_app';
    process.env.JWT_SECRET = 'test-secret-at-least-thirty-two-bytes-long';
    process.env.PORT = '3000';
    for (const key of ['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM', 'CORS_ORIGINS']) delete process.env[key];
    assert.doesNotThrow(validateRuntimeEnvironment);
  } finally {
    for (const [key, value] of original) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test('producción exige SMTP y orígenes CORS HTTPS exactos', () => {
  const original = new Map(
    ['NODE_ENV', 'MONGODB_URI', 'JWT_SECRET', 'PORT', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM', 'CORS_ORIGINS']
      .map((key) => [key, process.env[key]]),
  );
  try {
    process.env.NODE_ENV = 'production';
    process.env.MONGODB_URI = 'mongodb+srv://user:pass@example.test/booking_app';
    process.env.JWT_SECRET = 'test-secret-at-least-thirty-two-bytes-long';
    process.env.PORT = '3000';
    process.env.SMTP_HOST = 'smtp.example.test';
    process.env.SMTP_PORT = '465';
    process.env.SMTP_USER = 'smtp-user';
    process.env.SMTP_PASS = 'smtp-password';
    process.env.SMTP_FROM = 'Booking App <no-reply@example.test>';
    process.env.CORS_ORIGINS = 'https://app.example.test';
    assert.doesNotThrow(validateRuntimeEnvironment);

    process.env.CORS_ORIGINS = 'http://app.example.test';
    assert.throws(validateRuntimeEnvironment, /origen HTTPS/);
    process.env.CORS_ORIGINS = 'https://app.example.test/path';
    assert.throws(validateRuntimeEnvironment, /origen HTTPS/);
    process.env.CORS_ORIGINS = 'https://app.example.test';
    delete process.env.SMTP_PASS;
    assert.throws(validateRuntimeEnvironment, /Falta configurar SMTP/);
    process.env.SMTP_PASS = 'smtp-password';
    process.env.JWT_SECRET = 'generate-a-random-secret-with-at-least-32-bytes';
    assert.throws(validateRuntimeEnvironment, /JWT_SECRET debe ser aleatorio/);
  } finally {
    for (const [key, value] of original) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test('el .env se resuelve relativo al backend y no al directorio de trabajo', () => {
  assert.equal(ENV_FILE_PATH, fileURLToPath(new URL('../.env', import.meta.url)));
});

test('fuera de producción el .env sobrescribe un valor viejo del proceso', () => {
  const env = { NODE_ENV: 'development', NODE_PORT: '3000', WOMPI_PRIVATE_KEY: 'prv_test_vieja' };
  const outcome = applyEnvFile({
    path: '/app/backend/.env',
    env,
    readFile: () => 'WOMPI_PRIVATE_KEY=prv_test_nueva\n',
  });

  assert.equal(outcome.loaded, true);
  assert.equal(env.WOMPI_PRIVATE_KEY, 'prv_test_nueva');
  assert.deepEqual(outcome.applied, ['WOMPI_PRIVATE_KEY']);
  assert.deepEqual(outcome.conflicts, [{ key: 'WOMPI_PRIVATE_KEY', winner: 'file' }]);
});

test('en producción las variables del proceso tienen prioridad sobre el .env', () => {
  const env = { NODE_ENV: 'production', WOMPI_PRIVATE_KEY: 'prv_prod_real' };
  const outcome = applyEnvFile({
    path: '/app/backend/.env',
    env,
    readFile: () => 'WOMPI_PRIVATE_KEY=prv_test_vieja\n',
  });

  assert.equal(env.WOMPI_PRIVATE_KEY, 'prv_prod_real');
  assert.deepEqual(outcome.applied, []);
  assert.deepEqual(outcome.conflicts, [{ key: 'WOMPI_PRIVATE_KEY', winner: 'process' }]);
});

test('no falla cuando el .env no existe en la ruta resuelta', () => {
  const outcome = applyEnvFile({
    path: '/ruta/inexistente/.env',
    env: { NODE_ENV: 'development' },
    readFile: () => {
      throw new Error('ENOENT');
    },
  });

  assert.equal(outcome.loaded, false);
  assert.deepEqual(outcome.applied, []);
  assert.deepEqual(outcome.conflicts, []);
});
