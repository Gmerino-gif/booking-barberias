import type { Request, Response } from 'express';
import { Booking } from '../models/Booking.js';
import { Establishment } from '../models/Establishment.js';
import { Professional } from '../models/Professional.js';
import { Service } from '../models/Service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

const getOwnedEstablishment = (ownerId: string) => Establishment.findOne({ ownerId });

const parseServiceInput = (body: Record<string, unknown> | null) => {
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const description = typeof body?.description === 'string' ? body.description.trim() : '';
  const category = typeof body?.category === 'string' ? body.category.trim() : '';
  const rawPrice = body?.price;
  const rawDuration = body?.durationMin ?? body?.durationInMinutes ?? body?.duration;
  const price = typeof rawPrice === 'number' || (typeof rawPrice === 'string' && rawPrice.trim() !== '')
    ? Number(rawPrice)
    : Number.NaN;
  const durationMin = typeof rawDuration === 'number' || (typeof rawDuration === 'string' && rawDuration.trim() !== '')
    ? Number(rawDuration)
    : Number.NaN;
  if (name.length < 2 || name.length > 100 || description.length > 500 ||
      category.length > 100 || !Number.isFinite(price) || price < 0 ||
      !Number.isInteger(durationMin) || durationMin < 5 || durationMin > 480) return null;
  return { name, description, category, price, durationMin };
};

export const getServices = async (req: Request, res: Response): Promise<void> => {
  const establishmentId = typeof req.query.establishmentId === 'string' ? req.query.establishmentId.trim() : '';
  try {
    const filter = establishmentId ? { establishmentId } : {};
    const services = await Service.find(filter).limit(50);
    res.status(200).json({ services });
  } catch {
    res.status(500).json({ message: 'Error al obtener los servicios' });
  }
};

export const getServiceById = async (req: Request, res: Response): Promise<void> => {
  try {
    const service = await Service.findById(req.params.id);
    if (!service) {
      res.status(404).json({ message: 'Servicio no encontrado' });
      return;
    }
    res.status(200).json({ service });
  } catch {
    res.status(400).json({ message: 'ID de servicio no válido' });
  }
};

export const createService = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const input = parseServiceInput(req.body as Record<string, unknown> | null);
  if (!input) {
    res.status(400).json({ message: 'Nombre, precio o duración del servicio no válidos' });
    return;
  }
  try {
    const establishment = await getOwnedEstablishment(req.user!.id);
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }
    const service = await Service.create({ ...input, establishmentId: establishment._id });
    res.status(201).json({ message: 'Servicio creado exitosamente', service });
  } catch {
    res.status(500).json({ message: 'Error al crear el servicio' });
  }
};

export const updateService = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const input = parseServiceInput(req.body as Record<string, unknown> | null);
  if (!input) {
    res.status(400).json({ message: 'Nombre, precio o duración del servicio no válidos' });
    return;
  }
  try {
    const establishment = await getOwnedEstablishment(req.user!.id);
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }
    const service = await Service.findOneAndUpdate(
      { _id: req.params.id, establishmentId: establishment._id },
      { $set: input },
      { returnDocument: 'after', runValidators: true },
    );
    if (!service) {
      res.status(404).json({ message: 'Servicio no encontrado en tu establecimiento' });
      return;
    }
    res.status(200).json({ message: 'Servicio actualizado exitosamente', service });
  } catch {
    res.status(400).json({ message: 'No se pudo actualizar el servicio' });
  }
};

export const deleteService = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const establishment = await getOwnedEstablishment(req.user!.id);
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }
    const service = await Service.findOne({ _id: req.params.id, establishmentId: establishment._id });
    if (!service) {
      res.status(404).json({ message: 'Servicio no encontrado en tu establecimiento' });
      return;
    }
    if (await Booking.exists({ serviceId: service._id })) {
      res.status(409).json({ message: 'No puedes eliminar un servicio asociado a reservas; puedes editarlo o dejar de ofrecerlo' });
      return;
    }
    await Professional.updateMany({ services: service._id }, { $pull: { services: service._id } });
    await service.deleteOne();
    res.status(200).json({ message: 'Servicio eliminado' });
  } catch {
    res.status(400).json({ message: 'No se pudo eliminar el servicio' });
  }
};
