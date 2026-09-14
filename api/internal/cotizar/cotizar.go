// LAS FÓRMULAS DE LA COTIZACIÓN, SEPARADAS DE HTTP.
//
// POR QUÉ ESTE PAQUETE EXISTE Y NO VIVE DENTRO DEL MANEJADOR: aquí un error no revienta
// —da un número distinto— y nadie se entera hasta que no cuadra la caja. Un número sólo
// se puede vigilar si se puede probar solo, con una tabla de entradas y salidas, sin
// levantar un servidor ni una base de datos. Todo lo de este paquete es una función pura:
// mismas entradas, mismo número, siempre.
//
// EL CRITERIO DE TERMINADO ES DAR EL MISMO NÚMERO QUE LA APLICACIÓN DE NEXT, no el número
// que parezca correcto. Por eso hay aquí dentro cosas que en Go se escribirían de otra
// manera —el `+ Number.EPSILON` del redondeo, el `Number()` que convierte `null` en 0, el
// desempate del vecino más próximo— y no se «arreglan»: arreglarlas es volver a tener dos
// números para lo mismo, que es justo el fallo que esta reescritura viene a cerrar.
//
// Fuente: `../../../docs/reglas-negocio.md` §1 (geometría), §2 (pesos), §7 (domicilio),
// §8 (tasa), §9 (geocodificación) y el apéndice de constantes.
package cotizar

// RadioTierraKm es el radio terrestre que usan `pricing.ts` y `domicilioEntrega.ts`.
// Es el MISMO en los dos sitios (apéndice de constantes): cambiarlo en uno solo movería
// los kilómetros del camión sin mover los del cobro, o al revés.
const RadioTierraKm = 6371.0

// EpsilonJS es el `Number.EPSILON` de JavaScript: 2^-52.
//
// Se suma antes de redondear importes (§7). NO es una corrección cosmética: empuja los
// casos de medio exacto que la coma flotante deja justo por debajo (el clásico `1.005`,
// que en binario es 1.00499999999999989...). Sin él, `redondear(1.005, 2)` da 1.00 en vez
// de 1.01, y ese céntimo, multiplicado por los domicilios de un mes, es el descuadre.
const EpsilonJS = 2.220446049250313e-16
