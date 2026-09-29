import type { Request, Response, NextFunction } from 'express';
import { verifyAuthToken } from '../utils/auth-token.js';
import type { UserRole } from '../models/User.js';

// Extender la interfaz Request de Express para adjuntar el usuario autenticado
export interface AuthenticatedRequest extends Request {
  user?: {
    id: string;
    role: UserRole;
  };
}

export const authenticate = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void => {
  const tokenMatch = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization ?? '');
  const token = tokenMatch?.[1];
  if (!token) {
    res.status(401).json({ message: 'Acceso no autorizado: Token no proporcionado' });
    return;
  }

  if (!process.env.JWT_SECRET) {
    res.status(500).json({ message: 'Servicio de autenticación no configurado' });
    return;
  }

  try {
    const claims = verifyAuthToken(token, 'access');
    req.user = { id: claims.sub, role: claims.role };
    next();
  } catch {
    res.status(401).json({ message: 'Token expirado o no válido' });
  }
};