import { Router } from 'express';
import {
  getFavorites,
  addFavorite,
  removeFavorite,
} from '../controllers/favorite.controller.js';
import { getByEstablishment } from '../controllers/professional.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';

const router = Router();

router.get('/establishment/:establishmentId', getByEstablishment);

router.use(authenticate);

router.get('/', getFavorites);
router.post('/', addFavorite);
router.delete('/:establishmentId', removeFavorite);

export default router;