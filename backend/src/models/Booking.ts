import { model, Schema, Types } from 'mongoose';

export const BOOKING_STATUSES = ['pending', 'confirmed', 'completed', 'cancelled', 'no_show'] as const;
export type BookingStatus = (typeof BOOKING_STATUSES)[number];

const bookingSchema = new Schema(
  {
    clientId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    establishmentId: { type: Schema.Types.ObjectId, ref: 'Establishment', required: true, index: true },
    professionalId: { type: Schema.Types.ObjectId, ref: 'Professional', required: true, index: true },
    serviceId: { type: Schema.Types.ObjectId, ref: 'Service', required: true },
    startAt: { type: Date, required: true },
    endAt: { type: Date, required: true },
    // Offset (en minutos) del cliente respecto a UTC al agendar la cita.
    // Permite reconstruir la hora local exacta que el usuario eligió.
    timeZoneOffsetMinutes: { type: Number, default: 0, min: -14 * 60, max: 14 * 60 },
    status: { type: String, enum: BOOKING_STATUSES, default: 'pending' },
    reminderSent: { type: Boolean, default: false, select: false },
    reminderSentAt: { type: Date, select: false },
    reminderClaimedAt: { type: Date, select: false },
    price: { type: Number, required: true, min: 0 },
    notes: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

bookingSchema.index({ establishmentId: 1, startAt: 1 });
bookingSchema.index({ professionalId: 1, startAt: 1 });
bookingSchema.index(
  { status: 1, reminderSent: 1, startAt: 1 },
  { name: 'due_booking_reminders' },
);

export const Booking = model('Booking', bookingSchema);