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

// ⚠️ IMPORTANTE: Las rutas específicas (/me) van ANTES que las dinámicas (/:id)
router.get('/me', authenticate, requireRole(['owner', 'admin']), getMyEstablishment);
router.put('/me', authenticate, requireRole(['owner', 'admin']), updateMyEstablishment);

// Las rutas dinámicas SIEMPRE van al final
router.get('/:id', getEstablishmentById);

// Crear establecimiento (POST)
router.post('/', authenticate, requireRole(['owner', 'admin']), createEstablishment);

export default router;