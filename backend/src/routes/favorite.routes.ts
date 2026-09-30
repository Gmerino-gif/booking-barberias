import { Router } from 'express';
import {
  getFavorites,
  addFavorite,
  removeFavorite,
} from '../controllers/favorite.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';

const router = Router();

// Todas las rutas de favoritos requieren que el usuario esté autenticado
router.use(authenticate);

router.get('/', getFavorites);
router.post('/', addFavorite);
router.delete('/:establishmentId', removeFavorite);

export default router;