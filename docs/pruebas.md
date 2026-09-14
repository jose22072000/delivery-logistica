# Pruebas

> **Pendiente de Jose: la skill de QA.** El *cómo* se prueba sale de ahí. Este documento
> deja escrito el *qué*, que es lo que no puede quedar al criterio de nadie.

## El criterio de terminado

> **Da los mismos números que la de Next.**

`delivery` se queda en pie hasta el final precisamente para esto: es el patrón. Las dos
aplicaciones contra los mismos datos, y se comparan. No es una opinión sobre si «parece
bien» — es una comparación.

---

## Lo que hay que probar, por orden de riesgo

### 1 · Los números (riesgo alto)

Aquí un error **no revienta**: da un número distinto y nadie se entera hasta que no cuadra
el inventario o un cliente reclama. Ya nos pasó este mes con las asignaciones.

- Precios y cotización de domicilio.
- Emparejado de productos y cuadre con Ventra.
- Armado de ruta: capacidad por peso, orden de visita, kilómetros desde el almacén.
- Los totales del post-despacho.

**Cómo:** la misma entrada contra Next y contra Go, y las dos salidas tienen que ser
idénticas. No «parecidas».

### 2 · El alcance por sucursal (riesgo alto, y es seguridad)

Un fallo aquí enseña los datos de una sucursal a otra, o —lo que ya pasó en producción con
un id de sucursal que no existía— **devuelve cero con un 200 y sin una sola traza**, que
desde dentro es indistinguible de «no hay nada todavía».

- Cada logístico ve sólo lo suyo, en las 35 rutas.
- Una sucursal que no existe no acota a cero: se comporta como «todas» y deja ver el
  problema.
- El Super Admin ve todas.

### 3 · La sincronización (riesgo alto)

- **Subir dos veces el mismo lote** no duplica nada. Se corta la conexión justo después de
  que el servidor guarde y antes de contestar, y se reintenta.
- **El orden se respeta:** marcar una parada y corregirla después deja puesta la corrección,
  no la primera marca.
- **El identificador provisional se sustituye** en todo lo que quedaba en la cola detrás.
  Armar una ruta sin red, cerrarla sin red, y subir las dos cosas juntas.
- **Lo rechazado no desaparece** y llega con su motivo.
- **La hora es la del aparato:** marcar a una hora, subir horas después, y comprobar qué
  hora le llegó a PEDIDO.

### 4 · La sesión (riesgo alto: deja a gente fuera)

- **El candado de una sola renovación.** Recuperar señal con veinte apuntes en la cola no
  puede lanzar veinte renovaciones. Si lo hace, el servidor revoca todas las sesiones de la
  cuenta y el logístico se queda fuera con el trabajo del día dentro.
- Un 401 manda al login. Un fallo de red o un 5xx **conservan** los tokens.
- Arrancar sin red con sesión guardada: entra.
- Arrancar sin red sin sesión: dice que hace falta conexión, no un error raro.

### 5 · Sin conexión, el día entero (riesgo medio)

La prueba que de verdad importa, y hay que hacerla como se vive:

```
con red     → abrir, que baje el día
sin red     → cerrar la aplicación, abrirla otra vez  ← aquí es donde se rompe
sin red     → preparar el tablero, armar una ruta, cerrarla
sin red     → apagar el aparato y encenderlo          ← y aquí
con red     → que suba solo, en orden y con las horas buenas
```

Los dos puntos marcados son los que distinguen «guarda en memoria» de «vive en el aparato».

### 6 · Las pantallas (riesgo bajo, pero es lo que se ve)

- Las 7, contra las de Next: mismas columnas, mismos filtros, mismos valores por defecto,
  misma paginación.
- Las etiquetas en español, **literales**.
- Cajones en móvil, modal en escritorio, y la ✕ que nunca desaparece.
- El post-despacho impreso: mismas columnas y mismos totales que el de Next.
- Que funcione en un teléfono de verdad, no sólo en el navegador encogido.
