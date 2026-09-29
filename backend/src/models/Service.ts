import { model, Schema, Types } from 'mongoose';

const serviceSchema = new Schema(
  {
    establishmentId: { type: Schema.Types.ObjectId, ref: 'Establishment', required: true, index: true },
    name: { type: String, required: true, trim: true, minlength: 2, maxlength: 100 },
    description: { type: String, trim: true, maxlength: 500 },
    durationMin: { type: Number, required: true, min: 5, max: 480 },
    price: { type: Number, required: true, min: 0 },
    category: { type: String, trim: true },
  },
  { timestamps: true },
);

export const Service = model('Service', serviceSchema);