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
/// negativo es menor que una hora, así que `EstadoFrescura.de` contestaba
/// [DatosRecientes]: «Datos de las 16:40» —una hora que todavía no ha pasado—,
/// en gris y sin ámbar. Ése era el número creíble y equivocado.
///
/// Y detrás venía lo caro, que es lo que esta pareja de pruebas cierra: el Panel
/// arma `hayQueTraer` con ese mismo `enAmbar`, así que se plantaba en
/// [QueToca.todoAlDia] — verde, «Los datos son de ahora mismo», **y sin botón
/// de Traer el día**, porque `todoAlDia` no ofrece ninguno. El repartidor salía
/// del almacén con los pedidos de anteayer y la pantalla no sólo no lo decía:
/// le había quitado el gesto con el que se arreglaría.
///
/// **Arreglado el 24/09/2026 en `nucleo/frescura/reloj_de_datos.dart`**, que es
/// donde tenía que ir: una diferencia negativa mayor que el margen de los dos
/// relojes ya no es «reciente», es [RelojQueNoCuadra] — con su texto propio y en
/// ámbar. La guarda del Panel (`elRelojNoCuadra`) se queda: son dos piezas que
/// tienen que contestar lo mismo, y aquí están atadas por una prueba y no por un
/// comentario (§3-bis).
void main() {
  final bajada = DateTime(2026, 9, 24, 16, 40);

  group('lo que la franja pinta con el reloj detrás', () {
    test('`EstadoFrescura` NO se cree la hora del futuro: lo dice y lo pinta en '
        'ámbar', () {
      // El teléfono se apagó y volvió con el reloj cuatro días atrás.
      final conElRelojAtras = EstadoFrescura.de(
        bajada,
        ahora: DateTime(2026, 9, 20, 9),
      );

      expect(
        conElRelojAtras,
        isA<RelojQueNoCuadra>(),
        reason:
            'una diferencia negativa es menor que una hora, así que sin una '
            'rama propia esto cae en «recientes» y escribe una hora que '
            'todavía no ha pasado',
      );
      expect(
        conElRelojAtras.texto,
        'El reloj de este aparato no cuadra',
        reason:
            'y NO se dice la hora: la hora es justo lo que no vale. «Datos de '
            'las 16:40» a las 09:00 es el número creíble y equivocado',
      );
      expect(
        conElRelojAtras.enAmbar,
        isTrue,
        reason:
            'ámbar es lo que enciende el gesto de traer el día, que es lo que '
            'el fallo le quitaba a quien lo necesitaba',
      );
    });

    test('con el reloj en hora NO se dice nada de relojes', () {
      // La pareja obligatoria: un aviso que sale siempre deja de leerse, y éste
      // sale en la franja de las siete pantallas (§3-quinquies).
      final enHora = EstadoFrescura.de(
        bajada,
        ahora: bajada.add(const Duration(minutes: 20)),
      );
      expect(enHora, isA<DatosRecientes>());
      expect(enHora.texto, 'Datos de las 16:40');
      expect(enHora.enAmbar, isFalse);
    });

    test('un desfase de segundos tampoco: los dos relojes no los sincroniza '
        'nadie', () {
      // La marca la pone el servidor y la hora la pone el teléfono. Medio
      // minuto por detrás es lo normal, no un reloj movido.
      final casiEnHora = EstadoFrescura.de(
        bajada,
        ahora: bajada.subtract(const Duration(seconds: 30)),
      );
      expect(casiEnHora, isA<DatosRecientes>());
      expect(casiEnHora.enAmbar, isFalse);
    });

    test('LAS DOS PIEZAS USAN EL MISMO MARGEN, y se atan aquí', () {
      // §3-bis: cuando dos cosas tienen que contestar lo mismo se atan con una
      // prueba, no con un comentario. Si se separan, sale un Panel en ámbar
      // sobre una franja en gris — o al revés, que es peor.
      expect(margenDelReloj, EstadoFrescura.margenDelReloj);
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
