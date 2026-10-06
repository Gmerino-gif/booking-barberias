import { model, Schema, Types } from 'mongoose';

const establishmentSchema = new Schema(
  {
    ownerId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    name: { type: String, required: true, trim: true, minlength: 2, maxlength: 100 },
    description: { type: String, trim: true, maxlength: 1000 },
    photos: [{ type: String }],
    address: { type: String, required: true, trim: true, maxlength: 200 },
    city: { type: String, required: true, trim: true, maxlength: 100 },
    phone: { type: String, required: true, trim: true, maxlength: 20 },
    rating: { type: Number, default: 0, min: 0, max: 5 },
    plan: { type: String, enum: ['free', 'pro', 'business'], default: 'free' },
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], required: true }, // [longitude, latitude]
    },
  },
  { timestamps: true },
);

establishmentSchema.index({ location: '2dsphere' });

export const Establishment = model('Establishment', establishmentSchema);