# delivery-logistica

El reparto de Procovar, reconstruido. Tres piezas en un solo repositorio:

```
api/    Go       — las 35 rutas, los 11 modelos y la lógica de negocio
sync/   Go       — bajada por diferencias, subida por lotes, registro de aparatos
app/    Flutter  — la interfaz, única: se compila a web y a APK
docs/   el pliego, sacado del código de delivery
deploy/ los cinco Dockerfile y el nginx de la web
.github/workflows/  go.yml: comprueba que api/ y sync/ compilan y pasan las pruebas
```

**Los servicios los despliega Dokploy**, que clona y construye él con los Dockerfile de
`deploy/`. Aquí no se construye ninguna imagen: `go.yml` sólo comprueba, para que el Deploy
no se caiga después.

La aplicación se compila a mano: web y APK desde el portátil Linux, el `.exe` desde el
portátil Windows de Jose —Flutter no cruza de una plataforma a otra—. Las órdenes exactas
están en `docs/compilar.md`, y cómo le llega después una versión nueva a los diez aparatos
(con **la clave de firma del APK**, que hoy está mal) en `docs/actualizaciones.md`.

## Para qué

Diez logísticos, uno por sucursal, que arman las rutas de la suya. **Por la mañana tienen
conexión; durante el día, no.** Hoy eso significa que no pueden trabajar: sin red no abre
la página, no pueden entrar y no tienen datos.

El problema no es sincronizar. Es que la aplicación tiene que vivir en el aparato —el
código, la sesión y los datos—, y hoy las tres cosas viven en el servidor.

## `delivery` NO SE TOCA

El proyecto de Next se queda en pie, entero, hasta el final. Es dos cosas:

- **El pliego.** Dice qué hace cada pantalla, con qué filtros y contra qué endpoint. No hay
  que volver a decidir nada de eso: se lee y se copia.
- **El patrón.** Terminado aquí significa **da los mismos números que la de Next**. Las dos
  en pie a la vez y se comparan.

Se apaga al final, cuando los diez estén dentro y nadie la abra.

## Por qué se puede reconstruir entero

Delivery está construido pero **no está en uso** — el piloto de Santiago no se ha
encendido. Sin usuarios no hay nada que migrar, ni convivencia de dos versiones, ni
despliegue sucursal por sucursal, ni la obligación de que cada paso deje algo funcionando.
Se construye al lado y se enciende una vez.

Eso también deja el esquema libre: lo que en un sistema en marcha sería una migración
delicada aquí es escribirlo bien a la primera, empezando por el `updatedAt` que hoy falta
en 5 de los 11 modelos y sin el cual no hay bajada por diferencias posible.

## Las reglas que no se negocian

1. **Para entrar hace falta conexión. Una vez dentro, no.**
2. **Nunca esperar al servidor.** Todo se guarda en el aparato primero y se pinta hecho.
3. **Una sola renovación de sesión en vuelo** — dos a la vez y el servidor revoca todas las
   sesiones de la cuenta.
4. **Renovar antes de subir.**
5. **Un 401 mata la sesión. Un fallo de red, no.**
6. **Nada se descarta en silencio.**
7. **La hora es la del aparato.**
8. **Al cerrar sesión se borra lo local.**

Cada una está explicada en el README de la pieza a la que le toca.

## Pruebas

El criterio de terminado es **dar los mismos números que la de Next**, y por eso Next se
queda en pie hasta el final. Qué hay que probar y en qué orden de riesgo: `docs/pruebas.md`.
El *cómo* sale de la skill de QA, que está pendiente de Jose.

Plan completo: https://claude.ai/code/artifact/9ca0b1de-25a6-486d-87eb-6a6d85ac978f
