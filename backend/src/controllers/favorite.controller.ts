import type { Request, Response } from 'express';
import { Favorite } from '../models/Favorite.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

export const getFavorites = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const favorites = await Favorite.find({
      userId: req.user!.id,
    }).populate('establishmentId');
    res.status(200).json({ favorites });
  } catch {
    res.status(500).json({ message: 'Error al obtener los favoritos' });
  }
};

export const addFavorite = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const establishmentId = typeof body?.establishmentId === 'string' ? body.establishmentId.trim() : '';

  if (!establishmentId) {
    res.status(400).json({ message: 'El establecimiento es requerido' });
    return;
  }

  try {
    const existingFavorite = await Favorite.findOne({
      userId: req.user!.id,
      establishmentId,
    });

    if (existingFavorite) {
      res.status(409).json({ message: 'El establecimiento ya está en favoritos' });
      return;
    }

    const favorite = await Favorite.create({
      userId: req.user!.id,
      establishmentId,
    });

    res.status(201).json({
      message: 'Establecimiento agregado a favoritos',
      favorite,
    });
  } catch {
    res.status(500).json({ message: 'Error al agregar el favorito' });
  }
};

export const removeFavorite = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const establishmentId = typeof req.params.establishmentId === 'string' ? req.params.establishmentId.trim() : '';

  if (!establishmentId) {
    res.status(400).json({ message: 'El establecimiento es requerido' });
    return;
  }

  try {
    const favorite = await Favorite.findOneAndDelete({
      userId: req.user!.id,
      establishmentId,
    });

    if (!favorite) {
      res.status(404).json({ message: 'El favorito no existe' });
      return;
    }

    res.status(200).json({
      message: 'Establecimiento eliminado de favoritos',
    });
  } catch {
    res.status(500).json({ message: 'Error al eliminar el favorito' });
  }
};
