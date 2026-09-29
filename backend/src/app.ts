import express from 'express';
import cors from 'cors';

import authRoutes from './routes/auth.routes.js';

const app = express();

app.use(cors());
app.use(express.json());
app.use('/api/auth', authRoutes);

app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'booking-api',
    timestamp: new Date().toISOString(),
  });
});

export default app;