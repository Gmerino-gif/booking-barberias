import { Router } from 'express';
import {
  getServices,
  getServiceById,
  createService,
  updateService,
  deleteService,
} from '../controllers/service.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

// Rutas públicas (cualquier usuario o cliente puede consultar servicios o filtrarlos por establecimiento)
router.get('/', getServices);
router.get('/:id', getServiceById);

// Rutas protegidas (requieren autenticación para crear, modificar o eliminar)
router.post('/', authenticate, requireRole(['owner']), createService);
router.put('/:id', authenticate, requireRole(['owner']), updateService);
router.delete('/:id', authenticate, requireRole(['owner']), deleteService);

export default router;
