import { model, Schema } from 'mongoose';

const professionalSchema = new Schema(
  {
    establishmentId: { type: Schema.Types.ObjectId, ref: 'Establishment', required: true, index: true },
    userId: { type: Schema.Types.ObjectId, ref: 'User' },
    name: { type: String, required: true, trim: true, minlength: 2, maxlength: 80 },
    specialty: { type: String, trim: true, maxlength: 100 },
    services: [{ type: Schema.Types.ObjectId, ref: 'Service' }],
  },
  { timestamps: true },
);

// IMPORTANTE: Asegúrate de que tenga "export"
export const Professional = model('Professional', professionalSchema);