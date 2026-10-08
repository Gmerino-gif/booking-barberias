# Booking App

Aplicación Flutter para descubrir barberías y reservar citas. Incluye un backend Express, TypeScript y MongoDB.

## Ejecutar localmente

1. Instala Flutter y Node.js. Inicia MongoDB local.
2. En `backend`, copia `.env.example` a `.env`; configura `MONGODB_URI` y un `JWT_SECRET` aleatorio de al menos 32 bytes.
3. Ejecuta el backend:

   ```powershell
   cd backend
   npm ci
   npm run dev
   ```

4. Desde la raíz, instala y ejecuta la app:

   ```powershell
   flutter pub get
   flutter run
   ```

En modo debug, Android usa `10.0.2.2:3000` y otras plataformas usan `localhost:3000`. Para otro host local, compila/ejecuta con `--dart-define=API_BASE_URL=http://HOST:3000/api`.

## Validación

- App: `flutter analyze` y `flutter test`.
- Backend: `cd backend; npm test` compila y corre la prueba de integración del flujo de reserva.
- La prueba de backend requiere `MONGODB_TEST_URI` apuntando a una base aislada cuyo nombre empiece con `booking_app_test_`. La base se elimina al terminar. No apuntes esa variable a datos de desarrollo o producción.

## Producción

- Configura los secretos en el proveedor de despliegue; nunca subas `.env`.
- Usa `backend/.env.production.example` como lista de variables: `NODE_ENV=production`, `MONGODB_URI` con TLS, `JWT_SECRET` aleatorio de al menos 32 bytes, credenciales SMTP, `CORS_ORIGINS` con cada origen HTTPS exacto y `PORT` si el proveedor lo requiere.
- Genera el secreto JWT con `node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"` y guárdalo en el gestor de secretos del proveedor.
- Publica el backend detrás de HTTPS y comprueba `GET /api/health`.
- Compila cada plataforma con el dominio real del API:

  ```powershell
  flutter build appbundle --dart-define=API_BASE_URL=https://API_DOMINIO/api
  flutter build web --dart-define=API_BASE_URL=https://API_DOMINIO/api
  ```

  La app release valida `API_BASE_URL` al arrancar y rechaza URLs que no usen HTTPS.
- Android release requiere una llave propia: copia `android/key.properties.example` como `android/key.properties`, completa los valores y guarda el archivo y el keystore fuera de Git. iOS release requiere la firma y el equipo de Apple configurados en Xcode.
- Confirma que el `applicationId` de Android y el Bundle ID de iOS sean los identificadores definitivos antes de publicar la primera versión.
- Antes de invitar usuarios, define el dominio del API, crea la base y el usuario de MongoDB, configura el proveedor SMTP y prueba recuperación de contraseña desde un build de distribución. Esos recursos y credenciales son específicos de tu cuenta y no se pueden completar desde el repositorio.

## Alcance del MVP

El MVP reserva citas y registra el precio en la reserva; el pago se realiza en el local. No incluye cobro en línea ni notificaciones push. El estado de las citas se gestiona desde la agenda del negocio y las reseñas requieren una cita completada.
