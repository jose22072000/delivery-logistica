import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';

import '../../apoyo/apoyo_sesion.dart';
import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

/// EL ALTA DEL APARATO, `POST /sync/aparato`.
///
/// Sin esto, `POST /sync/subida` contestaba **404 «Ese aparato no está
/// registrado»** contra el servidor de verdad: el ciclo corria entero, el
/// trabajo se quedaba guardado, y no subia nada. Estas pruebas son las que
/// impiden que vuelva a pasar sin que nadie se entere.
void main() {
  late BaseLocal base;
  late RelojFalso reloj;
  late ColaDeSalida cola;

  const idDelServidor = '9f3a0d2e-0000-4000-8000-000000000001';

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 15, 17, 40));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });

  tearDown(() => base.close());

  ({Subida subida, IdentidadDelAparato aparato, ServidorFalso servidor}) montar(
    Future<RespuestaFalsa?> Function(PeticionVista) responder,
  ) {
    final servidor = ServidorFalso(responder);
    final cliente = clienteFalso(responder, baseUrl: 'https://sync.test');
    cliente.dio.httpClientAdapter = servidor;
    final aparato = IdentidadDelAparato(base, sync: cliente);
    return (
      subida: Subida(
        cliente: cliente,
        cola: cola,
        aparato: aparato,
        base: base,
        quienEsta: () async => null,
      ),
      aparato: aparato,
      servidor: servidor,
    );
  }

  /// Un servidor que da el alta y acepta lo que le llegue.
  Future<RespuestaFalsa?> normal(PeticionVista p) async {
    if (p.ruta.endsWith('/aparato')) {
      return RespuestaFalsa(201, <String, Object?>{
        'aparato': idDelServidor,
        'persona': 'u-1',
        'sucursal': 'STG',
      });
    }
    final cuerpo = p.cuerpo! as Map<String, Object?>;
    final apuntes = cuerpo['apuntes']! as List<Object?>;
    return RespuestaFalsa(200, <String, Object?>{
      'resultados': [
        for (final a in apuntes.cast<Map<String, Object?>>())
          <String, Object?>{'clave': a['clave'], 'estado': 'aplicado'},
      ],
    });
  }

  Future<void> encolar([int cuantos = 1]) async {
    for (var i = 1; i <= cuantos; i++) {
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-$i/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );
    }
  }

  group('el identificador lo pone el SERVIDOR', () {
    test('un aparato nuevo se da de alta antes del primer envio', () async {
      await encolar();
      final m = montar(normal);

      await m.subida.ciclo();

      final rutas = m.servidor.vistas.map((p) => p.ruta).toList();
      expect(
        rutas.first,
        endsWith('/aparato'),
        reason: 'el alta va ANTES: sin ella la subida es un 404',
      );
      expect(rutas, hasLength(2));

      // Y lo que viaja es el identificador del SERVIDOR, no uno inventado aqui:
      // uno inventado por el telefono podria repetirse entre dos instalaciones y
      // entonces dos aparatos compartirian cola y claves de idempotencia.
      final lote = m.servidor.vistas.last.cuerpo! as Map<String, Object?>;
      expect(lote['aparato'], idDelServidor);
    });

    test('la segunda subida NO vuelve a dar de alta', () async {
      await encolar(2);
      final m = montar(normal);

      await m.subida.ciclo();
      await cola.encolar(
        metodo: 'POST',
        ruta: '/api/routes/r-9/results',
        cuerpo: <String, Object?>{'resultado': 'entregado'},
      );
      await m.subida.ciclo();

      expect(
        m.servidor.vistas.where((p) => p.ruta.endsWith('/aparato')),
        hasLength(1),
        reason:
            'dar de alta en cada envio crearia un aparato por subida y '
            'llenaria el panel de fantasmas',
      );
    });

    test(
      'la sucursal NO se manda: la pone el servidor con la sesion',
      () async {
        await encolar();
        final m = montar(normal);
        await m.subida.ciclo();

        final alta =
            m.servidor.vistas
                    .firstWhere((p) => p.ruta.endsWith('/aparato'))
                    .cuerpo
                as Map<String, Object?>;
        expect(
          alta.containsKey('sucursal'),
          isFalse,
          reason:
              'mandarla seria ofrecerle a cualquiera darse de alta en otra '
              'sucursal y bajar desde ahi (`aparato.go`)',
        );
      },
    );
  });

  group('cuando el alta falla', () {
    test('se dice POR QUE y la cola queda ENTERA', () async {
      await encolar(3);
      final m = montar((p) async {
        if (p.ruta.endsWith('/aparato')) {
          return RespuestaFalsa(500, <String, Object?>{
            'mensaje': 'No se pudo registrar el aparato',
          });
        }
        return normal(p);
      });

      // Lo que lanza sale tal cual: quien llama tiene que poder decir por que en
      // vez de tragarselo y dejar la cola parada sin explicacion.
      await expectLater(m.subida.ciclo(), throwsA(isA<FalloApi>()));

      expect(
        await base.cuantosPendientes(),
        3,
        reason:
            'sin alta no se sube nada, y dar el lote por bueno seria tirar '
            'el dia',
      );
      expect(
        m.servidor.vistas.where((p) => p.ruta.endsWith('/subida')),
        isEmpty,
        reason: 'ni se intenta la subida: iba a ser un 404 seguro',
      );
    });

    test('sin red al dar de alta tampoco se toca la cola', () async {
      await encolar(2);
      final m = montar((p) async {
        if (p.ruta.endsWith('/aparato')) return null;
        return normal(p);
      });

      await expectLater(m.subida.ciclo(), throwsA(isA<FalloDeRed>()));
      expect(await base.cuantosPendientes(), 2);
    });
  });

  group('el aparato ya no esta registrado', () {
    test('un 404 da de alta otra vez y reintenta UNA sola vez', () async {
      // Pasa de verdad: al aparato lo borraron del registro, o se restauro una
      // copia de la base local con un alta que ya no existe.
      await aparatoYaDeAlta(base, id: 'el-viejo-que-ya-no-vale');
      await encolar(2);

      var altas = 0;
      final m = montar((p) async {
        if (p.ruta.endsWith('/aparato')) {
          altas++;
          return RespuestaFalsa(201, <String, Object?>{
            'aparato': idDelServidor,
          });
        }
        final cuerpo = p.cuerpo! as Map<String, Object?>;
        if (cuerpo['aparato'] == 'el-viejo-que-ya-no-vale') {
          return RespuestaFalsa(404, <String, Object?>{
            'mensaje':
                'Ese aparato no está registrado. Vuelve a darlo de alta.',
          });
        }
        return normal(p);
      });

      final resueltos = await m.subida.ciclo();

      expect(altas, 1, reason: 'se dio de alta otra vez, una sola');
      expect(resueltos, 2, reason: 'y el lote subio a la segunda');
      expect(await base.cuantosPendientes(), 0);
      expect(
        await m.aparato.leer(),
        idDelServidor,
        reason: 'y el identificador nuevo queda guardado',
      );
    });

    test('si el alta nueva tampoco sirve, NO se reintenta en bucle', () async {
      await aparatoYaDeAlta(base, id: 'el-viejo-que-ya-no-vale');
      await encolar(2);

      var subidas = 0;
      final m = montar((p) async {
        if (p.ruta.endsWith('/aparato')) {
          return RespuestaFalsa(201, <String, Object?>{
            'aparato': idDelServidor,
          });
        }
        subidas++;
        return RespuestaFalsa(404, <String, Object?>{
          'mensaje': 'Ese aparato no está registrado. Vuelve a darlo de alta.',
        });
      });

      await expectLater(m.subida.ciclo(), throwsA(isA<Rechazo>()));

      expect(
        subidas,
        2,
        reason:
            'un intento y UN reintento: un bucle le gastaria la bateria y '
            'los datos al logistico contra algo que no va a cambiar',
      );
      expect(await base.cuantosPendientes(), 2, reason: 'y la cola, entera');
    });
  });

  group('cerrar sesion', () {
    test(
      'el alta SOBREVIVE al logout: el aparato es el mismo aparato',
      () async {
        await aparatoYaDeAlta(base, id: idDelServidor);
        await base
            .into(base.preferencias)
            .insert(
              PreferenciasCompanion.insert(
                clave: 'otra-cosa',
                valor: 'se borra',
              ),
            );

        await base.borrarTodoLoDelDominio();

        expect(
          await IdentidadDelAparato(base).leer(),
          idDelServidor,
          reason:
              'si muriera aqui, cada logout daria de alta un aparato nuevo y '
              'el panel se llenaria de instalaciones fantasma entre las que no se '
              'podria distinguir el telefono que de verdad se quedo atras',
        );

        final resto = await (base.select(
          base.preferencias,
        )..where((p) => p.clave.equals('otra-cosa'))).get();
        expect(
          resto,
          isEmpty,
          reason:
              'y lo demas de `preferencias` se borra igual: lo que no puede '
              'quedarse en un telefono que cambia de manos es el dominio',
        );
      },
    );

    test('lo del DOMINIO si se borra', () async {
      await aparatoYaDeAlta(base);
      await base
          .into(base.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'c-1',
              name: 'Yasmani',
              lat: 20,
              lng: -75,
            ),
          );

      await base.borrarTodoLoDelDominio();

      expect(await base.select(base.customers).get(), isEmpty);
    });
  });
}
