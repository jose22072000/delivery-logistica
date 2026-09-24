import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/pantallas/panel/datos/textos_del_dia.dart';

/// EL RELOJ DEL TELÉFONO SE VA HACIA ATRÁS.
///
/// Pasa de verdad y no es raro: al repartidor se le apaga el teléfono en la
/// calle, lo enciende y el reloj arranca de fábrica; o alguien le cambia la hora
/// a mano; o se queda sin hora de red toda la mañana. A partir de ahí el reloj
/// del aparato está **detrás** de la marca de la última bajada, que la pone el
/// servidor.
///
/// Con el reloj detrás, `ahora.difference(bajadaAt)` sale **negativo**, y un
/// negativo es menor que una hora, así que `EstadoFrescura.de` contesta
/// [DatosRecientes]: «Datos de las 16:40» —una hora que todavía no ha pasado—,
/// en gris y sin ámbar. Ése es el número creíble y equivocado.
///
/// Y detrás viene lo caro, que es lo que esta pareja de pruebas cierra: el Panel
/// arma `hayQueTraer` con ese mismo `enAmbar`, así que se planta en
/// [QueToca.todoAlDia] — verde, «Los datos son de ahora mismo», **y sin botón
/// de Traer el día**, porque `todoAlDia` no ofrece ninguno. El repartidor sale
/// del almacén con los pedidos de anteayer y la pantalla no sólo no lo dice:
/// le ha quitado el gesto con el que se arreglaría.
void main() {
  final bajada = DateTime(2026, 9, 24, 16, 40);

  group('lo que la franja pinta con el reloj detrás', () {
    test('HALLAZGO · `EstadoFrescura` se cree la hora del futuro y NO avisa', () {
      // El teléfono se apagó y volvió con el reloj cuatro días atrás.
      final conElRelojAtras = EstadoFrescura.de(
        bajada,
        ahora: DateTime(2026, 9, 20, 9),
      );

      // ESTO ES EL FALLO, pinchado tal cual está hoy. Cuando
      // `EstadoFrescura.de` aprenda a decir «el reloj de este aparato no
      // cuadra», esta prueba se pondrá roja: entonces se cambia por la de
      // verdad, no se borra.
      expect(
        conElRelojAtras,
        isA<DatosRecientes>(),
        reason:
            'una diferencia negativa es menor que una hora, así que hoy cae en '
            '«recientes» — el arreglo va en `nucleo/frescura/reloj_de_datos.dart`',
      );
      expect(conElRelojAtras.texto, 'Datos de las 16:40');
      expect(
        conElRelojAtras.enAmbar,
        isFalse,
        reason: 'y ni siquiera se pinta en ámbar: no hay nada que mire nadie',
      );
    });
  });

  group('lo que el Panel decide con eso', () {
    test('el reloj hacia atrás NO puede dejar al Panel en «Todo al día» sin '
        'botón', () {
      final estado = EstadoFrescura.de(
        bajada,
        ahora: DateTime(2026, 9, 20, 9),
      );

      final toca = queTocaAhora(
        enVuelo: false,
        paso: null,
        vaMal: false,
        pendientes: 0,
        // Lo mismo que arma `EstadoDelDia`, con la guarda del reloj puesta.
        hayQueTraer:
            estado.enAmbar ||
            elRelojNoCuadra(bajada, ahora: DateTime(2026, 9, 20, 9)),
      );

      expect(
        toca,
        isNot(QueToca.todoAlDia),
        reason:
            'con el reloj detrás no se sabe de cuándo son los datos; darlos '
            'por «de ahora mismo» es el número creíble y equivocado',
      );
      expect(
        TextosDelDia.boton(toca),
        isNotNull,
        reason:
            'y sobre todo: el botón de Traer el día tiene que seguir ahí. '
            '`todoAlDia` no ofrece ninguno, así que el reloj movido le quitaba '
            'al repartidor el único gesto con el que se arreglaba',
      );
    });

    test('con el reloj en hora y los datos de hace un minuto, «Todo al día» '
        'sigue diciéndose', () {
      // La pareja del §3-quinquies: la guarda no puede encenderse siempre, o
      // vuelve el botón que se pulsa y no cambia nada.
      final ahora = DateTime(2026, 9, 24, 16, 41);
      final estado = EstadoFrescura.de(bajada, ahora: ahora);

      expect(elRelojNoCuadra(bajada, ahora: ahora), isFalse);
      expect(
        queTocaAhora(
          enVuelo: false,
          paso: null,
          vaMal: false,
          pendientes: 0,
          hayQueTraer: estado.enAmbar || elRelojNoCuadra(bajada, ahora: ahora),
        ),
        QueToca.todoAlDia,
      );
    });

    test('un desfase de segundos no cuenta: los relojes nunca cuadran al '
        'milisegundo', () {
      // La marca la pone el servidor y la hora la pone el teléfono. Que el
      // teléfono vaya medio minuto por detrás es lo normal, no un reloj movido:
      // saltar ahí sería el aviso que sale siempre.
      final ahora = bajada.subtract(const Duration(seconds: 30));
      expect(elRelojNoCuadra(bajada, ahora: ahora), isFalse);
    });

    test('sin bajada todavía no hay reloj que comparar', () {
      expect(elRelojNoCuadra(null, ahora: DateTime(2026, 9, 24)), isFalse);
    });
  });
}
