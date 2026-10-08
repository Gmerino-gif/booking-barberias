import { model, Schema } from 'mongoose';

const bookingSlotLockSchema = new Schema(
  {
    bookingId: { type: Schema.Types.ObjectId, ref: 'Booking', required: true, index: true },
    professionalId: { type: Schema.Types.ObjectId, ref: 'Professional', required: true },
    slotStartAt: { type: Date, required: true },
    expiresAt: { type: Date },
  },
  { timestamps: true },
);

bookingSlotLockSchema.index(
  { professionalId: 1, slotStartAt: 1 },
  { unique: true, name: 'one_active_booking_per_professional_slot' },
);
bookingSlotLockSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0, name: 'expire_orphaned_booking_locks' });

export const BookingSlotLock = model('BookingSlotLock', bookingSlotLockSchema);
