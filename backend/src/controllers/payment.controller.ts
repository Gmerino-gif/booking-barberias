import { randomBytes } from 'node:crypto';
import type { Request, Response } from 'express';
import { Establishment } from '../models/Establishment.js';
import { Payment } from '../models/Payment.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';
import {
  approveWompiPayment,
  createWompiPaymentLink,
  getSubscriptionPriceCop,
  verifyWompiEventSignature,
  WompiError,
} from '../services/wompi.service.js';
import {
  removeStoredImage,
  storeImageBuffer,
  UploadError,
} from '../utils/uploads.js';

type JsonRecord = Record<string, unknown>;

const isRecord = (value: unknown): value is JsonRecord =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const createSubscriptionReference = (establishmentId: string): string =>
  `SUB_${establishmentId}_${Date.now()}_${randomBytes(4).toString('hex')}`;

export const createWompiLink = async (
  req: AuthenticatedRequest,
  res: Response,
): Promise<void> => {
  try {
    const establishment = await Establishment.findOne({ ownerId: req.user!.id }).select('_id name');
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }

    const amount = getSubscriptionPriceCop();
    const reference = createSubscriptionReference(establishment._id.toString());
    const payment = await Payment.create({
      establishment: establishment._id,
      amount,
      method: 'wompi',
      status: 'pending',
      reference,
    });
    const paymentLink = await createWompiPaymentLink({
      amountCop: amount,
      establishmentName: establishment.name,
    });
    const updatedPayment = await Payment.findByIdAndUpdate(
      payment._id,
      { $set: { wompiPaymentLinkId: paymentLink.id } },
      { returnDocument: 'after', runValidators: true },
    );
    if (!updatedPayment) {
      throw new Error('No se pudo asociar el link de Wompi con el pago');
    }

    res.status(201).json({
      checkoutUrl: `https://checkout.wompi.co/l/${encodeURIComponent(paymentLink.id)}`,
      reference,
    });
  } catch (error) {
    if (error instanceof WompiError) {
      console.error('Error al crear el link de pago en Wompi', error.message);
      res.status(error.statusCode).json({ message: error.message });
      return;
    }
    console.error('Error al crear el link de suscripción', error);
    res.status(500).json({ message: 'No se pudo crear el link de pago' });
  }
};

export const createManualReceipt = async (
  req: AuthenticatedRequest,
  res: Response,
): Promise<void> => {
  const file = req.file;
  if (!file) {
    res.status(400).json({ message: 'Adjunta una imagen en el campo receipt' });
    return;
  }

  const body = isRecord(req.body) ? req.body : {};
  const notes = typeof body.notes === 'string' ? body.notes.trim() : '';
  if (notes.length > 1000) {
    res.status(400).json({ message: 'La nota no puede superar 1000 caracteres' });
    return;
  }

  let receiptUrl: string | null = null;
  try {
    const establishment = await Establishment.findOne({ ownerId: req.user!.id }).select('_id');
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }

    const amount = getSubscriptionPriceCop();
    const reference = createSubscriptionReference(establishment._id.toString());
    receiptUrl = await storeImageBuffer(file.buffer);
    try {
      const payment = await Payment.create({
        establishment: establishment._id,
        amount,
        method: 'manual_transfer',
        status: 'pending',
        reference,
        receiptUrl,
        ...(notes ? { notes } : {}),
      });
      res.status(201).json({ payment });
    } catch (error) {
      await removeStoredImage(receiptUrl);
      throw error;
    }
  } catch (error) {
    if (error instanceof UploadError) {
      res.status(error.status).json({ message: error.message });
      return;
    }
    if (error instanceof WompiError) {
      res.status(error.statusCode).json({ message: error.message });
      return;
    }
    console.error('Error al registrar el comprobante de pago', error);
    res.status(500).json({ message: 'No se pudo registrar el comprobante de pago' });
  }
};

export const getMyPaymentHistory = async (
  req: AuthenticatedRequest,
  res: Response,
): Promise<void> => {
  try {
    const establishment = await Establishment.findOne({ ownerId: req.user!.id }).select(
      '_id name isActive subscriptionStatus subscriptionExpiresAt',
    );
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }

    const priceCop = getSubscriptionPriceCop();
    const payments = await Payment.find({ establishment: establishment._id }).sort({ createdAt: -1 });

    res.status(200).json({
      establishment: {
        id: establishment._id.toString(),
        name: establishment.name,
        isActive: establishment.isActive,
        subscriptionStatus: establishment.subscriptionStatus,
        subscriptionExpiresAt: establishment.subscriptionExpiresAt,
        priceCop,
      },
      payments,
    });
  } catch (error) {
    if (error instanceof WompiError) {
      res.status(error.statusCode).json({ message: error.message });
      return;
    }
    console.error('Error al obtener el historial de pagos', error);
    res.status(500).json({ message: 'No se pudo obtener el historial de pagos' });
  }
};

export const handleWompiWebhook = async (req: Request, res: Response): Promise<void> => {
  try {
    const eventsSecret = process.env.WOMPI_EVENTS_SECRET?.trim();
    if (!eventsSecret) {
      console.error('WOMPI_EVENTS_SECRET no está configurada; se ignora el webhook');
      res.sendStatus(200);
      return;
    }
    if (!verifyWompiEventSignature(req.body, eventsSecret, req.get('x-event-checksum'))) {
      console.warn('Se recibió un webhook de Wompi con firma inválida');
      res.sendStatus(200);
      return;
    }

    const body = isRecord(req.body) ? req.body : {};
    const data = isRecord(body.data) ? body.data : {};
    const transaction = isRecord(data.transaction) ? data.transaction : {};
    if (body.event !== 'transaction.updated' || transaction.status !== 'APPROVED') {
      res.sendStatus(200);
      return;
    }

    const paymentLinkId = transaction.payment_link_id;
    const transactionId = transaction.id;
    const amountInCents = transaction.amount_in_cents;
    const currency = transaction.currency;
    if (
      typeof paymentLinkId !== 'string' ||
      typeof transactionId !== 'string' ||
      typeof amountInCents !== 'number' ||
      !Number.isSafeInteger(amountInCents) ||
      typeof currency !== 'string'
    ) {
      console.warn('El evento aprobado de Wompi no contiene los datos de pago requeridos');
      res.sendStatus(200);
      return;
    }

    const result = await approveWompiPayment({
      paymentLinkId,
      transactionId,
      amountInCents,
      currency,
    });
    if (result === 'invalid_payment') {
      console.error('El evento aprobado de Wompi no coincide con los datos del pago pendiente');
    } else if (result === 'not_found') {
      console.warn('No se encontró un pago asociado al link de Wompi recibido');
    }
  } catch (error) {
    console.error('No se pudo procesar el webhook de Wompi', error);
  }
  res.sendStatus(200);
};
