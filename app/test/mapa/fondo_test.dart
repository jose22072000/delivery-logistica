// LA TERCERA CAPA, dibujada.
//
// Lo que se comprueba es que el paquete se enchufa **por el puerto que ya
// existe** (`FondoDeCalles`), y que cuando no tiene nada devuelve `null` en vez
// de lanzar: eso último es lo que mantiene viva la promesa del proyecto —**el
// croquis se dibuja SIEMPRE**, con paquete o sin él.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/mapa/carpeta_del_mapa.dart';
import 'package:reparto/mapa/proveedores_de_mapa.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/mapa/fondo_del_paquete.dart';
import 'package:reparto/mapa/pmtiles.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';

Future<PaqueteDeTeselas> _muestra() async => PaqueteDeTeselas.abrir(
  RangosEnMemoria(
    await File('test/mapa/muestra/cuba-muestra.pmtiles').readAsBytes(),
  ),
);

/// Dónde cae La Habana en la rejilla de teselas, a un zoom dado. Es la misma
/// proyección —Mercator web— que usa `croquis_de_ruta.dart`: si aquí se usara
/// otra, la prueba buscaría la tesela de otro sitio y saldría verde sin serlo.
({int x, int y}) _habana(int z) {
  const lon = -82.38;
  const lat = 23.13;
  final n = 1 << z;
  final seno = math.sin(lat * math.pi / 180);
  return (
    x: ((lon + 180) / 360 * n).floor(),
    y: ((0.5 - math.log((1 + seno) / (1 - seno)) / (4 * math.pi)) * n).floor(),
  );
}

/// Una fuente que deja leer la cabecera y **revienta al leer las teselas**. Es
/// lo que pasa cuando el fichero se borra, la tarjeta se saca o el sistema
/// quita el permiso con la aplicación abierta.
class _FuenteQueRevienta implements LeerPorRangos {
  _FuenteQueRevienta(this.buena);

  final RangosEnMemoria buena;
  var yaLeyoLaCabecera = false;

  @override
  Future<Uint8List> leer(int desde, int largo) async {
    if (!yaLeyoLaCabecera) {
      yaLeyoLaCabecera = true;
      return buena.leer(desde, largo);
    }
    throw const FileSystemException('se quitó la tarjeta');
  }

  @override
  Future<void> cerrar() async {}
}

/// Un fondo que dice haber sido llamado. Para comprobar el orden.
class _FondoQueCuenta implements FondoDeCalles {
  int llamadas = 0;

  @override
  Future<ui.Image?> tesela(int z, int x, int y) async {
    llamadas++;
    return null;
  }
}

void main() {
  // Hace falta para `TextPainter` y para rasterizar. **Pruebas normales y no
  // `testWidgets`**: aquí no se monta ninguna pantalla, y dentro de un
  // `testWidgets` el reloj no avanza solo.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la tesela del paquete sale dibujada, de 256', () async {
    final paquete = await _muestra();
    final fondo = FondoDelPaquete(paquete);
    final donde = _habana(6);

    final imagen = await fondo.tesela(6, donde.x, donde.y);

    expect(imagen, isNotNull, reason: 'La Habana está en la muestra a z6');
    expect(imagen!.width, 256);
    expect(imagen.height, 256);
  });

  test('lo que el paquete no tiene NO se inventa', () async {
    final paquete = await _muestra();
    final fondo = FondoDelPaquete(paquete);

    // Medio mundo más allá: en la muestra no hay nada ahí.
    expect(await fondo.tesela(6, 0, 0), isNull);
  });

  test(
    'sin paquete y sin red NO se lanza: el croquis sigue debajo',
    () async {
      // Es la promesa del proyecto: **el paquete es una mejora, nunca un
      // requisito**. Si esto lanzara, el mapa de la ruta se quedaría en negro
      // justo donde tiene que servir.
      final paquete = await _muestra();
      final fondo = FondoDelPaquete(paquete);
      expect(await fondo.tesela(6, 0, 0), isNull);
      expect(await fondo.tesela(19, 0, 0), isNull);
      expect(await fondo.tesela(3, 100, 100), isNull);
    },
  );

  test('por encima del zoom del paquete se AMPLÍA, no se deja hueco', () async {
    // La muestra llega a z6 y el mapa de una ruta apretada pide z14. Sin esto,
    // el chofer que se acerca ve desaparecer el mapa.
    final paquete = await _muestra();
    final fondo = FondoDelPaquete(paquete);
    final donde = _habana(14);

    final imagen = await fondo.tesela(14, donde.x, donde.y);

    expect(
      imagen,
      isNotNull,
      reason:
          'el paquete llega a z${paquete.cabecera.zMax} y se pidió z14: hay que '
          'ampliar el antepasado, no devolver nada',
    );
    expect(imagen!.width, 256);
  });

  test('el paquete manda, y la red sólo se usa para lo que falta', () async {
    final paquete = await _muestra();
    final red = _FondoQueCuenta();
    final fondo = FondoDelPaquete(paquete, respaldo: red);
    final donde = _habana(6);

    await fondo.tesela(6, donde.x, donde.y);
    expect(
      red.llamadas,
      0,
      reason:
          'el paquete la tenía: salir a la red igual es gastar datos de Cuba '
          'para dibujar lo que ya estaba dentro',
    );

    await fondo.tesela(6, 0, 0);
    expect(red.llamadas, 1, reason: 'ésa no estaba, así que se pregunta fuera');
  });

  test('lo ya dibujado no se vuelve a decodificar', () async {
    final paquete = await _muestra();
    final red = _FondoQueCuenta();
    final fondo = FondoDelPaquete(paquete, respaldo: red);

    await fondo.tesela(6, 0, 0);
    await fondo.tesela(6, 0, 0);
    await fondo.tesela(6, 0, 0);
    expect(
      red.llamadas,
      1,
      reason: 'volver a abrir la misma ruta no puede volver a pedir lo mismo',
    );
  });

  test('un fichero que revienta al leerlo NO tumba el mapa', () async {
    // Es el try/catch de `_delPaquete`. Sin él, sacar la tarjeta con la
    // aplicación abierta deja la pantalla de la ruta en negro en vez de dejar el
    // croquis, que se dibuja con lo que ya está en la base local.
    final fuente = _FuenteQueRevienta(
      RangosEnMemoria(
        await File('test/mapa/muestra/cuba-muestra.pmtiles').readAsBytes(),
      ),
    );
    final paquete = await PaqueteDeTeselas.abrir(fuente);
    final fondo = FondoDelPaquete(paquete);

    expect(await fondo.tesela(6, _habana(6).x, _habana(6).y), isNull);
  });

  pruebasDelCableado();

  test('un paquete con bytes de basura no tumba el mapa', () async {
    // Se trucan los datos manteniendo la cabecera y los directorios: el lector
    // encuentra la entrada y lo que hay detrás no es una tesela.
    final crudo = Uint8List.fromList(
      await File('test/mapa/muestra/cuba-muestra.pmtiles').readAsBytes(),
    );
    final cabecera = ByteData.sublistView(crudo);
    final datosDesde = cabecera.getUint64(56, Endian.little);
    for (var i = datosDesde; i < crudo.length; i++) {
      crudo[i] = 0x41;
    }
    final paquete = await PaqueteDeTeselas.abrir(RangosEnMemoria(crudo));
    final fondo = FondoDelPaquete(paquete);
    final donde = _habana(6);

    // Ni lanza ni cuelga: devuelve nada y el croquis se dibuja igual.
    expect(await fondo.tesela(6, donde.x, donde.y), isNull);
  });
}

// ── EL CABLEADO, que es donde estuvo el fallo de verdad ─────────────────────
//
// `fondoConPaqueteProvider` es el que SUSTITUYE a `fondoDeCallesProvider` en
// `main.dart`. Si además lo mirase para sacar el respaldo de red, se estaría
// mirando a sí mismo: Riverpod entra en dependencia circular y **la pantalla de
// la ruta revienta al abrirse** — no al arrancar, que sería visible, sino al
// abrir una ruta, que es lo que hace el logístico a las siete de la mañana.
//
// Esta prueba monta exactamente la sustitución que va en `main.dart`. Es la
// única forma de que ese fallo no llegue al patio de un almacén, porque no lo
// caza ni el analizador ni ninguna prueba de las de arriba.
void pruebasDelCableado() {
  test('la sustitución de main.dart no se mira a sí misma', () {
    final contenedor = ProviderContainer(
      overrides: [
        trabajaSinConexionProvider.overrideWithValue(true),
        carpetaDelMapaProvider.overrideWith((ref) async => CarpetaEnMemoria()),
        // ÉSTA es la línea de `main.dart`, copiada tal cual.
        fondoDeCallesProvider.overrideWith(
          (ref) => ref.watch(fondoConPaqueteProvider),
        ),
      ],
    );
    addTearDown(contenedor.dispose);

    // Sin paquete guardado cae al de OSM, y sobre todo: **no revienta**.
    expect(contenedor.read(fondoDeCallesProvider), isA<FondoDeCalles>());
  });
}
