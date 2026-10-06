// backend/src/routes/auth.routes.ts
import { Router } from 'express';
import { rateLimit } from 'express-rate-limit';
import {
  register,
  login,
  refresh,
  getMe,
  forgotPassword,
  resetPassword,
} from '../controllers/auth.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';

const router = Router();
const passwordRecoveryLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Demasiadas solicitudes. Inténtalo de nuevo en 15 minutos.' },
});
const passwordResetLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Demasiados intentos. Inténtalo de nuevo en 15 minutos.' },
});

// POST /api/auth/register
router.post('/register', register);

// POST /api/auth/login
router.post('/login', login);

// POST /api/auth/forgot-password
router.post('/forgot-password', passwordRecoveryLimiter, forgotPassword);

// POST /api/auth/reset-password
router.post('/reset-password', passwordResetLimiter, resetPassword);

// POST /api/auth/refresh
router.post('/refresh', refresh);

// GET /api/auth/me
router.get('/me', authenticate, getMe);

export default router;