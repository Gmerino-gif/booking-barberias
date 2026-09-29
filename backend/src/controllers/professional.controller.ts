import type { Request, Response } from 'express';
import { Professional } from '../models/Professional.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

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

export const createProfessional = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const establishmentId = typeof body?.establishmentId === 'string' ? body.establishmentId : '';
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const specialty = typeof body?.specialty === 'string' ? body.specialty.trim() : '';
  const services = Array.isArray(body?.services) ? body!.services : [];

  if (!establishmentId || name.length < 2) {
    res.status(400).json({ message: 'Nombre y ID de establecimiento son requeridos' });
    return;
  }

  try {
    const professional = await Professional.create({ establishmentId, name, specialty, services });
    res.status(201).json({ message: 'Profesional registrado', professional });
  } catch {
    res.status(500).json({ message: 'Error al registrar profesional' });
  }
};