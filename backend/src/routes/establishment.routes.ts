import { Router } from 'express';
import { getEstablishments, getNearby, createEstablishment } from '../controllers/establishment.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.get('/', getEstablishments);
router.get('/nearby', getNearby);
router.post('/', authenticate, requireRole(['owner', 'admin']), createEstablishment);

export default router;