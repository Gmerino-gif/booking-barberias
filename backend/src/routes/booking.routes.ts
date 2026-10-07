import { Router } from 'express';
import { createBooking, getAvailability, getBusinessBookings, getMyBookings, updateBookingStatus } from '../controllers/booking.controller.js';
import { authenticate } from '../middleware/auth.middleware.js';
import { requireRole } from '../middleware/role.middleware.js';

const router = Router();

router.get('/availability', getAvailability);
router.post('/', authenticate, requireRole(['client']), createBooking);
router.get('/my', authenticate, requireRole(['client']), getMyBookings);
router.get('/business', authenticate, requireRole(['owner', 'admin']), getBusinessBookings);
router.patch('/:id/status', authenticate, updateBookingStatus);

export default router;
