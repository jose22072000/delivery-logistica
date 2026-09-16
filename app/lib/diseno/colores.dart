import 'dart:math' as math;

import 'package:flutter/material.dart';

/// LA PALETA. Sale del logo, y de ella sale todo lo demas.
///
/// `marca/icono.svg` usa DOS colores y no mas: el oro `#E0A52A` y la tinta
/// `#17130E`. Se comprobo trazo a trazo: el `#054C74` de PROCOVAR aparece en ese
/// fichero **en un comentario**, no en ningun dibujo, y darlo por bueno habria
/// metido en la aplicacion un azul que no esta en el logo.
///
/// Los cuatro que faltan —el verde de «entregado», el rojo de «no se puede», el
/// calido de «ojo con esto» y el de «va por la calle»— **no se eligen a ojo**:
/// se sacan del oro girandole el tono y dejandole SU misma saturacion y SU
/// misma luminosidad. Eso es lo que hace que un color parezca de la misma
/// familia que otro en vez de un parche pegado encima, y es lo que significa
/// que una paleta salga del logo.
///
/// ## Que se toca para cambiar el aspecto de la aplicacion
///
/// Estas ocho lineas. Nada mas. Los tonos derivados —el tinte de una insignia,
/// el borde de una tarjeta, el color de las letras de un boton— se CALCULAN de
/// aqui cada vez que arranca la aplicacion.
///
/// Antes no era asi y por eso esta escrito: `primarioTenue` era `#E9EDFC`, o sea
/// el azul viejo al 8 % **congelado en un numero**. El dia que el primario dejo
/// de ser azul, ese token se quedo azul, y con el la entrada activa del menu y
/// la opcion marcada de cada selector. «Cambiar la paleta» era en realidad cazar
/// cuarenta numeros por las pantallas, y siempre sobrevivia alguno.
abstract final class Paleta {
  // ─── Los tres del logo ─────────────────────────────────────────────────────

  /// EL ORO. El color de la aplicacion: lo que se pulsa, lo que esta activo, lo
  /// que tiene el foco.
  ///
  /// Sustituye al azul `#1F4FE0` que venia de delivery, y el motivo no es gusto:
  /// el icono del reparto es oro sobre tinta y los botones salian azules con
  /// letras blancas, de otra aplicacion. El color sale del logo, no del fondo.
  static const oro = Color(0xFFE0A52A);

  /// LA TINTA. El texto, y lo oscuro del logo. Calida, nunca negro puro: sobre
  /// el papel crema un negro puro se ve como un agujero.
  static const tinta = Color(0xFF17130E);

  // ─── El soporte ────────────────────────────────────────────────────────────

  /// EL PAPEL. El fondo. Se queda como estaba: «color del fondo no, color de los
  /// componentes».
  static const papel = Color(0xFFF7F4EF);

  /// El de las tarjetas, la barra lateral y el cajon.
  static const blanco = Color(0xFFFFFFFF);

  // ─── Las cuatro senales, sacadas del oro ───────────────────────────────────

  /// HECHO: entregado, cobrado, cerrado. El oro girado 115 grados.
  static final hecho = _familiaDelOro(155);

  /// IMPIDE: rechazado, pasado de capacidad. El oro girado hacia atras hasta el
  /// rojo, y ADEMAS bajado de luz.
  ///
  /// Es la unica que se sale de la luminosidad de la familia, y hay una prueba
  /// que lo cazo: con la luz del oro, el rojo y el ambar quedaban a 24 grados de
  /// tono, o sea que una insignia de «rechazado» y una de «ojo con esto» se
  /// veian igual de lejos. El tono solo no los separa —un rojo y un ambar son
  /// vecinos de verdad—, asi que lo que los separa es el peso: el que impide es
  /// mas oscuro, que es como se lee «alto» en cualquier sitio.
  static final impide = _oscurecer(_familiaDelOro(358), 0.12);

  /// AVISO: mira esto, puede que te este enganando. Datos de mas de un dia,
  /// pedidos sin ruta, capacidad al 80 %.
  ///
  /// Es de la familia del oro **a proposito** —un aviso es calido— y por eso hay
  /// una regla de forma que los separa: el aviso sale SIEMPRE como tinte de
  /// fondo con su texto oscuro encima (una insignia), y la marca sale SIEMPRE
  /// como relleno macizo (un boton). No se cruzan ni en peso ni en forma, asi
  /// que no se confunden aunque compartan familia.
  static final aviso = _familiaDelOro(42);

  /// EN CURSO: la ruta que va por la calle, el vehiculo fuera. Petroleo.
  ///
  /// Se probo primero con el COMPLEMENTARIO exacto del oro (su tono mas 180, o
  /// sea 220 grados) porque sobre el papel es lo mas correcto: el tono que mas
  /// se separa de la marca. Salia `#1F5BD6`, que es casi clavado al `#1F4FE0`
  /// de delivery — o sea, el azul que se acababa de quitar, volviendo por la
  /// puerta de atras con otro nombre.
  ///
  /// Asi que se queda a 196: petroleo, frio como hace falta para decir «esto se
  /// esta moviendo» pero sin ser el azul de Material. Va mas oscuro que la
  /// familia por lo mismo que [impide]: a la luz del oro se confundia con el
  /// verde de «entregado», que le queda a 40 grados.
  static final enCurso = _oscurecer(_familiaDelOro(196), 0.14);
}

/// El oro con otro tono, pero con SU saturacion y SU luminosidad.
///
/// Esta es la funcion que convierte «tres colores» en «una paleta»: un verde
/// cualquiera al lado del oro se ve prestado; el verde que tiene exactamente la
/// misma saturacion y la misma luz que el oro se ve de la casa.
/// Baja la luz de un color de la familia sin tocarle el tono ni la saturacion.
Color _oscurecer(Color c, double cuanto) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness - cuanto).clamp(0.0, 1.0)).toColor();
}

Color _familiaDelOro(double tono) {
  final base = HSLColor.fromColor(Paleta.oro);
  return HSLColor.fromAHSL(
    1,
    tono % 360,
    base.saturation,
    base.lightness,
  ).toColor();
}

// ─── La cocina. De aqui para abajo no hay ni un color escrito a mano. ────────

/// Contraste WCAG entre dos colores: de 1 (invisible) a 21 (negro sobre
/// blanco). El minimo para texto normal es 4.5; para texto grande o un icono, 3.
double contrasteEntre(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Mezcla [encima] sobre [debajo] con esa opacidad. Es lo que hace un tinte: el
/// rojo al 14 % sobre papel es el fondo de una insignia roja.
Color _mezcla(Color encima, Color debajo, double parte) =>
    Color.alphaBlend(encima.withValues(alpha: parte), debajo);

/// Mueve la luz de [c] —hacia abajo o hacia arriba, la que haga falta— hasta que
/// se lea sobre [fondo] con al menos [minimo] de contraste.
///
/// Esto es lo que deja cambiar la paleta sin mirar: pongas el tono que pongas en
/// [Paleta], su version de texto sale legible. No hay forma de dejar un color
/// ilegible cambiando un numero de arriba.
Color _legibleSobre(Color c, Color fondo, {double minimo = 4.5}) {
  // Si el fondo es claro hay que oscurecer; si es oscuro, aclarar.
  final paso = fondo.computeLuminance() > 0.4 ? -0.02 : 0.02;
  var hsl = HSLColor.fromColor(c);
  var salida = hsl.toColor();
  for (var i = 0; i < 50 && contrasteEntre(salida, fondo) < minimo; i++) {
    final luz = (hsl.lightness + paso).clamp(0.0, 1.0);
    if (luz == hsl.lightness) break;
    hsl = hsl.withLightness(luz);
    salida = hsl.toColor();
  }
  return salida;
}

/// EL COLOR DE LAS LETRAS QUE VAN ENCIMA DE [fondo]: tinta o blanco, el que se
/// lea mejor. **No se escribe «blanco» a mano en ningun boton.**
///
/// Sobre el oro contesta tinta (7,6 de contraste, contra el 2,2 que daria el
/// blanco), y ahi se acabo el «azul con letras blancas»: el dia que la marca
/// vuelva a ser un color oscuro, esta funcion contesta blanco ella sola.
Color letrasSobre(Color fondo) =>
    contrasteEntre(Paleta.tinta, fondo) >= contrasteEntre(Paleta.blanco, fondo)
    ? Paleta.tinta
    : Paleta.blanco;

/// Una senal entera: su tinte de fondo, su tono de texto y su tono vivo.
///
/// Las cinco se construyen con esta misma clase, asi que no puede quedarse
/// ninguna sin ajustar cuando se cambie su color en [Paleta].
final class Senal {
  Senal(this.base)
    : fondo = _mezcla(base, Paleta.papel, 0.14),
      fuerte = _legibleSobre(base, _mezcla(base, Paleta.papel, 0.14)),
      vivo = _legibleSobre(base, Paleta.blanco, minimo: 3);

  /// El color tal cual sale de [Paleta].
  final Color base;

  /// El tinte: el fondo de la insignia.
  final Color fondo;

  /// El texto y el icono que van sobre [fondo]. Garantizado 4.5 de contraste.
  final Color fuerte;

  /// El tono vivo para cifras grandes, puntos y barras sobre blanco, donde basta
  /// con el 3 que pide el texto grande.
  final Color vivo;
}

/// Los colores con nombre y con motivo. **Todo sale de [Paleta].**
abstract final class Colores {
  // ─── La marca ──────────────────────────────────────────────────────────────

  /// EL RELLENO. El oro tal cual: fondo del boton principal, barra activa,
  /// relleno de la casilla marcada, anillo del foco.
  static const marca = Paleta.oro;

  /// LAS LETRAS QUE VAN ENCIMA DE [marca]. Calculado, no elegido.
  static final sobreMarca = letrasSobre(Paleta.oro);

  /// EL PRIMARIO DE TEXTO: el oro oscurecido hasta que se lee sobre papel.
  ///
  /// Hacen falta los dos, y no es un capricho. El oro macizo con letras de tinta
  /// se lee de maravilla; el mismo oro **como texto** sobre blanco da 2,0 de
  /// contraste y no se lee. Asi que lo que se pulsa lleva [marca] y lo que se
  /// escribe lleva [primario].
  static final primario = _legibleSobre(Paleta.oro, Paleta.papel);

  /// El oro al 10 % sobre papel: fondo de la entrada activa del menu y de la
  /// opcion elegida de un selector.
  static final primarioTenue = _mezcla(Paleta.oro, Paleta.papel, 0.10);

  /// El oro aclarado, para lo que va encima de tinta.
  static final primarioClaro = _legibleSobre(Paleta.oro, Paleta.tinta);

  /// El oro, con el nombre con el que se llama en `marca/generar.sh` y en el
  /// icono de la aplicacion.
  static const oro = Paleta.oro;

  /// El verde del dinero cobrado, vivo: para las cifras grandes.
  static final secundario = _hecho.vivo;

  /// El calido de la flota, vivo.
  static final acento = _aviso.vivo;

  // ─── El papel y la tinta ───────────────────────────────────────────────────

  /// EL FONDO. Papel calido, no el `#F9FAFB` azulado de Material.
  static const papel = Paleta.papel;

  /// El de las tarjetas, la barra lateral y el cajon.
  static const blanco = Paleta.blanco;

  /// El texto.
  static const tinta = Paleta.tinta;

  /// Lo secundario: subtextos, etiquetas, notas. Es la tinta subida de luz hasta
  /// que se nota que es secundaria sin bajar del 4.5 sobre papel. Sale de la
  /// tinta, asi que si la tinta cambia de matiz, el subtexto cambia con ella.
  static final tintaSuave = HSLColor.fromColor(Paleta.tinta)
      .withLightness(0.33)
      .toColor();

  /// EL BORDE FINO de 1 px que llevan todas las tarjetas: tinta al 9 % sobre
  /// papel. Nace del fondo, asi que si el papel cambia, el borde lo sigue.
  static final linea = _mezcla(Paleta.tinta, Paleta.papel, 0.09);

  /// La misma linea, mas marcada: el borde de una casilla vacia, que con [linea]
  /// a secas no se ve sobre blanco.
  static final lineaFuerte = _mezcla(Paleta.tinta, Paleta.papel, 0.24);

  /// LA TINTA CON UNA OPACIDAD. De aqui salen las sombras, el velo que oscurece
  /// la pantalla detras de un cajon y la rejilla del papel: todo lo translucido
  /// tira a la tinta calida y nunca al negro puro, porque sobre papel crema una
  /// sombra negra se ve gris sucio y es lo que hace que una pantalla parezca de
  /// Material por defecto.
  static Color tintaCon(double opacidad) =>
      Paleta.tinta.withValues(alpha: opacidad);

  /// El velo del cajon.
  static final velo = tintaCon(0.32);

  /// El pulgar de la barra de desplazamiento, y el mismo con el raton encima.
  /// Son la linea de las tarjetas, dos pasos mas marcada.
  static final barra = _mezcla(Paleta.tinta, Paleta.papel, 0.22);
  static final barraEncima = _mezcla(Paleta.tinta, Paleta.papel, 0.34);

  // ─── Las cinco senales ─────────────────────────────────────────────────────

  static final _hecho = Senal(Paleta.hecho);
  static final _aviso = Senal(Paleta.aviso);
  static final _impide = Senal(Paleta.impide);
  static final _enCurso = Senal(Paleta.enCurso);
  static final _neutra = Senal(Paleta.tinta);

  /// AVISO = atencion. Datos de mas de un dia, pedidos sin ruta, rutas
  /// `planned`, capacidad al 80 %, informes que no estan al dia.
  static final ambar = _aviso.fuerte;
  static final ambarFondo = _aviso.fondo;

  /// HECHO = cerrado, cobrado, entregado.
  static final verde = _hecho.fuerte;
  static final verdeFondo = _hecho.fondo;

  /// EN CURSO = en marcha. El complementario del oro.
  static final enCurso = _enCurso.fuerte;
  static final enCursoFondo = _enCurso.fondo;

  /// IMPIDE = rechazado o pasado de capacidad.
  static final rojo = _impide.fuerte;
  static final rojoFondo = _impide.fondo;

  /// GRIS = lo normal, lo que no hay que mirar. Gris CALIDO, porque sale de la
  /// tinta: un gris azulado sobre papel crema se ve sucio.
  static final gris = tintaSuave;
  static final grisFondo = _neutra.fondo;

  // ─── Los nombres de siempre ────────────────────────────────────────────────

  /// El borde fino. Alias de [linea].
  static final borde = linea;

  /// El fondo de la aplicacion. Alias de [papel].
  static const fondo = Paleta.papel;
}
