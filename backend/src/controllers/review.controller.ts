import type { Request, Response } from 'express';
import { Review } from '../models/Review.js';
import { Establishment } from '../models/Establishment.js';
import { Booking } from '../models/Booking.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

export const getEstablishmentReviews = async (req: Request, res: Response): Promise<void> => {
  const establishmentId = typeof req.params.establishmentId === 'string' ? req.params.establishmentId.trim() : '';

  if (!establishmentId) {
    res.status(400).json({ message: 'El ID del establecimiento es requerido' });
    return;
  }

  try {
    const reviews = await Review.find({ establishmentId }).populate('userId', 'name').sort({ createdAt: -1 }).limit(50);
    res.status(200).json({ reviews });
  } catch {
    res.status(500).json({ message: 'Error al obtener las reseñas del establecimiento' });
  }
};

export const getMyReviews = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const reviews = await Review.find({ userId: req.user!.id }).select('_id');
    res.status(200).json({ reviews });
  } catch {
    res.status(500).json({ message: 'No se pudieron obtener tus reseñas' });
  }
};

export const createReview = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const establishmentId = typeof body?.establishmentId === 'string' ? body.establishmentId.trim() : '';
  const rating = Number(body?.rating);
  const comment = typeof body?.comment === 'string' ? body.comment.trim() : '';

  if (!establishmentId || !Number.isInteger(rating) || rating < 1 || rating > 5 || comment.length > 500) {
    res.status(400).json({ message: 'El establecimiento y una calificación válida (1-5) son requeridos' });
    return;
  }

  try {
    const establishment = await Establishment.findById(establishmentId).select('_id');
    if (!establishment) {
      res.status(404).json({ message: 'Establecimiento no encontrado' });
      return;
    }
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
    if (await Review.exists({ userId: req.user!.id, establishmentId })) {
      res.status(409).json({ message: 'Ya publicaste una reseña para este establecimiento' });
      return;
    }

    const review = await Review.create({
      userId: req.user!.id,
      establishmentId,
      rating,
      comment,
    });
    const [summary] = await Review.aggregate([
      { $match: { establishmentId: review.establishmentId } },
      { $group: { _id: '$establishmentId', rating: { $avg: '$rating' } } },
    ]);
    await Establishment.findByIdAndUpdate(establishmentId, { rating: summary?.rating ?? 0 });

    res.status(201).json({
      message: 'Reseña creada exitosamente',
      review,
    });
  } catch {
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

    const [summary] = await Review.aggregate([
      { $match: { establishmentId: review.establishmentId } },
      { $group: { _id: '$establishmentId', rating: { $avg: '$rating' } } },
    ]);
    await Establishment.findByIdAndUpdate(review.establishmentId, { rating: summary?.rating ?? 0 });

    res.status(200).json({
      message: 'Reseña eliminada exitosamente',
    });
  } catch {
    res.status(500).json({ message: 'Error al eliminar la reseña' });
  }
};
