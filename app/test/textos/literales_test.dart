/// Un puñado de textos críticos, comparados **carácter a carácter** contra una
/// copia del pliego.
///
/// No se comparan todos: se comparan los que, si cambian una coma, cambian lo
/// que alguien entiende. Y se comprueba la regla que más fácil se rompe sin
/// querer — que un `pedido(s)` del pliego no se convierta en un plural de ICU.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/post_despacho.dart';
import 'package:reparto/impresion/pre_despacho.dart';
import 'package:reparto/textos/textos.dart';

void main() {
  late Textos es;
  late Textos en;

  setUpAll(() async {
    es = await Textos.delegate.load(const Locale('es'));
    en = await Textos.delegate.load(const Locale('en'));
  });

  group('los textos que no pueden cambiar', () {
    test('los de la barra lateral', () {
      expect(es.navPanel, 'Panel');
      expect(es.navPedidos, 'Pedidos');
      expect(es.navRutas, 'Rutas');
      expect(es.navClientes, 'Clientes');
      expect(es.navVehiculos, 'Vehículos');
      expect(es.navAlmacenes, 'Almacenes');
      expect(es.navCerrarSesion, 'Cerrar sesión');
    });

    test('los avisos de sobrepeso, que deciden si sale un camión', () {
      expect(es.rutasSobrepeso, 'Sobrepeso');
      expect(
        es.rutasSobrepesoDetalle('3200', '2500'),
        'Peso total (3200 kg) supera capacidad (2500 kg)',
      );
      expect(
        es.rutasAvisoSobreCapacidad('3200', '2500'),
        'Peso (3200 kg) supera capacidad del vehículo (2500 kg)',
      );
    });

    test('el aviso de una ruta ya lanzada', () {
      expect(
        es.rutasNotaSoloLectura,
        'Ruta activa (solo lectura). Al completarla, el vehículo queda '
        'disponible y pasa al historial.',
      );
    });

    test('el de sucursal, que decide qué datos ve alguien', () {
      expect(
        es.usuariosNotaSucursal,
        'Un usuario con sucursal solo ve/gestiona los datos de ESA sucursal. '
        'Sin sucursal = admin global (ve todas).',
      );
      expect(es.usuariosSinSucursal, 'Sin sucursal (admin — ve todo)');
    });

    test('el de la única fórmula de precio del sistema', () {
      expect(
        es.ajustesAyudaDomicilio,
        'La ÚNICA fórmula de precio del sistema. Lo que se le cobra al cliente '
        'lo pone el repartidor desde la APK; esto es lo que delivery usa para '
        'repartir la carga del camión entre los pedidos.',
      );
    });

    test('el del código de sucursal, que enlaza con PEDIDO', () {
      expect(
        es.sucursalesNotaCodigo,
        'Identifica la sucursal y la enlaza con PEDIDO. Usa el mismo código '
        'que en PEDIDO.',
      );
    });

    test('los estados de una ruta y de un vehículo', () {
      expect(es.rutasEstadoPlanificada, 'Planificada');
      expect(es.rutasEstadoEnCurso, 'En curso');
      expect(es.rutasEstadoCompletada, 'Completada');
      expect(es.vehiculosEstadoDisponible, 'Disponible');
      expect(es.vehiculosEstadoEnUso, 'En uso');
      expect(es.vehiculosEstadoMantenimiento, 'Mantenimiento');
    });

    test('las tildes y las comillas angulares están donde estaban', () {
      // El pliego usa `…` y `—`, no tres puntos ni un guion normal.
      expect(es.comunCargando, 'Cargando...');
      expect(es.ubicacionBuscando, 'Buscando ubicación…');
      expect(
        es.ubicacionNoEncontrado,
        'No se encontró. Sé más específico, pega coordenadas, o usa el mapa.',
      );
    });
  });

  group('los mismos textos en inglés', () {
    test('están traducidos de verdad, no copiados', () {
      expect(en.navPanel, 'Dashboard');
      expect(en.navCerrarSesion, 'Log out');
      expect(en.rutasSobrepeso, 'Overweight');
      expect(
        en.rutasSobrepesoDetalle('3200', '2500'),
        'Total weight (3200 kg) exceeds capacity (2500 kg)',
      );
    });

    test('los marcadores siguen colocando el número en su sitio', () {
      expect(es.rutasParadasKm('12', '84'), '12 paradas · 84 km');
      expect(en.rutasParadasKm('12', '84'), '12 stops · 84 km');
      expect(
        es.usuariosActividad('9', '3', '2'),
        '9 órdenes, 3 rutas, 2 vehículos',
      );
      expect(
        en.usuariosActividad('9', '3', '2'),
        '9 orders, 3 routes, 2 vehicles',
      );
    });
  });

  group('nada de pluralizar con ICU lo que el pliego escribe con «(s)»', () {
    test('las hojas impresas conservan el `(s)` dentro del texto', () {
      // Estos son los que más se comparan con la de Next: van literales.
      expect(TextoPreDespacho.pedidos, ' pedido(s)');
      expect(TextoPostDespacho.entregadas, ' entregada(s)');
      expect(TextoPostDespacho.devueltas, ' devuelta(s)');
      expect(TextoPostDespacho.canceladas, ' cancelada(s)');

      // Y se escriben igual con uno que con muchos: no hay singular aparte.
      expect('1${TextoPreDespacho.pedidos}', '1 pedido(s)');
      expect('7${TextoPreDespacho.pedidos}', '7 pedido(s)');
    });

    test('ningún texto del ARB usa plural{} ni select{} de ICU', () {
      final arb = jsonDecode(
        File('lib/textos/arb/app_es.arb').readAsStringSync(),
      ) as Map<String, Object?>;

      for (final e in arb.entries) {
        if (e.key.startsWith('@')) continue;
        final v = e.value! as String;
        expect(
          v,
          isNot(contains(', plural,')),
          reason: '${e.key} pluraliza con ICU',
        );
        expect(
          v,
          isNot(contains(', select,')),
          reason: '${e.key} usa select de ICU',
        );
      }
    });
  });

  group('las hojas impresas no pasan por los textos traducidos', () {
    test('sus literales son constantes en español', () {
      // El papel es el punto de paridad con el de Next: no puede cambiar con el
      // idioma que tenga puesta la barra superior.
      expect(TextoPreDespacho.titulo, 'Pre-despacho');
      expect(TextoPreDespacho.firmaSaco, 'Sacó del almacén');
      expect(TextoPreDespacho.firmaRecibio, 'Recibió (chofer)');

      expect(TextoPostDespacho.titulo, 'Post-despacho');
      expect(TextoPostDespacho.seccionQueda, 'Tiene que quedar en el camión');
      expect(TextoPostDespacho.seccionDeQuien, 'De quién es lo que vuelve');
      expect(
        TextoPostDespacho.nadaQueda,
        'Nada: se entregó todo lo que salió.',
      );
      expect(
        TextoPostDespacho.todoEntregado,
        'Todas las paradas se entregaron.',
      );
      expect(TextoPostDespacho.firmaEntrego, 'Entregó (chofer)');
      expect(TextoPostDespacho.firmaRecibio, 'Recibió en almacén');
    });

    test('las columnas se llaman como en el pliego', () {
      expect(
        <String>[
          TextoPreDespacho.colProducto,
          TextoPreDespacho.colEmpaques,
          TextoPreDespacho.colUnidades,
          TextoPreDespacho.colKg,
          TextoPreDespacho.colSacado,
        ],
        <String>['Producto', 'Empaques', 'Unidades', 'kg', 'Sacado'],
      );
      expect(
        <String>[
          TextoPostDespacho.colProducto,
          TextoPostDespacho.colSalio,
          TextoPostDespacho.colEntregado,
          TextoPostDespacho.colQueda,
          TextoPostDespacho.colBajo,
        ],
        <String>['Producto', 'Salió', 'Entregado', 'Queda', 'Bajó'],
      );
    });

    test('las etiquetas de una parada que vuelve', () {
      expect(TextoPostDespacho.etiquetaDevuelto, 'Devuelto');
      expect(TextoPostDespacho.etiquetaCancelado, 'Cancelado');
      expect(TextoPostDespacho.etiquetaSinMarcar, 'Sin marcar');
    });
  });

  group('los textos nuevos de esta aplicación', () {
    test('la vista previa tiene sus tres acciones en los dos idiomas', () {
      expect(es.nuevoImprimir, 'Imprimir');
      expect(es.nuevoCompartir, 'Compartir');
      expect(es.nuevoCerrar, 'Cerrar');
      expect(en.nuevoImprimir, 'Print');
      expect(en.nuevoCompartir, 'Share');
      expect(en.nuevoCerrar, 'Close');
    });
  });

  group('los dos idiomas de la casa', () {
    test('español primero: es el idioma del almacén', () {
      expect(idiomas.first.languageCode, 'es');
      expect(idiomas.map((l) => l.languageCode), <String>['es', 'en']);
    });

    test(
      'la lista de la casa y la que declara la clase generada coinciden',
      () {
        expect(
          Textos.supportedLocales.map((l) => l.languageCode).toSet(),
          idiomas.map((l) => l.languageCode).toSet(),
        );
      },
    );

    test('van las delegaciones de Material, no solo las nuestras', () {
      // Sin ellas, un selector de fecha sale en inglés dentro de una pantalla
      // en español y nadie sabe por qué.
      expect(delegacionesDeIdioma.length, greaterThan(1));
    });
  });
}
