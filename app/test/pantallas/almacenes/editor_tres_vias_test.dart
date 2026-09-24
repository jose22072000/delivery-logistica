import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/almacenes/datos/almacen_api.dart';
import 'package:reparto/pantallas/almacenes/datos/coordenadas.dart';
import 'package:reparto/pantallas/almacenes/datos/geocodificar.dart';
import 'package:reparto/pantallas/almacenes/vista/editor_almacen.dart';
import 'package:reparto/pantallas/almacenes/vista/mapa_para_elegir_punto.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';

/// LAS TRES VIAS DE PONER EL PUNTO DE UN ALMACEN, y lo que pasa con cada una
/// cuando no hay red.
///
/// De ese punto salen los kilometros de cada cliente de la sucursal y de ahi lo
/// que se le cobra a cada domicilio **todos los dias**. Las tres cosas que estas
/// pruebas no dejan pasar:
///
///  1. que el punto que se elige no sea el que se guarda;
///  2. que lo que conteste la geocodificacion se cambie por el camino;
///  3. que sin red la pantalla **finja** que geocodifico.
///
/// El geocodificador es siempre falso: **no sale ni una peticion**, que es regla
/// de la casa en este PC. Y el fondo del mapa es [SinCalles], que ademas deja la
/// pantalla como se ve en el patio de un almacen.
///
/// Nada de Drift aqui dentro: el editor no toca la base, y por eso se prueba
/// suelto en vez de abrirlo desde la pantalla (una consulta de Drift dentro de
/// un `testWidgets` **cuelga** la prueba en vez de fallarla, `CLAUDE.md` §5).
class GeoFalso implements Geocodificador {
  GeoFalso({
    this.contesta = const NoHayTalDireccion(),
    this.contestaALaInversa = const SinNombreParaEsePunto(),
  });

  /// El que no contesta nunca, que es como esta el mundo sin señal.
  factory GeoFalso.sinRed() => GeoFalso(
    contesta: const NoSePudoPreguntar('sin red'),
    contestaALaInversa: const NoSePudoPreguntarElPunto('sin red'),
  );

  final BusquedaDeDireccion contesta;
  final BusquedaDePunto contestaALaInversa;

  final List<String> buscadas = [];
  final List<PuntoEnElMapa> preguntadas = [];

  @override
  Future<BusquedaDeDireccion> buscarDireccion(String texto) async {
    buscadas.add(texto);
    return contesta;
  }

  @override
  Future<BusquedaDePunto> comoSeLlamaEstePunto(PuntoEnElMapa punto) async {
    preguntadas.add(punto);
    return contestaALaInversa;
  }
}

void main() {
  /// Donde contesta Nominatim en estas pruebas. Con cinco decimales, que es como
  /// se escribe un punto (`escribirCoordenadas`).
  const elPuntoQueContesta = PuntoEnElMapa(20.0247, -75.8219);
  const textoDeEsePunto = '20.02470, -75.82190';

  /// Lo que el editor mando a guardar. Una caja y no una variable suelta para
  /// poder leerla despues de que la prueba haya seguido corriendo.
  Future<LoGuardado> pintar(
    WidgetTester tester, {
    required GeoFalso geo,
    AlmacenDeAccesos? almacen,
    PuntoEnElMapa? centro,
  }) async {
    final caja = LoGuardado();
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorAlmacen(
            almacen: almacen,
            sucursal: 'Santiago',
            guardando: false,
            geocodificador: geo,
            fondoDelMapa: const SinCalles(),
            centroDelMapa: centro,
            alGuardar: (a) => caja.almacen = a,
          ),
        ),
      ),
    );
    return caja;
  }

  /// Lo que hay escrito en una caja, buscada por su rotulo.
  String loEscritoEn(WidgetTester tester, String rotulo) {
    final campo = tester.widget<TextField>(
      find.ancestor(
        of: find.text(rotulo),
        matching: find.byType(TextField),
      ),
    );
    return campo.controller!.text;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // VIA 1: la direccion, geocodificada. EN PAREJA: con red y sin red.
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('CON RED: buscar la dirección pone EXACTAMENTE el punto que '
      'contestó, y es ese el que se guarda', (tester) async {
    final geo = GeoFalso(
      contesta: const PuntoHallado(
        elPuntoQueContesta,
        comoLoLlama: 'Almacén central, Santiago de Cuba',
      ),
    );
    final loGuardado = await pintar(tester, geo: geo);
    await tester.pump();

    await tester.enterText(
      find.ancestor(
        of: find.text('Nombre del almacén'),
        matching: find.byType(TextField),
      ),
      'Central',
    );
    await tester.enterText(
      find.ancestor(
        of: find.text('Dirección'),
        matching: find.byType(TextField),
      ),
      'Almacén central Santiago',
    );
    await tester.pump();
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(geo.buscadas, ['Almacén central Santiago']);
    expect(
      loEscritoEn(tester, 'Coordenadas'),
      textoDeEsePunto,
      reason:
          'el punto que se enseña tiene que ser el que contestó el servicio, '
          'sin tocar: con dos dígitos cambiados se lee igual de bien y está mal',
    );
    expect(find.textContaining('Encontrado «Almacén central'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final guardado = loGuardado.almacen;
    expect(guardado, isNotNull, reason: 'tenía que guardar');
    expect(guardado!.latitud, elPuntoQueContesta.lat);
    expect(guardado.longitud, elPuntoQueContesta.lng);
  });

  testWidgets('SIN RED: lo dice, NO inventa un punto y deja la caja de '
      'coordenadas vacía', (tester) async {
    final geo = GeoFalso.sinRed();
    final loGuardado = await pintar(tester, geo: geo);
    await tester.pump();

    await tester.enterText(
      find.ancestor(
        of: find.text('Nombre del almacén'),
        matching: find.byType(TextField),
      ),
      'Central',
    );
    await tester.enterText(
      find.ancestor(
        of: find.text('Dirección'),
        matching: find.byType(TextField),
      ),
      'Almacén central Santiago',
    );
    await tester.pump();
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    // 1. LO DICE, y dice que no se preguntó: no es lo mismo que «no existe».
    expect(
      find.textContaining('Sin conexión no se puede buscar una dirección'),
      findsOneWidget,
      reason:
          'sin red hay que decirlo; quedarse girando o decir «no se encontró» '
          'manda a buscar otra dirección en vez de escribir el punto',
    );
    expect(find.textContaining('No se encontró esa dirección'), findsNothing);
    // 2. Y MANDA A LA VIA QUE NUNCA FALLA.
    expect(find.textContaining('escribe las coordenadas a mano'), findsOneWidget);
    // 3. NO SE INVENTA NADA.
    expect(
      loEscritoEn(tester, 'Coordenadas'),
      '',
      reason: 'sin respuesta no puede aparecer ningún punto en la caja',
    );

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final guardado = loGuardado.almacen;
    expect(guardado!.latitud, isNull, reason: 'sin punto se guarda SIN punto');
    expect(guardado.longitud, isNull);
  });

  testWidgets('cuando el servicio contesta y no conoce la dirección, el punto '
      'que ya había NO se mueve', (tester) async {
    // No encontrar una direccion no es motivo para mover un almacen que ya
    // estaba colocado.
    final geo = GeoFalso();
    await pintar(
      tester,
      geo: geo,
      almacen: const AlmacenDeAccesos(
        id: 'w1',
        nombre: 'Central',
        latitud: 20.0247,
        longitud: -75.8219,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.ancestor(
        of: find.text('Dirección'),
        matching: find.byType(TextField),
      ),
      'una dirección que no existe',
    );
    await tester.pump();
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No se encontró esa dirección'), findsOneWidget);
    expect(loEscritoEn(tester, 'Coordenadas'), '20.0247, -75.8219');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // VIA 3: pulsar en el mapa. EN PAREJA: con red y sin red.
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('CON RED: pulsar en el mapa pone el punto Y trae la dirección', (
    tester,
  ) async {
    final geo = GeoFalso(
      contestaALaInversa: const DireccionHallada('Calle 5 nº 12, Santiago'),
    );
    final loGuardado = await pintar(
      tester,
      geo: geo,
      // El mapa abre aqui porque el almacen es nuevo: es el punto de otro
      // almacen de la misma sucursal.
      centro: elPuntoQueContesta,
    );
    await tester.pump();

    await tester.enterText(
      find.ancestor(
        of: find.text('Nombre del almacén'),
        matching: find.byType(TextField),
      ),
      'Patio sur',
    );
    await tester.pump();
    expect(loEscritoEn(tester, 'Coordenadas'), '');

    await tester.tapAt(
      tester.getCenter(find.byKey(MapaParaElegirPunto.clave)),
    );
    await tester.pumpAndSettle();

    // Pulsar en el centro del mapa devuelve el punto en el que abrio.
    expect(loEscritoEn(tester, 'Coordenadas'), textoDeEsePunto);
    expect(geo.preguntadas, hasLength(1));
    // La direccion estaba vacia, asi que se rellena sola.
    expect(loEscritoEn(tester, 'Dirección'), 'Calle 5 nº 12, Santiago');

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final guardado = loGuardado.almacen;
    expect(
      guardado!.latitud,
      elPuntoQueContesta.lat,
      reason: 'el punto que se pulsó tiene que ser el que se manda a Accesos',
    );
    expect(guardado.longitud, elPuntoQueContesta.lng);
    expect(guardado.direccion, 'Calle 5 nº 12, Santiago');
  });

  testWidgets('SIN RED: pulsar en el mapa SIGUE poniendo el punto, y la '
      'dirección se queda vacía en vez de rellenarse con las coordenadas', (
    tester,
  ) async {
    // Es la diferencia de fondo con el patron: su `reverseGeocode` devuelve
    // `formatCoords(lat,lng)` cuando falla, o sea que la caja de la direccion se
    // rellena sola con «20.02470, -75.82190» y la pantalla queda IDENTICA a si
    // hubiera geocodificado. Un hueco disfrazado de dato.
    final geo = GeoFalso.sinRed();
    final loGuardado = await pintar(tester, geo: geo, centro: elPuntoQueContesta);
    await tester.pump();

    await tester.enterText(
      find.ancestor(
        of: find.text('Nombre del almacén'),
        matching: find.byType(TextField),
      ),
      'Patio sur',
    );
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(MapaParaElegirPunto.clave)),
    );
    await tester.pumpAndSettle();

    // EL PUNTO SI, porque eso es geometria del aparato y no depende de nadie.
    expect(
      loEscritoEn(tester, 'Coordenadas'),
      textoDeEsePunto,
      reason: 'pulsar en el mapa tiene que funcionar sin señal',
    );
    // LA DIRECCION NO, y se dice por que.
    expect(
      loEscritoEn(tester, 'Dirección'),
      '',
      reason:
          'sin conexión la dirección se queda VACÍA: el patrón la rellena con '
          'las coordenadas formateadas y entonces la pantalla se ve igual que '
          'si hubiera geocodificado',
    );
    expect(
      find.textContaining('Sin conexión no se pudo traer la dirección'),
      findsOneWidget,
    );

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final guardado = loGuardado.almacen;
    expect(guardado!.latitud, elPuntoQueContesta.lat);
    expect(guardado.longitud, elPuntoQueContesta.lng);
    expect(
      guardado.direccion,
      isNull,
      reason: 'sin dirección se guarda sin dirección, no con un número dentro',
    );
  });

  testWidgets('una dirección ya escrita NO la pisa el mapa: se ofrece', (
    tester,
  ) async {
    final geo = GeoFalso(
      contestaALaInversa: const DireccionHallada('90400, Cuba'),
    );
    await pintar(tester, geo: geo, centro: elPuntoQueContesta);
    await tester.pump();

    await tester.enterText(
      find.ancestor(
        of: find.text('Dirección'),
        matching: find.byType(TextField),
      ),
      'Carretera del Morro km 3, junto a la nave azul',
    );
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(MapaParaElegirPunto.clave)),
    );
    await tester.pumpAndSettle();

    expect(
      loEscritoEn(tester, 'Dirección'),
      'Carretera del Morro km 3, junto a la nave azul',
      reason: 'un toque sin querer no puede borrar lo que escribió una persona',
    );
    expect(find.textContaining('El mapa dice que ahí es «90400, Cuba»'), findsOneWidget);

    // Y si se quiere, se coge.
    await tester.tap(find.text('Usar ésa'));
    await tester.pumpAndSettle();
    expect(loEscritoEn(tester, 'Dirección'), '90400, Cuba');
  });

  // ───────────────────────────────────────────────────────────────────────────
  // VIA 2: a mano. LA QUE NO SE TOCA.
  // ───────────────────────────────────────────────────────────────────────────

  testWidgets('escribir las coordenadas a mano funciona SIN geocodificador y '
      'sin mapa cargado', (tester) async {
    final loGuardado = await pintar(tester, geo: GeoFalso.sinRed());
    await tester.pump();

    await tester.enterText(
      find.ancestor(
        of: find.text('Nombre del almacén'),
        matching: find.byType(TextField),
      ),
      'Central',
    );
    await tester.enterText(
      find.ancestor(
        of: find.text('Coordenadas'),
        matching: find.byType(TextField),
      ),
      '19.83, -75.82',
    );
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final guardado = loGuardado.almacen;
    expect(guardado!.latitud, 19.83);
    expect(guardado.longitud, -75.82);
  });

  testWidgets('el mapa dice que su fondo no cargó, y que aun así se puede '
      'pulsar', (tester) async {
    await pintar(tester, geo: GeoFalso.sinRed());
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('El fondo del mapa no ha cargado'),
      findsOneWidget,
    );
    expect(find.textContaining('pone el punto igual'), findsOneWidget);
  });

  testWidgets('la ✕ del cajón sigue estando', (tester) async {
    // Regla de la casa para todos los proyectos de Procovar: cajón siempre, y la
    // ✕ nunca puede desaparecer.
    await pintar(tester, geo: GeoFalso.sinRed());
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byTooltip('Cerrar'), findsOneWidget);
  });
}

/// Donde cae lo que el editor manda a guardar.
class LoGuardado {
  AlmacenDeAccesos? almacen;
}
