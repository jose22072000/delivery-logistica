import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/red/salud.dart';

/// SI LAS PETICIONES ESTAN LLEGANDO.
///
/// El caso de verdad no es «sin conexión», es **«conexión mala»**: sin conexión
/// la aplicacion lo sabe enseguida; con una que va y viene, el aparato cree que
/// esta conectado y el logistico se come una rueda girando. Lo que se prueba
/// aqui es que el aviso sea **lento en ponerse y rapido en quitarse**, porque
/// una senal que parpadea deja de leerse a los diez minutos.
void main() {
  SaludDeLaRed conFallos(int cuantos) {
    var salud = SaludDeLaRed.bienDeSalida;
    for (var i = 0; i < cuantos; i++) {
      salud = salud.conUnaMala();
    }
    return salud;
  }

  group('lento en ponerse', () {
    test('un fallo suelto NO dice que la conexion va mal', () {
      // Un ciclo caido ya son ochenta segundos largos de reintentos por dentro
      // (1 s, 4 s, 15 s y 60 s). Aun asi, uno no basta: en una conexion que va y
      // viene, avisar a la primera es parpadear todo el dia.
      expect(conFallos(1).vaMal, isFalse);
    });

    test('dos tampoco', () {
      expect(conFallos(2).vaMal, isFalse);
    });

    test('al TERCERO seguido si: ya lleva minutos sin servir', () {
      expect(conFallos(SaludDeLaRed.fallosParaDarlaPorMala).vaMal, isTrue);
      expect(SaludDeLaRed.fallosParaDarlaPorMala, 3);
    });
  });

  group('rapido en quitarse', () {
    test('UNA buena basta para volver a normal', () {
      // Tardar en recuperarse dejaria el aviso puesto delante de alguien que ya
      // tiene senal, y entonces miente en la otra direccion.
      final mala = conFallos(9);
      expect(mala.vaMal, isTrue);

      final buena = mala.conUnaBuena(DateTime(2026, 9, 15, 16, 20));
      expect(buena.vaMal, isFalse);
      expect(buena.fallosSeguidos, 0);
      expect(buena.ultimaBuena, DateTime(2026, 9, 15, 16, 20));
    });

    test('y la cuenta se reinicia de verdad, no se descuenta', () {
      final buena = conFallos(9).conUnaBuena(DateTime(2026, 9, 15, 16, 20));
      expect(
        buena.conUnaMala().vaMal,
        isFalse,
        reason:
            'despues de una buena hacen falta otros tres seguidos; si solo '
            'se descontara uno, el aviso volveria al primer fallo',
      );
    });
  });

  group('que cuenta como mala', () {
    test('solo el fallo DE RED; los demas dicen que la peticion SI llego', () {
      // Es la linea que separa «no llego» de «llego y el servidor dijo que no».
      // Un rechazo o una sesion muerta no son un problema de conexion, y
      // contarlos apagaria el gesto por algo que no tiene que ver.
      expect(const FalloDeRed(), isA<FalloApi>());
      expect(const SesionMuerta(), isA<FalloApi>());
      expect(
        const Rechazo(409, 'ya están en otra ruta'),
        isNot(isA<FalloDeRed>()),
      );
    });
  });
}
