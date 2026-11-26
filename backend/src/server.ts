// Debe ser la PRIMERA importación: carga el .env (resuelto como backend/.env,
// sin depender del cwd) antes de que se evalúe cualquier otro módulo.
import './config/bootstrap-env.js';

import app from './app.js';
import { connectDB } from './config/database.js';
import { validateRuntimeEnvironment } from './config/env.js';
import { BookingSlotLock } from './models/BookingSlotLock.js';
import { Booking } from './models/Booking.js';
import { assertJwtSecret } from './utils/auth-token.js';
import { initializeFirebaseAdmin } from './services/push-notification.service.js';
import { startBookingReminderScheduler } from './services/booking-reminder.service.js';
import { logWompiConfiguration } from './services/wompi.service.js';

const PORT = Number(process.env.PORT || 3000);

async function main() {
  validateRuntimeEnvironment();
  assertJwtSecret();
  logWompiConfiguration();
  initializeFirebaseAdmin();
  await connectDB();
  await BookingSlotLock.createIndexes();
  await Booking.createIndexes();
  startBookingReminderScheduler();

  app.listen(PORT, () => {
    console.log(`Servidor corriendo en el puerto ${PORT}`);
  });
}

main();
