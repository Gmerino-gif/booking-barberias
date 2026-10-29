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

// PNG de 1x1 píxel: sirve para comprobar que el servidor valida el formato real
// del archivo (no confía en el mime declarado en el data URL).
const PNG_DATA_URL =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';

test('imágenes de negocio y de profesionales: permisos, validación y publicación', async () => {
  const owner = await register('owner', 'imagenes-negocio');
  const client = await register('client', 'imagenes-cliente');
  const origin = baseUrl.replace(/\/api$/, '');
  const { removeStoredImage } = await import('../dist/utils/uploads.js');

  // Permisos: la subida exige token y rol de negocio.
  assert.equal((await call('/uploads/image', {
    method: 'POST', body: { image: PNG_DATA_URL },
  })).status, 401);
  assert.equal((await call('/uploads/image', {
    method: 'POST', token: client.token, body: { image: PNG_DATA_URL },
  })).status, 403, 'Solo dueños y admin pueden subir imágenes');

  // Validación del contenido.
  assert.equal((await call('/uploads/image', {
    method: 'POST', token: owner.token, body: {},
  })).status, 400);
  assert.equal((await call('/uploads/image', {
    method: 'POST', token: owner.token, body: { image: 'data:image/png;base64,' },
  })).status, 400);
  const notAnImage = Buffer.from('esto no es una imagen').toString('base64');
  assert.equal((await call('/uploads/image', {
    method: 'POST', token: owner.token, body: { image: `data:image/png;base64,${notAnImage}` },
  })).status, 400, 'Debe validar el formato real del archivo, no el mime declarado');

  const logoUpload = await call('/uploads/image', {
    method: 'POST', token: owner.token, body: { image: PNG_DATA_URL },
  });
  assert.equal(logoUpload.status, 201, JSON.stringify(logoUpload.payload));
  const logoRef = logoUpload.payload.url;
  assert.match(logoRef, /^\/uploads\/[a-z0-9-]+\.png$/);

  const bannerUpload = await call('/uploads/image', {
    method: 'POST', token: owner.token, body: { image: PNG_DATA_URL },
  });
  assert.equal(bannerUpload.status, 201);
  const bannerRef = bannerUpload.payload.url;
  assert.notEqual(bannerRef, logoRef, 'Cada subida debe generar un archivo propio');

  const served = await fetch(`${origin}${logoRef}`);
  assert.equal(served.status, 200, 'La imagen subida debe servirse públicamente');
  assert.equal((served.headers.get('content-type') ?? '').split(';')[0], 'image/png');
  await served.arrayBuffer();

  const created = await call('/establishments', {
    method: 'POST', token: owner.token,
    body: {
      name: 'Barbería con imágenes', address: 'Calle 1 # 2-3', city: 'Barranquilla',
      description: 'Prueba de imágenes', phone: '3001234567', lat: 10.92, lng: -74.8,
    },
  });
  assert.equal(created.status, 201, JSON.stringify(created.payload));
  const establishmentId = String(created.payload.establishment._id ?? created.payload.establishment.id);

  const profileUpdate = await call('/establishments/me', {
    method: 'PUT', token: owner.token, body: { logo: logoRef, banner: bannerRef },
  });
  assert.equal(profileUpdate.status, 200, JSON.stringify(profileUpdate.payload));
  assert.equal(profileUpdate.payload.establishment.logo, logoRef);
  assert.equal(profileUpdate.payload.establishment.banner, bannerRef);

  const publicProfile = await call(`/establishments/${establishmentId}`);
  assert.equal(publicProfile.status, 200);
  assert.equal(publicProfile.payload.establishment.logo, logoRef,
    'El logo debe llegar a la vista pública que consume el cliente');

  const professional = await call('/professionals', {
    method: 'POST', token: owner.token,
    body: { name: 'Alex', specialty: 'Barbería', photo: bannerRef },
  });
  assert.equal(professional.status, 201, JSON.stringify(professional.payload));
  assert.equal(professional.payload.professional.photo, bannerRef);
  const listedProfessionals = await call(`/professionals/establishment/${establishmentId}`);
  assert.equal(listedProfessionals.status, 200);
  assert.ok(listedProfessionals.payload.professionals.some((item) => item.photo === bannerRef),
    'La foto debe exponerse en el listado público de profesionales');

  assert.equal((await call('/professionals', {
    method: 'POST', token: owner.token,
    body: { name: 'Sin formato', specialty: 'Barbería', photo: 'no-es-una-imagen' },
  })).status, 400, 'Debe rechazar referencias de imagen que no sean válidas');

  // Quitar la imagen borra el archivo anterior del disco.
  const cleared = await call('/establishments/me', {
    method: 'PUT', token: owner.token, body: { logo: '' },
  });
  assert.equal(cleared.status, 200);
  assert.equal(cleared.payload.establishment.logo, null);
  assert.equal((await fetch(`${origin}${logoRef}`)).status, 404,
    'Quitar la imagen debe borrar el archivo almacenado');

  await removeStoredImage(bannerRef);
});

test('reseña desde el historial: etiquetas, profesional y recálculo de promedios', async () => {
  const owner = await register('owner', 'resenas-negocio');
  const client = await register('client', 'resenas-cliente');
  const otherClient = await register('client', 'resenas-ajeno');

  const created = await call('/establishments', {
    method: 'POST', token: owner.token,
    body: {
      name: 'Barbería con reseñas', address: 'Calle 5 # 6-7', city: 'Barranquilla',
      description: 'Prueba de reseñas', phone: '3001234567', lat: 10.92, lng: -74.8,
    },
  });
  assert.equal(created.status, 201, JSON.stringify(created.payload));
  const establishmentId = String(created.payload.establishment._id ?? created.payload.establishment.id);

  const serviceResult = await call('/services', {
    method: 'POST', token: owner.token, body: { name: 'Degradado', price: 40000, durationMin: 30 },
  });
  assert.equal(serviceResult.status, 201, JSON.stringify(serviceResult.payload));
  const serviceId = serviceResult.payload.service._id;

  const professionalResult = await call('/professionals', {
    method: 'POST', token: owner.token, body: { name: 'Alex', specialty: 'Barbería' },
  });
  assert.equal(professionalResult.status, 201, JSON.stringify(professionalResult.payload));
  const professional = professionalResult.payload.professional;
  assert.equal(professional.rating, 0, 'Un profesional nuevo debe empezar sin calificación');
  assert.equal(professional.reviewCount, 0);

  const localTomorrow = new Date(Date.now() - 5 * 60 * 60 * 1000);
  localTomorrow.setUTCDate(localTomorrow.getUTCDate() + 1);
  const date = `${localTomorrow.getUTCFullYear()}-${String(localTomorrow.getUTCMonth() + 1).padStart(2, '0')}-${String(localTomorrow.getUTCDate()).padStart(2, '0')}`;
  const startAt = new Date(Date.UTC(localTomorrow.getUTCFullYear(), localTomorrow.getUTCMonth(), localTomorrow.getUTCDate(), 16));
  const availabilityQuery = new URLSearchParams({
    establishmentId, professionalId: professional._id,
    serviceId, date, utcOffsetMinutes: '-300',
  });
  const availability = await call(`/bookings/availability?${availabilityQuery}`);
  assert.equal(availability.status, 200, JSON.stringify(availability.payload));
  assert.ok(availability.payload.slots.includes(startAt.toISOString()));

  const bookingResult = await call('/bookings', {
    method: 'POST', token: client.token,
    body: {
      establishmentId, professionalId: professional._id,
      serviceId, startAt: startAt.toISOString(), utcOffsetMinutes: -300,
    },
  });
  assert.equal(bookingResult.status, 201, JSON.stringify(bookingResult.payload));
  const bookingId = String(bookingResult.payload.booking._id ?? bookingResult.payload.booking.id);

  const reviewBody = {
    bookingId, establishmentId, professionalId: professional._id,
    rating: 5, ratingProfessional: 4,
    tags: ['Excelente atención', 'Puntual'], comment: '',
  };

  // Sólo se califica un servicio terminado.
  assert.equal((await call('/reviews', {
    method: 'POST', token: client.token, body: reviewBody,
  })).status, 403, 'No debe calificarse una cita aún no completada');
  assert.equal((await call('/reviews', {
    method: 'POST', token: otherClient.token, body: reviewBody,
  })).status, 404, 'Otra persona no puede calificar una reserva ajena');

  // Validación de los datos de la reseña.
  assert.equal((await call('/reviews', {
    method: 'POST', token: client.token, body: { ...reviewBody, rating: 9 },
  })).status, 400);
  assert.equal((await call('/reviews', {
    method: 'POST', token: client.token, body: { ...reviewBody, comment: 'x'.repeat(501) },
  })).status, 400);
  assert.equal((await call('/reviews', {
    method: 'POST', token: client.token, body: { bookingId },
  })).status, 400, 'Debe exigir etiquetas, estrellas o comentario');

  // Completar el servicio habilita la reseña.
  const { Booking } = await import('../dist/models/Booking.js');
  await Booking.findByIdAndUpdate(bookingId, {
    startAt: new Date(Date.now() - 20 * 60 * 1000), endAt: new Date(Date.now() - 5 * 60 * 1000),
  });
  assert.equal((await call(`/bookings/${bookingId}/status`, {
    method: 'PATCH', token: owner.token, body: { status: 'completed' },
  })).status, 200);

  assert.equal((await call('/reviews', {
    method: 'POST', token: client.token,
    body: { ...reviewBody, professionalId: '000000000000000000000002' },
  })).status, 400, 'El profesional debe coincidir con el de la reserva');
  assert.equal((await call('/reviews', {
    method: 'POST', token: client.token,
    body: { ...reviewBody, establishmentId: '000000000000000000000003' },
  })).status, 400, 'El establecimiento debe coincidir con el de la reserva');

  const published = await call('/reviews', { method: 'POST', token: client.token, body: reviewBody });
  assert.equal(published.status, 201, JSON.stringify(published.payload));
  const review = published.payload.review;
  assert.deepEqual(review.tags, ['Excelente atención', 'Puntual']);
  assert.equal(review.rating, 5);
  assert.equal(review.ratingProfessional, 4);
  assert.equal(String(review.bookingId), bookingId, 'La reseña queda ligada a la cita');
  assert.equal(String(review.professionalId), String(professional._id));

  assert.equal((await call('/reviews', {
    method: 'POST', token: client.token, body: reviewBody,
  })).status, 409, 'Una cita sólo admite una reseña');

  // Los promedios se recalculan en el establecimiento y en el barbero.
  const ratedProfessional = (await call(`/professionals/establishment/${establishmentId}`))
    .payload.professionals.find((item) => String(item._id) === String(professional._id));
  assert.equal(ratedProfessional.rating, 4, 'El barbero debe reflejar las estrellas que recibió');
  assert.equal(ratedProfessional.reviewCount, 1);
  assert.equal((await call(`/establishments/${establishmentId}`)).payload.establishment.rating, 5);

  const myReviews = await call('/reviews/my', { token: client.token });
  assert.equal(myReviews.status, 200);
  const own = myReviews.payload.reviews.find((item) => String(item.bookingId) === bookingId);
  assert.ok(own, 'El historial del cliente debe reconocer la cita ya calificada');
  assert.equal(own.establishmentId.name, 'Barbería con reseñas');
  assert.equal(own.professionalId.name, 'Alex');

  const publicReviews = await call(`/reviews/establishment/${establishmentId}`);
  assert.equal(publicReviews.status, 200);
  const publicReview = publicReviews.payload.reviews.find((item) => String(item.bookingId) === bookingId);
  assert.equal(publicReview.professionalId.name, 'Alex',
    'La vista pública debe mostrar a qué barbero se calificó');
  assert.deepEqual(publicReview.tags, ['Excelente atención', 'Puntual']);

  // El panel del negocio recibe la reseña junto a la cita correspondiente.
  const businessView = await call('/bookings/business', { token: owner.token });
  assert.equal(businessView.status, 200);
  const reviewedBooking = businessView.payload.bookings.find((item) => item.id === bookingId);
  assert.ok(reviewedBooking, 'La cita debe aparecer en la agenda del negocio');
  assert.equal(reviewedBooking.review.rating, 5);
  assert.equal(reviewedBooking.review.ratingProfessional, 4);
  assert.deepEqual(reviewedBooking.review.tags, ['Excelente atención', 'Puntual']);

  // Eliminar la reseña devuelve los promedios a cero (no deja datos obsoletos).
  assert.equal((await call(`/reviews/${review._id}`, { method: 'DELETE', token: client.token })).status, 200);
  const resetProfessional = (await call(`/professionals/establishment/${establishmentId}`))
    .payload.professionals.find((item) => String(item._id) === String(professional._id));
  assert.equal(resetProfessional.rating, 0);
  assert.equal(resetProfessional.reviewCount, 0);
  assert.equal((await call(`/establishments/${establishmentId}`)).payload.establishment.rating, 0);
});
