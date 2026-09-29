import { model, Schema } from 'mongoose';

export const USER_ROLES = ['client', 'owner', 'professional', 'admin'] as const;
export type UserRole = (typeof USER_ROLES)[number];

const userSchema = new Schema(
  {
    name: { type: String, required: true, trim: true, minlength: 2, maxlength: 80 },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true, maxlength: 254 },
    passwordHash: { type: String, required: true, select: false },
    role: { type: String, required: true, enum: USER_ROLES, default: 'client' },
    phone: { type: String, trim: true },
    photoUrl: { type: String },
  },
  { timestamps: true },
);

export const User = model('User', userSchema);