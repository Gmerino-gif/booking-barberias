import type { Request, Response } from 'express';
import { Service } from '../models/Service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

export const getByEstablishment = async (req: Request, res: Response): Promise<void> => {
  const establishmentId = typeof req.params.establishmentId === 'string' ? req.params.establishmentId : '';

  if (!establishmentId) {
    res.status(400).json({ message: 'El ID del establecimiento es requerido' });
    return;
  }

  try {
    const services = await Service.find({ establishmentId });
    res.status(200).json({ services });
  } catch {
    res.status(500).json({ message: 'Error al obtener los servicios' });
  }
};

export const createService = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const establishmentId = typeof body?.establishmentId === 'string' ? body.establishmentId : '';
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const durationMin = Number(body?.durationMin);
  const price = Number(body?.price);

  if (!establishmentId || name.length < 2 || isNaN(durationMin) || isNaN(price)) {
    res.status(400).json({ message: 'Faltan datos obligatorios para el servicio' });
    return;
  }

  try {
    const service = await Service.create({
      establishmentId,
      name,
      durationMin,
      price,
      description: typeof body?.description === 'string' ? body.description.trim() : '',
      category: typeof body?.category === 'string' ? body.category.trim() : '',
    });

    res.status(201).json({ message: 'Servicio creado exitosamente', service });
  } catch {
    res.status(500).json({ message: 'Error al crear servicio' });
  }
};