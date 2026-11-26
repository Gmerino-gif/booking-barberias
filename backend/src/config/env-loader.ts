import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

/**
 * Carga determinista de variables de entorno.
 *
 * Dos problemas motivaron este módulo:
 *  1. `dotenv.config()` resuelve el `.env` contra `process.cwd()`, así que al
 *     arrancar el servidor desde otra carpeta se leía un `.env` distinto (o
 *     ninguno) y la aplicación quedaba con valores viejos.
 *  2. `dotenv.config()` **no sobrescribe** variables ya presentes en
 *     `process.env`: una variable del sistema (p. ej. una llave vieja de Wompi)
 *     ganaba silenciosamente sobre el `.env` recién actualizado.
 *
 * Ahora la ruta se resuelve relativa a este módulo (siempre `backend/.env`,
 * se ejecute desde donde se ejecute) y los conflictos se registran en el log
 * indicando qué origen ganó, sin exponer valores.
 */

export type EnvValueSource = 'dotenv-file' | 'process-env' | 'missing';

export type EnvConflict = { key: string; winner: 'file' | 'process' };

export type EnvFileOutcome = {
  path: string;
  loaded: boolean;
  applied: string[];
  conflicts: EnvConflict[];
};

export const ENV_FILE_PATH = fileURLToPath(new URL('../../.env', import.meta.url));

const envSources = new Map<string, EnvValueSource>();

export const applyEnvFile = (
  input: {
    path?: string;
    env?: NodeJS.ProcessEnv;
    override?: boolean;
    readFile?: (filePath: string) => string;
  } = {},
): EnvFileOutcome => {
  const path = input.path ?? ENV_FILE_PATH;
  const env = input.env ?? process.env;
  const readFile = input.readFile ?? ((filePath: string) => readFileSync(filePath, 'utf8'));
  const override = input.override ?? env.NODE_ENV !== 'production';
  const trackSources = env === process.env;

  let raw: string;
  try {
    raw = readFile(path);
  } catch {
    return { path, loaded: false, applied: [], conflicts: [] };
  }

  const applied: string[] = [];
  const conflicts: EnvConflict[] = [];

  for (const [key, value] of Object.entries(dotenv.parse(raw))) {
    const inherited = env[key];
    if (inherited !== undefined && inherited.trim() !== value.trim()) {
      conflicts.push({ key, winner: override ? 'file' : 'process' });
      if (!override) {
        if (trackSources) envSources.set(key, 'process-env');
        continue;
      }
    }
    env[key] = value;
    applied.push(key);
    if (trackSources) envSources.set(key, 'dotenv-file');
  }

  return { path, loaded: true, applied, conflicts };
};

export const loadEnvironment = (): EnvFileOutcome => {
  const override = process.env.NODE_ENV !== 'production';
  const outcome = applyEnvFile({ path: ENV_FILE_PATH, override });

  if (!outcome.loaded) {
    console.warn(
      'No se encontró el archivo .env; se usan únicamente las variables del proceso',
      { path: outcome.path },
    );
  } else if (outcome.conflicts.length > 0) {
    console.warn(
      'Variables de entorno definidas tanto en el .env como en el proceso (orígenes en conflicto)',
      {
        path: outcome.path,
        gana: override ? 'archivo .env' : 'variables del proceso',
        keys: outcome.conflicts.map((conflict) => conflict.key),
      },
    );
  }

  return outcome;
};

/** Indica de dónde salió el valor efectivo de una variable (sin exponerlo). */
export const describeEnvSource = (key: string): EnvValueSource => {
  const tracked = envSources.get(key);
  if (tracked) return tracked;
  return process.env[key]?.trim() ? 'process-env' : 'missing';
};
