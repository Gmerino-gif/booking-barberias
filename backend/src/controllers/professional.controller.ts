import type { Request, Response } from 'express';
import { Booking } from '../models/Booking.js';
import { Establishment } from '../models/Establishment.js';
import { Professional } from '../models/Professional.js';
import { Service } from '../models/Service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

const getOwnedEstablishment = (ownerId: string) => Establishment.findOne({ ownerId });

const validateServiceIds = async (serviceIds: unknown, establishmentId: string): Promise<string[] | null> => {
  if (!Array.isArray(serviceIds) || serviceIds.some((id) => typeof id !== 'string')) return null;
  const ids = [...new Set(serviceIds as string[])];
  if (ids.some((id) => !/^[a-f\d]{24}$/i.test(id))) return null;
  if (ids.length === 0) return ids;
  const services = await Service.find({ _id: { $in: ids }, establishmentId }).select('_id');
  return services.length === ids.length ? ids : null;
};

export const getByEstablishment = async (req: Request, res: Response): Promise<void> => {
  const establishmentId = typeof req.params.establishmentId === 'string' ? req.params.establishmentId : '';
  if (!establishmentId) {
    res.status(400).json({ message: 'El ID del establecimiento es requerido' });
    return;
  }
  try {
    const professionals = await Professional.find({ establishmentId }).populate('services');
    res.status(200).json({ professionals });
  } catch {
    res.status(500).json({ message: 'Error al obtener los profesionales' });
  }
};

export const getMyProfessionals = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const establishment = await getOwnedEstablishment(req.user!.id);
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }
    const professionals = await Professional.find({ establishmentId: establishment._id }).populate('services');
    res.status(200).json({ professionals, establishmentId: establishment._id.toString() });
  } catch {
    res.status(500).json({ message: 'Error al obtener los profesionales' });
  }
};

export const createProfessional = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const specialty = typeof body?.specialty === 'string' ? body.specialty.trim() : '';
  if (name.length < 2 || name.length > 80 || specialty.length > 100) {
    res.status(400).json({ message: 'Nombre o especialidad inválidos' });
    return;
  }
  try {
    const establishment = await getOwnedEstablishment(req.user!.id);
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }
    const services = await validateServiceIds(body?.services ?? [], establishment._id.toString());
    if (services === null) {
      res.status(400).json({ message: 'Uno o más servicios no pertenecen a tu establecimiento' });
      return;
    }
    const professional = await Professional.create({ establishmentId: establishment._id, name, specialty, services });
    res.status(201).json({ message: 'Profesional registrado', professional });
  } catch {
    res.status(500).json({ message: 'Error al registrar el profesional' });
  }
};

export const updateProfessional = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  try {
    const establishment = await getOwnedEstablishment(req.user!.id);
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }
    const professional = await Professional.findOne({ _id: req.params.id, establishmentId: establishment._id });
    if (!professional) {
      res.status(404).json({ message: 'Profesional no encontrado' });
      return;
    }

    if (body?.name !== undefined) {
      if (typeof body.name !== 'string' || body.name.trim().length < 2 || body.name.trim().length > 80) {
        res.status(400).json({ message: 'El nombre del profesional no es válido' });
        return;
      }
      professional.name = body.name.trim();
    }
    if (body?.specialty !== undefined) {
      if (typeof body.specialty !== 'string' || body.specialty.trim().length > 100) {
        res.status(400).json({ message: 'La especialidad no es válida' });
        return;
      }
      professional.specialty = body.specialty.trim();
    }
    if (body?.services !== undefined) {
      const services = await validateServiceIds(body.services, establishment._id.toString());
      if (services === null) {
        res.status(400).json({ message: 'Uno o más servicios no pertenecen a tu establecimiento' });
        return;
      }
      professional.set('services', services);
    }
    await professional.save();
    res.status(200).json({ message: 'Profesional actualizado', professional });
  } catch {
    res.status(500).json({ message: 'Error al actualizar el profesional' });
  }
};

export const deleteProfessional = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const establishment = await getOwnedEstablishment(req.user!.id);
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }
    const professional = await Professional.findOne({ _id: req.params.id, establishmentId: establishment._id });
    if (!professional) {
      res.status(404).json({ message: 'Profesional no encontrado' });
      return;
    }
    const hasUpcomingBookings = await Booking.exists({
      professionalId: professional._id,
      startAt: { $gt: new Date() },
      status: { $in: ['pending', 'confirmed'] },
    });
    if (hasUpcomingBookings) {
      res.status(409).json({ message: 'No puedes eliminar un profesional con citas pendientes o confirmadas' });
      return;
    }
    await professional.deleteOne();
    res.status(200).json({ message: 'Profesional eliminado' });
  } catch {
    res.status(500).json({ message: 'Error al eliminar el profesional' });
  }
};
