import assert from 'node:assert/strict';
import { test } from 'node:test';
import { validateRuntimeEnvironment } from '../dist/config/env.js';

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
