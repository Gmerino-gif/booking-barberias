import cron, { type ScheduledTask } from 'node-cron';
import { Booking } from '../models/Booking.js';
import { sendPushToUser } from './push-notification.service.js';

const THREE_HOURS_MS = 3 * 60 * 60 * 1000;
const REMINDER_WINDOW_MS = 5 * 60 * 1000;
const CLAIM_LEASE_MS = 10 * 60 * 1000;
const REMINDER_BATCH_SIZE = 100;

interface ReminderWindow {
  lowerBound: Date;
  upperBound: Date;
}

export const getBookingReminderWindow = (now: Date): ReminderWindow => ({
  lowerBound: new Date(now.getTime() + THREE_HOURS_MS - REMINDER_WINDOW_MS),
  upperBound: new Date(now.getTime() + THREE_HOURS_MS),
});

export const formatBookingStart = (
  startAt: Date,
  timeZoneOffsetMinutes: number,
): string => {
  const localStartAt = new Date(
    startAt.getTime() + timeZoneOffsetMinutes * 60_000,
  );
  return new Intl.DateTimeFormat('es-CO', {
    timeZone: 'UTC',
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(localStartAt);
};

export const runBookingReminders = async (
  now: Date = new Date(),
): Promise<void> => {
  const window = getBookingReminderWindow(now);
  const staleClaimBefore = new Date(now.getTime() - CLAIM_LEASE_MS);
  const dueBookings = await Booking.find({
    status: 'confirmed',
    reminderSent: { $ne: true },
    startAt: { $gt: window.lowerBound, $lte: window.upperBound },
  })
    .select('_id clientId startAt timeZoneOffsetMinutes')
    .sort({ startAt: 1 })
    .limit(REMINDER_BATCH_SIZE)
    .lean();

  for (const dueBooking of dueBookings) {
    const claimedBooking = await Booking.findOneAndUpdate(
      {
        _id: dueBooking._id,
        status: 'confirmed',
        reminderSent: { $ne: true },
        startAt: { $gt: window.lowerBound, $lte: window.upperBound },
        $or: [
          { reminderClaimedAt: null },
          { reminderClaimedAt: { $lte: staleClaimBefore } },
        ],
      },
      { $set: { reminderClaimedAt: now } },
      { new: true },
    )
      .select('_id clientId startAt timeZoneOffsetMinutes')
      .lean();
    if (!claimedBooking) continue;

    try {
      const result = await sendPushToUser(claimedBooking.clientId.toString(), {
        title: 'Recordatorio de tu cita',
        body: `Te esperamos el ${formatBookingStart(
          claimedBooking.startAt,
          claimedBooking.timeZoneOffsetMinutes ?? 0,
        )}.`,
        data: {
          type: 'booking_reminder',
          bookingId: claimedBooking._id.toString(),
        },
      });

      if (result.successCount > 0) {
        const marked = await Booking.updateOne(
          {
            _id: claimedBooking._id,
            status: 'confirmed',
            reminderSent: { $ne: true },
          },
          {
            $set: { reminderSent: true, reminderSentAt: now },
            $unset: { reminderClaimedAt: 1 },
          },
        );
        if (marked.modifiedCount === 0) {
          await releaseReminderClaim(claimedBooking._id);
        }
      } else {
        await releaseReminderClaim(claimedBooking._id);
      }
    } catch (error) {
      console.error(
        `No se pudo enviar el recordatorio de la reserva ${claimedBooking._id}`,
        error,
      );
      await releaseReminderClaim(claimedBooking._id);
    }
  }
};

const releaseReminderClaim = async (
  bookingId: unknown,
): Promise<void> => {
  try {
    await Booking.updateOne(
      { _id: bookingId, reminderSent: { $ne: true } },
      { $unset: { reminderClaimedAt: 1 } },
    );
  } catch (error) {
    console.error(`No se pudo liberar el recordatorio de la reserva ${bookingId}`, error);
  }
};

let reminderTask: ScheduledTask | null = null;
let reminderRunInProgress = false;

export const startBookingReminderScheduler = (): void => {
  if (reminderTask) return;

  reminderTask = cron.schedule(
    '* * * * *',
    () => {
      if (reminderRunInProgress) return;
      reminderRunInProgress = true;
      void runBookingReminders()
        .catch((error: unknown) => {
          console.error('Falló la ejecución de recordatorios de reservas', error);
        })
        .finally(() => {
          reminderRunInProgress = false;
        });
    },
    { timezone: 'UTC' },
  );
  console.log('Cron de recordatorios de reservas iniciado');
};
