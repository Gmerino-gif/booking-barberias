import { Booking } from '../models/Booking.js';
import { Professional } from '../models/Professional.js';
import { Service } from '../models/Service.js';
import { Establishment } from '../models/Establishment.js';

const SLOT_INTERVAL_MINUTES = 30;

export type AvailabilityInput = {
  establishmentId: string;
  professionalId: string;
  serviceId: string;
  date: string;
  utcOffsetMinutes: number;
};

export const getAvailableSlots = async (input: AvailabilityInput): Promise<string[]> => {
  const [professional, service, establishment] = await Promise.all([
    Professional.findOne({ _id: input.professionalId, establishmentId: input.establishmentId }),
    Service.findOne({ _id: input.serviceId, establishmentId: input.establishmentId }),
    Establishment.findById(input.establishmentId).select('openingMinutes closingMinutes'),
  ]);

  if (!professional || !service || !establishment) return [];
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

  const openingMinutes = establishment.openingMinutes ?? 540;
  const closingMinutes = establishment.closingMinutes ?? 1080;
  const candidates: Date[] = [];
  for (let minutes = openingMinutes; minutes + service.durationMin <= closingMinutes; minutes += SLOT_INTERVAL_MINUTES) {
    candidates.push(new Date(localMidnightUtc + minutes * 60_000));
  }

  return candidates
    .filter((startAt) => startAt > new Date())
    .filter((startAt) => {
      const endAt = new Date(startAt.getTime() + service.durationMin * 60_000);
      return !bookings.some((booking) => booking.startAt < endAt && booking.endAt > startAt);
    })
    .map((startAt) => startAt.toISOString());
};
