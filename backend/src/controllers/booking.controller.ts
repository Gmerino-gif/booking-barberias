import type { Response } from 'express';
import { Booking } from '../models/Booking.js';
import { Establishment } from '../models/Establishment.js';
import { Service } from '../models/Service.js';
import { Professional } from '../models/Professional.js';
import { getAvailableSlots } from '../services/availability.service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

export const createBooking = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const establishmentId = typeof body?.establishmentId === 'string' ? body.establishmentId : '';
  const professionalId = typeof body?.professionalId === 'string' ? body.professionalId : '';
  const serviceId = typeof body?.serviceId === 'string' ? body.serviceId : '';
  const startAtStr = typeof body?.startAt === 'string' ? body.startAt : '';
  const utcOffsetMinutes = Number(body?.utcOffsetMinutes);

  if (!establishmentId || !professionalId || !serviceId || !startAtStr || !Number.isInteger(utcOffsetMinutes) || Math.abs(utcOffsetMinutes) > 14 * 60) {
    res.status(400).json({ message: 'Faltan parámetros obligatorios para la reserva' });
    return;
  }

  const startAt = new Date(startAtStr);
  if (isNaN(startAt.getTime()) || startAt < new Date()) {
    res.status(400).json({ message: 'Fecha de inicio inválida' });
    return;
  }

  try {
    const [service, professional] = await Promise.all([
      Service.findOne({ _id: serviceId, establishmentId }),
      Professional.findOne({ _id: professionalId, establishmentId }),
    ]);
    if (!service) {
      res.status(404).json({ message: 'Servicio no encontrado' });
      return;
    }
    if (!professional || (professional.services.length > 0 && !professional.services.some((id) => id.toString() === serviceId))) {
      res.status(400).json({ message: 'El profesional no ofrece este servicio en el establecimiento' });
      return;
    }

    const localStartAt = new Date(startAt.getTime() + utcOffsetMinutes * 60_000);
    const date = `${localStartAt.getUTCFullYear().toString().padStart(4, '0')}-${(localStartAt.getUTCMonth() + 1).toString().padStart(2, '0')}-${localStartAt.getUTCDate().toString().padStart(2, '0')}`;
    const availableSlots = await getAvailableSlots({ establishmentId, professionalId, serviceId, date, utcOffsetMinutes });
    if (!availableSlots.includes(startAt.toISOString())) {
      res.status(409).json({ message: 'El horario seleccionado ya no está disponible' });
      return;
    }

    // Calcular hora de finalización basada en la duración del servicio
    const endAt = new Date(startAt.getTime() + service.durationMin * 60 * 1000);

    // Verificación anticolisión: comprobación de traslape de horarios
    const hasConflict = await Booking.exists({
      professionalId,
      status: { $ne: 'cancelled' },
      startAt: { $lt: endAt },
      endAt: { $gt: startAt },
    });

    if (hasConflict) {
      res.status(409).json({ message: 'El profesional seleccionado ya no tiene disponibilidad en ese horario' });
      return;
    }

    const booking = await Booking.create({
      clientId: req.user!.id,
      establishmentId,
      professionalId,
      serviceId,
      startAt,
      endAt,
      price: service.price,
      notes: typeof body?.notes === 'string' ? body.notes.trim() : '',
    });

    res.status(201).json({ message: 'Reserva creada exitosamente', booking });
  } catch {
    res.status(500).json({ message: 'Error interno al procesar la reserva' });
  }
};

export const getAvailability = async (req: import('express').Request, res: Response): Promise<void> => {
  const establishmentId = typeof req.query.establishmentId === 'string' ? req.query.establishmentId : '';
  const professionalId = typeof req.query.professionalId === 'string' ? req.query.professionalId : '';
  const serviceId = typeof req.query.serviceId === 'string' ? req.query.serviceId : '';
  const date = typeof req.query.date === 'string' ? req.query.date : '';
  const utcOffsetMinutes = Number(req.query.utcOffsetMinutes);

  if (!establishmentId || !professionalId || !serviceId || !/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isInteger(utcOffsetMinutes) || Math.abs(utcOffsetMinutes) > 14 * 60) {
    res.status(400).json({ message: 'Establecimiento, servicio, profesional, fecha y zona horaria son requeridos' });
    return;
  }

  try {
    const slots = await getAvailableSlots({ establishmentId, professionalId, serviceId, date, utcOffsetMinutes });
    res.status(200).json({ slots });
  } catch {
    res.status(500).json({ message: 'No se pudo consultar la disponibilidad' });
  }
};

export const updateBookingStatus = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const bookingId = typeof req.params.id === 'string' ? req.params.id : '';
  const nextStatus = typeof req.body?.status === 'string' ? req.body.status : '';
  const allowedStatuses = ['confirmed', 'completed', 'cancelled', 'no_show'];

  if (!bookingId || !allowedStatuses.includes(nextStatus)) {
    res.status(400).json({ message: 'La reserva y el estado solicitado son requeridos' });
    return;
  }

  try {
    const booking = await Booking.findById(bookingId);
    if (!booking) {
      res.status(404).json({ message: 'Reserva no encontrada' });
      return;
    }

    if (req.user!.role === 'client') {
      if (booking.clientId.toString() !== req.user!.id || nextStatus !== 'cancelled' || booking.startAt <= new Date() || !['pending', 'confirmed'].includes(booking.status)) {
        res.status(403).json({ message: 'No puedes cambiar el estado de esta reserva' });
        return;
      }
    } else if (req.user!.role === 'owner') {
      const establishment = await Establishment.findOne({ ownerId: req.user!.id });
      if (!establishment || booking.establishmentId.toString() !== establishment._id.toString()) {
        res.status(403).json({ message: 'No puedes cambiar reservas de otro establecimiento' });
        return;
      }
      const transitions: Record<string, string[]> = {
        pending: ['confirmed', 'cancelled'],
        confirmed: ['completed', 'cancelled', 'no_show'],
      };
      if (!transitions[booking.status]?.includes(nextStatus)) {
        res.status(400).json({ message: 'La transición de estado no es válida' });
        return;
      }
      if ((nextStatus === 'completed' || nextStatus === 'no_show') && booking.endAt > new Date()) {
        res.status(400).json({ message: 'La cita aún no ha terminado' });
        return;
      }
      if (nextStatus === 'cancelled' && booking.startAt <= new Date()) {
        res.status(400).json({ message: 'No se puede cancelar una cita que ya comenzó' });
        return;
      }
    } else if (req.user!.role !== 'admin') {
      res.status(403).json({ message: 'No tienes permiso para cambiar esta reserva' });
      return;
    }

    booking.status = nextStatus as typeof booking.status;
    await booking.save();
    res.status(200).json({ message: 'Reserva actualizada', booking: serializeBooking(booking) });
  } catch {
    res.status(500).json({ message: 'No se pudo actualizar la reserva' });
  }
};

const serializeBooking = (booking: any) => ({
  id: booking._id?.toString?.() ?? booking.id,
  clientId: booking.clientId?._id?.toString?.() ?? booking.clientId ?? null,
  establishmentId: booking.establishmentId?._id?.toString?.() ?? booking.establishmentId ?? null,
  professionalId: booking.professionalId?._id?.toString?.() ?? booking.professionalId ?? null,
  serviceId: booking.serviceId?._id?.toString?.() ?? booking.serviceId ?? null,
  establishmentName: booking.establishmentId?.name ?? null,
  clientName: booking.clientId?.name ?? null,
  professionalName: booking.professionalId?.name ?? null,
  serviceName: booking.serviceId?.name ?? null,
  durationMin: booking.serviceId?.durationMin ?? booking.durationMin ?? null,
  price: booking.price ?? booking.serviceId?.price ?? null,
  status: booking.status,
  startAt: booking.startAt,
  endAt: booking.endAt,
  notes: booking.notes ?? '',
});

export const getMyBookings = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const bookings = await Booking.find({ clientId: req.user!.id })
      .populate('establishmentId', 'name address phone')
      .populate('clientId', 'name phone')
      .populate('professionalId', 'name')
      .populate('serviceId', 'name durationMin price')
      .sort({ startAt: -1 });

    res.status(200).json({ bookings: bookings.map((booking) => serializeBooking(booking.toObject())) });
  } catch {
    res.status(500).json({ message: 'Error al obtener tus reservas' });
  }
};

export const getBusinessBookings = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const establishment = await Establishment.findOne({ ownerId: req.user!.id });
    if (!establishment) {
      res.status(404).json({ message: 'No tienes un establecimiento registrado' });
      return;
    }

    const bookings = await Booking.find({ establishmentId: establishment._id })
      .populate('establishmentId', 'name address phone')
      .populate('clientId', 'name phone')
      .populate('professionalId', 'name')
      .populate('serviceId', 'name durationMin price')
      .sort({ startAt: -1 });

    res.status(200).json({ bookings: bookings.map((booking) => serializeBooking(booking.toObject())) });
  } catch {
    res.status(500).json({ message: 'Error al obtener las reservas del negocio' });
  }
};
