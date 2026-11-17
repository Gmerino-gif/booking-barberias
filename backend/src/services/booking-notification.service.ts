import { User } from '../models/User.js';
import { sendPushToUser } from './push-notification.service.js';

interface NewBookingNotificationInput {
  establishmentOwnerId: string;
  clientId: string;
  bookingId: string;
  startAt: Date;
  timeZoneOffsetMinutes: number;
  serviceName: string;
  professionalName: string;
}

export const notifyOwnerAboutNewBooking = async (
  input: NewBookingNotificationInput,
): Promise<void> => {
  const client = await User.findById(input.clientId).select('name');
  const clientName = client?.name ?? 'Un cliente';
  const localStartAt = new Date(
    input.startAt.getTime() + input.timeZoneOffsetMinutes * 60_000,
  );
  const formattedStartAt = new Intl.DateTimeFormat('es-CO', {
    timeZone: 'UTC',
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(localStartAt);

  await sendPushToUser(input.establishmentOwnerId, {
    title: 'Nueva reserva',
    body: `${clientName} reservó ${input.serviceName} con ${input.professionalName} para el ${formattedStartAt}.`,
    data: {
      type: 'new_booking',
      bookingId: input.bookingId,
    },
  });
};
