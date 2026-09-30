import { Router } from 'express';
import {
  getEstablishmentReviews,
  createReview,
  deleteReview,
} from '../controllers/review.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';

const router = Router();

// Ruta pública (cualquier usuario puede ver las reseñas de un establecimiento)
router.get('/establishment/:establishmentId', getEstablishmentReviews);

// Rutas protegidas (requieren autenticación para publicar o eliminar reseñas)
router.post('/', authenticate, createReview);
router.delete('/:id', authenticate, deleteReview);

export default router;