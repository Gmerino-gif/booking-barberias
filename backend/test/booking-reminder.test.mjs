import assert from 'node:assert/strict';
import { test } from 'node:test';

const { Booking } = await import('../dist/models/Booking.js');
const { getBookingReminderWindow } = await import('../dist/services/booking-reminder.service.js');

test('el recordatorio se programa dentro de los cinco minutos previos a cumplir tres horas', () => {
  const now = new Date('2026-11-17T03:00:00.000Z');
  const window = getBookingReminderWindow(now);

  assert.equal(window.lowerBound.toISOString(), '2026-11-17T05:55:00.000Z');
  assert.equal(window.upperBound.toISOString(), '2026-11-17T06:00:00.000Z');
});

test('las reservas incluyen estado persistente para evitar recordatorios duplicados', () => {
  assert.equal(Booking.schema.path('reminderSent')?.defaultValue, false);
});
