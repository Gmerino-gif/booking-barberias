import { model, Schema } from 'mongoose';

const reviewSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    establishmentId: { type: Schema.Types.ObjectId, ref: 'Establishment', required: true, index: true },
    rating: { type: Number, required: true, min: 1, max: 5 },
    comment: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

export const Review = model('Review', reviewSchema);