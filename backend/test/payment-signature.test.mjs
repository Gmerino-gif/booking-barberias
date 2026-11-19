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

test('crea un link de pago con monto COP en centavos y autenticación privada', async () => {
  const originalFetch = globalThis.fetch;
  const originalPrivateKey = process.env.WOMPI_PRIVATE_KEY;
  const originalBaseUrl = process.env.WOMPI_BASE_URL;
  let capturedUrl;
  let capturedOptions;
  process.env.WOMPI_PRIVATE_KEY = 'private-test-key';
  process.env.WOMPI_BASE_URL = 'https://sandbox.wompi.co/v1';
  globalThis.fetch = async (url, options) => {
    capturedUrl = url;
    capturedOptions = options;
    return new Response(JSON.stringify({ data: { id: 'link-123' } }), { status: 201 });
  };
  try {
    assert.deepEqual(
      await createWompiPaymentLink({ amountCop: 39900, establishmentName: 'Barbería' }),
      { id: 'link-123' },
    );
    assert.equal(capturedUrl, 'https://sandbox.wompi.co/v1/payment_links');
    assert.equal(capturedOptions.headers.Authorization, 'Bearer private-test-key');
    assert.deepEqual(JSON.parse(capturedOptions.body), {
      name: 'Suscripción de Barbería',
      description: 'Suscripción mensual del establecimiento',
      single_use: true,
      collect_shipping: false,
      currency: 'COP',
      amount_in_cents: 3990000,
    });
  } finally {
    globalThis.fetch = originalFetch;
    if (originalPrivateKey === undefined) delete process.env.WOMPI_PRIVATE_KEY;
    else process.env.WOMPI_PRIVATE_KEY = originalPrivateKey;
    if (originalBaseUrl === undefined) delete process.env.WOMPI_BASE_URL;
    else process.env.WOMPI_BASE_URL = originalBaseUrl;
  }
});
