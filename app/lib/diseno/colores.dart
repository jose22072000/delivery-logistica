import 'package:flutter/material.dart';

/// Los colores del pliego, con nombre y con motivo.
///
/// Son **los tokens de `delivery/src/app/globals.css`**, uno a uno. Estan aqui y
/// no sueltos por las pantallas por dos razones distintas:
///
/// 1. Los de marca (`primario`, `papel`, `tinta`, `linea`) son la identidad de
///    delivery. Si cada pantalla elige su azul, a los tres meses hay cuatro.
/// 2. Los semanticos (`ambar`, `verde`, `azul`, `rojo`) **significan algo** en
///    esta aplicacion: el ambar es «mira esto, puede que te este enganando». Si
///    cada pantalla elige su tono, deja de ser una senal y pasa a ser decoracion.
///
/// El tema que los reparte esta en `tema.dart`.
abstract final class Colores {
  // ─── La marca. `globals.css :root` ─────────────────────────────────────────

  /// `--primary: #1F4FE0`. El azul de delivery. **No es el indigo de Material**:
  /// el de antes (`#4F46E5`) era la semilla de un `ColorScheme.fromSeed`, que se
  /// inventaba una paleta morada y pintaba de lila la mitad de la aplicacion.
  static const primario = Color(0xFF1F4FE0);

  /// El primario al 8 %, sobre papel. Es el fondo de la entrada activa del menu
  /// y de la opcion elegida de un selector (`bg-primary/[0.08]`).
  static const primarioTenue = Color(0xFFE9EDFC);

  /// El primario aclarado, para lo que va encima de tinta.
  static const primarioClaro = Color(0xFFAFC1F5);

  /// `--secondary: #0E9F6E`. El verde del dinero cobrado.
  static const secundario = Color(0xFF0E9F6E);

  /// `--accent: #E8820C`. El naranja de la flota.
  static const acento = Color(0xFFE8820C);

  /// `--paper: #F7F4EF`. EL FONDO. Es papel calido, no el `#F9FAFB` azulado de
  /// Material: es lo primero que se ve y lo primero que delata que una pantalla
  /// no es la de delivery.
  static const papel = Color(0xFFF7F4EF);

  /// `--paper-2: #FFFFFF`. El de las tarjetas, la barra lateral y el cajon.
  static const blanco = Color(0xFFFFFFFF);

  /// `--ink: #17130E`. El texto. Tinta calida, nunca negro.
  static const tinta = Color(0xFF17130E);

  /// `--ink-soft: #5C544A`. Lo secundario: subtextos, etiquetas, notas.
  static const tintaSuave = Color(0xFF5C544A);

  /// `--line: #E8E2D7`. EL BORDE FINO de 1 px que llevan todas las tarjetas.
  /// En el `globals.css` esta puesto a mano sobre cada `.bg-white.rounded-2xl`
  /// justamente para que no falte en ninguna.
  static const linea = Color(0xFFE8E2D7);

  /// La misma linea, un punto mas marcada: el borde de una casilla vacia, que
  /// con `linea` a secas no se ve sobre blanco.
  static const lineaFuerte = Color(0xFFCFC7BA);

  // ─── Los semanticos ────────────────────────────────────────────────────────

  /// AMBAR = atencion. Lo usan: datos de mas de un dia, pedidos sin ruta,
  /// rutas `planned`, capacidad al 80 % y los informes que no estan al dia.
  /// El tono sale del `--accent`, oscurecido hasta que se lee sobre su fondo.
  static const ambar = Color(0xFF96560A);
  static const ambarFondo = Color(0xFFFBEEDA);

  /// VERDE = cerrado, cobrado, entregado. Es el `--secondary` oscurecido; el
  /// `#0E9F6E` de marca se queda para las cifras grandes, donde si contrasta.
  static const verde = Color(0xFF0B7A55);
  static const verdeFondo = Color(0xFFDCF2E8);

  /// AZUL = en marcha. Es el propio `--primary`: lo que esta en curso es lo
  /// normal de esta aplicacion, y por eso lleva su color.
  static const azul = primario;
  static const azulFondo = Color(0xFFE1E8FD);

  /// ROJO = rechazado o pasado de capacidad. No es lo mismo que ambar: el ambar
  /// avisa, el rojo impide.
  static const rojo = Color(0xFFB3261E);
  static const rojoFondo = Color(0xFFFBE4E1);

  /// GRIS = lo normal, lo que no hay que mirar. Es `--ink-soft`, o sea un gris
  /// CALIDO: un gris azulado sobre papel crema se ve sucio.
  static const gris = tintaSuave;
  static const grisFondo = Color(0xFFF0EBE3);

  // ─── Los nombres de siempre ────────────────────────────────────────────────
  // Se quedan como alias porque los leen cuarenta y pico sitios y renombrarlos
  // no cambia ni un pixel. Lo que cambia es a que apuntan.

  /// El borde fino. Alias de [linea].
  static const borde = linea;

  /// El fondo de la aplicacion. Alias de [papel].
  static const fondo = papel;
}
