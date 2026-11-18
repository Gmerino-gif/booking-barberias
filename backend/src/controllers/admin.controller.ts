import type { Request, Response } from 'express';
import { Types } from 'mongoose';
import { Booking } from '../models/Booking.js';
import { Establishment } from '../models/Establishment.js';
import { Professional } from '../models/Professional.js';

const getEstablishmentId = (req: Request, res: Response): string | null => {
  const id = typeof req.params.id === 'string' ? req.params.id.trim() : '';
  if (!Types.ObjectId.isValid(id)) {
    res.status(400).json({ message: 'El ID del establecimiento no es válido' });
    return null;
  }
  return id;
};

export const getAdminEstablishments = async (_req: Request, res: Response): Promise<void> => {
  try {
    const establishments = await Establishment.aggregate([
      {
        $lookup: {
          from: Booking.collection.name,
          let: { establishmentId: '$_id' },
          pipeline: [
            { $match: { $expr: { $eq: ['$establishmentId', '$$establishmentId'] } } },
            { $count: 'count' },
          ],
          as: 'bookingCounts',
        },
      },
      {
        $lookup: {
          from: Professional.collection.name,
          let: { establishmentId: '$_id' },
          pipeline: [
            { $match: { $expr: { $eq: ['$establishmentId', '$$establishmentId'] } } },
            { $count: 'count' },
          ],
          as: 'professionalCounts',
        },
      },
      {
        $addFields: {
          bookingsCount: { $ifNull: [{ $arrayElemAt: ['$bookingCounts.count', 0] }, 0] },
          professionalsCount: { $ifNull: [{ $arrayElemAt: ['$professionalCounts.count', 0] }, 0] },
          isActive: { $ifNull: ['$isActive', true] },
          subscriptionStatus: { $ifNull: ['$subscriptionStatus', 'trial'] },
          subscriptionExpiresAt: { $ifNull: ['$subscriptionExpiresAt', null] },
        },
      },
      {
        $project: {
          _id: 1,
          name: 1,
          address: 1,
          phone: 1,
          createdAt: 1,
          isActive: 1,
          subscriptionStatus: 1,
          subscriptionExpiresAt: 1,
          bookingsCount: 1,
          professionalsCount: 1,
        },
      },
    ]);

    res.status(200).json({ establishments });
  } catch {
    res.status(500).json({ message: 'Error al obtener los establecimientos' });
  }
};

export const toggleEstablishment = async (req: Request, res: Response): Promise<void> => {
  const establishmentId = getEstablishmentId(req, res);
  if (!establishmentId) return;

  try {
    const currentEstablishment = await Establishment.findById(establishmentId).lean();
    if (!currentEstablishment) {
      res.status(404).json({ message: 'Establecimiento no encontrado' });
      return;
    }

    const isActive = currentEstablishment.isActive !== false ? false : true;
    const establishment = await Establishment.findByIdAndUpdate(
      establishmentId,
      { $set: { isActive, subscriptionStatus: isActive ? 'active' : 'suspended' } },
      { returnDocument: 'after', runValidators: true },
    );
    if (!establishment) {
      res.status(404).json({ message: 'Establecimiento no encontrado' });
      return;
    }

    res.status(200).json({ establishment });
  } catch {
    res.status(500).json({ message: 'No se pudo actualizar el estado del establecimiento' });
  }
};

export const renewEstablishment = async (req: Request, res: Response): Promise<void> => {
  const establishmentId = getEstablishmentId(req, res);
  if (!establishmentId) return;

  try {
    const currentEstablishment = await Establishment.findById(establishmentId).lean();
    if (!currentEstablishment) {
      res.status(404).json({ message: 'Establecimiento no encontrado' });
      return;
    }

    const now = new Date();
    const currentExpiration = currentEstablishment.subscriptionExpiresAt;
    const baseDate = currentExpiration && currentExpiration > now ? currentExpiration : now;
    const establishment = await Establishment.findByIdAndUpdate(
      establishmentId,
      {
        $set: {
          subscriptionExpiresAt: new Date(baseDate.getTime() + 30 * 24 * 60 * 60 * 1000),
          isActive: true,
          subscriptionStatus: 'active',
        },
      },
      { returnDocument: 'after', runValidators: true },
    );
    if (!establishment) {
      res.status(404).json({ message: 'Establecimiento no encontrado' });
      return;
    }

    res.status(200).json({ establishment });
  } catch {
    res.status(500).json({ message: 'No se pudo renovar la suscripción del establecimiento' });
  }
};
