/**
 * Reglas de antelación para cancelar o reprogramar una cita.
 *
 * El establecimiento guarda cuántas horas antes del inicio se permite cada
 * acción (`0` = sin límite). Estas funciones concentran la lectura, la
 * comparación con la hora actual y el mensaje que ve el cliente, para que el
 * backend y la app describan la misma regla.
 */

/** Valor por defecto si el establecimiento aún no guardó la ventana. */
export const DEFAULT_RESCHEDULE_WINDOW_HOURS = 4;

/** Valor por defecto si el establecimiento aún no guardó la ventana. */
export const DEFAULT_CANCELLATION_WINDOW_HOURS = 2;

/** Tope de horas antes de la cita para reprogramar/cancelar (7 días). */
export const MAX_WINDOW_HOURS = 168;

const HOUR_MS = 60 * 60 * 1000;

export type BookingWindowAction = 'cancel' | 'reschedule';

export type BookingWindowSettings = {
  rescheduleWindowHours: number;
  cancellationWindowHours: number;
};

/** Horas de un establecimiento (o de su ausencia) ya normalizadas. */
type EstablishmentWindowSource = {
  rescheduleWindowHours?: unknown;
  cancellationWindowHours?: unknown;
} | null | undefined;

/** Normaliza un valor guardado: entero entre 0 y `MAX_WINDOW_HOURS`. */
export const normalizeWindowHours = (value: unknown, fallback: number): number => {
  if (value === null || value === undefined || value === '') return fallback;
  const hours = Number(value);
  if (!Number.isFinite(hours) || hours < 0) return fallback;
  return Math.min(Math.round(hours), MAX_WINDOW_HOURS);
};

/** Ventanas efectivas de un establecimiento (0 = sin límite). */
export const readBookingWindows = (
  establishment: EstablishmentWindowSource,
): BookingWindowSettings => ({
  rescheduleWindowHours: normalizeWindowHours(
    establishment?.rescheduleWindowHours,
    DEFAULT_RESCHEDULE_WINDOW_HOURS,
  ),
  cancellationWindowHours: normalizeWindowHours(
    establishment?.cancellationWindowHours,
    DEFAULT_CANCELLATION_WINDOW_HOURS,
  ),
});

/** Hora límite de la acción; `null` cuando no hay límite (0 horas). */
export const bookingWindowDeadline = (startAt: Date, windowHours: number): Date | null =>
  windowHours > 0 ? new Date(startAt.getTime() - windowHours * HOUR_MS) : null;

/** `true` mientras la cita siga dentro de la ventana permitida. */
export const isBookingWindowOpen = (
  startAt: Date,
  windowHours: number,
  now: Date = new Date(),
): boolean => {
  const deadline = bookingWindowDeadline(startAt, windowHours);
  return deadline === null || now.getTime() < deadline.getTime();
};

/** "4 horas" / "1 hora", para los mensajes al cliente. */
export const formatWindowHours = (windowHours: number): string =>
  windowHours === 1 ? '1 hora' : `${windowHours} horas`;

/** Mensaje legible que explica por qué la acción ya no está disponible. */
export const describeClosedWindow = (
  action: BookingWindowAction,
  windowHours: number,
): string => {
  const limit = formatWindowHours(windowHours);
  return action === 'cancel'
    ? `Ya no puedes cancelar esta cita: el negocio permite cancelar hasta ${limit} antes del inicio. Contacta al negocio si necesitas ayuda.`
    : `Ya no puedes reprogramar esta cita: el negocio permite reprogramar hasta ${limit} antes del inicio. Contacta al negocio si necesitas ayuda.`;
};

/** Ventana que aplica a cada acción. */
export const windowHoursForAction = (
  windows: BookingWindowSettings,
  action: BookingWindowAction,
): number => (action === 'cancel' ? windows.cancellationWindowHours : windows.rescheduleWindowHours);
