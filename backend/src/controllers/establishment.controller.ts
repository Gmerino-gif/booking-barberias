import type { Request, Response } from 'express';
import { Establishment } from '../models/Establishment.js';
import { isValidPhoneNumber } from '../utils/phone.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

const serializeEstablishment = (establishment: Record<string, any>) => {
  const coordinates = Array.isArray(establishment.location?.coordinates)
    ? establishment.location.coordinates
    : [];
  const [lng, lat] = coordinates;

  return {
    id: establishment._id?.toString?.() ?? establishment.id,
    ownerId: establishment.ownerId?.toString?.() ?? establishment.ownerId,
    name: establishment.name,
    address: establishment.address,
    city: establishment.city,
    description: establishment.description ?? '',
    phone: establishment.phone,
    rating: establishment.rating ?? 0,
    openingMinutes: establishment.openingMinutes ?? 540,
    closingMinutes: establishment.closingMinutes ?? 1080,
    plan: establishment.plan ?? 'free',
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
    createdAt: establishment.createdAt,
    updatedAt: establishment.updatedAt,
  };
};

const parseLocation = (body: Record<string, unknown> | null) => {
  const lat = Number(body?.lat);
  const lng = Number(body?.lng);
  return { lat, lng };
};

const validateEstablishmentInput = (
  name: string,
  address: string,
  city: string,
  description: string,
  phone: string,
  lat: number,
  lng: number,
): boolean => {
  return (
    name.length >= 2 &&
    name.length <= 100 &&
    address.length > 0 &&
    address.length <= 200 &&
    city.length > 0 &&
    city.length <= 100 &&
    description.length <= 1000 &&
    isValidPhoneNumber(phone) &&
    Number.isFinite(lat) &&
    lat >= -90 &&
    lat <= 90 &&
    Number.isFinite(lng) &&
    lng >= -180 &&
    lng <= 180
  );
};

export const getEstablishments = async (req: Request, res: Response): Promise<void> => {
  try {
    const query = typeof req.query.q === 'string' ? req.query.q.trim() : '';
    const filter = query ? {
      $or: [
        { name: { $regex: query, $options: 'i' } },
        { city: { $regex: query, $options: 'i' } },
        { address: { $regex: query, $options: 'i' } },
      ],
    } : {};
    const establishments = await Establishment.find(filter).limit(50);
    res.status(200).json({ establishments });
  } catch {
    res.status(500).json({ message: 'Error al obtener los establecimientos' });
  }
};

export const getEstablishmentById = async (req: Request, res: Response): Promise<void> => {
  const establishmentId = typeof req.params.id === 'string' ? req.params.id.trim() : '';

  if (!establishmentId) {
    res.status(400).json({ message: 'El ID del establecimiento es requerido' });
    return;
  }

  try {
    const establishment = await Establishment.findById(establishmentId);
    if (!establishment) {
      res.status(404).json({ message: 'Establecimiento no encontrado' });
      return;
    }

    res.status(200).json({ establishment: serializeEstablishment(establishment.toObject()) });
  } catch {
    res.status(500).json({ message: 'Error al obtener el establecimiento' });
  }
};

export const getMyEstablishment = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const establishment = await Establishment.findOne({ ownerId: req.user!.id });
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }

    res.status(200).json({ establishment: serializeEstablishment(establishment.toObject()) });
  } catch {
    res.status(500).json({ message: 'Error al obtener tu establecimiento' });
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
  const description = typeof body?.description === 'string' ? body.description.trim() : '';
  const phone = typeof body?.phone === 'string' ? body.phone.trim() : '';
  const { lat, lng } = parseLocation(body);

  if (!validateEstablishmentInput(name, address, city, description, phone, lat, lng)) {
    res.status(400).json({ message: 'Datos de establecimiento incompletos o inválidos' });
    return;
  }

  try {
    const existingEstablishment = await Establishment.findOne({ ownerId: req.user!.id });
    if (existingEstablishment) {
      res.status(200).json({
        message: 'El establecimiento ya estaba registrado',
        establishment: serializeEstablishment(existingEstablishment.toObject()),
      });
      return;
    }

    const establishment = await Establishment.create({
      ownerId: req.user!.id,
      name,
      address,
      city,
      description,
      phone,
      location: { type: 'Point', coordinates: [lng, lat] },
    });

    res.status(201).json({ message: 'Establecimiento creado exitosamente', establishment });
  } catch {
    res.status(500).json({ message: 'Error al crear el establecimiento' });
  }
};

export const updateMyEstablishment = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const establishment = await Establishment.findOne({ ownerId: req.user!.id });

  if (!establishment) {
    res.status(404).json({ message: 'No tienes un establecimiento registrado' });
    return;
  }

  const name = typeof body?.name === 'string' ? body.name.trim() : establishment.name;
  const address = typeof body?.address === 'string' ? body.address.trim() : establishment.address;
  const city = typeof body?.city === 'string' ? body.city.trim() : establishment.city;
  const description = typeof body?.description === 'string' ? body.description.trim() : establishment.description ?? '';
  const phone = typeof body?.phone === 'string' ? body.phone.trim() : establishment.phone;
  const currentCoords = establishment.location?.coordinates ?? [0, 0];
  const lat = Number.isFinite(Number(body?.lat)) ? Number(body?.lat) : Number(currentCoords[1]);
  const lng = Number.isFinite(Number(body?.lng)) ? Number(body?.lng) : Number(currentCoords[0]);
  const openingMinutes = body?.openingMinutes === undefined ? establishment.openingMinutes ?? 540 : Number(body.openingMinutes);
  const closingMinutes = body?.closingMinutes === undefined ? establishment.closingMinutes ?? 1080 : Number(body.closingMinutes);

  if (!validateEstablishmentInput(name, address, city, description, phone, lat, lng) ||
      !Number.isInteger(openingMinutes) || !Number.isInteger(closingMinutes) ||
      openingMinutes < 0 || closingMinutes > 1440 || closingMinutes - openingMinutes < 30) {
    res.status(400).json({ message: 'Datos de establecimiento incompletos o inválidos' });
    return;
  }

  try {
    const updated = await Establishment.findOneAndUpdate(
      { _id: establishment._id },
      {
        $set: {
          name,
          address,
          city,
          description,
          phone,
          location: { type: 'Point', coordinates: [lng, lat] },
          openingMinutes,
          closingMinutes,
        },
      },
      { returnDocument: 'after', runValidators: true },
    );

    if (!updated) {
      res.status(404).json({ message: 'No se pudo actualizar el establecimiento' });
      return;
    }

    res.status(200).json({
      message: 'Establecimiento actualizado exitosamente',
      establishment: serializeEstablishment(updated.toObject()),
    });
  } catch {
    res.status(500).json({ message: 'Error al actualizar el establecimiento' });
  }
};
