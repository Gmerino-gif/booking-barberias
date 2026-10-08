import assert from 'node:assert/strict';
import { once } from 'node:events';
import { after, before, test } from 'node:test';
import mongoose from 'mongoose';

const mongoUri = process.env.MONGODB_TEST_URI;
if (!mongoUri) {
  throw new Error('Define MONGODB_TEST_URI con una base aislada booking_app_test_<id> para ejecutar las pruebas de integración.');
}
const databaseName = decodeURIComponent(new URL(mongoUri).pathname.slice(1));
if (!/^booking_app_test_[a-z0-9_-]+$/i.test(databaseName)) {
  throw new Error('MONGODB_TEST_URI debe apuntar únicamente a una base booking_app_test_<id>; se rechazó para proteger otros datos.');
}

process.env.JWT_SECRET ??= 'integration-test-only-secret-at-least-32-chars';

const { default: app } = await import('../dist/app.js');
const { BookingSlotLock } = await import('../dist/models/BookingSlotLock.js');
let server;
let baseUrl;

before(async () => {
  await mongoose.connect(mongoUri, { serverSelectionTimeoutMS: 5000 });
  await BookingSlotLock.createIndexes();
  server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  baseUrl = `http://127.0.0.1:${address.port}/api`;
});

after(async () => {
  if (server) {
    server.closeAllConnections();
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
  if (mongoose.connection.readyState === 1) await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
});

async function call(path, { method = 'GET', token, body } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const payload = await response.json();
  return { status: response.status, payload };
}

async function register(role, suffix) {
  const result = await call('/auth/register', {
    method: 'POST',
    body: {
      name: `Prueba ${suffix}`,
      email: `${suffix}@example.test`,
      password: 'ClaveDePrueba123!',
      phone: '3001234567',
      role,
    },
  });
  assert.equal(result.status, 201, JSON.stringify(result.payload));
  return result.payload;
}

test('flujo integral negocio → servicio → reserva → reseña y límites de permisos', async () => {
  const owner = await register('owner', 'negocio');
  const client = await register('client', 'cliente');
  const concurrentClient = await register('client', 'cliente-paralelo');
  const otherOwner = await register('owner', 'otro-negocio');

  const establishmentInput = {
    name: 'Barbería de prueba', address: 'Calle 10 # 20-30', city: 'Barranquilla',
    description: 'Pruebas de integración', phone: '3001234567', lat: 10.92, lng: -74.8,
  };
  const establishmentResult = await call('/establishments', {
    method: 'POST', token: owner.token, body: establishmentInput,
  });
  assert.equal(establishmentResult.status, 201, JSON.stringify(establishmentResult.payload));
  const establishment = establishmentResult.payload.establishment;
  const establishmentId = String(establishment._id ?? establishment.id);
  const repeatedRegistration = await call('/establishments', {
    method: 'POST', token: owner.token, body: establishmentInput,
  });
  assert.equal(repeatedRegistration.status, 200);
  assert.equal(String(repeatedRegistration.payload.establishment.id), establishmentId);
  const discovery = await call('/establishments?q=Barbería%20de%20prueba');
  assert.equal(discovery.status, 200);
  assert.ok(discovery.payload.establishments.some((item) => String(item._id) === establishmentId));
  assert.equal((await call(`/establishments/${establishmentId}`)).status, 200);

  const serviceInput = {
    establishmentId: '000000000000000000000001',
    name: 'Corte clásico', description: 'Corte y acabado', price: 25000, durationMin: 30,
  };
  assert.equal((await call('/services', { method: 'POST', body: serviceInput })).status, 401);
  assert.equal((await call('/services', { method: 'POST', token: client.token, body: serviceInput })).status, 403);

  const serviceResult = await call('/services', { method: 'POST', token: owner.token, body: serviceInput });
  assert.equal(serviceResult.status, 201, JSON.stringify(serviceResult.payload));
  const service = serviceResult.payload.service;
  assert.equal(service.establishmentId, establishmentId, 'El servidor debe usar el establecimiento del propietario autenticado');

  const otherEstablishmentResult = await call('/establishments', {
    method: 'POST', token: otherOwner.token,
    body: { ...establishmentInput, name: 'Otro negocio', address: 'Carrera 1 # 2-3' },
  });
  assert.equal(otherEstablishmentResult.status, 201);
  const otherService = await call('/services', {
    method: 'POST', token: otherOwner.token,
    body: { name: 'Servicio ajeno', price: 10000, durationMin: 30 },
  });
  assert.equal(otherService.status, 201);
  assert.equal((await call(`/services/${otherService.payload.service._id}`, {
    method: 'PUT', token: owner.token,
    body: { name: 'Manipulado', price: 1, durationMin: 5 },
  })).status, 404, 'Un propietario no debe editar servicios de otro negocio');

  const updateResult = await call(`/services/${service._id}`, {
    method: 'PUT', token: owner.token,
    body: { name: 'Corte clásico actualizado', description: serviceInput.description, price: 27000, durationMin: 30 },
  });
  assert.equal(updateResult.status, 200);
  assert.equal(updateResult.payload.service.price, 27000);

  const professionalResult = await call('/professionals', {
    method: 'POST', token: owner.token,
    body: { name: 'Alex', specialty: 'Barbería', services: [service._id] },
  });
  assert.equal(professionalResult.status, 201, JSON.stringify(professionalResult.payload));
  const professional = professionalResult.payload.professional;

  const localTomorrow = new Date(Date.now() - 5 * 60 * 60 * 1000);
  localTomorrow.setUTCDate(localTomorrow.getUTCDate() + 1);
  const date = `${localTomorrow.getUTCFullYear()}-${String(localTomorrow.getUTCMonth() + 1).padStart(2, '0')}-${String(localTomorrow.getUTCDate()).padStart(2, '0')}`;
  const startAt = new Date(Date.UTC(localTomorrow.getUTCFullYear(), localTomorrow.getUTCMonth(), localTomorrow.getUTCDate(), 15));
  const query = new URLSearchParams({
    establishmentId, professionalId: professional._id,
    serviceId: service._id, date, utcOffsetMinutes: '-300',
  });
  const availability = await call(`/bookings/availability?${query}`);
  assert.equal(availability.status, 200, JSON.stringify(availability.payload));
  assert.ok(availability.payload.slots.includes(startAt.toISOString()), 'La hora seleccionada debe ofrecerse como disponible');

  const bookingBody = {
    establishmentId, professionalId: professional._id,
    serviceId: service._id, startAt: startAt.toISOString(), utcOffsetMinutes: -300,
  };
  const concurrentAttempts = await Promise.all([
    call('/bookings', { method: 'POST', token: client.token, body: bookingBody }),
    call('/bookings', { method: 'POST', token: concurrentClient.token, body: bookingBody }),
  ]);
  assert.deepEqual(concurrentAttempts.map((result) => result.status).sort(), [201, 409],
    'Dos solicitudes concurrentes para el mismo profesional y horario deben crear una sola reserva');
  const winningIndex = concurrentAttempts.findIndex((result) => result.status === 201);
  const bookingClientToken = winningIndex === 0 ? client.token : concurrentClient.token;
  const bookingResult = concurrentAttempts[winningIndex];
  const booking = bookingResult.payload.booking;
  assert.equal(booking.price, 27000);
  assert.equal((await call('/bookings', { method: 'POST', token: bookingClientToken, body: bookingBody })).status, 409);
  const availabilityAfterBooking = await call(`/bookings/availability?${query}`);
  assert.ok(!availabilityAfterBooking.payload.slots.includes(startAt.toISOString()));

  const clientBookings = await call('/bookings/my', { token: bookingClientToken });
  assert.equal(clientBookings.status, 200);
  assert.equal(clientBookings.payload.bookings.length, 1);
  const businessBookings = await call('/bookings/business', { token: owner.token });
  assert.equal(businessBookings.status, 200);
  assert.equal(businessBookings.payload.bookings.length, 1);
  assert.equal((await call(`/bookings/${booking._id}/status`, {
    method: 'PATCH', token: bookingClientToken, body: { status: 'confirmed' },
  })).status, 403, 'El cliente no debe confirmar su propia reserva');
  assert.equal((await call(`/bookings/${booking._id}/status`, {
    method: 'PATCH', token: owner.token, body: { status: 'confirmed' },
  })).status, 200);

  assert.equal((await call('/reviews', {
    method: 'POST', token: owner.token, body: { establishmentId, rating: 5, comment: 'Excelente' },
  })).status, 403, 'Los propietarios no deben publicar reseñas');
  assert.equal((await call('/reviews', {
    method: 'POST', token: bookingClientToken, body: { establishmentId, rating: 5, comment: 'Excelente' },
  })).status, 403, 'La reseña requiere una cita completada');

  const { Booking } = await import('../dist/models/Booking.js');
  await Booking.findByIdAndUpdate(booking._id, {
    startAt: new Date(Date.now() - 20 * 60 * 1000), endAt: new Date(Date.now() - 5 * 60 * 1000),
  });
  const completion = await call(`/bookings/${booking._id}/status`, {
    method: 'PATCH', token: owner.token, body: { status: 'completed' },
  });
  assert.equal(completion.status, 200, JSON.stringify(completion.payload));
  const review = await call('/reviews', {
    method: 'POST', token: bookingClientToken,
    body: { establishmentId, rating: 5, comment: 'Excelente servicio' },
  });
  assert.equal(review.status, 201, JSON.stringify(review.payload));
  assert.equal((await call('/reviews', {
    method: 'POST', token: bookingClientToken,
    body: { establishmentId, rating: 4, comment: 'Otra reseña' },
  })).status, 409);

  const secondStartAt = new Date(startAt.getTime() + 30 * 60 * 1000);
  const secondBooking = await call('/bookings', {
    method: 'POST', token: bookingClientToken,
    body: { ...bookingBody, startAt: secondStartAt.toISOString() },
  });
  assert.equal(secondBooking.status, 201, JSON.stringify(secondBooking.payload));
  const cancelled = await call(`/bookings/${secondBooking.payload.booking._id}/status`, {
    method: 'PATCH', token: bookingClientToken, body: { status: 'cancelled' },
  });
  assert.equal(cancelled.status, 200);
  const refreshedAvailability = await call(`/bookings/availability?${query}`);
  assert.ok(refreshedAvailability.payload.slots.includes(secondStartAt.toISOString()),
    'Cancelar la cita debe liberar el horario de nuevo');

  assert.equal((await call(`/services/${service._id}`, { method: 'DELETE', token: owner.token })).status, 409,
    'No debe eliminarse un servicio que conserve historial de reservas');
  const disposableService = await call('/services', {
    method: 'POST', token: owner.token,
    body: { name: 'Servicio temporal', price: 5000, durationMin: 15 },
  });
  assert.equal(disposableService.status, 201);
  assert.equal((await call(`/services/${disposableService.payload.service._id}`, {
    method: 'DELETE', token: owner.token,
  })).status, 200);
});
