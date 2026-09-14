# reparto-api

La API de reparto, en Go. Sustituye a las 35 rutas de `delivery` (Next.js).

**No se toca `delivery`.** Ese proyecto se queda en pie, entero, hasta el final: es el
pliego —dice qué hace cada pantalla, con qué filtros y contra qué endpoint— y es el patrón
contra el que comparar. Terminado aquí significa **da los mismos números que la de Next**.

## Por qué se puede reconstruir entera

Delivery no está en uso: el piloto de Santiago no se ha encendido. Sin usuarios no hay nada
que migrar, ni convivencia, ni despliegue sucursal por sucursal, ni obligación de que cada
paso deje algo funcionando. Se construye al lado y se enciende una vez.

## Lo que hay que respetar

- **El alcance por sucursal es la regla de seguridad.** Quien pertenece a una sucursal ve
  sólo la suya. Va en la base del servicio, no repetido en cada endpoint.
- **Los mensajes de error son visibles y están en español.** Se conservan literales.
- **`updatedAt` en los 11 modelos.** Hoy sólo lo tienen 6. Sin esa marca no hay bajada por
  diferencias posible, y como no hay nada en producción esto no es una migración: es
  escribirlo bien a la primera.
- **Lo delicado se compara antes de darlo por bueno:** precios, cotización de domicilio y
  cuadre con Ventra. Ahí un error no revienta — da un número distinto y nadie se entera.

Plan completo: `../docs/`
