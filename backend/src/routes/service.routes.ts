import { Router } from 'express';
import {
  getServices,
  getServiceById,
  createService,
  updateService,
  deleteService,
} from '../controllers/service.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';

const router = Router();

// Rutas públicas (cualquier usuario o cliente puede consultar servicios o filtrarlos por establecimiento)
router.get('/', getServices);
router.get('/:id', getServiceById);

// Rutas protegidas (requieren autenticación para crear, modificar o eliminar)
router.post('/', authenticate, createService);
router.put('/:id', authenticate, updateService);
router.delete('/:id', authenticate, deleteService);

export default router;