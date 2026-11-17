# Booking API

API REST Express + TypeScript + MongoDB. Para los comandos de desarrollo, configuración de entorno, integración de prueba y despliegue, consulta el [README del proyecto](../README.md).

## Comandos

- `npm run dev`: inicia el servidor de desarrollo con recarga.
- `npm run build`: compila TypeScript a `dist/`.
- `npm start`: inicia el backend compilado.
- `npm test`: compila y ejecuta el recorrido de integración sobre una base MongoDB aislada indicada por `MONGODB_TEST_URI`.

En producción el servidor valida MongoDB, un secreto JWT de al menos 32 bytes, SMTP y la lista explícita `CORS_ORIGINS` antes de escuchar conexiones. Firebase Admin usa Application Default Credentials, `GOOGLE_APPLICATION_CREDENTIALS` o el secreto `FIREBASE_SERVICE_ACCOUNT_JSON`; nunca guardes la clave de servicio en el repositorio. El servidor envía nuevas reservas al dueño del establecimiento y ejecuta recordatorios para clientes con reserva confirmada.
