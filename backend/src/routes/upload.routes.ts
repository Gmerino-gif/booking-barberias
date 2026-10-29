import { Router } from 'express';
import { uploadImage } from '../controllers/upload.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

// Solo dueños de negocio y administradores gestionan imágenes de perfiles.
router.post('/image', authenticate, requireRole(['owner', 'admin']), uploadImage);

export default router;
