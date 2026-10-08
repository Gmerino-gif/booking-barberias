import bcrypt from 'bcryptjs';
import { createHash, randomBytes } from 'node:crypto';
import type { Request, Response } from 'express';
import { User } from '../models/User.js';
import type { UserRole } from '../models/User.js';
import { createAccessToken, createRefreshToken, verifyAuthToken } from '../utils/auth-token.js';
import { sendPasswordResetEmail } from '../services/email.service.js';
import { isValidPhoneNumber } from '../utils/phone.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

const isEmail = (value: string): boolean => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
const passwordResetResponse = {
  message: 'Si existe una cuenta con ese correo, recibirás instrucciones para restablecer tu contraseña.',
};

const hashPasswordResetToken = (token: string): string =>
  createHash('sha256').update(token).digest('hex');

const publicUser = (user: {
  _id: { toString(): string };
  name: string;
  email: string;
  role: UserRole;
  phone?: string;
}) => ({
  id: user._id.toString(),
  name: user.name,
  email: user.email,
  role: user.role,
  phone: user.phone ?? '',
});

export const register = async (req: Request, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = typeof body?.password === 'string' ? body.password : '';
  const phone = typeof body?.phone === 'string' ? body.phone.trim() : '';
  const requestedRole = body?.role ?? 'client';

  if (name.length < 2 || name.length > 80 || !isEmail(email)) {
    res.status(400).json({ message: 'Nombre o correo inválido' });
    return;
  }

  if (!isValidPhoneNumber(phone)) {
    res.status(400).json({ message: 'El número celular debe tener entre 7 y 15 dígitos' });
    return;
  }

  const passwordLength = Buffer.byteLength(password, 'utf8');
  if (passwordLength < 8 || passwordLength > 72) {
    res.status(400).json({ message: 'La contraseña debe tener entre 8 y 72 bytes' });
    return;
  }

  if (requestedRole !== 'client' && requestedRole !== 'owner') {
    res.status(400).json({ message: 'Rol de registro inválido' });
    return;
  }

  try {
    const existingUser = await User.exists({ email });
    if (existingUser) {
      res.status(409).json({ message: 'Ya existe una cuenta con ese correo' });
      return;
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const user = await User.create({ name, email, passwordHash, role: requestedRole, phone });
    const userId = user._id.toString();

    res.status(201).json({
      message: 'Usuario registrado exitosamente',
      token: createAccessToken(userId, user.role, user.tokenVersion),
      refreshToken: createRefreshToken(userId, user.role, user.tokenVersion),
      user: publicUser(user),
    });
  } catch (error) {
    if (typeof error === 'object' && error !== null && 'code' in error && error.code === 11000) {
      res.status(409).json({ message: 'Ya existe una cuenta con ese correo' });
      return;
    }
    res.status(500).json({ message: 'Error al registrar usuario' });
  }
};

export const login = async (req: Request, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = typeof body?.password === 'string' ? body.password : '';

  if (!isEmail(email) || password.length === 0) {
    res.status(400).json({ message: 'Correo o contraseña inválidos' });
    return;
  }

  try {
    const user = await User.findOne({ email }).select('+passwordHash +tokenVersion');
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
      res.status(401).json({ message: 'Correo o contraseña incorrectos' });
      return;
    }

    const userId = user._id.toString();
    res.status(200).json({
      message: 'Inicio de sesión exitoso',
      token: createAccessToken(userId, user.role, user.tokenVersion),
      refreshToken: createRefreshToken(userId, user.role, user.tokenVersion),
      user: publicUser(user),
    });
  } catch {
    res.status(500).json({ message: 'Error en el inicio de sesión' });
  }
};

export const forgotPassword = async (req: Request, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';

  if (!isEmail(email)) {
    res.status(400).json({ message: 'Ingresa un correo electrónico válido' });
    return;
  }

  try {
    const user = await User.findOne({ email });
    if (!user) {
      res.status(200).json(passwordResetResponse);
      return;
    }

    const token = randomBytes(32).toString('hex');
    const tokenHash = hashPasswordResetToken(token);
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    user.passwordResetTokenHash = tokenHash;
    user.passwordResetExpiresAt = expiresAt;
    await user.save();

    res.status(200).json(passwordResetResponse);

    try {
      await sendPasswordResetEmail(user.email, token);
    } catch (error) {
      try {
        await User.updateOne(
          { _id: user._id },
          { $unset: { passwordResetTokenHash: 1, passwordResetExpiresAt: 1 } },
        );
      } catch {
        console.error('No se pudo invalidar el código de recuperación tras un error SMTP');
      }
      const errorCode =
        typeof error === 'object' && error !== null && 'code' in error
          ? String(error.code)
          : 'unknown';
      console.error('No se pudo enviar el correo de recuperación:', errorCode);
    }
  } catch {
    res.status(500).json({ message: 'Error al procesar la solicitud de recuperación' });
  }
};

export const resetPassword = async (req: Request, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  const token = typeof body?.token === 'string' ? body.token.trim() : '';
  const password = typeof body?.password === 'string' ? body.password : '';
  const passwordLength = Buffer.byteLength(password, 'utf8');

  if (!isEmail(email) || !/^[a-f0-9]{64}$/i.test(token)) {
    res.status(400).json({ message: 'El código de recuperación o el correo no son válidos o ya vencieron' });
    return;
  }

  if (passwordLength < 8 || passwordLength > 72) {
    res.status(400).json({ message: 'La contraseña debe tener entre 8 y 72 bytes' });
    return;
  }

  try {
    const tokenHash = hashPasswordResetToken(token);
    const user = await User.findOne({
      email,
      passwordResetTokenHash: tokenHash,
      passwordResetExpiresAt: { $gt: new Date() },
    }).select('+passwordResetTokenHash +passwordResetExpiresAt');

    if (!user) {
      res.status(400).json({ message: 'El código de recuperación o el correo no son válidos o ya vencieron' });
      return;
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const updatedUser = await User.findOneAndUpdate(
      {
        _id: user._id,
        passwordResetTokenHash: tokenHash,
        passwordResetExpiresAt: { $gt: new Date() },
      },
      {
        $set: { passwordHash },
        $unset: { passwordResetTokenHash: 1, passwordResetExpiresAt: 1 },
        $inc: { tokenVersion: 1 },
      },
      { returnDocument: 'after', runValidators: true },
    );

    if (!updatedUser) {
      res.status(400).json({ message: 'El código de recuperación o el correo no son válidos o ya vencieron' });
      return;
    }

    res.status(200).json({ message: 'Contraseña restablecida correctamente. Ya puedes iniciar sesión.' });
  } catch {
    res.status(500).json({ message: 'Error al restablecer la contraseña' });
  }
};

export const refresh = async (req: Request, res: Response): Promise<void> => {
  const refreshToken = req.body?.refreshToken;
  if (typeof refreshToken !== 'string' || refreshToken.length === 0) {
    res.status(401).json({ message: 'Token de refresco inválido o expirado' });
    return;
  }

  let claims;
  try {
    claims = verifyAuthToken(refreshToken, 'refresh');
  } catch {
    res.status(401).json({ message: 'Token de refresco inválido o expirado' });
    return;
  }

  try {
    const user = await User.findById(claims.sub).select('+tokenVersion');
    if (!user || (claims.tokenVersion ?? 0) !== user.tokenVersion) {
      res.status(401).json({ message: 'Token de refresco inválido o expirado' });
      return;
    }

    res.status(200).json({
      message: 'Token renovado correctamente',
      accessToken: createAccessToken(user._id.toString(), user.role, user.tokenVersion),
    });
  } catch {
    res.status(500).json({ message: 'Error al renovar el token' });
  }
};

export const getMe = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  if (!req.user) {
    res.status(401).json({ message: 'Acceso no autorizado' });
    return;
  }

  try {
    const user = await User.findById(req.user.id);
    if (!user) {
      res.status(404).json({ message: 'Usuario no encontrado' });
      return;
    }

    res.status(200).json({ user: publicUser(user) });
  } catch {
    res.status(500).json({ message: 'Error al obtener el perfil' });
  }
};

export const updateMe = async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const phone = typeof body?.phone === 'string' ? body.phone.trim() : '';
  if (name.length < 2 || name.length > 80 || !isValidPhoneNumber(phone)) {
    res.status(400).json({ message: 'Nombre o teléfono inválido' });
    return;
  }

  try {
    const user = await User.findByIdAndUpdate(req.user!.id, { $set: { name, phone } }, { returnDocument: 'after', runValidators: true });
    if (!user) {
      res.status(404).json({ message: 'Usuario no encontrado' });
      return;
    }
    res.status(200).json({ message: 'Perfil actualizado', user: publicUser(user) });
  } catch {
    res.status(500).json({ message: 'No se pudo actualizar el perfil' });
  }
};
