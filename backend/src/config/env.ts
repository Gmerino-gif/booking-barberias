const required = (name: string): string => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} no está configurada`);
  return value;
};

export const validateRuntimeEnvironment = (): void => {
  const mongoUri = required('MONGODB_URI');
  if (!/^mongodb(?:\+srv)?:\/\//i.test(mongoUri)) {
    throw new Error('MONGODB_URI debe usar el protocolo mongodb:// o mongodb+srv://');
  }

  const jwtSecret = required('JWT_SECRET');
  if (Buffer.byteLength(jwtSecret, 'utf8') < 32 || /replace-with|generate-a-random|your[-_ ]|change[-_ ]/i.test(jwtSecret)) {
    throw new Error('JWT_SECRET debe ser aleatorio y tener al menos 32 bytes');
  }

  const port = Number(process.env.PORT ?? 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT debe ser un puerto válido entre 1 y 65535');
  }

  if (process.env.NODE_ENV === 'production') {
    const missingSmtp = ['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_FROM']
      .filter((name) => !process.env[name]?.trim());
    if (missingSmtp.length > 0) {
      throw new Error(`Falta configurar SMTP para producción: ${missingSmtp.join(', ')}`);
    }
    if (!process.env.CORS_ORIGINS?.split(',').some((origin) => origin.trim().length > 0)) {
      throw new Error('CORS_ORIGINS debe incluir al menos el origen web de producción');
    }
    const origins = process.env.CORS_ORIGINS.split(',').map((origin) => origin.trim()).filter(Boolean);
    if (origins.some((origin) => {
      try {
        const url = new URL(origin);
        return url.protocol !== 'https:' || url.origin !== origin;
      } catch {
        return true;
      }
    })) {
      throw new Error('Cada origen de CORS en producción debe ser un origen HTTPS completo, sin rutas');
    }

    const smtpPort = Number(required('SMTP_PORT'));
    if (!Number.isInteger(smtpPort) || smtpPort < 1 || smtpPort > 65535) {
      throw new Error('SMTP_PORT debe ser un puerto válido entre 1 y 65535');
    }
  }
};
