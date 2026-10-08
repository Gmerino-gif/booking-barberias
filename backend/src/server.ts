import dotenv from 'dotenv';
dotenv.config();

import app from './app.js';
import { connectDB } from './config/database.js';
import { validateRuntimeEnvironment } from './config/env.js';
import { BookingSlotLock } from './models/BookingSlotLock.js';
import { assertJwtSecret } from './utils/auth-token.js';

const PORT = Number(process.env.PORT || 3000);

async function main() {
  validateRuntimeEnvironment();
  assertJwtSecret();
  await connectDB();
  await BookingSlotLock.createIndexes();

  app.listen(PORT, () => {
    console.log(`Servidor corriendo en el puerto ${PORT}`);
  });
}

main();
