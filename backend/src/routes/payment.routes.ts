import { Router, type RequestHandler } from 'express';
import multer from 'multer';
import {
  createManualReceipt,
  createWompiLink,
  getMyPaymentHistory,
  handleWompiWebhook,
} from '../controllers/payment.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const receiptUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
}).single('receipt');

const receiveReceipt: RequestHandler = (req, res, next) => {
  receiptUpload(req, res, (error: unknown) => {
    if (!error) {
      next();
      return;
    }
    if (error instanceof multer.MulterError) {
      const status = error.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
      res.status(status).json({
        message: status === 413
          ? 'El comprobante supera el tamaño máximo de 5 MB'
          : 'El archivo del comprobante no es válido',
      });
      return;
    }
    next(error);
  });
};

const router = Router();

router.post('/wompi-link', authenticate, requireRole(['owner']), createWompiLink);
router.post('/manual-receipt', authenticate, requireRole(['owner']), receiveReceipt, createManualReceipt);
router.get('/my-history', authenticate, requireRole(['owner']), getMyPaymentHistory);

export const wompiWebhookRouter = Router();
wompiWebhookRouter.post('/wompi', handleWompiWebhook);

export default router;
