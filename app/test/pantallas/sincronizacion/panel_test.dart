import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/pantallas/sincronizacion/datos/panel_sincronizacion.dart';
import 'package:reparto/pantallas/sincronizacion/datos/repositorio_sincronizacion.dart';

import 'apoyo_sincronizacion.dart';

/// Lo que decide el color y el texto de cada fila, probado sin pintar nada.
void main() {
  AparatoDelPanel leer(Map<String, Object?> j) => AparatoDelPanel.deJson(j);

  group('«nunca ha subido» NO es «lleva 0 horas»', () {
    final nunca = leer(aparatoJson(aparato: 'ap-palma', persona: 'María'));
    final recienSubido = leer(
      aparatoJson(
        aparato: 'ap-camaguey',
        persona: 'Luis',
        subida: '2026-09-14T09:58:00Z',
        horasSinSubir: 0,
      ),
    );

    test(
      'se distinguen por `subida`, que es lo que el servicio deja vacío',
      () {
        expect(nunca.nuncaSubio, isTrue);
        expect(nunca.horasSinSubir, isNull);
        expect(recienSubido.nuncaSubio, isFalse);
        expect(recienSubido.horasSinSubir, 0);
      },
    );

    test(
      'no comparten gravedad: uno es el peor caso y el otro está al día',
      () {
        expect(nunca.gravedad, GravedadSincro.nunca);
        expect(recienSubido.gravedad, GravedadSincro.alDia);
      },
    );

    test('no comparten texto', () {
      expect(TextosDeSincronizacion.sinSubir(nunca), 'Nunca ha subido');
      expect(
        TextosDeSincronizacion.sinSubir(recienSubido),
        'Hace menos de una hora',
      );
      expect(
        TextosDeSincronizacion.sinSubir(nunca),
        isNot(TextosDeSincronizacion.sinSubir(recienSubido)),
      );
    });

    test('un 0 que llegara con `subida` vacía sigue siendo «nunca»', () {
      // Si el servicio cambiara y mandara un 0 con la subida vacía —o el -1 de
      // `segundos_sin_subir` se colara por aquí—, lo que manda es `subida`.
      // «Nunca» no puede degradarse a «0 horas» por un número.
      final raro = leer(
        aparatoJson(aparato: 'ap-raro', persona: 'X', horasSinSubir: 0),
      );
      expect(raro.nuncaSubio, isTrue);
      expect(raro.gravedad, GravedadSincro.nunca);
      expect(TextosDeSincronizacion.sinSubir(raro), 'Nunca ha subido');
    });
  });

  group('los umbrales, que son los que deciden el color', () {
    AparatoDelPanel conHoras(int horas) => leer(
      aparatoJson(
        aparato: 'a',
        persona: 'p',
        subida: '2026-09-13T09:00:00Z',
        horasSinSubir: horas,
      ),
    );

    test('hasta la jornada, al día', () {
      expect(conHoras(0).gravedad, GravedadSincro.alDia);
      expect(conHoras(7).gravedad, GravedadSincro.alDia);
    });

    test('una jornada entera sin subir ya es ámbar', () {
      expect(conHoras(8).gravedad, GravedadSincro.atencion);
      expect(conHoras(23).gravedad, GravedadSincro.atencion);
    });

    test('un día entero es rojo: es el de llamar', () {
      expect(conHoras(24).gravedad, GravedadSincro.tarde);
      expect(conHoras(96).gravedad, GravedadSincro.tarde);
    });

    test('las palabras cuadran con el número', () {
      expect(TextosDeSincronizacion.sinSubir(conHoras(1)), 'Hace 1 hora');
      expect(TextosDeSincronizacion.sinSubir(conHoras(9)), 'Hace 9 horas');
      expect(TextosDeSincronizacion.sinSubir(conHoras(24)), 'Hace 1 día');
      // El caso del pliego: «Palma lleva desde el martes sin subir».
      expect(TextosDeSincronizacion.sinSubir(conHoras(74)), 'Hace 3 días');
    });
  });

  group('la respuesta de GET /sync/estado', () {
    final crudo = estadoJson(
      aparatos: [
        aparatoJson(aparato: 'ap-palma', persona: 'María', pendientes: 12),
        aparatoJson(
          aparato: 'ap-camaguey',
          persona: 'Luis',
          subida: '2026-09-12T09:00:00Z',
          horasSinSubir: 49,
          pendientes: 3,
          rechazados: 2,
        ),
        aparatoJson(
          aparato: 'ap-holguin',
          persona: 'Ana',
          subida: '2026-09-14T09:00:00Z',
          horasSinSubir: 1,
        ),
      ],
      bandeja: [
        rechazoJson(
          rechazo: 'r1',
          motivo:
              '3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.',
        ),
      ],
      sinAtender: [
        <String, Object?>{'sucursal': 'b-palma', 'sin_atender': 1},
      ],
    );

    test('se lee entera, con los campos del servicio', () {
      final estado = EstadoDelSincronizador.deJson(crudo);

      expect(estado.aparatos, hasLength(3));
      expect(estado.bandeja, hasLength(1));
      expect(estado.nuncaSubieron, 1);
      expect(estado.llevanMasDeUnDia, 1);
      expect(estado.pendientesEnTotal, 15);
      expect(estado.sinAtenderEnTotal, 1);

      final rechazo = estado.bandeja.single;
      expect(
        rechazo.motivo,
        '3 de los 8 pedidos ya están en otra ruta. Vuelve a elegirlos.',
      );
      expect(rechazo.hecho, isNotNull);
      expect(rechazo.rechazadoEl, isNotNull);
      expect(rechazo.metodo, 'POST');
    });

    test('el orden del servidor se respeta: el que nunca subió va primero', () {
      // Viene por `subida_at ASC NULLS FIRST`. Reordenar aquí —por sucursal,
      // por nombre— enterraría a Palma entre nueve filas verdes.
      final estado = EstadoDelSincronizador.deJson(crudo);
      expect(estado.aparatos.first.aparato, 'ap-palma');
      expect(estado.aparatos.first.nuncaSubio, isTrue);
      expect(estado.aparatos.last.aparato, 'ap-holguin');
    });

    test('una respuesta sin listas no revienta: sale vacía', () {
      final estado = EstadoDelSincronizador.deJson(const <String, Object?>{});
      expect(estado.aparatos, isEmpty);
      expect(estado.bandeja, isEmpty);
      expect(estado.sinAtenderEnTotal, 0);
    });
  });

  group('el repositorio', () {
    test('pide /estado y, con sucursal, la manda en la dirección', () async {
      final servidor = SincroFalso(estadoJson());
      final repo = RepositorioSincronizacion(clienteDePrueba(servidor));

      await repo.leer();
      expect(servidor.pedidas.single.path, '/estado');
      expect(servidor.pedidas.single.queryParameters, isEmpty);

      // El alcance lo cierra el servidor; esto sólo ESTRECHA, y sólo se lo
      // admite al Super Admin.
      await repo.leer(sucursal: 'b-palma');
      expect(servidor.pedidas.last.queryParameters['sucursal'], 'b-palma');
    });

    test('sin red sale FalloDeRed, no una lista vacía', () async {
      // Son cosas distintas: una lista vacía se lee como «todos al día», que es
      // lo contrario de «no lo sé».
      final servidor = SincroFalso(null);
      final repo = RepositorioSincronizacion(clienteDePrueba(servidor));

      await expectLater(repo.leer(), throwsA(isA<FalloDeRed>()));
    });
  });
}
