import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { test } from 'node:test';
import {
  createWompiPaymentLink,
  verifyWompiEventSignature,
} from '../dist/services/wompi.service.js';

const secret = 'test-events-secret';

const createEvent = () => {
  const event = {
    event: 'transaction.updated',
    data: {
      transaction: {
        id: 'tx-123',
        status: 'APPROVED',
        amount_in_cents: 3990000,
      },
    },
    timestamp: 1730000000,
    signature: {
      properties: ['transaction.id', 'transaction.status', 'transaction.amount_in_cents'],
      checksum: '',
    },
  };
  const signedValues = event.signature.properties
    .map((path) => path.split('.').reduce((value, key) => value[key], event.data))
    .join('');
  event.signature.checksum = createHash('sha256')
    .update(`${signedValues}${event.timestamp}${secret}`)
    .digest('hex');
  return event;
};

test('valida la firma Wompi usando properties, timestamp y secreto', () => {
  assert.equal(verifyWompiEventSignature(createEvent(), secret), true);
});

test('rechaza una firma incorrecta y cambios en una propiedad firmada', () => {
  const invalidChecksum = createEvent();
  invalidChecksum.signature.checksum = '0'.repeat(64);
  assert.equal(verifyWompiEventSignature(invalidChecksum, secret), false);

  const changedEvent = createEvent();
  changedEvent.data.transaction.status = 'DECLINED';
  assert.equal(verifyWompiEventSignature(changedEvent, secret), false);
});

const withWompiEnv = async (
  env,
  run,
) => {
  const originalFetch = globalThis.fetch;
  const originalPrivateKey = process.env.WOMPI_PRIVATE_KEY;
  const originalBaseUrl = process.env.WOMPI_BASE_URL;
  if (env.WOMPI_PRIVATE_KEY === undefined) delete process.env.WOMPI_PRIVATE_KEY;
  else process.env.WOMPI_PRIVATE_KEY = env.WOMPI_PRIVATE_KEY;
  if (env.WOMPI_BASE_URL === undefined) delete process.env.WOMPI_BASE_URL;
  else process.env.WOMPI_BASE_URL = env.WOMPI_BASE_URL;
  if (env.fetch) globalThis.fetch = env.fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = originalFetch;
    if (originalPrivateKey === undefined) delete process.env.WOMPI_PRIVATE_KEY;
    else process.env.WOMPI_PRIVATE_KEY = originalPrivateKey;
    if (originalBaseUrl === undefined) delete process.env.WOMPI_BASE_URL;
    else process.env.WOMPI_BASE_URL = originalBaseUrl;
  }
};

test('crea un link de pago con monto COP en centavos y autenticación privada', async () => {
  let capturedUrl;
  let capturedOptions;
  await withWompiEnv(
    {
      WOMPI_PRIVATE_KEY: 'prv_test_private-key',
      // Aunque la variable esté desincronizada, la URL se deriva de la llave.
      WOMPI_BASE_URL: 'https://production.wompi.co/v1',
      fetch: async (url, options) => {
        capturedUrl = url;
        capturedOptions = options;
        return new Response(JSON.stringify({ data: { id: 'link-123' } }), { status: 201 });
      },
    },
    async () => {
      assert.deepEqual(
        await createWompiPaymentLink({ amountCop: 39900, establishmentName: 'Barbería' }),
        { id: 'link-123' },
      );
      assert.equal(capturedUrl, 'https://sandbox.wompi.co/v1/payment_links');
      assert.equal(capturedOptions.headers.Authorization, 'Bearer prv_test_private-key');
      assert.deepEqual(JSON.parse(capturedOptions.body), {
        name: 'Suscripción de Barbería',
        description: 'Suscripción mensual del establecimiento',
        single_use: true,
        collect_shipping: false,
        currency: 'COP',
        amount_in_cents: 3990000,
      });
    },
  );
});

test('usa producción solo cuando la llave privada empieza con prv_prod_', async () => {
  let capturedUrl;
  await withWompiEnv(
    {
      WOMPI_PRIVATE_KEY: '  prv_prod_one  ',
      WOMPI_BASE_URL: 'https://sandbox.wompi.co/v1',
      fetch: async (url) => {
        capturedUrl = url;
        return new Response(JSON.stringify({ data: { id: 'link-456' } }), { status: 201 });
      },
    },
    async () => {
      await createWompiPaymentLink({ amountCop: 39900, establishmentName: 'Barbería' });
      assert.equal(capturedUrl, 'https://production.wompi.co/v1/payment_links');
    },
  );
});

test('rechaza llaves públicas o con prefijo desconocido antes de llamar a Wompi', async () => {
  let fetchCalls = 0;
  const fetch = async () => {
    fetchCalls += 1;
    return new Response('{}', { status: 201 });
  };

  await withWompiEnv({ WOMPI_PRIVATE_KEY: 'pub_test_public-key', fetch }, async () => {
    await assert.rejects(
      createWompiPaymentLink({ amountCop: 39900, establishmentName: 'Barbería' }),
      /llave privada/,
    );
  });

  await withWompiEnv({ WOMPI_PRIVATE_KEY: 'llave-sin-prefijo', fetch }, async () => {
    await assert.rejects(
      createWompiPaymentLink({ amountCop: 39900, establishmentName: 'Barbería' }),
      /prv_test_/,
    );
  });

  assert.equal(fetchCalls, 0);
});

test('registra el cuerpo del error de Wompi cuando la creación del link falla', async () => {
  const wompiErrorBody = {
    error: {
      type: 'AUTHENTICATION_ERROR',
      reason: 'La llave privada no es válida para este ambiente',
    },
  };
  const logged = [];
  const originalConsoleError = console.error;
  console.error = (...args) => logged.push(args);

  try {
    await withWompiEnv(
      {
        WOMPI_PRIVATE_KEY: 'prv_test_invalid-key',
        fetch: async () =>
          new Response(JSON.stringify(wompiErrorBody), { status: 401 }),
      },
      async () => {
        await assert.rejects(
          createWompiPaymentLink({ amountCop: 39900, establishmentName: 'Barbería' }),
          /401/,
        );
      },
    );
  } finally {
    console.error = originalConsoleError;
  }

  assert.equal(logged.length, 1);
  const [message, details] = logged[0];
  assert.match(message, /Wompi rechazó la creación del link/);
  assert.equal(details.status, 401);
  assert.equal(details.url, 'https://sandbox.wompi.co/v1/payment_links');
  assert.equal(details.environment, 'sandbox');
  assert.equal(details.privateKeyPrefix, 'prv_test_***');
  assert.equal(details.privateKeyLength, 'prv_test_invalid-key'.length);
  assert.equal(details.source, 'process-env');
  assert.match(details.hint, /llave privada/);
  assert.deepEqual(details.response, wompiErrorBody.error);
});
