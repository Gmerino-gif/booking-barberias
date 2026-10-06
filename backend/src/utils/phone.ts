export const isValidPhoneNumber = (value: string): boolean => {
  const digits = value.replace(/\D/g, '');
  return (
    value.length <= 20 &&
    /^\+?[0-9\s().-]+$/.test(value) &&
    digits.length >= 7 &&
    digits.length <= 15
  );
};
