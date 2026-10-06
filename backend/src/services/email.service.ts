import nodemailer from 'nodemailer';

export const sendPasswordResetEmail = async (
  email: string,
  token: string,
): Promise<void> => {
  const host = process.env.SMTP_HOST;
  const port = Number(process.env.SMTP_PORT);
  const user = process.env.SMTP_USER;
  const password = process.env.SMTP_PASS;
  const from = process.env.SMTP_FROM;

  if (!host || !Number.isInteger(port) || port < 1 || port > 65535 || !user || !password || !from) {
    throw new Error('La configuración SMTP está incompleta');
  }

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    requireTLS: port !== 465,
    auth: { user, pass: password },
  });

  await transporter.sendMail({
    from,
    to: email,
    subject: 'Restablece tu contraseña de Booking App',
    text: [
      'Recibimos una solicitud para restablecer la contraseña de tu cuenta de Booking App.',
      '',
      'Ingresa este código en la pantalla de recuperación de la aplicación:',
      token,
      '',
      'El código vence en 15 minutos y solo se puede usar una vez.',
      'Si no solicitaste este cambio, ignora este correo.',
    ].join('\n'),
  });
};
