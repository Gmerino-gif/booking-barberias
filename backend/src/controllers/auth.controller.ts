import bcrypt from 'bcryptjs';
import type { Request, Response } from 'express';
import { User } from '../models/User.js';
import type { UserRole } from '../models/User.js';
import { createAccessToken, createRefreshToken, verifyAuthToken } from '../utils/auth-token.js';
import type { AuthenticatedRequest } from '../middleware/auth.middleware.js';

const isEmail = (value: string): boolean => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);

const publicUser = (user: {
  _id: { toString(): string };
  name: string;
  email: string;
  role: UserRole;
}) => ({
  id: user._id.toString(),
  name: user.name,
  email: user.email,
  role: user.role,
});

export const register = async (req: Request, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = typeof body?.password === 'string' ? body.password : '';
  const requestedRole = body?.role ?? 'client';

  if (name.length < 2 || name.length > 80 || !isEmail(email)) {
    res.status(400).json({ message: 'Nombre o correo inválido' });
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
    const user = await User.create({ name, email, passwordHash, role: requestedRole });
    const userId = user._id.toString();

    res.status(201).json({
      message: 'Usuario registrado exitosamente',
      token: createAccessToken(userId, user.role),
      refreshToken: createRefreshToken(userId, user.role),
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
    const user = await User.findOne({ email }).select('+passwordHash');
    if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
      res.status(401).json({ message: 'Correo o contraseña incorrectos' });
      return;
    }

    const userId = user._id.toString();
    res.status(200).json({
      message: 'Inicio de sesión exitoso',
      token: createAccessToken(userId, user.role),
      refreshToken: createRefreshToken(userId, user.role),
      user: publicUser(user),
    });
  } catch {
    res.status(500).json({ message: 'Error en el inicio de sesión' });
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
    const user = await User.findById(claims.sub);
    if (!user) {
      res.status(401).json({ message: 'Token de refresco inválido o expirado' });
      return;
    }

    res.status(200).json({
      message: 'Token renovado correctamente',
      accessToken: createAccessToken(user._id.toString(), user.role),
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