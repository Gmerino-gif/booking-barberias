import { Router } from 'express';
import {
  createProfessional,
  deleteProfessional,
  getByEstablishment,
  getMyProfessionals,
  updateProfessional,
} from '../controllers/professional.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.get('/establishment/:establishmentId', getByEstablishment);
router.use(authenticate, requireRole(['owner']));
router.get('/me', getMyProfessionals);
router.post('/', createProfessional);
router.put('/:id', updateProfessional);
router.delete('/:id', deleteProfessional);

export default router;
