import { Booking } from '../models/Booking.js';
import { Professional } from '../models/Professional.js';
import { Service } from '../models/Service.js';

const BUSINESS_END_MINUTES = 18 * 60;
const SLOT_STARTS_MINUTES = [540, 600, 630, 660, 750, 840, 930, 960, 1050];

export type AvailabilityInput = {
  establishmentId: string;
  professionalId: string;
  serviceId: string;
  date: string;
  utcOffsetMinutes: number;
};

export const getAvailableSlots = async (input: AvailabilityInput): Promise<string[]> => {
  const [professional, service] = await Promise.all([
    Professional.findOne({ _id: input.professionalId, establishmentId: input.establishmentId }),
    Service.findOne({ _id: input.serviceId, establishmentId: input.establishmentId }),
  ]);

  if (!professional || !service) return [];
  if (professional.services.length > 0 && !professional.services.some((id) => id.toString() === input.serviceId)) return [];

  const dateParts = input.date.split('-').map(Number);
  const year = dateParts[0];
  const month = dateParts[1];
  const day = dateParts[2];
  if (year === undefined || month === undefined || day === undefined || month < 1 || month > 12 || day < 1 || day > 31) return [];
  if (new Date(Date.UTC(year, month - 1, day)).getUTCDate() !== day) return [];
  const localMidnightUtc = Date.UTC(year, month - 1, day) - input.utcOffsetMinutes * 60_000;
  const nextMidnightUtc = localMidnightUtc + 24 * 60 * 60_000;
  const dayStart = new Date(localMidnightUtc);
  const dayEnd = new Date(nextMidnightUtc);

  const bookings = await Booking.find({
    professionalId: input.professionalId,
    status: { $nin: ['cancelled', 'no_show'] },
    startAt: { $lt: dayEnd },
    endAt: { $gt: dayStart },
  }).select('startAt endAt');

  return SLOT_STARTS_MINUTES
    .filter((minutes) => minutes + service.durationMin <= BUSINESS_END_MINUTES)
    .map((minutes) => new Date(localMidnightUtc + minutes * 60_000))
    .filter((startAt) => startAt > new Date())
    .filter((startAt) => {
      const endAt = new Date(startAt.getTime() + service.durationMin * 60_000);
      return !bookings.some((booking) => booking.startAt < endAt && booking.endAt > startAt);
    })
    .map((startAt) => startAt.toISOString());
};
