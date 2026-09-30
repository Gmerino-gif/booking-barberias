import express from 'express';
import cors from 'cors';

import authRoutes from './routes/auth.routes.js';
import bookingRoutes from './routes/booking.routes.js';
import establishmentRoutes from './routes/establishment.routes.js';
import favoriteRoutes from './routes/favorite.routes.js';
import professionalRoutes from './routes/professional.routes.js';
import reviewRoutes from './routes/review.routes.js';
import serviceRoutes from './routes/service.routes.js';

const app = express();

app.use(cors());
app.use(express.json());

// Endpoint de verificación (Healthcheck)
app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'booking-api',
    timestamp: new Date().toISOString(),
  });
});

// Rutas del sistema
app.use('/api/auth', authRoutes);
app.use('/api/bookings', bookingRoutes);
app.use('/api/establishments', establishmentRoutes);
app.use('/api/favorites', favoriteRoutes);
app.use('/api/professionals', professionalRoutes);
app.use('/api/reviews', reviewRoutes);
app.use('/api/services', serviceRoutes);

export default app;
