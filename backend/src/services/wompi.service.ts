import { createHash, timingSafeEqual } from 'node:crypto';
import mongoose, { type ClientSession } from 'mongoose';
import { Establishment } from '../models/Establishment.js';
import { Payment } from '../models/Payment.js';

const DEFAULT_SANDBOX_URL = 'https://sandbox.wompi.co/v1';
const DEFAULT_PRODUCTION_URL = 'https://production.wompi.co/v1';
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

const getWompiBaseUrl = (): string => {
  const configuredUrl = process.env.WOMPI_BASE_URL?.trim();
  const baseUrl = configuredUrl || (
    process.env.NODE_ENV === 'production' ? DEFAULT_PRODUCTION_URL : DEFAULT_SANDBOX_URL
  );
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(baseUrl);
  } catch {
    throw new WompiError('WOMPI_BASE_URL no contiene una URL válida', 503);
  }
  if (parsedUrl.protocol !== 'https:') {
    throw new WompiError('WOMPI_BASE_URL debe usar HTTPS', 503);
  }
  return baseUrl.replace(/\/+$/, '');
};

export const createWompiPaymentLink = async (input: {
  amountCop: number;
  establishmentName: string;
}): Promise<{ id: string }> => {
  const privateKey = process.env.WOMPI_PRIVATE_KEY?.trim();
  if (!privateKey) {
    throw new WompiError('WOMPI_PRIVATE_KEY no está configurada', 503);
  }
  const amountInCents = input.amountCop * 100;
  if (!Number.isSafeInteger(amountInCents)) {
    throw new WompiError('El monto de la suscripción no es válido', 503);
  }
  const paymentLinksUrl = `${getWompiBaseUrl()}/payment_links`;

  let response: Response;
  try {
    response = await fetch(paymentLinksUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${privateKey}`,
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

  let responseBody: unknown;
  try {
    responseBody = JSON.parse(await response.text()) as unknown;
  } catch {
    throw new WompiError('Wompi devolvió una respuesta inválida');
  }
  if (!response.ok) {
    throw new WompiError(`Wompi rechazó la creación del link (${response.status})`);
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
