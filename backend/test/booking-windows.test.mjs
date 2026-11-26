import test from 'node:test';
import assert from 'node:assert/strict';

import {
  bookingWindowDeadline,
  describeClosedWindow,
  formatWindowHours,
  isBookingWindowOpen,
  normalizeWindowHours,
  readBookingWindows,
  windowHoursForAction,
} from '../dist/utils/booking-windows.js';

const HOUR_MS = 60 * 60 * 1000;

test('normalizeWindowHours cae al valor por defecto cuando no hay dato válido', () => {
  assert.equal(normalizeWindowHours(undefined, 4), 4);
  assert.equal(normalizeWindowHours(null, 2), 2);
  assert.equal(normalizeWindowHours('', 2), 2);
  assert.equal(normalizeWindowHours('abc', 2), 2);
  assert.equal(normalizeWindowHours(-3, 2), 2);
});

test('normalizeWindowHours acepta 0 (sin límite), redondea y respeta el tope', () => {
  assert.equal(normalizeWindowHours(0, 4), 0);
  assert.equal(normalizeWindowHours('6', 4), 6);
  assert.equal(normalizeWindowHours(2.4, 4), 2);
  assert.equal(normalizeWindowHours(500, 4), 168);
});

test('readBookingWindows usa los valores por defecto del negocio', () => {
  assert.deepEqual(readBookingWindows(null), {
    rescheduleWindowHours: 4,
    cancellationWindowHours: 2,
  });
  assert.deepEqual(readBookingWindows({ rescheduleWindowHours: 0, cancellationWindowHours: 12 }), {
    rescheduleWindowHours: 0,
    cancellationWindowHours: 12,
  });
});

test('bookingWindowDeadline no existe cuando la ventana es 0', () => {
  const startAt = new Date(Date.now() + 10 * HOUR_MS);
  assert.equal(bookingWindowDeadline(startAt, 0), null);
  assert.equal(
    bookingWindowDeadline(startAt, 4)?.toISOString(),
    new Date(startAt.getTime() - 4 * HOUR_MS).toISOString(),
  );
});

test('isBookingWindowOpen respeta la ventana y el valor 0', () => {
  const now = new Date('2026-03-10T12:00:00.000Z');
  const inTwoHours = new Date(now.getTime() + 2 * HOUR_MS);
  const inTenHours = new Date(now.getTime() + 10 * HOUR_MS);

  assert.equal(isBookingWindowOpen(inTenHours, 4, now), true);
  assert.equal(isBookingWindowOpen(inTwoHours, 4, now), false);
  // 0 = sin límite: la acción sigue abierta incluso minutos antes.
  assert.equal(isBookingWindowOpen(new Date(now.getTime() + 60_000), 0, now), true);
  // Justo en el límite ya está cerrada.
  assert.equal(isBookingWindowOpen(new Date(now.getTime() + 4 * HOUR_MS), 4, now), false);
});

test('los mensajes explican el límite de cada acción', () => {
  assert.equal(formatWindowHours(1), '1 hora');
  assert.equal(formatWindowHours(3), '3 horas');

  const cancelMessage = describeClosedWindow('cancel', 2);
  assert.match(cancelMessage, /cancelar/);
  assert.match(cancelMessage, /2 horas/);

  const rescheduleMessage = describeClosedWindow('reschedule', 1);
  assert.match(rescheduleMessage, /reprogramar/);
  assert.match(rescheduleMessage, /1 hora/);
});

test('windowHoursForAction elige la ventana correcta', () => {
  const windows = { rescheduleWindowHours: 6, cancellationWindowHours: 2 };
  assert.equal(windowHoursForAction(windows, 'cancel'), 2);
  assert.equal(windowHoursForAction(windows, 'reschedule'), 6);
});
