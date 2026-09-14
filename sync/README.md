# reparto-sync

El sincronizador. Es lo que hace posible que un logístico trabaje sin conexión.

Diez logísticos, uno por sucursal. Por la mañana tienen conexión; durante el día, no.

## Tres trabajos

1. **Bajada por diferencias** — sólo lo que cambió desde la última vez, por sucursal. Sin
   esto, cada mañana se baja el mundo entero y en la conexión de allá eso no termina.
2. **Subida por lotes** — la cola del aparato entera, en orden, con la hora de cada apunte
   y clave de idempotencia. Contesta apunte por apunte: aplicado, repetido o rechazado con
   motivo.
3. **Registro de aparatos** — quién bajó, quién subió, qué le queda pendiente y qué se le
   rechazó. De aquí sale lo que hoy no existe: **ver que Palma lleva desde el martes sin
   subir**, y poder llamar.

## No es un intermediario

Los datos son de `reparto-api`. Esto reparte diferencias y recibe lotes; no es una segunda
verdad.

Protocolo: `../docs/`
