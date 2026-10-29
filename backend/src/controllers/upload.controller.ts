import type { Request, Response } from 'express';
import {
  UploadError,
  storeImageFromDataUrl,
  storeImageFromUrl,
} from '../utils/uploads.js';

/**
 * Sube una imagen de negocio (logo/banner) o de un profesional.
 *
 * Acepta dos formatos en el cuerpo JSON:
 *  - `{ "image": "data:image/png;base64,..." }` para subir bytes directamente.
 *  - `{ "url": "https://..." }` para que el servidor descargue la imagen y la
 *    almacene junto al resto de archivos subidos.
 *
 * Responde `{ url }` con la referencia persistible (`/uploads/archivo.png`).
 */
export const uploadImage = async (req: Request, res: Response): Promise<void> => {
  const body = req.body as Record<string, unknown> | null;
  const dataUrl =
    typeof body?.image === 'string'
      ? body.image
      : typeof body?.dataUrl === 'string'
        ? body.dataUrl
        : '';
  const remoteUrl = typeof body?.url === 'string' ? body.url.trim() : '';

  if (!dataUrl && !remoteUrl) {
    res.status(400).json({
      message: 'Envía la imagen como data URL base64 (`image`) o como enlace (`url`)',
    });
    return;
  }

  try {
    const url = dataUrl
      ? await storeImageFromDataUrl(dataUrl)
      : await storeImageFromUrl(remoteUrl);
    res.status(201).json({ message: 'Imagen subida correctamente', url });
  } catch (error) {
    if (error instanceof UploadError) {
      res.status(error.status).json({ message: error.message });
      return;
    }
    res.status(500).json({ message: 'No se pudo guardar la imagen' });
  }
};
