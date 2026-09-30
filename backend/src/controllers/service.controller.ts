import type { Request, Response } from 'express';
import { Service } from '../models/Service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

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
  const serviceId = typeof req.params.id === 'string' ? req.params.id.trim() : '';

  if (!serviceId) {
    res.status(400).json({ message: 'El ID del servicio es requerido' });
    return;
  }

  try {
    const service = await Service.findById(serviceId);

    if (!service) {
      res.status(404).json({ message: 'Servicio no encontrado' });
      return;
    }

    res.status(200).json({ service });
  } catch {
    res.status(500).json({ message: 'Error al obtener el servicio' });
  }
};

export const createService = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const establishmentId = typeof body?.establishmentId === 'string' ? body.establishmentId.trim() : '';
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const price = Number(body?.price);
  const durationMin = Number(body?.durationMin ?? body?.durationInMinutes ?? body?.duration);

  if (!establishmentId || name.length < 2 || isNaN(price) || price < 0 || isNaN(durationMin) || durationMin <= 0) {
    res.status(400).json({ message: 'Datos de servicio incompletos o inválidos' });
    return;
  }

  try {
    const service = await Service.create({
      establishmentId,
      name,
      description: typeof body?.description === 'string' ? body.description.trim() : '',
      price,
      durationMin,
    });

    res.status(201).json({
      message: 'Servicio creado exitosamente',
      service,
    });
  } catch {
    res.status(500).json({ message: 'Error al crear el servicio' });
  }
};

export const updateService = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const serviceId = typeof req.params.id === 'string' ? req.params.id.trim() : '';

  if (!serviceId) {
    res.status(400).json({ message: 'El ID del servicio es requerido' });
    return;
  }

  try {
    const service = await Service.findByIdAndUpdate(serviceId, req.body, { new: true });

    if (!service) {
      res.status(404).json({ message: 'Servicio no encontrado' });
      return;
    }

    res.status(200).json({
      message: 'Servicio actualizado exitosamente',
      service,
    });
  } catch {
    res.status(500).json({ message: 'Error al actualizar el servicio' });
  }
};

export const deleteService = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const serviceId = typeof req.params.id === 'string' ? req.params.id.trim() : '';

  if (!serviceId) {
    res.status(400).json({ message: 'El ID del servicio es requerido' });
    return;
  }

  try {
    const service = await Service.findByIdAndDelete(serviceId);

    if (!service) {
      res.status(404).json({ message: 'Servicio no encontrado' });
      return;
    }

    res.status(200).json({
      message: 'Servicio eliminado exitosamente',
    });
  } catch {
    res.status(500).json({ message: 'Error al eliminar el servicio' });
  }
};