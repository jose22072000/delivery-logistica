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

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../diseno/colores.dart';
import '../pantallas/rutas/datos/mapa_en_vivo.dart';
import 'mvt.dart';
import 'pmtiles.dart';

/// El lado de una tesela en píxeles. El mismo número de siempre.
const ladoDeTeselaDelPaquete = 256.0;

/// Qué grosor y qué color le toca a cada clase de vía, y **desde qué zoom se
/// dibuja**. Una calle de servicio pintada a z10 es una mancha.
({Color color, double grosor})? _comoSePinta(String? clase, int z) =>
    switch (clase) {
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

    // El orden es el que manda un mapa: agua, costa, calles, nombres. Al revés
    // el agua tapa las carreteras que la cruzan.
    for (final nombre in const ['agua', 'costa', 'carretera', 'poblacion']) {
      for (final capa in capas) {
        if (capa.nombre != nombre) continue;
        final escala = lado * aumento / capa.extension;
        _pintarCapa(lienzo, capa, escala, z);
      }
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
          _rotulo(lienzo, donde + const Offset(0, 5), nombre, r.clase == 'ciudad');
        }
    }
  }

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
    final pintor = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          color: ColoresDelMapa.nucleo,
          fontSize: grande ? 10 : 8.5,
          fontWeight: grande ? FontWeight.w700 : FontWeight.w600,
          height: 1,
          // Un halo del color del papel: sin él, un nombre encima de una
          // carretera no se lee.
          shadows: const [
            Shadow(color: ColoresDelMapa.fondo, blurRadius: 2.5),
            Shadow(color: ColoresDelMapa.fondo, blurRadius: 2.5),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110);
    pintor.paint(lienzo, donde - Offset(pintor.width / 2, 0));
  }
}
