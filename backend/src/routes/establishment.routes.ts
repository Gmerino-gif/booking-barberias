import { Router } from 'express';
import {
  getEstablishments,
  getEstablishmentById,
  getNearby,
  createEstablishment,
  getMyEstablishment,
  updateMyEstablishment,
} from '../controllers/establishment.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.get('/', getEstablishments);
router.get('/nearby', getNearby);
router.get('/:id', getEstablishmentById);
router.get('/me', authenticate, requireRole(['owner', 'admin']), getMyEstablishment);
router.post('/', authenticate, requireRole(['owner', 'admin']), createEstablishment);
router.put('/me', authenticate, requireRole(['owner', 'admin']), updateMyEstablishment);

export default router;