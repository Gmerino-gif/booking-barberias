import type { Request, Response } from 'express';
import { Types } from 'mongoose';
import { MAX_REVIEW_TAGS, Review } from '../models/Review.js';
import { Establishment } from '../models/Establishment.js';
import { Professional } from '../models/Professional.js';
import { Booking } from '../models/Booking.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

const isObjectId = (value: string): boolean => /^[a-f\d]{24}$/i.test(value);

/** Valor ausente (`null`), válido (1-5) o inválido (`undefined`). */
const parseOptionalRating = (value: unknown): number | null | undefined => {
  if (value === undefined || value === null || value === '') return null;
  const rating = Number(value);
  return Number.isInteger(rating) && rating >= 1 && rating <= 5 ? rating : undefined;
};

/** Etiquetas normalizadas o `null` si la entrada no es válida. */
const parseTags = (value: unknown): string[] | null => {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) return null;
  const tags = [...new Set(
    value
      .filter((tag): tag is string => typeof tag === 'string')
      .map((tag) => tag.trim())
      .filter((tag) => tag.length > 0),
  )];
  if (tags.some((tag) => tag.length > 40)) return null;
  return tags.slice(0, MAX_REVIEW_TAGS);
};

const isDuplicateKeyError = (error: unknown): boolean =>
  typeof error === 'object' && error !== null && (error as { code?: number }).code === 11000;

/** Recalcula el promedio de estrellas del establecimiento. */
const recalculateEstablishmentRating = async (establishmentId: string | Types.ObjectId): Promise<void> => {
  const [summary] = await Review.aggregate([
    { $match: { establishmentId: new Types.ObjectId(establishmentId), rating: { $type: 'number' } } },
    { $group: { _id: '$establishmentId', rating: { $avg: '$rating' } } },
  ]);
  await Establishment.findByIdAndUpdate(establishmentId, { rating: summary?.rating ?? 0 });
};

/** Recalcula el promedio de estrellas del profesional/barbero. */
const recalculateProfessionalRating = async (professionalId: string | Types.ObjectId): Promise<void> => {
  const [summary] = await Review.aggregate([
    { $match: { professionalId: new Types.ObjectId(professionalId), ratingProfessional: { $type: 'number' } } },
    { $group: { _id: '$professionalId', rating: { $avg: '$ratingProfessional' }, count: { $sum: 1 } } },
  ]);
  await Professional.findByIdAndUpdate(professionalId, {
    rating: summary?.rating ?? 0,
    reviewCount: summary?.count ?? 0,
  });
};

export const getEstablishmentReviews = async (req: Request, res: Response): Promise<void> => {
  const establishmentId = typeof req.params.establishmentId === 'string' ? req.params.establishmentId.trim() : '';

  if (!establishmentId) {
    res.status(400).json({ message: 'El ID del establecimiento es requerido' });
    return;
  }

  try {
    const reviews = await Review.find({ establishmentId })
      .populate('userId', 'name')
      .populate('professionalId', 'name photo')
      .sort({ createdAt: -1 })
      .limit(50);
    res.status(200).json({ reviews });
  } catch {
    res.status(500).json({ message: 'Error al obtener las reseñas del establecimiento' });
  }
};

/**
 * Reseñas escritas por el usuario autenticado. El cliente las usa para saber
 * qué servicios completados ya calificó (y con qué etiquetas).
 */
export const getMyReviews = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const reviews = await Review.find({ userId: req.user!.id })
      .populate('establishmentId', 'name')
      .populate('professionalId', 'name photo')
      .sort({ createdAt: -1 })
      .limit(100);
    res.status(200).json({ reviews });
  } catch {
    res.status(500).json({ message: 'No se pudieron obtener tus reseñas' });
  }
};

export const createReview = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const bookingId = typeof body?.bookingId === 'string' ? body.bookingId.trim() : '';
  const requestedEstablishmentId = typeof body?.establishmentId === 'string' ? body.establishmentId.trim() : '';
  const requestedProfessionalId = typeof body?.professionalId === 'string' ? body.professionalId.trim() : '';
  const rating = parseOptionalRating(body?.rating);
  const ratingProfessional = parseOptionalRating(body?.ratingProfessional);
  const tags = parseTags(body?.tags);
  const comment = typeof body?.comment === 'string' ? body.comment.trim() : '';

  if (rating === undefined || ratingProfessional === undefined || tags === null || comment.length > 500) {
    res.status(400).json({ message: 'Los datos de la reseña no son válidos' });
    return;
  }
  if (bookingId && !isObjectId(bookingId)) {
    res.status(400).json({ message: 'El ID de la reserva no es válido' });
    return;
  }
  if (requestedEstablishmentId && !isObjectId(requestedEstablishmentId)) {
    res.status(400).json({ message: 'El establecimiento no es válido' });
    return;
  }
  if (requestedProfessionalId && !isObjectId(requestedProfessionalId)) {
    res.status(400).json({ message: 'El profesional no es válido' });
    return;
  }
  if (rating === null && ratingProfessional === null && tags.length === 0 && comment.length === 0) {
    res.status(400).json({ message: 'Elige una etiqueta o escribe un comentario para tu reseña' });
    return;
  }

  try {
    let establishmentId = requestedEstablishmentId;
    let professionalId = requestedProfessionalId;

    if (bookingId) {
      const booking = await Booking.findOne({ _id: bookingId, clientId: req.user!.id }).select(
        'establishmentId professionalId status',
      );
      if (!booking) {
        res.status(404).json({ message: 'La reserva no existe o no te pertenece' });
        return;
      }
      if (booking.status !== 'completed') {
        res.status(403).json({ message: 'Solo puedes calificar un servicio completado' });
        return;
      }
      const bookingEstablishmentId = booking.establishmentId.toString();
      if (establishmentId && establishmentId !== bookingEstablishmentId) {
        res.status(400).json({ message: 'La reserva no pertenece a este establecimiento' });
        return;
      }
      establishmentId = bookingEstablishmentId;
      const bookingProfessionalId = booking.professionalId?.toString() ?? '';
      if (professionalId && professionalId !== bookingProfessionalId) {
        res.status(400).json({ message: 'El profesional no coincide con la reserva' });
        return;
      }
      professionalId = bookingProfessionalId;
    }

    if (!establishmentId) {
      res.status(400).json({ message: 'El establecimiento es requerido' });
      return;
    }

    const establishment = await Establishment.findById(establishmentId).select('_id');
    if (!establishment) {
      res.status(404).json({ message: 'Establecimiento no encontrado' });
      return;
    }

    if (professionalId) {
      const professional = await Professional.findOne({ _id: professionalId, establishmentId }).select('_id');
      if (!professional) {
        res.status(400).json({ message: 'El profesional no pertenece a este establecimiento' });
        return;
      }
    }

    if (!bookingId) {
      // Reseña general del establecimiento: sigue exigiendo una cita completada
      // y se permite una sola por establecimiento (comportamiento histórico).
      const completedBooking = await Booking.exists({
        clientId: req.user!.id,
        establishmentId,
        status: 'completed',
        endAt: { $lte: new Date() },
      });
      if (!completedBooking) {
        res.status(403).json({ message: 'Solo puedes reseñar un establecimiento después de completar una cita allí' });
        return;
      }
      if (rating === null) {
        res.status(400).json({ message: 'Una calificación válida (1-5) es requerida' });
        return;
      }
    }

    const duplicate = bookingId
      ? await Review.exists({ userId: req.user!.id, bookingId })
      : await Review.exists({ userId: req.user!.id, establishmentId });
    if (duplicate) {
      res.status(409).json({
        message: bookingId
          ? 'Ya calificaste este servicio'
          : 'Ya publicaste una reseña para este establecimiento',
      });
      return;
    }

    const review = await Review.create({
      userId: req.user!.id,
      establishmentId,
      ...(bookingId ? { bookingId } : {}),
      ...(professionalId ? { professionalId } : {}),
      ...(rating !== null ? { rating } : {}),
      ...(professionalId && ratingProfessional !== null ? { ratingProfessional } : {}),
      ...(tags.length ? { tags } : {}),
      comment,
    });

    await recalculateEstablishmentRating(review.establishmentId);
    if (review.professionalId) {
      await recalculateProfessionalRating(review.professionalId);
    }

    res.status(201).json({
      message: 'Reseña creada exitosamente',
      review,
    });
  } catch (error) {
    if (isDuplicateKeyError(error)) {
      res.status(409).json({ message: 'Ya calificaste este servicio' });
      return;
    }
    res.status(500).json({ message: 'Error al crear la reseña' });
  }
};

export const deleteReview = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const reviewId = typeof req.params.id === 'string' ? req.params.id.trim() : '';

  if (!reviewId) {
    res.status(400).json({ message: 'El ID de la reseña es requerido' });
    return;
  }

  try {
    const review = await Review.findOneAndDelete({
      _id: reviewId,
      userId: req.user!.id,
    });

    if (!review) {
      res.status(404).json({ message: 'La reseña no existe o no tienes permiso para eliminarla' });
      return;
    }

    await recalculateEstablishmentRating(review.establishmentId);
    if (review.professionalId) {
      await recalculateProfessionalRating(review.professionalId);
    }

    res.status(200).json({
      message: 'Reseña eliminada exitosamente',
    });
  } catch {
    res.status(500).json({ message: 'Error al eliminar la reseña' });
  }
};
