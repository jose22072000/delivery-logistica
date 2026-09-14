# El pliego

Todo lo que hace falta saber para reconstruir el reparto **sin abrir el repositorio de
Next**. Sacado del código de `delivery`, que se queda en pie hasta el final como patrón.

| Documento | Qué hay dentro | De dónde sale |
|---|---|---|
| `modelo-datos.md` | Los 11 modelos con todos sus campos, las relaciones, los 10 pseudo-enums y los campos calculados | `prisma/schema.prisma` + `src/` |
| `contratos-api.md` | Las 35 rutas: parámetros, cuerpos, respuestas y los mensajes de error **literales** | `src/app/api/**` |
| `reglas-negocio.md` | Las 15 reglas con sus fórmulas, constantes y casos límite | `src/lib/` + el armado de ruta |
| `pantallas.md` | Las 7 pantallas, la navegación, los componentes y **qué sale impreso** | `src/app/(dashboard)/` + `src/components/` |
| `sincronizacion.md` | El protocolo entre la aplicación y el sincronizador | diseño nuevo |
| `identidad.md` | Entrar, renovar y trabajar sin conexión | diseño nuevo, patrón de `call-center-board` |
| `pruebas.md` | El guion de QA del dominio | diseño nuevo, método de `qa-como-usuario` |

Los cuatro primeros describen **lo que ya existe** y no hay que volver a decidir: se leen y
se copian. Los tres últimos son **lo que hay que decidir bien**, porque no existe todavía.

## Dos cosas que salieron al escribir esto y hay que resolver

- **`Vehicle.type` es un conjunto abierto.** No hay catálogo declarado en ninguna parte, así
  que en Go no se puede cerrar el tipo sin decidir antes cuáles son los valores válidos.
- **`updatedAt` falta en 5 de los 11 modelos.** Sin esa marca no hay bajada por diferencias.
  Ver el apartado 4 de `modelo-datos.md`.
