import type { Request, Response } from 'express';
import { Establishment } from '../models/Establishment.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

export const getEstablishments = async (req: Request, res: Response): Promise<void> => {
  try {
    const establishments = await Establishment.find().limit(50);
    res.status(200).json({ establishments });
  } catch {
    res.status(500).json({ message: 'Error al obtener los establecimientos' });
  }
};

export const getNearby = async (req: Request, res: Response): Promise<void> => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  const radius = Number(req.query.radius) || 5000; // metros por defecto: 5km

  if (isNaN(lat) || isNaN(lng)) {
    res.status(400).json({ message: 'Coordenadas latitud y longitud son requeridas' });
    return;
  }

  try {
    const establishments = await Establishment.find({
      location: {
        $near: {
          $geometry: { type: 'Point', coordinates: [lng, lat] },
          $maxDistance: radius,
        },
      },
    });

    res.status(200).json({ establishments });
  } catch {
    res.status(500).json({ message: 'Error en la búsqueda geográfica' });
  }
};

export const createEstablishment = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const address = typeof body?.address === 'string' ? body.address.trim() : '';
  const city = typeof body?.city === 'string' ? body.city.trim() : '';
  const lat = Number(body?.lat);
  const lng = Number(body?.lng);

  if (name.length < 2 || !address || !city || isNaN(lat) || isNaN(lng)) {
    res.status(400).json({ message: 'Datos de establecimiento incompletos o inválidos' });
    return;
  }

  try {
    const establishment = await Establishment.create({
      ownerId: req.user!.id,
      name,
      address,
      city,
      description: typeof body?.description === 'string' ? body.description.trim() : '',
      phone: typeof body?.phone === 'string' ? body.phone.trim() : '',
      location: { type: 'Point', coordinates: [lng, lat] },
    });

    res.status(201).json({ message: 'Establecimiento creado exitosamente', establishment });
  } catch {
    res.status(500).json({ message: 'Error al crear el establecimiento' });
  }
};