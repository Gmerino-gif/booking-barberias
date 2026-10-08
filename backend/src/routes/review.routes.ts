import { Router } from 'express';
import {
  getEstablishmentReviews,
  getMyReviews,
  createReview,
  deleteReview,
} from '../controllers/review.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

// Ruta pública (cualquier usuario puede ver las reseñas de un establecimiento)
router.get('/establishment/:establishmentId', getEstablishmentReviews);
router.get('/my', authenticate, getMyReviews);

// Rutas protegidas (requieren autenticación para publicar o eliminar reseñas)
router.post('/', authenticate, requireRole(['client']), createReview);
router.delete('/:id', authenticate, deleteReview);

export default router;
