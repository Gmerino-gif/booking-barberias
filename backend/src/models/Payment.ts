import { model, Schema } from 'mongoose';

export const PAYMENT_METHODS = ['wompi', 'manual_transfer'] as const;
export const PAYMENT_STATUSES = ['pending', 'approved', 'rejected'] as const;

const paymentSchema = new Schema(
  {
    establishment: {
      type: Schema.Types.ObjectId,
      ref: 'Establishment',
      required: true,
      index: true,
    },
    amount: { type: Number, required: true, min: 1 },
    method: { type: String, enum: PAYMENT_METHODS, required: true },
    status: { type: String, enum: PAYMENT_STATUSES, default: 'pending', index: true },
    reference: { type: String, required: true, unique: true, trim: true },
    wompiTransactionId: { type: String, trim: true },
    wompiPaymentLinkId: { type: String, trim: true, unique: true, sparse: true },
    receiptUrl: { type: String, trim: true },
    notes: { type: String, trim: true, maxlength: 1000 },
  },
  { timestamps: true },
);

paymentSchema.index({ establishment: 1, createdAt: -1 });

export const Payment = model('Payment', paymentSchema);
