// LA TERCERA CAPA: el mapa de calles que sale del paquete guardado.
//
// ═══════════════════════════════════════════════════════════════════════════
// LA DECISIÓN QUE IMPORTA AQUÍ: NO SE TOCA NADA DEL MAPA QUE YA HAY
// ═══════════════════════════════════════════════════════════════════════════
//
// `croquis_de_ruta.dart` ya dibuja en dos capas —abajo el croquis con las
// coordenadas locales, encima las teselas si llegan— y pide esas teselas por un
// puerto: `FondoDeCalles.tesela(z, x, y) → ui.Image?`.
//
// Esto es **otra implementación de ese puerto**. Nada más. Y eso trae cuatro
// cosas gratis, que es justo lo que hace que sea la solución correcta y no un
// atajo:
//
//  1. **El croquis se sigue dibujando SIEMPRE.** El paquete es una mejora, nunca
//     un requisito. Jose creía que sin mapa no se pueden crear rutas, y en esta
//     aplicación no es verdad: que siga sin serlo.
//  2. **La atribución de OpenStreetMap sigue saliendo**, también sin conexión.
//     El pintor la escribe en cuanto se dibuja una tesela, venga de donde venga
//     (`croquis_de_ruta.dart`, paso 6). La licencia la exige y aquí no se pierde.
//  3. **La barra de escala, el encuadre y los pines siguen cuadrando**, porque
//     la proyección es la misma —Mercator web— y la tesela se entrega en el
//     mismo sitio y del mismo tamaño que la de OSM.
//  4. **No hay ninguna biblioteca de mapas.** La decisión de la casa se mantiene:
//     `CustomPainter` y nada más. Lo único que se añadió es un decodificador
//     (`mvt.dart`) y un lector de fichero (`pmtiles.dart`), los dos Dart puro.
//
// ## Por qué se rasteriza a una `ui.Image` de 256 en vez de pintar vectores
//
// Porque lo que el paquete vectorial ahorra es **tamaño en el disco** —26 MB en
// vez de 6,5 GB—, no nitidez: la geometría ya está en el aparato y dibujarla
// cuesta lo mismo aquí que dentro del pintor. A cambio, entregarla como tesela
// encaja pieza a pieza con lo que ya está escrito y probado, sin abrir un solo
// fichero de los de la otra tarea.
//
// Lo que se pierde: al ampliar mucho, la tesela rasterizada se ve algo suave. Es
// exactamente lo que ya pasa hoy con las teselas de OSM.
//
// ## El acercamiento por encima de lo que trae el paquete
//
// El paquete llega hasta z11, z14 o z15 según el nivel, y el mapa de la ruta
// puede pedir hasta z19 cuando las paradas están en dos manzanas. Ahí **no se
// devuelve nada, que dejaría un hueco**: se coge la tesela más profunda que haya
// y se dibuja el trocito que toca, ampliado. Se ve más gordo, y se ve — que es
// lo que hace falta en el patio de un almacén.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../diseno/colores.dart';
import '../pantallas/rutas/datos/mapa_en_vivo.dart';
import 'mvt.dart';
import 'pmtiles.dart';

/// El lado de una tesela en píxeles. El mismo número de siempre.
const ladoDeTeselaDelPaquete = 256.0;

/// Qué grosor y qué color le toca a cada clase de vía, y **desde qué zoom se
/// dibuja**. Una calle de servicio pintada a z10 es una mancha.
/// De qué color va cada clase de suelo.
///
/// UNA CLASE QUE NO CONOCEMOS **SE PINTA IGUAL**, con el tono más flojo, en vez
/// de no pintarse. Es la regla 4 de la casa aplicada al dibujo: si el generador
/// empieza a mandar una clase nueva —un uso del suelo que hoy no existe— lo que
/// tiene que pasar es que se vea algo raro y se arregle, no que quede un hueco
/// blanco que nadie sabe si es un descampado o un fallo.
///
/// Y eso es exactamente lo que pasó con `humedal`, la clase que estrenó el
/// generador la tarde del 21/09/2026 al coser los multipolígonos: durante un día
/// entero la Ciénaga de Zapata se pintó **del color de un prado**, sin un solo
/// error por ningún lado. El `_ =>` hizo su trabajo —se vio— y esto es la otra
/// mitad: que la clase nueva tenga su línea. **Cada clase que añada el generador
/// (la tabla del §3 de `docs/mapa-sin-conexion.md`) tiene que entrar aquí**, o
/// vuelve a salir del color de otra cosa.
///
/// Se expone para las pruebas porque lo que hay que poder comprobar es **la
/// decisión** —de qué color sale cada clase, y que ninguna se cae al de por
/// defecto—, no los píxeles de una imagen, que es una prueba que no explica nada
/// cuando falla.
@visibleForTesting
Color colorDelSuelo(String? clase) => switch (clase) {
  'bosque' => ColoresDelMapa.bosque,
  'parque' => ColoresDelMapa.parque,
  'hierba' => ColoresDelMapa.hierba,
  'humedal' => ColoresDelMapa.humedal,
  'urbano' => ColoresDelMapa.urbano,
  'industrial' => ColoresDelMapa.industrial,
  'portuario' => ColoresDelMapa.portuario,
  _ => ColoresDelMapa.hierba,
};

({Color color, double grosor})? _comoSePinta(
  String? clase,
  int z,
) => switch (clase) {
  'autopista' => (color: ColoresDelMapa.troncal, grosor: z >= 12 ? 3.2 : 2.0),
  'carretera' => (color: ColoresDelMapa.troncal, grosor: z >= 12 ? 2.6 : 1.6),
  'principal' => (color: ColoresDelMapa.via, grosor: z >= 12 ? 2.2 : 1.3),
  'secundaria' => (color: ColoresDelMapa.via, grosor: z >= 12 ? 1.8 : 1.0),
  'terciaria' => (color: ColoresDelMapa.via, grosor: 1.3),
  'calle' when z >= 12 => (color: ColoresDelMapa.calle, grosor: 1.1),
  'servicio' when z >= 14 => (color: ColoresDelMapa.calle, grosor: 0.8),
  'camino' when z >= 14 => (color: ColoresDelMapa.calle, grosor: 0.7),
  _ => null,
};

// ═══════════════════════════════════════════════════════════════════════════
// LOS NOMBRES DE LAS CALLES
// ═══════════════════════════════════════════════════════════════════════════
//
// Jose, 21/09/2026, con el mapa sin conexión ya funcionando en el teléfono:
// «nos faltan mas cosas q tiene el mapa con conexion q aqui no tenemos».
//
// Y una de ellas estaba **ya dentro del paquete y sin enseñar**: el generador
// escribe `nombre` en los rasgos de la capa `carretera` desde el z9
// (`herramientas/mapa-cuba/teselar.go`, con `nivel.NombresDesde`), y aquí sólo
// se rotulaba la capa `poblacion`. El dato estaba en el aparato y no se veía,
// así que esto se arregla **sin tocar el generador y sin que nadie vuelva a
// bajar los 26 MB**.
//
// Las cuatro reglas que hacen que un rótulo de calle ayude en vez de estorbar,
// y que son las mismas que sigue el mapa de OSM con conexión:
//
//  1. **Sólo donde se lee.** Que el nombre viaje desde el z9 no quiere decir que
//     se pinte desde el z9: a ese tamaño la calle entera mide dos píxeles. Cada
//     clase entra a su zoom (`_rotuloDeViaDesde`) y además el rótulo sólo se
//     pone si **cabe recto sobre el trazo**, que es la prueba de verdad.
//  2. **Un nombre por tesela.** Una avenida llega partida en veinte rasgos; sin
//     esto, «Avenida 26» sale veinte veces en 256 píxeles.
//  3. **Siguiendo la calle y nunca boca abajo.** El rótulo va sobre el trazo con
//     la inclinación del tramo donde cae; si ese tramo va de derecha a
//     izquierda se le da la vuelta, porque un nombre invertido no se lee: se
//     descifra.
//  4. **Sin amontonarse, y con los de población mandando.** Se lleva la lista de
//     cajas ya ocupadas y el rótulo que se pise con otra se tira. Los nombres de
//     población se apuntan ANTES: son los que convierten la telaraña en un sitio
//     reconocible, y perder «Alamar» para poder leer «Calle 3ra» es mal cambio.

/// Desde qué zoom se escribe el nombre de cada clase de vía.
///
/// El número es además **la prioridad**: cuanto más bajo, más manda cuando dos
/// rótulos se pisan. Una autopista rotulada vale más que la calle de servicio
/// que la cruza, y es el mismo orden en el que se leen.
int? _rotuloDeViaDesde(String? clase) => switch (clase) {
  'autopista' => 10,
  'carretera' => 10,
  'principal' => 11,
  'secundaria' => 13,
  'terciaria' => 13,
  'calle' => 14,
  // Servicio y camino son el callejón de un almacén y la guardarraya de una
  // finca. Sólo tienen sitio cuando ya se está encima del sitio.
  'servicio' => 16,
  'camino' => 16,
  _ => null,
};

/// Un rótulo de calle ya colocado: dónde cae, cómo va inclinado y qué cuadro
/// ocupa. Se expone para que las pruebas puedan mirar **las decisiones** —que no
/// se repite, que no va boca abajo, que no se pisa con otro— sin tener que
/// descifrar los píxeles de una imagen, que es una prueba que no explica nada
/// cuando falla.
@immutable
class RotuloDeCalle {
  const RotuloDeCalle({
    required this.texto,
    required this.centro,
    required this.angulo,
    required this.caja,
  });

  final String texto;

  /// El centro del texto, en píxeles de la tesela **sin trasladar**.
  final Offset centro;

  /// La inclinación del tramo, en radianes. Siempre entre -π/2 y π/2: fuera de
  /// ahí el texto sale boca abajo.
  final double angulo;

  /// El cuadro que ocupa ya girado, alineado a los ejes. Es lo que se compara
  /// para no amontonar.
  final Rect caja;
}

/// El pintor de un rótulo, con su halo. **Uno solo para los dos sitios**: los
/// nombres de población y los de calle comparten el halo del color del papel,
/// que es lo único que hace que un nombre encima de una carretera se lea.
TextPainter _pintorDeRotulo(
  String texto, {
  required double tamano,
  required FontWeight peso,
  required Color color,
  required double maxAncho,
}) => TextPainter(
  text: TextSpan(
    text: texto,
    style: TextStyle(
      color: color,
      fontSize: tamano,
      fontWeight: peso,
      height: 1,
      shadows: const [
        Shadow(color: ColoresDelMapa.fondo, blurRadius: 2.5),
        Shadow(color: ColoresDelMapa.fondo, blurRadius: 2.5),
      ],
    ),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
  ellipsis: '…',
)..layout(maxWidth: maxAncho);

TextPainter _pintorDeNombreDeCalle(String texto) => _pintorDeRotulo(
  texto,
  tamano: 8,
  peso: FontWeight.w600,
  color: ColoresDelMapa.rotuloDeCalle,
  maxAncho: 160,
);

/// DÓNDE VA EL RÓTULO SOBRE LA CALLE, si es que va.
///
/// Se busca el tramo más corto del trazo que ya mida [ancho] y que sea **casi
/// recto**: el texto se escribe en línea, así que sobre una curva cerrada se
/// despegaría del asfalto y quedaría flotando.
///
/// Devuelve `null` cuando la calle no tiene sitio, y eso es una respuesta buena:
/// media palabra sobre una calle de treinta píxeles estorba más que el hueco.
({Offset centro, double angulo})? _seguirLaCalle(
  List<Offset> puntos,
  double ancho,
  Rect visible,
) {
  var i = 0;
  var recorrida = 0.0;
  for (var j = 1; j < puntos.length; j++) {
    recorrida += (puntos[j] - puntos[j - 1]).distance;
    // La ventana más corta que ya mide lo que el texto: así el rótulo se apoya
    // en el trozo de calle más recto que hay, no en media ciudad.
    while (i + 1 < j &&
        recorrida - (puntos[i + 1] - puntos[i]).distance >= ancho) {
      recorrida -= (puntos[i + 1] - puntos[i]).distance;
      i++;
    }
    if (recorrida < ancho) continue;

    final a = puntos[i];
    final b = puntos[j];
    final cuerda = (b - a).distance;
    // La calle da la vuelta: mide de sobra recorriéndola, pero en línea recta no
    // cabe. Sin esto, el nombre de una rotonda se pinta atravesándola.
    if (cuerda < ancho) continue;
    // Y el tramo tiene que ser casi recto, o el texto se sale del asfalto.
    if (recorrida > cuerda * 1.25) continue;

    final centro = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    if (!visible.contains(centro)) continue;

    // NUNCA BOCA ABAJO. El tramo que va de derecha a izquierda se recorre al
    // revés: el texto se escribe siempre hacia la derecha y el ángulo se queda
    // entre -π/2 y π/2. Sin esta vuelta, media ciudad sale del revés —las
    // calles vienen del fichero en el orden en que las dibujó quien las dibujó,
    // que no tiene nada que ver con cómo se leen.
    final (desde, hasta) = b.dx < a.dx ? (b, a) : (a, b);
    return (
      centro: centro,
      angulo: math.atan2(hasta.dy - desde.dy, hasta.dx - desde.dx),
    );
  }
  return null;
}

/// LOS RÓTULOS DE CALLE DE UNA TESELA, ya repartidos y sin pisarse.
///
/// Se calcula aparte de pintar por dos razones: porque las decisiones —cuál
/// entra, cuál se cae, cuál va girado— son lo que hay que poder probar, y
/// porque los nombres de población tienen que estar apuntados **antes** de
/// repartir los de calle.
///
/// [aumento], [dentroX] y [dentroY] son los mismos del acercamiento por encima
/// del paquete: las coordenadas salen sin trasladar, igual que las pinta
/// `_dibujar`.
@visibleForTesting
List<RotuloDeCalle> rotulosDeCalleDeLaTesela(
  List<CapaVectorial> capas,
  int z, {
  double aumento = 1,
  int dentroX = 0,
  int dentroY = 0,
}) {
  const lado = ladoDeTeselaDelPaquete;
  final visible = Rect.fromLTWH(dentroX * lado, dentroY * lado, lado, lado);

  // PRIMERO LOS NOMBRES DE POBLACIÓN, que son los que mandan.
  final ocupadas = <Rect>[];
  for (final capa in capas) {
    if (capa.nombre != 'poblacion') continue;
    final escala = lado * aumento / capa.extension;
    for (final r in capa.rasgos) {
      final nombre = r.nombre;
      if (nombre == null || nombre.isEmpty) continue;
      if (r.partes.isEmpty || r.partes.first.isEmpty) continue;
      ocupadas.add(
        _cajaDeNombreDePoblacion(
          r.partes.first.first * escala + const Offset(0, 5),
          nombre,
          r.clase == 'ciudad',
        ),
      );
    }
  }

  // Los candidatos, ordenados por lo que más se lee: primero la clase (una
  // autopista antes que un callejón) y, dentro de la clase, la calle más larga,
  // que es la que se ve entera.
  final candidatos =
      <({int orden, double largo, String nombre, List<Offset> puntos})>[];
  final vistos = <String>{};
  for (final capa in capas) {
    if (capa.nombre != 'carretera') continue;
    final escala = lado * aumento / capa.extension;
    for (final r in capa.rasgos) {
      final nombre = r.nombre;
      if (nombre == null || nombre.isEmpty) continue;
      final desde = _rotuloDeViaDesde(r.clase);
      if (desde == null || z < desde) continue;
      // Lo que no se dibuja no se rotula: un nombre solo, sin su calle debajo,
      // es una palabra flotando en el papel.
      if (_comoSePinta(r.clase, z) == null) continue;
      // Un ancho de mentira, a ojo, para no montar un `TextPainter` por cada uno
      // de los 573 rasgos de la tesela de La Habana. El bueno se mide después,
      // sólo para los que llegan hasta ahí.
      final anchoAproximado = nombre.length * 4.4;
      for (final parte in r.partes) {
        if (parte.length < 2) continue;
        final puntos = [for (final p in parte) p * escala];
        var largo = 0.0;
        for (var i = 1; i < puntos.length; i++) {
          largo += (puntos[i] - puntos[i - 1]).distance;
        }
        if (largo < anchoAproximado) continue;
        candidatos.add((
          orden: desde,
          largo: largo,
          nombre: nombre,
          puntos: puntos,
        ));
      }
    }
  }
  candidatos.sort((a, b) {
    final porClase = a.orden.compareTo(b.orden);
    return porClase != 0 ? porClase : b.largo.compareTo(a.largo);
  });

  final puestos = <RotuloDeCalle>[];
  for (final c in candidatos) {
    // UN NOMBRE POR TESELA. Una avenida llega partida en un rasgo por manzana y
    // sin esto sale rotulada en cada una.
    if (!vistos.add(c.nombre)) continue;
    final pintor = _pintorDeNombreDeCalle(c.nombre);
    final sitio = _seguirLaCalle(c.puntos, pintor.width + 4, visible);
    if (sitio == null) {
      // No cabía: el nombre se queda sin usar y se le deja el turno a otro rasgo
      // suyo más largo, si lo hay.
      vistos.remove(c.nombre);
      continue;
    }
    final caja = _cajaGirada(
      sitio.centro,
      pintor.width,
      pintor.height,
      sitio.angulo,
    );
    // SIN AMONTONARSE. Dos nombres superpuestos no son dos nombres: son una
    // mancha, y se pierden los dos.
    if (ocupadas.any(caja.overlaps)) {
      vistos.remove(c.nombre);
      continue;
    }
    ocupadas.add(caja);
    puestos.add(
      RotuloDeCalle(
        texto: c.nombre,
        centro: sitio.centro,
        angulo: sitio.angulo,
        caja: caja,
      ),
    );
  }
  return puestos;
}

/// El cuadro que ocupa un texto de [ancho]×[alto] girado [angulo] sobre su
/// centro, alineado a los ejes. Se queda un poco largo en las diagonales, y así
/// tiene que ser: separa de más, nunca de menos.
Rect _cajaGirada(Offset centro, double ancho, double alto, double angulo) {
  final c = math.cos(angulo).abs();
  final s = math.sin(angulo).abs();
  return Rect.fromCenter(
    center: centro,
    width: ancho * c + alto * s,
    height: ancho * s + alto * c,
  );
}

/// Dónde cae el nombre de un núcleo. Mismo cálculo que hace `_rotulo` al
/// pintarlo: si los dos se separan, los de calle esquivarían un sitio donde no
/// hay nada y se pisarían con el que sí está.
Rect _cajaDeNombreDePoblacion(Offset donde, String texto, bool grande) {
  final pintor = _pintorDeRotulo(
    texto,
    tamano: grande ? 10 : 8.5,
    peso: grande ? FontWeight.w700 : FontWeight.w600,
    color: ColoresDelMapa.nucleo,
    maxAncho: 110,
  );
  return Rect.fromLTWH(
    donde.dx - pintor.width / 2,
    donde.dy,
    pintor.width,
    pintor.height,
  );
}

/// EL FONDO QUE SALE DEL PAQUETE GUARDADO.
///
/// Si el paquete no tiene esa tesela y hay un [respaldo] —el de OSM— se le
/// pregunta a él. El orden es ése y no al revés: el paquete es instantáneo y no
/// gasta datos, y es lo único que hay en el patio de un almacén.
class FondoDelPaquete implements FondoDeCalles {
  FondoDelPaquete(this.paquete, {this.respaldo});

  final PaqueteDeTeselas paquete;

  /// De dónde sacar lo que el paquete no tenga. `null` en la APK cuando se
  /// quiere el mapa **exactamente** como se ve sin señal.
  final FondoDeCalles? respaldo;

  /// Lo ya dibujado. Volver a abrir la misma ruta no vuelve a decodificar nada.
  final _dibujadas = <String, ui.Image?>{};

  @override
  Future<ui.Image?> tesela(int z, int x, int y) async {
    final clave = '$z/$x/$y';
    if (_dibujadas.containsKey(clave)) return _dibujadas[clave];

    final imagen = await _delPaquete(z, x, y);
    if (imagen != null) return _dibujadas[clave] = imagen;

    // Sin respaldo, `null` es la respuesta buena: el croquis se dibuja igual y
    // la pantalla dice lo que se está viendo. Nada de cuadros grises.
    final deLaRed = await respaldo?.tesela(z, x, y);
    return _dibujadas[clave] = deLaRed;
  }

  Future<ui.Image?> _delPaquete(int z, int x, int y) async {
    // El acercamiento por encima del paquete: se busca el antepasado más
    // profundo que exista y se amplía el trozo que toca.
    final zDelPaquete = z > paquete.cabecera.zMax ? paquete.cabecera.zMax : z;
    final salto = z - zDelPaquete;
    final ax = x >> salto;
    final ay = y >> salto;

    Uint8List? crudo;
    try {
      crudo = await paquete.tesela(zDelPaquete, ax, ay);
    } on Object {
      // Un paquete que no se deja leer no puede tumbar el mapa: el croquis
      // sigue debajo. Se devuelve nada y ya.
      return null;
    }
    if (crudo == null) return null;

    final capas = leerTeselaVectorial(crudo);
    if (capas.isEmpty) return null;

    final aumento = 1 << salto;
    // Qué parte del antepasado cae en esta tesela.
    final dentroX = x - (ax << salto);
    final dentroY = y - (ay << salto);
    return _dibujar(capas, z, aumento.toDouble(), dentroX, dentroY);
  }

  ui.Image _dibujar(
    List<CapaVectorial> capas,
    int z,
    double aumento,
    int dentroX,
    int dentroY,
  ) {
    final grabadora = ui.PictureRecorder();
    final lienzo = ui.Canvas(grabadora);
    const lado = ladoDeTeselaDelPaquete;

    lienzo.drawRect(
      const Rect.fromLTWH(0, 0, lado, lado),
      Paint()..color = ColoresDelMapa.fondo,
    );
    // Recorte al cuadro: al ampliar, la geometría del antepasado se sale por los
    // cuatro lados y sin esto se pinta encima de las teselas vecinas.
    lienzo.clipRect(const Rect.fromLTWH(0, 0, lado, lado));
    lienzo.translate(-dentroX * lado, -dentroY * lado);

    // EL ORDEN ES EL QUE MANDA UN MAPA, y aquí no es cosmético: al revés, la
    // mancha del barrio tapa las manzanas y las manzanas tapan las calles, que
    // es justo lo que hay que ver. Suelo debajo del todo, la ruta encima de
    // todo (eso lo pinta `croquis_de_ruta.dart`, en otra capa).
    for (final nombre in const [
      'suelo',
      'agua',
      'costa',
      'edificio',
      'tren',
      'carretera',
      'poblacion',
    ]) {
      for (final capa in capas) {
        if (capa.nombre != nombre) continue;
        final escala = lado * aumento / capa.extension;
        _pintarCapa(lienzo, capa, escala, z);
      }
    }

    // Y los nombres de las calles encima de todo, que es donde van: debajo de
    // una carretera no se leen, y debajo del nombre de un núcleo tampoco —por
    // eso el reparto se hace con los de población ya apuntados.
    for (final r in rotulosDeCalleDeLaTesela(
      capas,
      z,
      aumento: aumento,
      dentroX: dentroX,
      dentroY: dentroY,
    )) {
      final pintor = _pintorDeNombreDeCalle(r.texto);
      lienzo.save();
      lienzo.translate(r.centro.dx, r.centro.dy);
      lienzo.rotate(r.angulo);
      pintor.paint(lienzo, Offset(-pintor.width / 2, -pintor.height / 2));
      lienzo.restore();
    }

    // `toImageSync` y no `toImage`: el asíncrono espera a que el motor
    // rasterice, y dentro de un `testWidgets` el reloj lo manda el `tester` y no
    // avanza solo — la prueba **se cuelga en vez de fallar**, que es lo peor que
    // puede hacer una prueba (`CLAUDE.md` §5). Aquí no hace falta esperar a
    // nadie: la geometría ya está en memoria.
    final dibujo = grabadora.endRecording();
    return dibujo.toImageSync(lado.toInt(), lado.toInt());
  }

  void _pintarCapa(ui.Canvas lienzo, CapaVectorial capa, double escala, int z) {
    switch (capa.nombre) {
      case 'agua':
        final pincel = Paint()..color = ColoresDelMapa.agua;
        for (final r in capa.rasgos) {
          if (r.forma != FormaVectorial.area) continue;
          lienzo.drawPath(_camino(r, escala, cerrado: true), pincel);
        }
      case 'suelo':
        // LO QUE HAY ENTRE LAS CALLES. Viene del paquete desde z9 —salvo la
        // hierba, desde z13— y es la capa que más pesa de las tres nuevas
        // (18,6 MB en el detallado). Se paga porque es lo único que funciona a
        // zoom bajo: una mancha de ciudad a z10 dice dónde está el pueblo; una
        // manzana a z10 no se ve.
        for (final r in capa.rasgos) {
          if (r.forma != FormaVectorial.area) continue;
          final color = colorDelSuelo(r.clase);
          lienzo.drawPath(
            _camino(r, escala, cerrado: true),
            Paint()..color = color,
          );
        }
      case 'edificio':
        // LAS MANZANAS. Sólo viajan a z14 y z15, que es donde se ven: son
        // 582.433 y meterlas un zoom más abajo dispara el fichero sin que nadie
        // las distinga.
        final pincel = Paint()..color = ColoresDelMapa.edificio;
        for (final r in capa.rasgos) {
          if (r.forma != FormaVectorial.area) continue;
          lienzo.drawPath(_camino(r, escala, cerrado: true), pincel);
        }
      case 'tren':
        final pincel = Paint()
          ..color = ColoresDelMapa.tren
          ..style = PaintingStyle.stroke
          ..strokeWidth = z >= 12 ? 1.0 : 0.7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (final r in capa.rasgos) {
          lienzo.drawPath(_camino(r, escala), pincel);
        }
      case 'costa':
        final pincel = Paint()
          ..color = ColoresDelMapa.costa
          ..style = PaintingStyle.stroke
          ..strokeWidth = z <= 8 ? 0.8 : 1.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        for (final r in capa.rasgos) {
          lienzo.drawPath(_camino(r, escala), pincel);
        }
      case 'carretera':
        for (final r in capa.rasgos) {
          final como = _comoSePinta(r.clase, z);
          if (como == null) continue;
          lienzo.drawPath(
            _camino(r, escala),
            Paint()
              ..color = como.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = como.grosor
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }
      case 'poblacion':
        for (final r in capa.rasgos) {
          if (r.partes.isEmpty || r.partes.first.isEmpty) continue;
          final donde = r.partes.first.first * escala;
          lienzo.drawCircle(
            donde,
            r.clase == 'ciudad' ? 2.6 : 1.8,
            Paint()..color = ColoresDelMapa.nucleo,
          );
          // EL NOMBRE. Es lo que convierte una telaraña de líneas en un sitio
          // reconocible: sin él, dos manzanas de Camagüey y dos de Holguín se
          // dibujan exactamente igual.
          final nombre = r.nombre;
          if (nombre == null || nombre.isEmpty) continue;
          _rotulo(
            lienzo,
            donde + const Offset(0, 5),
            nombre,
            r.clase == 'ciudad',
          );
        }
    }
  }

  /// EL CAMINO DE UN RASGO. **Todos sus trozos en UN SOLO `Path`**, y eso no es
  /// comodidad: es lo que hace que los agujeros se vean como agujeros.
  ///
  /// Desde el 21/09/2026 los rellenos traen huecos de verdad —la laguna dentro
  /// del bosque, y las de la Ciénaga de Zapata—. En el formato un hueco no se
  /// marca con ninguna etiqueta: **se marca dando la vuelta al anillo**, el
  /// contorno para un lado y el agujero para el otro, y eso lo garantiza el
  /// generador al escribir cada tesela (`enderezarAnillos` en `teselar.go`; el
  /// porqué, en el §3-bis de `docs/mapa-sin-conexion.md`).
  ///
  /// Un `Path` de Flutter rellena con [PathFillType.nonZero] de por defecto, y
  /// `nonZero` es justo la regla que lee esa vuelta: dos anillos girando al
  /// revés dentro del mismo `Path` dejan el hueco sin pintar.
  ///
  /// **De ahí salen dos cambios que parecen inocentes y rompen las lagunas sin
  /// que salte absolutamente nada** —ni el analizador, ni una prueba, ni un
  /// error en pantalla: la laguna se pinta de verde y hay que mirarla para
  /// verlo—:
  ///
  ///  1. Ponerle `..fillType = PathFillType.evenOdd`. Con los anillos ya
  ///     enderezados, `evenOdd` acierta con un agujero y **falla con dos
  ///     anidados**, y sobre todo deja de depender del sentido de giro, que es
  ///     lo único que el generador promete.
  ///  2. Dibujar cada trozo en su propio `Path` (un `drawPath` por parte). Ahí
  ///     el agujero deja de ser un agujero y pasa a ser **otra mancha del mismo
  ///     color encima**, que es exactamente lo que se veía antes de coser los
  ///     multipolígonos.
  ///
  /// Si algún día hay que tocar esto, lo que lo caza es mirar una tesela de la
  /// Ciénaga de Zapata con los ojos (`test/mapa/sonda_dibujo_test.dart`), no la
  /// suite.
  Path _camino(RasgoVectorial r, double escala, {bool cerrado = false}) {
    final camino = Path();
    for (final parte in r.partes) {
      if (parte.isEmpty) continue;
      camino.moveTo(parte.first.dx * escala, parte.first.dy * escala);
      for (var i = 1; i < parte.length; i++) {
        camino.lineTo(parte[i].dx * escala, parte[i].dy * escala);
      }
      if (cerrado) camino.close();
    }
    return camino;
  }

  void _rotulo(ui.Canvas lienzo, Offset donde, String texto, bool grande) {
    // El halo del color del papel va dentro de `_pintorDeRotulo`, compartido con
    // los nombres de calle: sin él, un nombre encima de una carretera no se lee.
    final pintor = _pintorDeRotulo(
      texto,
      tamano: grande ? 10 : 8.5,
      peso: grande ? FontWeight.w700 : FontWeight.w600,
      color: ColoresDelMapa.nucleo,
      maxAncho: 110,
    );
    pintor.paint(lienzo, donde - Offset(pintor.width / 2, 0));
  }
}
