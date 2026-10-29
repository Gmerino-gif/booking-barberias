import { model, Schema } from 'mongoose';

export const MAX_REVIEW_TAGS = 6;
export const MAX_REVIEW_TAG_LENGTH = 40;

const reviewSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    establishmentId: { type: Schema.Types.ObjectId, ref: 'Establishment', required: true, index: true },
    // Cita que originó la reseña (opcional: las reseñas antiguas no la tienen).
    // Permite una reseña por servicio completado y calificar al profesional.
    bookingId: { type: Schema.Types.ObjectId, ref: 'Booking', index: true },
    professionalId: { type: Schema.Types.ObjectId, ref: 'Professional', index: true },
    // Calificación del establecimiento (1-5). Puede faltar si el cliente solo
    // dejó etiquetas rápidas o un comentario.
    rating: { type: Number, min: 1, max: 5 },
    // Calificación del profesional/barbero que atendió la cita (1-5).
    ratingProfessional: { type: Number, min: 1, max: 5 },
    // Etiquetas de opinión rápida elegidas por el cliente.
    tags: [{ type: String, trim: true, maxlength: MAX_REVIEW_TAG_LENGTH }],
    comment: { type: String, trim: true, maxlength: 500 },
  },
  { timestamps: true },
);

// Una sola reseña por cita; el índice parcial deja fuera las reseñas sin cita.
reviewSchema.index(
  { userId: 1, bookingId: 1 },
  { unique: true, partialFilterExpression: { bookingId: { $type: 'objectId' } } },
);
reviewSchema.index({ professionalId: 1, createdAt: -1 });

export const Review = model('Review', reviewSchema);
