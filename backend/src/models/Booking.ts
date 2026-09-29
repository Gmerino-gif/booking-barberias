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
    status: { type: String, enum: BOOKING_STATUSES, default: 'pending' },
    price: { type: Number, required: true, min: 0 },
    notes: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

bookingSchema.index({ establishmentId: 1, startAt: 1 });
bookingSchema.index({ professionalId: 1, startAt: 1 });

export const Booking = model('Booking', bookingSchema);