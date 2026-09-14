# reparto-app

La interfaz, en Flutter. **Una sola**, compilada a web y a APK de Android, para que se vea
igual en los dos sitios.

## Las reglas que no se negocian

1. **Para entrar hace falta conexión. Una vez dentro, no.** No hay acceso sin conexión y no
   se intenta. Quien entró sigue trabajando aunque pase días sin señal.
2. **Nunca esperar al servidor.** Toda acción se guarda en el aparato primero y se pinta
   como hecha. La subida va por detrás. Con red se nota instantáneo; sin red, igual.
3. **Una sola renovación de sesión en vuelo.** El refresh es de un solo uso. Dos
   renovaciones a la vez presentan el mismo, el servidor lo lee como robo y **revoca todas
   las sesiones de la cuenta**. Aquí es más peligroso que en otros sitios: el teléfono
   recupera señal y dispara la cola entera de golpe.
4. **Renovar antes de subir.** Ocho horas sin conexión dejan el token de acceso caducado.
5. **Un 401 mata la sesión. Un fallo de red, no.**
6. **Nada se descarta en silencio.** Lo rechazado queda a la vista con su motivo y su hora.
7. **La hora es la del aparato.** Lo que se marca a las cuatro llega como las cuatro.
8. **Al cerrar sesión se borra lo local.** Quedan clientes con sus direcciones y los
   pedidos del día: si el aparato cambia de manos, eso no puede seguir ahí.

## De dónde sale cada pantalla

De `delivery` (Next.js), que no se toca. Terminado = hace lo mismo, con los mismos filtros
y los mismos números.

Pliego: `../docs/`
