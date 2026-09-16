/// EL SISTEMA VISUAL DE DELIVERY, traido tal cual desde la de Next.
///
/// La fuente de verdad es `delivery/src/app/globals.css` y
/// `delivery/tailwind.config.js`. Los numeros de aqui **no son gustos**: son los
/// mismos tokens, convertidos de `rem` a pixeles logicos (1 rem = 16 px).
///
/// El motivo de que exista este fichero es concreto: antes el tema salia de
/// `ColorScheme.fromSeed(seedColor: indigo)`, que se inventa una paleta morada
/// de Material y pinta fondos lilas en los botones, en los menus y en los
/// cajones. Jose abrio la aplicacion desplegada y lo primero que dijo fue «muy
/// cambiado a como esta el de Next». Lo estaba: era otra aplicacion.
///
/// Aqui no hay `fromSeed`. Cada rol del `ColorScheme` esta escrito a mano con el
/// token que le toca.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colores.dart';

/// Los radios del `tailwind.config.js` de delivery, en pixeles.
///
/// `xl: 0.85rem` y `2xl: 1.15rem` estan ahi sobrescritos a proposito: los de
/// Tailwind por defecto (12 y 16) se ven mas duros. Las tarjetas usan `2xl`, los
/// botones y los campos `xl`.
abstract final class Radios {
  /// Lo pequeno: las insignias cuadradas, los chips de una tabla.
  static const double sm = 8;

  /// Los botones de paginacion y los campos dentro de un menu.
  static const double md = 10;

  /// `rounded-xl` — botones, selectores, entradas del menu lateral.
  static const double lg = 13.6;

  /// `rounded-2xl` — LAS TARJETAS. Es el radio que mas se ve.
  static const double xl = 18.4;

  /// `rounded-full`, para las insignias de estado.
  static const double pastilla = 999;
}

/// Las sombras del `tailwind.config.js`. Todas tiran a la tinta calida
/// (`rgba(23,19,14,·)`), nunca al negro puro: sobre el papel `#F7F4EF` una
/// sombra negra se ve gris sucio y es lo que hace que una pantalla parezca de
/// Material por defecto.
abstract final class Sombras {
  static final List<BoxShadow> sm = [
    BoxShadow(
      color: Colores.tintaCon(0.05),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// `shadow-md` — la de las tarjetas del panel.
  static final List<BoxShadow> md = [
    BoxShadow(
      color: Colores.tintaCon(0.10),
      blurRadius: 20,
      spreadRadius: -6,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Colores.tintaCon(0.06),
      blurRadius: 6,
      spreadRadius: -2,
      offset: Offset(0, 2),
    ),
  ];

  /// `shadow-lg` — la tarjeta con el raton encima.
  static final List<BoxShadow> lg = [
    BoxShadow(
      color: Colores.tintaCon(0.14),
      blurRadius: 36,
      spreadRadius: -10,
      offset: Offset(0, 16),
    ),
    BoxShadow(
      color: Colores.tintaCon(0.08),
      blurRadius: 10,
      spreadRadius: -4,
      offset: Offset(0, 4),
    ),
  ];

  /// `shadow-2xl` — el cajon lateral y los menus flotantes.
  static final List<BoxShadow> xl = [
    BoxShadow(
      color: Colores.tintaCon(0.20),
      blurRadius: 56,
      spreadRadius: -14,
      offset: Offset(0, 28),
    ),
  ];
}

/// El aire. Delivery respira en multiplos de 4, y las pantallas grandes usan 24
/// (`p-6`) donde el telefono usa 12 (`p-3`).
abstract final class Aire {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Las tres tipografias REALES de delivery (`src/app/layout.tsx`).
///
/// Los `.ttf` estan embebidos en `assets/google_fonts/`, asi que
/// `allowRuntimeFetching` se apaga: esto se abre en el patio de un almacen y una
/// tipografia que se baja por red es una pantalla que sale con otra letra.
abstract final class Tipos {
  /// Bricolage Grotesque. Los titulos y las cifras grandes.
  static TextStyle display({
    double? tamano,
    FontWeight peso = FontWeight.w700,
    Color? color,
    double? interletra,
    double? alto,
  }) => GoogleFonts.bricolageGrotesque(
    fontSize: tamano,
    fontWeight: peso,
    color: color,
    // `letter-spacing: -0.018em` del `globals.css`, en pixeles.
    letterSpacing: interletra ?? (tamano == null ? null : -0.018 * tamano),
    height: alto,
  );

  /// Hanken Grotesk. Todo el texto corrido.
  static TextStyle texto({
    double? tamano,
    FontWeight peso = FontWeight.w400,
    Color? color,
    double? interletra,
    double? alto,
  }) => GoogleFonts.hankenGrotesk(
    fontSize: tamano,
    fontWeight: peso,
    color: color,
    letterSpacing: interletra,
    height: alto,
  );

  /// JetBrains Mono, **con cifras de ancho fijo**.
  ///
  /// Lo de `tabular-nums` no es un adorno: los folios, los kilos y los importes
  /// van en columna, y con cifras de ancho variable el `1` es mas estrecho que
  /// el `8` y las unidades dejan de estar alineadas entre filas.
  static TextStyle mono({
    double? tamano,
    FontWeight peso = FontWeight.w500,
    Color? color,
    double? alto,
  }) => GoogleFonts.jetBrainsMono(
    fontSize: tamano,
    fontWeight: peso,
    color: color,
    height: alto,
    letterSpacing: tamano == null ? null : -0.01 * tamano,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Cifras de ancho fijo **sin cambiar de familia**: para los numeros que van
  /// dentro de un texto normal o de una cifra de titular.
  static const List<FontFeature> cifrasEnColumna = [
    FontFeature.tabularFigures(),
  ];
}

/// La escala de texto, con los tamanos que usa delivery de verdad.
///
/// Los nombres son los de Material porque es lo que leen los widgets
/// (`textTheme.titleMedium`), pero lo que hay dentro sale de la de Next:
///
///   displaySmall   2.1rem w800  la cifra de una tarjeta del panel
///   headlineSmall  1.5rem w700  los titulares de una pantalla
///   titleLarge     1.4rem w700  el titulo de la barra superior
///   titleMedium    1.125rem w700  el titulo de un cajon y de una tarjeta
///   titleSmall     0.95rem w700  la cabecera de una tabla
///   bodyMedium     0.875rem w400  `text-sm`, el tamano por defecto de todo
///   bodySmall      0.75rem w400  `text-xs`, las notas
///   labelSmall     0.6875rem w600 `text-[11px]`, las insignias
TextTheme _escala() => TextTheme(
  displayLarge: Tipos.display(tamano: 44, peso: FontWeight.w800, alto: 1.05),
  displayMedium: Tipos.display(tamano: 38, peso: FontWeight.w800, alto: 1.05),
  displaySmall: Tipos.display(tamano: 33.6, peso: FontWeight.w800, alto: 1),
  headlineLarge: Tipos.display(tamano: 30, peso: FontWeight.w700, alto: 1.1),
  headlineMedium: Tipos.display(tamano: 26, peso: FontWeight.w700, alto: 1.15),
  headlineSmall: Tipos.display(tamano: 24, peso: FontWeight.w700, alto: 1.15),
  titleLarge: Tipos.display(tamano: 22.4, peso: FontWeight.w700, alto: 1.2),
  titleMedium: Tipos.display(tamano: 18, peso: FontWeight.w700, alto: 1.25),
  titleSmall: Tipos.display(tamano: 15.2, peso: FontWeight.w700, alto: 1.3),
  bodyLarge: Tipos.texto(tamano: 15, alto: 1.5),
  bodyMedium: Tipos.texto(tamano: 14, alto: 1.5),
  bodySmall: Tipos.texto(tamano: 12.5, alto: 1.45),
  labelLarge: Tipos.texto(tamano: 14, peso: FontWeight.w600, alto: 1.2),
  labelMedium: Tipos.texto(tamano: 12, peso: FontWeight.w600, alto: 1.2),
  labelSmall: Tipos.texto(
    tamano: 11,
    peso: FontWeight.w600,
    alto: 1.2,
    interletra: 0.2,
  ),
);

/// El tema de la aplicacion.
/// EL ANILLO DEL FOCO, para que se vea por donde va el tabulador.
///
/// Sin esto, quien recorre la pantalla con el teclado no sabe donde esta parado:
/// pulsar Tab no ensena nada y hay que adivinar. Se descubrio mirandolo en el
/// navegador el 15/09/2026, y es la clase de fallo que no aparece en ninguna
/// prueba porque nadie prueba con el teclado.
///
/// Va en TINTA y no en el primario: el primario es el fondo del boton relleno, y
/// un anillo azul sobre azul no es un anillo. Dos pixeles, que es lo que se ve
/// de reojo sin pedir la vista cuando no hay foco.
///
/// [enCalma] es el borde que ya tenia el boton cuando NO esta enfocado — el
/// contorno fino del `OutlinedButton`, por ejemplo. Sin el, enfocar y soltar le
/// borraria su borde de siempre.
WidgetStateProperty<BorderSide?> anilloDeFoco({BorderSide? enCalma}) =>
    WidgetStateProperty.resolveWith<BorderSide?>(
      (estados) => estados.contains(WidgetState.focused)
          ? const BorderSide(color: Colores.tinta, width: 2)
          : enCalma,
    );

ThemeData temaDeReparto() {
  // Nada de bajar tipografias por red: estan en `assets/google_fonts/`.
  GoogleFonts.config.allowRuntimeFetching = false;

  final texto = _escala().apply(
    bodyColor: Colores.tinta,
    displayColor: Colores.tinta,
  );

  final esquema = ColorScheme(
    brightness: Brightness.light,
    // `primary` es EL RELLENO —el oro del logo—, no el tono de texto: Material
    // lo usa de fondo del `FilledButton` y pone `onPrimary` encima. El tono de
    // texto es `Colores.primario`, que es otra cosa y va en `onPrimaryContainer`.
    //
    // Y `onPrimary` NO se escribe: lo contesta `letrasSobre`. Aqui ponia
    // `Colors.white`, y de ahi salia el «azul con letras blancas». Sobre el oro
    // el blanco da 2,2 de contraste —ilegible— y la tinta da 7,6.
    primary: Colores.marca,
    onPrimary: Colores.sobreMarca,
    primaryContainer: Colores.primarioTenue,
    onPrimaryContainer: Colores.primario,
    secondary: Colores.secundario,
    onSecondary: letrasSobre(Colores.secundario),
    secondaryContainer: Colores.verdeFondo,
    onSecondaryContainer: Colores.verde,
    tertiary: Colores.acento,
    onTertiary: letrasSobre(Colores.acento),
    tertiaryContainer: Colores.ambarFondo,
    onTertiaryContainer: Colores.ambar,
    error: Colores.rojo,
    onError: letrasSobre(Colores.rojo),
    errorContainer: Colores.rojoFondo,
    onErrorContainer: Colores.rojo,
    // El papel y la tinta. `surface` es BLANCO y `scaffoldBackgroundColor` es el
    // papel: es lo que hace que una tarjeta se despegue del fondo sin sombra.
    surface: Colores.blanco,
    onSurface: Colores.tinta,
    surfaceContainerLowest: Colores.blanco,
    surfaceContainerLow: Colores.papel,
    surfaceContainer: Colores.papel,
    surfaceContainerHigh: Colores.grisFondo,
    surfaceContainerHighest: Colores.grisFondo,
    onSurfaceVariant: Colores.tintaSuave,
    outline: Colores.linea,
    outlineVariant: Colores.linea,
    shadow: Colores.tinta,
    scrim: Colores.tinta,
    inverseSurface: Colores.tinta,
    onInverseSurface: Colores.papel,
    inversePrimary: Colores.primarioClaro,
  );

  final bordeFino = OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radios.lg),
    borderSide: BorderSide(color: Colores.linea),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    textTheme: texto,
    // La tipografia por defecto de CUALQUIER `Text` sin estilo: Hanken, no la
    // Roboto del sistema.
    fontFamily: texto.bodyMedium?.fontFamily,
    // TRANSPARENTE a proposito: el papel y su rejilla los pinta [FondoDePapel],
    // que va por debajo de todo en el `builder` de `MaterialApp`. Un `Scaffold`
    // opaco encima taparia la rejilla y volveriamos al gris plano.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colores.papel,
    dividerColor: Colores.linea,
    dividerTheme: DividerThemeData(
      color: Colores.linea,
      thickness: 1,
      space: 1,
    ),
    // Sin efecto de rebote en las tablas: con desplazamiento horizontal propio
    // el rebote hace creer que la tabla se acabo cuando queda media a la derecha.
    splashFactory: InkSparkle.splashFactory,
    // El velo del cajon: negro al 40 %, el del pliego §9.2.
    dialogTheme: DialogThemeData(
      backgroundColor: Colores.blanco,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colores.blanco,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
        side: BorderSide(color: Colores.linea),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colores.papel,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colores.tinta,
      elevation: 0,
      titleTextStyle: texto.titleLarge,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: Colores.blanco,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Border(right: BorderSide(color: Colores.linea)),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: texto.bodyMedium,
      subtitleTextStyle: texto.bodySmall?.copyWith(color: Colores.tintaSuave),
      iconColor: Colores.tintaSuave,
      selectedColor: Colores.primario,
      selectedTileColor: Colores.primarioTenue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.md),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colores.blanco,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colores.tintaCon(0.20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        side: BorderSide(color: Colores.linea),
      ),
      textStyle: texto.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colores.blanco),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radios.lg),
            side: BorderSide(color: Colores.linea),
          ),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Colores.tinta,
        borderRadius: BorderRadius.circular(Radios.sm),
      ),
      textStyle: Tipos.texto(tamano: 12, color: Colores.papel),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      waitDuration: const Duration(milliseconds: 400),
    ),
    // Los botones. Radio `xl` (13.6) y la tipografia de texto, no la de titular:
    // en delivery los botones son `text-sm font-medium`.
    //
    // **Todos llevan anillo de foco** ([anilloDeFoco]). Sin el, quien recorre la
    // pantalla con el tabulador no sabe donde esta parado: se ve pasar nada.
    // Visto en el navegador el 15/09/2026, pulsando Tab por el Panel entero.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colores.marca,
        foregroundColor: Colores.sobreMarca,
        elevation: 0,
        textStyle: Tipos.texto(tamano: 14, peso: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
      ).copyWith(side: anilloDeFoco()),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colores.marca,
        foregroundColor: Colores.sobreMarca,
        elevation: 0,
        textStyle: Tipos.texto(tamano: 14, peso: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
      ).copyWith(side: anilloDeFoco()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            backgroundColor: Colores.blanco,
            foregroundColor: Colores.tinta,
            textStyle: Tipos.texto(tamano: 14, peso: FontWeight.w500),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radios.lg),
            ),
          ).copyWith(
            side: anilloDeFoco(enCalma: BorderSide(color: Colores.linea)),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colores.primario,
        textStyle: Tipos.texto(tamano: 14, peso: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.md),
        ),
      ).copyWith(side: anilloDeFoco()),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: Colores.tintaSuave,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
      ).copyWith(side: anilloDeFoco()),
    ),
    iconTheme: IconThemeData(color: Colores.tintaSuave, size: 20),
    // Los campos: fondo blanco, borde fino de `--line`, y el foco en primario
    // — el mismo `outline` del `globals.css`.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colores.blanco,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: Tipos.texto(tamano: 14, color: Colores.tintaSuave),
      labelStyle: Tipos.texto(tamano: 14, color: Colores.tintaSuave),
      floatingLabelStyle: Tipos.texto(
        tamano: 13,
        peso: FontWeight.w600,
        color: Colores.primario,
      ),
      prefixIconColor: Colores.tintaSuave,
      suffixIconColor: Colores.tintaSuave,
      border: bordeFino,
      enabledBorder: bordeFino,
      disabledBorder: bordeFino,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        borderSide: BorderSide(color: Colores.primario, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        borderSide: BorderSide(color: Colores.rojo),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
        borderSide: BorderSide(color: Colores.rojo, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colores.grisFondo,
      side: BorderSide(color: Colores.linea),
      labelStyle: Tipos.texto(tamano: 12, peso: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.pastilla),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: Colores.lineaFuerte, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStatePropertyAll(Colores.linea),
      thumbColor: const WidgetStatePropertyAll(Colores.blanco),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: Colores.primario,
      linearTrackColor: Colores.grisFondo,
      circularTrackColor: Colores.grisFondo,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colores.tinta,
      contentTextStyle: Tipos.texto(tamano: 14, color: Colores.papel),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
    ),
    // Las barras de desplazamiento finas y calidas del `globals.css`
    // (`scrollbar-color: #cfc7ba transparent`).
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(9),
      radius: const Radius.circular(Radios.pastilla),
      thumbColor: WidgetStateProperty.resolveWith(
        (e) => e.contains(WidgetState.hovered)
            ? Colores.barraEncima
            : Colores.barra,
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: Tipos.texto(
        tamano: 11,
        peso: FontWeight.w600,
        color: Colores.tintaSuave,
        interletra: 0.6,
      ),
      dataTextStyle: texto.bodyMedium,
      dividerThickness: 1,
      headingRowColor: const WidgetStatePropertyAll(Colores.papel),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Colores.primario,
      // El 18 % del `::selection` de delivery, pero de la marca de AHORA: antes
      // era `0x2E1F4FE0`, el azul viejo congelado en un numero.
      selectionColor: Colores.marca.withValues(alpha: 0.28),
      selectionHandleColor: Colores.primario,
    ),
  );
}

/// EL PAPEL CON SU REJILLA.
///
/// El `body::before` del `globals.css`: una cuadricula calida de 32 px al 2,5 %
/// de tinta, que se desvanece hacia abajo con una mascara elíptica. Sin esto el
/// fondo es un gris plano y la aplicacion **se ve de Material**, por muy bien
/// que esten los colores: es la unica pieza del sistema que no se consigue con
/// un `ThemeData`.
///
/// El grano de pelicula del `body::after` no se copia: en Flutter habria que
/// pintar ruido por pixel en cada fotograma y en el portatil de un almacen eso
/// se nota. La rejilla es lo que se lee a simple vista.
class FondoDePapel extends StatelessWidget {
  const FondoDePapel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: Colores.papel),
    child: CustomPaint(
      painter: const _Rejilla(),
      // `isComplex` + `willChange: false`: la rejilla no cambia nunca, asi que
      // se guarda en cache y no se vuelve a trazar en cada fotograma.
      isComplex: true,
      willChange: false,
      child: child,
    ),
  );
}

class _Rejilla extends CustomPainter {
  const _Rejilla();

  /// `background-size: 32px 32px`.
  static const double _paso = 32;

  @override
  void paint(Canvas lienzo, Size medida) {
    if (medida.isEmpty) return;

    // `mask-image: radial-gradient(ellipse 120% 90% at 50% 0%, #000 35%,
    // transparent 100%)`. Se pinta la rejilla y se le aplica la mascara con
    // `dstIn`, que es lo mismo que hace el navegador.
    lienzo.saveLayer(Offset.zero & medida, Paint());

    final trazo = Paint()
      ..color = Colores.tintaCon(0.025)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= medida.width; x += _paso) {
      lienzo.drawLine(Offset(x, 0), Offset(x, medida.height), trazo);
    }
    for (var y = 0.0; y <= medida.height; y += _paso) {
      lienzo.drawLine(Offset(0, y), Offset(medida.width, y), trazo);
    }

    // `ellipse 120% 90% at 50% 0%`: el radio vertical es el 90 % del alto. Se
    // usa un circulo de ESE radio y no una elipse porque `RadialGradient` de
    // Flutter no es eliptico, y lo que se lee a simple vista es el desvanecido
    // de arriba abajo, no el de los lados. El rect va cuadrado a proposito:
    // `createShader` toma el radio del lado corto, y con un rect ancho en un
    // telefono estrecho el degradado saldria la mitad de alto.
    final radio = medida.height * 0.9;
    final elipse = Rect.fromCircle(
      center: Offset(medida.width / 2, 0),
      radius: radio,
    );
    lienzo.drawRect(
      Offset.zero & medida,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.35, 1],
        ).createShader(elipse),
    );

    lienzo.restore();
  }

  @override
  bool shouldRepaint(_Rejilla anterior) => false;
}
