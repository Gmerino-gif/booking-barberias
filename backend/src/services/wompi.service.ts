import { createHash, timingSafeEqual } from 'node:crypto';
import mongoose, { type ClientSession } from 'mongoose';
import { describeEnvSource } from '../config/env-loader.js';
import { Establishment } from '../models/Establishment.js';
import { Payment } from '../models/Payment.js';

const WOMPI_SANDBOX_BASE_URL = 'https://sandbox.wompi.co/v1';
const WOMPI_PRODUCTION_BASE_URL = 'https://production.wompi.co/v1';
const WOMPI_TEST_PRIVATE_KEY_PREFIX = 'prv_test_';
const WOMPI_PRODUCTION_PRIVATE_KEY_PREFIX = 'prv_prod_';
const WOMPI_PUBLIC_KEY_PREFIX = 'pub_';
const SUBSCRIPTION_DURATION_MS = 30 * 24 * 60 * 60 * 1000;

type JsonRecord = Record<string, unknown>;

export class WompiError extends Error {
  constructor(
    message: string,
    readonly statusCode = 502,
  ) {
    super(message);
    this.name = 'WompiError';
  }
}

const isRecord = (value: unknown): value is JsonRecord =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const getSubscriptionPriceCop = (): number => {
  const rawPrice = process.env.SUBSCRIPTION_PRICE_COP?.trim();
  const price = rawPrice ? Number(rawPrice) : 39900;
  if (!Number.isSafeInteger(price) || price < 1) {
    throw new WompiError('SUBSCRIPTION_PRICE_COP debe ser un entero positivo', 503);
  }
  return price;
};

export type WompiEnvironment = 'sandbox' | 'production';

/**
 * La URL base de la API de Wompi se deriva **siempre** del prefijo de la llave
 * privada (`prv_test_` → sandbox, `prv_prod_` → producción) y nunca de una
 * variable de entorno suelta, de modo que no pueda quedar desincronizada con
 * las credenciales y provocar rechazos 401.
 */
export const getWompiBaseUrl = (privateKey: string): string => {
  if (privateKey.startsWith(WOMPI_TEST_PRIVATE_KEY_PREFIX)) {
    return WOMPI_SANDBOX_BASE_URL;
  }
  if (privateKey.startsWith(WOMPI_PRODUCTION_PRIVATE_KEY_PREFIX)) {
    return WOMPI_PRODUCTION_BASE_URL;
  }
  throw new WompiError(
    'WOMPI_PRIVATE_KEY debe iniciar con prv_test_ o prv_prod_',
    503,
  );
};

const readWompiPrivateKey = (): string => {
  const privateKey = process.env.WOMPI_PRIVATE_KEY?.trim();
  if (!privateKey) {
    throw new WompiError('WOMPI_PRIVATE_KEY no está configurada', 503);
  }
  if (privateKey.startsWith(WOMPI_PUBLIC_KEY_PREFIX)) {
    throw new WompiError(
      'WOMPI_PRIVATE_KEY debe contener la llave privada (prv_...) y no la pública (pub_...)',
      503,
    );
  }
  return privateKey;
};

/**
 * `WOMPI_BASE_URL` quedó obsoleto: se conserva solo para avisar en logs si
 * todavía está configurada y no coincide con el entorno de la llave privada.
 */
const warnIfLegacyBaseUrlIsOutOfSync = (expectedBaseUrl: string): void => {
  const configuredUrl = process.env.WOMPI_BASE_URL?.trim().replace(/\/+$/, '');
  if (configuredUrl && configuredUrl !== expectedBaseUrl) {
    console.warn(
      'WOMPI_BASE_URL se ignora: la URL de Wompi se deriva de WOMPI_PRIVATE_KEY',
      { configuredUrl, expectedBaseUrl },
    );
  }
};

const getWompiEnvironment = (privateKey: string): WompiEnvironment =>
  privateKey.startsWith(WOMPI_TEST_PRIVATE_KEY_PREFIX) ? 'sandbox' : 'production';

/** Descripción segura de la llave: nunca incluye el secreto completo. */
const describePrivateKey = (privateKey: string): { privateKeyPrefix: string; privateKeyLength: number } => ({
  privateKeyPrefix: `${privateKey.slice(0, WOMPI_TEST_PRIVATE_KEY_PREFIX.length)}***`,
  privateKeyLength: privateKey.length,
});

/**
 * Deja en el log, al arrancar el servidor, con qué credenciales y contra qué
 * entorno se hablará con Wompi. Sirve para detectar de inmediato una llave
 * vieja o una variable del sistema que esté ganando sobre el `.env`.
 */
export const logWompiConfiguration = (): void => {
  try {
    const privateKey = readWompiPrivateKey();
    console.log('Configuración de Wompi resuelta', {
      environment: getWompiEnvironment(privateKey),
      baseUrl: getWompiBaseUrl(privateKey),
      ...describePrivateKey(privateKey),
      source: describeEnvSource('WOMPI_PRIVATE_KEY'),
      legacyBaseUrlIgnored: process.env.WOMPI_BASE_URL?.trim() || null,
    });
  } catch (error) {
    console.warn('La configuración de Wompi no está lista', {
      message: error instanceof Error ? error.message : String(error),
      source: describeEnvSource('WOMPI_PRIVATE_KEY'),
    });
  }
};

export const createWompiPaymentLink = async (input: {
  amountCop: number;
  establishmentName: string;
}): Promise<{ id: string }> => {
  const privateKey = readWompiPrivateKey();
  const baseUrl = getWompiBaseUrl(privateKey);
  warnIfLegacyBaseUrlIsOutOfSync(baseUrl);
  const amountInCents = input.amountCop * 100;
  if (!Number.isSafeInteger(amountInCents)) {
    throw new WompiError('El monto de la suscripción no es válido', 503);
  }
  const paymentLinksUrl = `${baseUrl}/payment_links`;

  let response: Response;
  try {
    response = await fetch(paymentLinksUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${privateKey.trim()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: `Suscripción de ${input.establishmentName}`.slice(0, 100),
        description: 'Suscripción mensual del establecimiento',
        single_use: true,
        collect_shipping: false,
        currency: 'COP',
        amount_in_cents: amountInCents,
      }),
      signal: AbortSignal.timeout(10000),
    });
  } catch {
    throw new WompiError('No fue posible conectar con Wompi');
  }

  const rawBody = await response.text();
  let responseBody: unknown = null;
  try {
    responseBody = rawBody.length > 0 ? (JSON.parse(rawBody) as unknown) : null;
  } catch {
    responseBody = null;
  }

  if (!response.ok) {
    // Se registra el cuerpo completo del error de Wompi (equivalente a
    // `error.response?.data`) para poder diagnosticar rechazos como el 401.
    console.error('Wompi rechazó la creación del link de pago', {
      status: response.status,
      statusText: response.statusText,
      url: paymentLinksUrl,
      environment: getWompiEnvironment(privateKey),
      ...describePrivateKey(privateKey),
      source: describeEnvSource('WOMPI_PRIVATE_KEY'),
      response: isRecord(responseBody) ? responseBody.error ?? responseBody : rawBody,
      ...(response.status === 401
        ? {
            hint: 'WOMPI_PRIVATE_KEY debe ser la llave privada (prv_...) del mismo comercio y del mismo entorno que la URL. Revisa que no tenga comillas ni espacios, y que ninguna variable de entorno del sistema esté sobrescribiendo el .env.',
          }
        : {}),
    });
    throw new WompiError(`Wompi rechazó la creación del link (${response.status})`);
  }

  if (responseBody === null) {
    throw new WompiError('Wompi devolvió una respuesta inválida');
  }

  const data = isRecord(responseBody) && isRecord(responseBody.data)
    ? responseBody.data
    : null;
  if (!data || typeof data.id !== 'string' || data.id.length === 0) {
    throw new WompiError('Wompi no devolvió el identificador del link de pago');
  }
  return { id: data.id };
};

const getPathValue = (root: unknown, path: string): unknown => {
  let value = root;
  for (const key of path.split('.')) {
    if (!isRecord(value) || !Object.prototype.hasOwnProperty.call(value, key)) {
      return undefined;
    }
    value = value[key];
  }
  return value;
};

const calculateEventChecksum = (body: unknown, secret: string): string | null => {
  if (!isRecord(body) || !isRecord(body.signature) || !Array.isArray(body.signature.properties)) {
    return null;
  }
  if (!Number.isSafeInteger(body.timestamp)) return null;

  const properties = body.signature.properties;
  if (
    properties.length === 0 ||
    properties.length > 100 ||
    !properties.every((property) => typeof property === 'string' && property.length <= 200)
  ) {
    return null;
  }

  let propertyValues = '';
  for (const property of properties as string[]) {
    const value = getPathValue(body.data, property);
    if (value === undefined || (value !== null && !['string', 'number', 'boolean'].includes(typeof value))) {
      return null;
    }
    propertyValues += value === null ? 'null' : String(value);
  }

  return createHash('sha256')
    .update(`${propertyValues}${body.timestamp}${secret}`, 'utf8')
    .digest('hex');
};

export const verifyWompiEventSignature = (
  body: unknown,
  secret: string,
  headerChecksum?: string,
): boolean => {
  const signature = isRecord(body) && isRecord(body.signature) ? body.signature : null;
  const suppliedChecksum = signature?.checksum ?? headerChecksum;
  if (typeof suppliedChecksum !== 'string' || !/^[\da-f]{64}$/i.test(suppliedChecksum)) {
    return false;
  }
  const expectedChecksum = calculateEventChecksum(body, secret);
  if (!expectedChecksum) return false;

  const expected = Buffer.from(expectedChecksum, 'hex');
  const supplied = Buffer.from(suppliedChecksum, 'hex');
  return expected.length === supplied.length && timingSafeEqual(expected, supplied);
};

export const renewEstablishmentSubscription = async (
  establishmentId: string,
  session?: ClientSession,
): Promise<void> => {
  const query = Establishment.findById(establishmentId).select('subscriptionExpiresAt');
  if (session) query.session(session);
  const establishment = await query.lean();
  if (!establishment) throw new Error('No existe el establecimiento asociado al pago');

  const now = new Date();
  const currentExpiration = establishment.subscriptionExpiresAt;
  const baseDate = currentExpiration && currentExpiration > now ? currentExpiration : now;
  const updateQuery = Establishment.updateOne(
    { _id: establishmentId },
    {
      $set: {
        subscriptionExpiresAt: new Date(baseDate.getTime() + SUBSCRIPTION_DURATION_MS),
        isActive: true,
        subscriptionStatus: 'active',
      },
    },
    session ? { session } : {},
  );
  const result = await updateQuery;
  if (result.matchedCount !== 1) {
    throw new Error('No se pudo renovar el establecimiento asociado al pago');
  }
};

export type PaymentApprovalResult =
  | 'approved'
  | 'already_approved'
  | 'not_found'
  | 'not_pending'
  | 'invalid_payment';

export const approveWompiPayment = async (input: {
  paymentLinkId: string;
  transactionId: string;
  amountInCents: number;
  currency: string;
}): Promise<PaymentApprovalResult> => {
  const session = await mongoose.startSession();
  let result: PaymentApprovalResult = 'not_found';
  try {
    await session.withTransaction(async () => {
      result = 'not_found';
      const payment = await Payment.findOne({
        wompiPaymentLinkId: input.paymentLinkId,
        method: 'wompi',
      }).session(session).lean();
      if (!payment) return;
      if (!payment.reference.startsWith('SUB_') || input.currency !== 'COP' ||
          payment.amount * 100 !== input.amountInCents) {
        result = 'invalid_payment';
        return;
      }
      if (payment.status === 'approved') {
        result = 'already_approved';
        return;
      }
      if (payment.status !== 'pending') {
        result = 'not_pending';
        return;
      }

      const updatedPayment = await Payment.findOneAndUpdate(
        { _id: payment._id, status: 'pending' },
        { $set: { status: 'approved', wompiTransactionId: input.transactionId } },
        { returnDocument: 'after', runValidators: true, session },
      );
      if (!updatedPayment) {
        result = 'not_pending';
        return;
      }
      await renewEstablishmentSubscription(String(payment.establishment), session);
      result = 'approved';
    });
    return result;
  } finally {
    await session.endSession();
  }
};

export const approveManualSubscriptionPayment = async (
  paymentId: string,
): Promise<PaymentApprovalResult> => {
  const session = await mongoose.startSession();
  let result: PaymentApprovalResult = 'not_found';
  try {
    await session.withTransaction(async () => {
      result = 'not_found';
      const payment = await Payment.findOne({
        _id: paymentId,
        method: 'manual_transfer',
      }).session(session).lean();
      if (!payment) return;
      if (payment.status === 'approved') {
        result = 'already_approved';
        return;
      }
      if (payment.status !== 'pending') {
        result = 'not_pending';
        return;
      }

      const updatedPayment = await Payment.findOneAndUpdate(
        { _id: payment._id, status: 'pending' },
        { $set: { status: 'approved' } },
        { returnDocument: 'after', runValidators: true, session },
      );
      if (!updatedPayment) {
        result = 'not_pending';
        return;
      }
      await renewEstablishmentSubscription(String(payment.establishment), session);
      result = 'approved';
    });
    return result;
  } finally {
    await session.endSession();
  }
};
