import { Router } from 'express';
import {
  approveManualPayment,
  getPendingManualPayments,
  getAdminEstablishments,
  renewEstablishment,
  toggleEstablishment,
} from '../controllers/admin.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireSuperAdmin } from '../middleware/role.middleware.js';

const router = Router();

router.use(authenticate, requireSuperAdmin);
router.get('/establishments', getAdminEstablishments);
router.patch('/establishments/:id/toggle', toggleEstablishment);
router.patch('/establishments/:id/renew', renewEstablishment);
router.get('/payments/pending', getPendingManualPayments);
router.patch('/payments/:id/approve', approveManualPayment);

export default router;
