import { model, Schema } from 'mongoose';

const favoriteSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    establishmentId: { type: Schema.Types.ObjectId, ref: 'Establishment', required: true, index: true },
  },
  { timestamps: true },
);

favoriteSchema.index({ userId: 1, establishmentId: 1 }, { unique: true });

export const Favorite = model('Favorite', favoriteSchema);