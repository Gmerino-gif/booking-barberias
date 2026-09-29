import type { Response } from 'express';
import { Booking } from '../models/Booking.js';
import { Service } from '../models/Service.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

export const createBooking = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const establishmentId = typeof body?.establishmentId === 'string' ? body.establishmentId : '';
  const professionalId = typeof body?.professionalId === 'string' ? body.professionalId : '';
  const serviceId = typeof body?.serviceId === 'string' ? body.serviceId : '';
  const startAtStr = typeof body?.startAt === 'string' ? body.startAt : '';

  if (!establishmentId || !professionalId || !serviceId || !startAtStr) {
    res.status(400).json({ message: 'Faltan parámetros obligatorios para la reserva' });
    return;
  }

  const startAt = new Date(startAtStr);
  if (isNaN(startAt.getTime()) || startAt < new Date()) {
    res.status(400).json({ message: 'Fecha de inicio inválida' });
    return;
  }

  try {
    const service = await Service.findById(serviceId);
    if (!service) {
      res.status(404).json({ message: 'Servicio no encontrado' });
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

export const getMyBookings = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const bookings = await Booking.find({ clientId: req.user!.id })
      .populate('establishmentId', 'name address')
      .populate('professionalId', 'name')
      .populate('serviceId', 'name durationMin price')
      .sort({ startAt: -1 });

    res.status(200).json({ bookings });
  } catch {
    res.status(500).json({ message: 'Error al obtener tus reservas' });
  }
};