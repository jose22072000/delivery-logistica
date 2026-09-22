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

/// Cuántos niveles se sube como mucho para saber si un sitio es mar, cuando el
/// paquete no tiene esa tesela. El porqué del tope, en
/// [FondoDelPaquete._elMarDelAntepasado].
const saltosParaElMar = 4;

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

// ═══════════════════════════════════════════════════════════════════════════
// EL MAR
// ═══════════════════════════════════════════════════════════════════════════
//
// Jose, 22/09/2026, alejando el mapa en el teléfono: el océano salía del MISMO
// crema que la tierra, y en un punto intermedio aparecía una banda azul cortada
// en línea recta que no seguía ninguna costa.
//
// Las dos cosas son el mismo fallo, y no es de color: **el paquete no lleva el
// mar**. La capa `agua` sólo trae lo que OpenStreetMap dibuja como polígono
// —embalses, lagunas, ríos anchos y alguna bahía— y además entra a partir del
// z7 (`aguaDesde`, en `herramientas/mapa-cuba/niveles.go`). El océano no es un
// polígono en OSM y no lo es en ningún sitio: lo que hay es `natural=coastline`,
// una LÍNEA. Así que el pintor rellenaba la tesela de papel, dibujaba encima lo
// que hubiera y el Atlántico se quedaba del color de Pinar del Río.
//
// Y la banda recta era la otra mitad de lo mismo: el Golfo de Batabanó SÍ está
// mapeado como `natural=water`, así que se pintaba de azul — y donde ese
// polígono se acaba, mar adentro, se acababa el azul con el corte recto del
// polígono. El mismo mar de dos colores, con una raya en medio que nadie puso
// en el agua.
//
// ## Lo que sí está en el paquete, y basta
//
// `costa` viaja **desde el z0** y es la costa entera de Cuba. Y trae dentro,
// gratis, el dato que hacía falta: en OSM una línea de costa se dibuja SIEMPRE
// con la tierra a la izquierda según se camina. Es una regla del proyecto, no
// una costumbre, y la vigilan sus validadores.
//
// La tesela le da la vuelta al eje vertical (la `y` crece hacia el sur), así
// que aquí dentro **la tierra queda a la derecha y el agua a la izquierda**.
// Con eso, la costa de una tesela se puede cerrar contra el borde del cuadro y
// sale el mar como polígono. Sin inventar nada: la raya recta que queda en el
// borde de la tesela es la MISMA que trae la tesela de al lado, así que las dos
// casan y no se ve.
//
// Comprobado contra el paquete de verdad (`cuba-completo`, 22/09/2026): cosiendo
// los trozos de `costa` por sus extremos salen 0 cabos sueltos en z1, z3, z6,
// z8, z10 y z12 — o cierran en anillo, o mueren en el borde. Por eso se puede
// hacer esto y por eso hay una guarda para cuando deje de ser verdad.

/// Un nudo: las coordenadas de tesela de un punto metidas en un entero, para
/// emparejar extremos por igualdad exacta.
///
/// Se puede porque las coordenadas de una tesela vectorial son **enteras** —el
/// formato las guarda así— y dos vías que comparten un nodo de OSM caen en el
/// mismo entero. Comparar `Offset` con `==` sobre dobles sería una ruleta.
int _nudo(Offset p) => (p.dx.round() + 32768) * 65536 + (p.dy.round() + 32768);

/// Une los trozos de `costa` por sus extremos y devuelve las cadenas enteras,
/// en unidades de tesela.
///
/// Hace falta porque la costa llega partida en cientos de trozos —una vía de OSM
/// cada vez— y un trozo que empieza y acaba en mitad del cuadro no se puede
/// cerrar contra ningún borde. Cosidos, cada cadena o cierra en anillo (un cayo,
/// la isla entera) o muere en el borde, que son los dos únicos casos que sabe
/// tratar [marDeLaCosta].
@visibleForTesting
List<List<Offset>> coserLaCosta(List<CapaVectorial> capas) {
  final trozos = <List<Offset>>[];
  for (final capa in capas) {
    if (capa.nombre != 'costa') continue;
    for (final rasgo in capa.rasgos) {
      for (final parte in rasgo.partes) {
        if (parte.length >= 2) trozos.add(parte);
      }
    }
  }
  if (trozos.isEmpty) return const [];

  final porInicio = <int, List<int>>{};
  for (var i = 0; i < trozos.length; i++) {
    porInicio.putIfAbsent(_nudo(trozos[i].first), () => <int>[]).add(i);
  }
  // UN TROZO QUE ES CONTINUACIÓN DE OTRO NO PUEDE EMPEZAR UNA CADENA. Si se
  // empezara por él, la misma costa saldría en dos cadenas y la primera tendría
  // un cabo suelto en mitad del cuadro — que es justo lo que [marDeLaCosta] no
  // sabe cerrar y por lo que se rendiría entera.
  final esContinuacion = List.filled(trozos.length, false);
  for (var i = 0; i < trozos.length; i++) {
    for (final j in porInicio[_nudo(trozos[i].last)] ?? const <int>[]) {
      if (j != i) esContinuacion[j] = true;
    }
  }

  final gastado = List.filled(trozos.length, false);
  final cadenas = <List<Offset>>[];

  List<Offset> seguirDesde(int i) {
    gastado[i] = true;
    final cadena = List<Offset>.of(trozos[i]);
    while (_nudo(cadena.first) != _nudo(cadena.last)) {
      var siguiente = -1;
      for (final j in porInicio[_nudo(cadena.last)] ?? const <int>[]) {
        if (gastado[j]) continue;
        siguiente = j;
        break;
      }
      if (siguiente < 0) break;
      gastado[siguiente] = true;
      cadena.addAll(trozos[siguiente].skip(1));
    }
    return cadena;
  }

  for (var i = 0; i < trozos.length; i++) {
    if (gastado[i] || esContinuacion[i]) continue;
    cadenas.add(seguirDesde(i));
  }
  // Lo que queda son anillos: ningún trozo suyo es «el primero» porque todos
  // son continuación del anterior. Se empieza por donde sea, que da igual.
  for (var i = 0; i < trozos.length; i++) {
    if (gastado[i]) continue;
    cadenas.add(seguirDesde(i));
  }
  return cadenas;
}

/// El doble del área con signo de un anillo, en coordenadas de tesela (la `y`
/// hacia abajo).
///
/// **El signo es el dato**, no el tamaño: con la tierra a la derecha, un anillo
/// de costa con TIERRA dentro —un cayo, la isla— sale negativo, y uno con AGUA
/// dentro —una laguna abierta al mar— sale positivo. Medido sobre el paquete de
/// verdad: el anillo de Cuba en la tesela z3/2/3 da −162.500.
double _areaDoble(List<Offset> anillo) {
  var a = 0.0;
  for (var i = 0; i + 1 < anillo.length; i++) {
    a += anillo[i].dx * anillo[i + 1].dy - anillo[i + 1].dx * anillo[i].dy;
  }
  return a;
}

/// Recorta un segmento al cuadro (Liang-Barsky). `null` si se queda fuera
/// entero.
(Offset, Offset)? _recortarSegmento(Offset a, Offset b, Rect cuadro) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  var desde = 0.0;
  var hasta = 1.0;
  for (var lado = 0; lado < 4; lado++) {
    final (p, q) = switch (lado) {
      0 => (-dx, a.dx - cuadro.left),
      1 => (dx, cuadro.right - a.dx),
      2 => (-dy, a.dy - cuadro.top),
      _ => (dy, cuadro.bottom - a.dy),
    };
    if (p == 0) {
      if (q < 0) return null;
      continue;
    }
    final r = q / p;
    if (p < 0) {
      if (r > hasta) return null;
      if (r > desde) desde = r;
    } else {
      if (r < desde) return null;
      if (r < hasta) hasta = r;
    }
  }
  return (
    Offset(a.dx + desde * dx, a.dy + desde * dy),
    Offset(a.dx + hasta * dx, a.dy + hasta * dy),
  );
}

/// Recorta una cadena de costa al cuadro, **sin perder el sentido de la
/// marcha** y partiéndola donde se sale.
///
/// Hace falta y no es un detalle: lo que el paquete guarda en una tesela es la
/// vía ENTERA de OSM que la toca, no el trozo que cae dentro, así que las
/// cadenas mueren en cualquier sitio del margen —medido: en (4132, 4168) o en
/// (−371, 2377), no en un borde—. Sin recortar aquí, esos extremos no están en
/// ningún borde contra el que cerrar y el mar de la tesela se daría por perdido.
List<List<Offset>> _recortarCadena(List<Offset> cadena, Rect cuadro) {
  final juntas = math.max(cuadro.width, cuadro.height) * 1e-9 + 1e-12;
  final trozos = <List<Offset>>[];
  List<Offset>? actual;
  for (var i = 0; i + 1 < cadena.length; i++) {
    final trozo = _recortarSegmento(cadena[i], cadena[i + 1], cuadro);
    if (trozo == null) {
      actual = null;
      continue;
    }
    final (p, q) = trozo;
    if (actual != null && (actual.last - p).distance <= juntas) {
      actual.add(q);
    } else {
      actual = [p, q];
      trozos.add(actual);
    }
  }
  // Una cadena que venía cerrada no empieza en ningún sitio: el punto por el
  // que se abrió el anillo es arbitrario y cortar ahí partiría en dos un trozo
  // que es uno solo.
  if (trozos.length > 1 &&
      (cadena.first - cadena.last).distance <= juntas &&
      (trozos.last.last - trozos.first.first).distance <= juntas) {
    trozos.last.addAll(trozos.first.skip(1));
    trozos.removeAt(0);
  }
  return [
    for (final t in trozos)
      if (t.length >= 2 && (t.first - t.last).distance > juntas || t.length > 2)
        t,
  ];
}

/// De qué lado de la costa cae [punto]: `true` si es agua, `null` si no hay
/// costa contra la que medir.
///
/// Es el desempate de la tesela que está **toda** de un lado y sólo ve costa
/// fuera de su cuadro. Se mira el segmento de costa más cercano y de qué lado
/// queda el punto: con la tierra a la derecha, a la izquierda hay agua.
@visibleForTesting
bool? esAgua(Offset punto, List<List<Offset>> cadenas) {
  var masCerca = double.infinity;
  bool? agua;
  for (final cadena in cadenas) {
    for (var i = 0; i + 1 < cadena.length; i++) {
      final a = cadena[i];
      final b = cadena[i + 1];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final largo2 = dx * dx + dy * dy;
      if (largo2 == 0) continue;
      var t = ((punto.dx - a.dx) * dx + (punto.dy - a.dy) * dy) / largo2;
      t = t < 0 ? 0 : (t > 1 ? 1 : t);
      final cx = punto.dx - (a.dx + t * dx);
      final cy = punto.dy - (a.dy + t * dy);
      final d2 = cx * cx + cy * cy;
      if (d2 >= masCerca) continue;
      masCerca = d2;
      final lado = dx * (punto.dy - a.dy) - dy * (punto.dx - a.dx);
      if (lado == 0) continue;
      agua = lado > 0;
    }
  }
  return agua;
}

/// Por dónde cae [p] en el borde de [cuadro], medido a lo largo del perímetro
/// desde la esquina de arriba a la izquierda y **dejando el cuadro a la
/// izquierda**: arriba de izquierda a derecha, derecha hacia abajo, abajo de
/// derecha a izquierda e izquierda hacia arriba.
///
/// Ese sentido no es una elección: es el que hace que un anillo recorrido así
/// salga con el área positiva, igual que salen las cadenas de costa al
/// caminarlas con el agua a la izquierda. Los dos pedazos del anillo del mar
/// tienen que girar para el mismo lado o el relleno se anula solo.
///
/// `null` cuando el punto no está en el borde: eso es un cabo suelto y con uno
/// solo el mar de esa tesela deja de ser fiable.
double? _enElBorde(Offset p, Rect cuadro, double tolerancia) {
  final w = cuadro.width;
  final h = cuadro.height;
  double sujeto(double v, double max) => v < 0 ? 0 : (v > max ? max : v);
  if ((p.dy - cuadro.top).abs() <= tolerancia) {
    return sujeto(p.dx - cuadro.left, w);
  }
  if ((p.dx - cuadro.right).abs() <= tolerancia) {
    return w + sujeto(p.dy - cuadro.top, h);
  }
  if ((p.dy - cuadro.bottom).abs() <= tolerancia) {
    return w + h + sujeto(cuadro.right - p.dx, w);
  }
  if ((p.dx - cuadro.left).abs() <= tolerancia) {
    return 2 * w + h + sujeto(cuadro.bottom - p.dy, h);
  }
  return null;
}

/// El cierre de emergencia: por el borde, pero **por el lado que menos borde
/// gasta**.
///
/// Sólo se usa cuando el relevo se rompe. Ir hacia adelante como siempre puede
/// dar la vuelta entera al cuadro, y entonces el mar se traga la tierra que sí
/// había —se vio en la z8/72/113, que quedó azul con sus dos pueblos dentro—.
/// Por el arco corto lo peor que sale es un anillo pequeño de más o de menos.
List<Offset> _porElArcoCorto(double t0, double t1, Rect cuadro) {
  final perimetro = 2 * (cuadro.width + cuadro.height);
  var adelante = t1 - t0;
  if (adelante < 0) adelante += perimetro;
  if (adelante <= perimetro / 2) return _esquinasEntre(t0, t1, cuadro);
  return _esquinasEntre(t1, t0, cuadro).reversed.toList();
}

/// Las esquinas de [cuadro] que hay que meter para ir por el borde desde [t0]
/// hasta [t1], en el sentido de [_enElBorde]. Sin ellas el mar se cerraría en
/// diagonal por dentro de la tesela y se comería una esquina de tierra.
List<Offset> _esquinasEntre(double t0, double t1, Rect cuadro) {
  final w = cuadro.width;
  final h = cuadro.height;
  final perimetro = 2 * (w + h);
  var hasta = t1 - t0;
  if (hasta < -1e-9) hasta += perimetro;
  if (hasta <= 0) return const [];

  final salida = <({double cuanto, Offset donde})>[];
  for (final esquina in <(double, Offset)>[
    (0, cuadro.topLeft),
    (w, cuadro.topRight),
    (w + h, cuadro.bottomRight),
    (2 * w + h, cuadro.bottomLeft),
  ]) {
    var cuanto = esquina.$1 - t0;
    if (cuanto < -1e-9) cuanto += perimetro;
    if (cuanto > 1e-9 && cuanto < hasta) {
      salida.add((cuanto: cuanto, donde: esquina.$2));
    }
  }
  salida.sort((a, b) => a.cuanto.compareTo(b.cuanto));
  return [for (final e in salida) e.donde];
}

/// EL MAR DE UNA TESELA, en anillos ya cerrados y en píxeles.
///
/// [lado] es el lado del cuadro que se está dibujando. Cuando se amplía un
/// antepasado es el del antepasado entero (`256 · aumento`), porque la costa que
/// trae la tesela es la suya y el recorte al trozo que toca lo hace el lienzo.
///
/// Devuelve `null` cuando **no se puede decir**, y eso es tan importante como el
/// resto:
///
///  * Sin capa `costa` no hay nada que responder. Una tesela de tierra adentro
///    —La Habana a z14— no lleva costa, y ahí el papel es lo correcto.
///  * Una costa con un cabo suelto en mitad del cuadro tampoco: el anillo que
///    saldría de cerrarla a ojo pintaría de agua media ciudad. **Antes ninguno
///    que uno inventado** (regla 4 de la casa).
@visibleForTesting
List<List<Offset>>? marDeLaCosta(
  List<CapaVectorial> capas, {
  required double lado,
}) {
  final costa = [
    for (final c in capas)
      if (c.nombre == 'costa') c,
  ];
  if (costa.isEmpty || costa.first.extension <= 0) return null;
  final escala = lado / costa.first.extension;

  final enteras = <List<Offset>>[];
  for (final cruda in coserLaCosta(capas)) {
    if (cruda.length < 2) continue;
    enteras.add([for (final p in cruda) Offset(p.dx * escala, p.dy * escala)]);
  }
  if (enteras.isEmpty) return null;

  final cuadro = Rect.fromLTWH(0, 0, lado, lado);
  final tolerancia = lado * 1e-7 + 1e-9;
  final cadenas = [
    for (final entera in enteras) ..._recortarCadena(entera, cuadro),
  ];

  if (cadenas.isEmpty) {
    // La costa entera se queda fuera del cuadro: o esto es mar abierto y la
    // costa que se ve es la de la tesela de al lado, o es tierra adentro. Lo
    // decide el lado del trozo de costa más cercano.
    final agua = esAgua(cuadro.center, enteras);
    if (agua != true) return null;
    return [
      [
        cuadro.topLeft,
        cuadro.topRight,
        cuadro.bottomRight,
        cuadro.bottomLeft,
        cuadro.topLeft,
      ],
    ];
  }

  final abiertas = <List<Offset>>[];
  final anillos = <List<Offset>>[];
  for (final cadena in cadenas) {
    if ((cadena.first - cadena.last).distance <= tolerancia) {
      anillos.add(cadena);
    } else {
      abiertas.add(cadena);
    }
  }

  final empieza = <double>[];
  final acaba = <double>[];
  for (final cadena in abiertas) {
    final a = _enElBorde(cadena.first, cuadro, tolerancia);
    final b = _enElBorde(cadena.last, cuadro, tolerancia);
    if (a == null || b == null) return null;
    empieza.add(a);
    acaba.add(b);
  }

  if (abiertas.isEmpty) {
    if (anillos.isEmpty) return null;
    // Ninguna costa cortada por el borde: el cuadro entero cae de un lado, y lo
    // dice el anillo más grande. Con tierra dentro (negativo) es un cayo, o la
    // isla, y alrededor hay mar; con agua dentro (positivo) es una laguna, y
    // alrededor hay tierra.
    var mayor = anillos.first;
    for (final a in anillos) {
      if (_areaDoble(a).abs() > _areaDoble(mayor).abs()) mayor = a;
    }
    if (_areaDoble(mayor) >= 0) return anillos;
    return [
      [
        cuadro.topLeft,
        cuadro.topRight,
        cuadro.bottomRight,
        cuadro.bottomLeft,
        cuadro.topLeft,
      ],
      ...anillos,
    ];
  }

  // EL COSIDO POR EL BORDE. Se camina la costa en su sentido —el agua queda a
  // la izquierda— y al llegar al borde se sigue por el borde, en el mismo
  // sentido, hasta el arranque de la siguiente costa. Lo que queda encerrado es
  // el agua.
  final orden = List.generate(abiertas.length, (i) => i)
    ..sort((a, b) => empieza[a].compareTo(empieza[b]));
  int siguienteTras(double t) {
    for (final i in orden) {
      if (empieza[i] > t + 1e-9) return i;
    }
    return orden.first;
  }

  final gastada = List.filled(abiertas.length, false);
  for (var arranque = 0; arranque < abiertas.length; arranque++) {
    if (gastada[arranque]) continue;
    final anillo = <Offset>[];
    var i = arranque;
    for (var vueltas = 0; ; vueltas++) {
      gastada[i] = true;
      anillo.addAll(abiertas[i]);
      final j = siguienteTras(acaba[i]);
      // **EL ANILLO SE CIERRA SIEMPRE POR EL BORDE, NUNCA EN LÍNEA RECTA POR
      // DENTRO.** La tentación, al llegar al final, es unir el último punto con
      // el primero y ya; eso dibuja una diagonal a través de la tesela, que es
      // exactamente la raya inventada que se está arreglando. Por el borde, en
      // cambio, la raya cae **en el borde de la tesela**, que es el mismo sitio
      // por el que la de al lado trae la suya: casan y no se ve ninguna.
      if (j == arranque) {
        anillo.addAll(_esquinasEntre(acaba[i], empieza[arranque], cuadro));
        anillo.add(anillo.first);
        anillos.add(anillo);
        break;
      }
      // EL RELEVO NO LLEGA: el siguiente arranque ya se usó. Pasa cuando los
      // extremos de la costa en el borde **no se alternan** —uno sale y el
      // siguiente también sale—, y eso no es un fallo del cosido: es lo que
      // deja el generador al simplificar. En la z8/72/113 había un lazo de
      // cuatro puntos que se cruza consigo mismo y cruza cuatro veces el borde
      // de arriba; recortado, sus dos trozos emparejaban dos veces el mismo
      // arranque y el anillo grande —el mar de casi toda la tesela— se quedaba
      // sin cerrar.
      //
      // Se cierra igual por el borde, pero **por el lado que menos borde
      // gasta**. Las tres salidas que se probaron antes están todas mal, y las
      // tres se vieron en esa misma tesela:
      //
      //  * en línea recta contra el arranque: un pico de tierra atravesando el
      //    Golfo de Guacanayabo en diagonal.
      //  * hacia adelante como siempre: el borde daba la vuelta entera y la
      //    tesela quedó azul con sus dos pueblos dentro.
      //  * tirar el anillo: un cuadro de papel en mitad del mar.
      if (gastada[j] || vueltas >= abiertas.length) {
        anillo.addAll(_porElArcoCorto(acaba[i], empieza[arranque], cuadro));
        anillo.add(anillo.first);
        anillos.add(anillo);
        break;
      }
      anillo.addAll(_esquinasEntre(acaba[i], empieza[j], cuadro));
      i = j;
    }
  }
  return anillos;
}

/// Los anillos, en un solo [Path].
///
/// Se expone para que las pruebas pregunten lo único que importa —«¿este punto
/// es mar?»— con la MISMA regla de relleno que usa el pintor. Armar el camino
/// aparte en la prueba sería comprobar otro dibujo.
///
/// **Todos en uno y con [PathFillType.nonZero]**, que es lo por lo mismo que
/// está escrito en [FondoDelPaquete._camino]: un anillo que gira al revés
/// —un cayo dentro del mar— se lee como agujero. En caminos separados el cayo
/// sería otra mancha de agua encima de sí mismo.
@visibleForTesting
Path caminoDelMar(List<List<Offset>> anillos) {
  final camino = Path();
  for (final anillo in anillos) {
    if (anillo.length < 3) continue;
    camino.addPolygon(anillo, true);
  }
  return camino;
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
    if (deLaRed != null) return _dibujadas[clave] = deLaRed;

    // Ni el paquete ni la red. Antes se acababa aquí, y sobre el mar eso es
    // dejar el papel puesto — o sea, pintar el Atlántico del color de la
    // tierra. El antepasado sí sabe contestar a una sola pregunta, que es la
    // única que se le hace: **¿esto es mar?**
    return _dibujadas[clave] = await _elMarDelAntepasado(z, x, y);
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

  /// SÓLO EL MAR, sacado del antepasado más profundo que exista.
  ///
  /// Se llama cuando no hay tesela ni en el paquete ni en la red, y eso es casi
  /// siempre una cosa: **mar abierto**. El paquete sólo guarda las teselas que
  /// llevan algo dentro, y a 20 km de la costa no hay ni una carretera ni un
  /// trozo de costa que guardar, así que esa tesela no existe — y lo que se veía
  /// era el papel, o sea tierra.
  ///
  /// Se dibuja **el mar y nada más**. Ni carreteras ampliadas ni nombres
  /// gigantes: el antepasado está diez veces más lejos y lo único que sabe decir
  /// con la misma certeza a cualquier tamaño es de qué lado de la costa cae
  /// esto. Si no lo sabe —si no tiene costa, o si su costa no cierra— se
  /// devuelve nada y todo queda como estaba.
  ///
  /// ## Por qué se para en [saltosParaElMar]
  ///
  /// Subiendo sin freno se acaba llegando al z0, donde la costa de Cuba cabe en
  /// cien unidades de tesela y donde «lo que no es Cuba es mar» empieza a
  /// significar que Florida es mar. El tope deja el relleno donde de verdad
  /// responde —el mar de alrededor de la isla— y lo corta a cientos de
  /// kilómetros de la costa, que es donde ya no hay mapa que enseñar.
  Future<ui.Image?> _elMarDelAntepasado(int z, int x, int y) async {
    final desde = z > paquete.cabecera.zMax ? paquete.cabecera.zMax : z;
    for (var za = desde - 1; za >= paquete.cabecera.zMin; za--) {
      if (desde - za > saltosParaElMar) break;
      final salto = z - za;
      final ax = x >> salto;
      final ay = y >> salto;

      Uint8List? crudo;
      try {
        crudo = await paquete.tesela(za, ax, ay);
      } on Object {
        return null;
      }
      if (crudo == null) continue;

      final capas = leerTeselaVectorial(crudo);
      if (capas.isEmpty) continue;

      final imagen = _dibujarSoloElMar(
        capas,
        (1 << salto).toDouble(),
        x - (ax << salto),
        y - (ay << salto),
      );
      if (imagen != null) return imagen;
    }
    return null;
  }

  ui.Image? _dibujarSoloElMar(
    List<CapaVectorial> capas,
    double aumento,
    int dentroX,
    int dentroY,
  ) {
    const lado = ladoDeTeselaDelPaquete;
    final anillos = marDeLaCosta(capas, lado: lado * aumento);
    if (anillos == null) return null;

    final camino = caminoDelMar(anillos)
        .shift(Offset(-dentroX * lado, -dentroY * lado));

    // ¿CAE ALGO DE MAR EN ESTE TROZO? Si no, se devuelve nada en vez de una
    // imagen transparente: una tesela entregada hace que el croquis escriba la
    // atribución de OSM y eche el velo de papel encima, y las dos cosas serían
    // mentira sobre una tesela que no dibuja absolutamente nada.
    const dentro = 0.5;
    final pruebas = <Offset>[
      const Offset(lado / 2, lado / 2),
      const Offset(dentro, dentro),
      const Offset(lado - dentro, dentro),
      const Offset(dentro, lado - dentro),
      const Offset(lado - dentro, lado - dentro),
    ];
    if (!pruebas.any(camino.contains)) return null;

    final grabadora = ui.PictureRecorder();
    final lienzo = ui.Canvas(grabadora);
    lienzo.clipRect(const Rect.fromLTWH(0, 0, lado, lado));
    lienzo.drawPath(camino, Paint()..color = ColoresDelMapa.agua);
    return grabadora.endRecording().toImageSync(lado.toInt(), lado.toInt());
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

    // EL MAR, DEBAJO DE TODO Y ANTES QUE NADA. No viene de ninguna capa: se
    // saca de cerrar la línea de costa contra el borde del cuadro, y es lo
    // único que distingue el océano de la tierra — la capa `agua` no lo lleva y
    // por debajo del z7 ni siquiera existe.
    final mar = marDeLaCosta(capas, lado: lado * aumento);
    if (mar != null) {
      lienzo.drawPath(caminoDelMar(mar), Paint()..color = ColoresDelMapa.agua);
    }

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
