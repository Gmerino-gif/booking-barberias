import jwt from 'jsonwebtoken';
import type { JwtPayload } from 'jsonwebtoken';
import type { UserRole } from '../models/User.js';

export interface AuthTokenPayload extends JwtPayload {
  sub: string;
  role: UserRole;
  tokenType: 'access' | 'refresh';
  tokenVersion?: number;
}

export const assertJwtSecret = (): void => {
  if (!process.env.JWT_SECRET) {
    throw new Error('JWT_SECRET no está configurado');
  }
};

const getJwtSecret = (): string => {
  assertJwtSecret();
  return process.env.JWT_SECRET as string;
};

export const createAccessToken = (
  userId: string,
  role: UserRole,
  tokenVersion = 0,
): string =>
  jwt.sign({ role, tokenType: 'access', tokenVersion }, getJwtSecret(), {
    subject: userId,
    expiresIn: '15m',
  });

export const createRefreshToken = (
  userId: string,
  role: UserRole,
  tokenVersion = 0,
): string =>
  jwt.sign({ role, tokenType: 'refresh', tokenVersion }, getJwtSecret(), {
    subject: userId,
    expiresIn: '7d',
  });

export const verifyAuthToken = (
  token: string,
  expectedType: AuthTokenPayload['tokenType'],
): AuthTokenPayload => {
  const payload = jwt.verify(token, getJwtSecret());
  const validRoles: readonly string[] = ['client', 'owner', 'professional', 'admin'];

  if (
    typeof payload === 'string' ||
    typeof payload.sub !== 'string' ||
    typeof payload.role !== 'string' ||
    !validRoles.includes(payload.role) ||
    (payload.tokenVersion !== undefined &&
      (typeof payload.tokenVersion !== 'number' ||
        !Number.isInteger(payload.tokenVersion) ||
        payload.tokenVersion < 0)) ||
    payload.tokenType !== expectedType
  ) {
    throw new Error('Token inválido');
  }

  return payload as AuthTokenPayload;
};