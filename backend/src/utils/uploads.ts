import { randomBytes } from 'node:crypto';
import { mkdir, unlink, writeFile } from 'node:fs/promises';
import { get as httpGet } from 'node:http';
import { get as httpsGet } from 'node:https';
import path from 'node:path';
import { URL } from 'node:url';

/**
 * Almacenamiento de imágenes subidas (logos, banners y fotos de profesionales).
 *
 * El proyecto no usa un servicio externo de archivos: las imágenes se guardan en
 * `backend/uploads` y se sirven como estáticos en `{UPLOADS_ROUTE_PREFIX}`. Las
 * referencias persistidas en MongoDB son rutas relativas (`/uploads/archivo.png`)
 * para que el cliente pueda resolverlas contra el origen de la API.
 */

export const UPLOADS_ROUTE_PREFIX = '/uploads';
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // 5 MB
const DOWNLOAD_TIMEOUT_MS = 8000;
const MAX_REDIRECTS = 3;
const MAX_IMAGE_REF_LENGTH = 500;

const EXTENSIONS: Record<string, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

const DATA_URL_PATTERN = /^data:(image\/[a-z0-9.+-]+);base64,([a-z0-9+/=\s]+)$/i;

/** Hosts que nunca deben descargarse desde el servidor (mitiga SSRF). */
const PRIVATE_HOST_PATTERNS: RegExp[] = [
  /^localhost$/i,
  /^127\./,
  /^0\./,
  /^10\./,
  /^192\.168\./,
  /^169\.254\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
  /^\[?::1\]?$/,
  /^\[?f[cd][0-9a-f]{2}:/i,
  /\.local$/i,
  /\.internal$/i,
];

export class UploadError extends Error {
  readonly status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.name = 'UploadError';
    this.status = status;
  }
}

export const uploadsDirectory = path.resolve(process.cwd(), 'uploads');

export const ensureUploadsDirectory = async (): Promise<void> => {
  await mkdir(uploadsDirectory, { recursive: true });
};

/** Detecta el formato real de la imagen por sus bytes iniciales (no confía en el mime declarado). */
const detectImageMime = (buffer: Buffer): string | null => {
  const head = buffer.toString('hex', 0, Math.min(buffer.length, 12));
  if (head.startsWith('89504e47')) return 'image/png';
  if (head.startsWith('ffd8ff')) return 'image/jpeg';
  if (head.startsWith('52494646') && head.slice(16, 24) === '57454250') return 'image/webp';
  if (head.startsWith('474946')) return 'image/gif';
  return null;
};

/** Guarda los bytes de una imagen y devuelve su referencia pública (`/uploads/...`). */
export const storeImageBuffer = async (buffer: Buffer): Promise<string> => {
  if (buffer.length === 0) {
    throw new UploadError('El archivo de imagen está vacío');
  }
  if (buffer.length > MAX_IMAGE_BYTES) {
    throw new UploadError('La imagen supera el tamaño máximo de 5 MB');
  }
  const mime = detectImageMime(buffer);
  const extension = mime ? EXTENSIONS[mime] : undefined;
  if (!extension) {
    throw new UploadError('Formato no soportado. Usa una imagen PNG, JPG, WEBP o GIF');
  }

  await ensureUploadsDirectory();
  const fileName = `${Date.now().toString(36)}-${randomBytes(8).toString('hex')}.${extension}`;
  await writeFile(path.join(uploadsDirectory, fileName), buffer);
  return `${UPLOADS_ROUTE_PREFIX}/${fileName}`;
};

/** Guarda una imagen enviada como data URL base64 (`data:image/png;base64,...`). */
export const storeImageFromDataUrl = async (dataUrl: string): Promise<string> => {
  const match = DATA_URL_PATTERN.exec(dataUrl.trim());
  const base64 = (match?.[2] ?? '').replace(/\s+/g, '');
  if (!match || base64.length === 0) {
    throw new UploadError('La imagen debe enviarse como data URL base64 válida');
  }
  if (base64.length > Math.ceil((MAX_IMAGE_BYTES * 4) / 3) + 4) {
    throw new UploadError('La imagen supera el tamaño máximo de 5 MB');
  }
  return storeImageBuffer(Buffer.from(base64, 'base64'));
};

/** Valida que un enlace remoto sea http(s) y no apunte a la red interna del servidor. */
export const assertSupportedImageUrl = (value: string): URL => {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch {
    throw new UploadError('El enlace de la imagen no es una URL válida');
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new UploadError('El enlace de la imagen debe usar http o https');
  }
  const host = parsed.hostname.trim().toLowerCase();
  if (!host || PRIVATE_HOST_PATTERNS.some((pattern) => pattern.test(host))) {
    throw new UploadError('El enlace de la imagen no es accesible');
  }
  return parsed;
};

const downloadImage = (target: URL, redirectsLeft = MAX_REDIRECTS): Promise<Buffer> =>
  new Promise<Buffer>((resolve, reject) => {
    const getter = target.protocol === 'https:' ? httpsGet : httpGet;
    const request = getter(
      target,
      {
        headers: { accept: 'image/*', 'user-agent': 'booking_app/1.0 (image upload)' },
        timeout: DOWNLOAD_TIMEOUT_MS,
      },
      (response) => {
        const status = response.statusCode ?? 0;
        const location = response.headers.location;

        if (status >= 300 && status < 400 && location) {
          response.resume();
          if (redirectsLeft <= 0) {
            reject(new UploadError('El enlace de la imagen redirige demasiadas veces'));
            return;
          }
          try {
            resolve(downloadImage(assertSupportedImageUrl(new URL(location, target).toString()), redirectsLeft - 1));
          } catch (error) {
            reject(error instanceof UploadError ? error : new UploadError('El enlace de la imagen no es válido'));
          }
          return;
        }

        if (status !== 200) {
          response.resume();
          reject(new UploadError('No se pudo descargar la imagen del enlace indicado'));
          return;
        }

        const contentType = (String(response.headers['content-type'] ?? '').split(';')[0] ?? '')
          .trim()
          .toLowerCase();
        if (!contentType.startsWith('image/')) {
          response.resume();
          reject(new UploadError('El enlace no apunta a una imagen'));
          return;
        }

        const chunks: Buffer[] = [];
        let received = 0;
        response.on('data', (chunk: Buffer) => {
          received += chunk.length;
          if (received > MAX_IMAGE_BYTES) {
            response.destroy();
            reject(new UploadError('La imagen supera el tamaño máximo de 5 MB'));
            return;
          }
          chunks.push(chunk);
        });
        response.on('end', () => resolve(Buffer.concat(chunks)));
        response.on('error', () => reject(new UploadError('No se pudo descargar la imagen del enlace indicado')));
      },
    );

    request.on('timeout', () => {
      request.destroy();
      reject(new UploadError('La descarga de la imagen tardó demasiado'));
    });
    request.on('error', () => reject(new UploadError('No se pudo descargar la imagen del enlace indicado')));
  });

/** Descarga una imagen desde una URL pública y la guarda en el almacenamiento propio. */
export const storeImageFromUrl = async (value: string): Promise<string> => {
  const target = assertSupportedImageUrl(value.trim());
  const buffer = await downloadImage(target);
  return storeImageBuffer(buffer);
};

export const isStoredImageRef = (value: string): boolean =>
  value.startsWith(`${UPLOADS_ROUTE_PREFIX}/`);

/**
 * Normaliza la referencia de imagen recibida en un cuerpo JSON.
 * Devuelve `undefined` si el campo no viene, `''` para limpiar la imagen,
 * la referencia normalizada si es válida y `null` si es inválida.
 */
export const parseImageRef = (value: unknown): string | null | undefined => {
  if (value === undefined) return undefined;
  if (typeof value !== 'string') return null;
  const ref = value.trim();
  if (ref.length === 0) return '';
  if (ref.length > MAX_IMAGE_REF_LENGTH || /\s/.test(ref)) return null;
  if (isStoredImageRef(ref)) return ref;
  if (/^https?:\/\//i.test(ref)) return ref;
  return null;
};

/** Borra un archivo subido (solo rutas locales); ignora errores de archivos ausentes. */
export const removeStoredImage = async (value: string | null | undefined): Promise<void> => {
  const ref = value?.trim() ?? '';
  if (!isStoredImageRef(ref)) return;
  const fileName = ref.slice(UPLOADS_ROUTE_PREFIX.length + 1);
  if (!fileName || fileName.includes('/') || fileName.includes('\\') || fileName.startsWith('.')) return;
  await unlink(path.join(uploadsDirectory, fileName)).catch(() => undefined);
};
