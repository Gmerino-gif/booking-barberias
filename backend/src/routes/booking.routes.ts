import { Router } from 'express';
import { createBooking, getMyBookings } from '../controllers/booking.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';

const router = Router();

router.post('/', authenticate, createBooking);
router.get('/my', authenticate, getMyBookings);

export default router;