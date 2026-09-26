// CAMBIAR DE SUCURSAL VUELVE A TRAER LA COPIA ENTERA.
//
// La bajada es por diferencias: pide «lo que cambió desde …», y ese «desde» es el de la
// bajada anterior — la de la OTRA sucursal—. Los pedidos de la nueva no han cambiado desde
// entonces, así que **no vienen nunca**. Y no falla nada: sale un número, y es mentira.
//
// Jose, 26/09/2026, cambiando a Camagüey: el Tablero decía «Sin colocar (0)» y a los dos
// minutos «(24)» mientras `GET /api/board` contestaba **40**. Comprobado pidiéndoselo al
// servidor desde la propia página, no deducido. Es el fallo del `CLAUDE.md` §4, el que más
// caro sale aquí: un cero creíble que ninguna pantalla desmiente.
//
// LO QUE SE PRUEBA, y son tres cosas que se rompen por separado:
//
//  1. que el cursor se olvida —si no, el ciclo vuelve a pedir desde donde iba—;
//  2. que **`bajadaAt` NO se olvida**, porque es lo que deja distinguir «esta sucursal no
//     lo tiene» de «todavía no ha bajado». Borrarlo cambia un número equivocado por un
//     cartel equivocado, y en el Tablero eso es la pantalla en blanco del 25/09;
//  3. que el ciclo se dispara **después** de olvidar, no antes. Al revés lee el cursor
//     viejo y la vuelta se pierde entera sin que nada lo diga.
//
// Y la pareja: volver a elegir LA MISMA sucursal no trae nada. Sin eso, tocar el selector
// sin cambiar nada sería una bajada completa por la conexión de allá.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../apoyo/base_de_prueba.dart';

void main() {
  late BaseLocal base;
  late RegistroDeFrescura frescura;
  final ahora = DateTime(2026, 9, 26, 13);

  setUp(() {
    base = baseDePrueba();
    frescura = RegistroDeFrescura(base, reloj: () => ahora);
  });
  tearDown(() => base.close());

  /// Una copia ya bajada: con su cursor y con su marca de que llegó.
  Future<void> yaBajado() async {
    for (final c in Colecciones.todas) {
      await frescura.marcar(
        c,
        hasta: '2026-09-26T12:00:00.000Z',
        bajadaAt: DateTime(2026, 9, 26, 12),
        completa: true,
      );
    }
  }

  group('olvidarElCursor', () {
    test('deja el cursor en nulo y la marca de bajada intacta', () async {
      await yaBajado();

      await frescura.olvidarElCursor(Colecciones.todas);

      for (final c in Colecciones.todas) {
        final fila = await frescura.leer(c);
        expect(
          fila?.hasta,
          isNull,
          reason:
              'con el cursor puesto el ciclo pide «lo que cambió desde la '
              'sucursal de antes», y los pedidos de la nueva no cambiaron: no '
              'vienen nunca',
        );
        expect(
          fila?.bajadaAt,
          isNotNull,
          reason:
              'esto llegó alguna vez a este aparato, y borrarlo cambia un '
              'número equivocado por «todavía no ha bajado», que es el cartel '
              'en blanco del Tablero',
        );
      }
    });

    test('sólo toca las colecciones que se le nombran', () async {
      await yaBajado();

      await frescura.olvidarElCursor(const [Colecciones.pedidos]);

      expect((await frescura.leer(Colecciones.pedidos))?.hasta, isNull);
      expect(
        (await frescura.leer(Colecciones.clientes))?.hasta,
        isNotNull,
        reason: 'olvidar de más es volver a bajarlo todo sin motivo',
      );
    });
  });

  group('al tocar el selector de sucursal', () {
    /// El orden importa y por eso se apunta: si el ciclo corre ANTES de
    /// olvidar, lee el cursor viejo y la vuelta se pierde.
    late List<String> pasos;

    ProviderContainer montar() {
      pasos = [];
      return ProviderContainer(
        overrides: [
          baseProvider.overrideWithValue(base),
          frescuraProvider.overrideWithValue(
            _FrescuraQueApunta(base, reloj: () => ahora, pasos: pasos),
          ),
          dispararCicloProvider.overrideWithValue((motivo) async {
            pasos.add('ciclo');
            // EL CURSOR YA TIENE QUE ESTAR OLVIDADO AQUI DENTRO. Comprobarlo en
            // el momento en que el ciclo corre es lo unico que ata el orden: la
            // lista de pasos sola se puede cumplir con las dos cosas sueltas.
            final fila = await frescura.leer(Colecciones.pedidos);
            if (fila?.hasta != null) pasos.add('ciclo con el cursor VIEJO');
          }),
        ],
      );
    }

    test('cambiar de sucursal olvida el cursor Y LUEGO baja', () async {
      await yaBajado();
      final c = montar();
      addTearDown(c.dispose);

      c.read(sucursalMiradaProvider.notifier).mirar('b-cam');
      // `mirar` no espera a propósito —quien toca el selector ya está viendo la
      // otra sucursal—, así que aquí se le da el turno al trabajo de después.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        pasos,
        ['olvidar', 'ciclo'],
        reason: 'al revés, el ciclo lee el cursor viejo y no trae nada',
      );
      expect((await frescura.leer(Colecciones.pedidos))?.hasta, isNull);
    });

    test('volver a elegir la MISMA no baja nada', () async {
      await yaBajado();
      final c = montar();
      addTearDown(c.dispose);

      c.read(sucursalMiradaProvider.notifier).mirar('b-cam');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      pasos.clear();

      c.read(sucursalMiradaProvider.notifier).mirar('b-cam');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        pasos,
        isEmpty,
        reason:
            'tocar el selector sin cambiar nada no puede costar una bajada '
            'completa por la conexión de allá',
      );
    });
  });
}

/// Apunta cuándo se olvidó el cursor, y lo olvida de verdad.
class _FrescuraQueApunta extends RegistroDeFrescura {
  _FrescuraQueApunta(super.base, {required super.reloj, required this.pasos});

  final List<String> pasos;

  @override
  Future<void> olvidarElCursor(List<String> colecciones) {
    pasos.add('olvidar');
    return super.olvidarElCursor(colecciones);
  }
}
