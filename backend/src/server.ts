import dotenv from 'dotenv';
dotenv.config();

import app from './app.js';
import { connectDB } from './config/database.js';
import { assertJwtSecret } from './utils/auth-token.js';

const PORT = process.env.PORT || 3000;

async function main() {
  assertJwtSecret();
  await connectDB();

  app.listen(PORT, () => {
    console.log(`Servidor corriendo en el puerto ${PORT}`);
  });
}

main();