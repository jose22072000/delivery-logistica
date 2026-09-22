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
      // Un ciclo caido ya son cerca de un minuto de reintentos por dentro
      // (1 s, 4 s y 10 s sobre cuatro intentos, `cliente_api.dart`). Aun asi,
      // uno no basta: en una conexion que va y viene, avisar a la primera es
      // parpadear todo el dia.
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
  // EL «NO» DEL SISTEMA SE CREE AL MOMENTO — 22/09/2026.
  //
  // Con el modo avión puesto a las 12:21:31, la franja siguió diciendo «Datos de
  // las 12:20» en gris hasta las 12:23. Dos minutos en los que el Panel afirmaba
  // «Los datos son de ahora mismo»: una pantalla mintiendo.
  //
  // La pista de `connectivity_plus` no vale para decir que HAY red —en Cuba el
  // teléfono enseña el wifi conectado y no sale un paquete— pero su «no hay ni
  // interfaz» es del sistema operativo. Miente en un solo sentido, y las pruebas
  // van en pareja por eso: se cree su «no» y NO se cree su «sí».
  group('sin interfaz', () {
    test('sin red se dice al momento, sin esperar tres fallos', () {
      expect(SaludDeLaRed.bienDeSalida.sinRed().vaMal, isTrue);
    });

    test('vuelve la interfaz: se quita la certeza, pero NO se dice que va bien', () {
      // Dos fallos y además sin interfaz. Al volver la interfaz siguen los dos
      // fallos: que haya wifi no significa que salga un paquete, y eso sólo lo
      // dice una petición que llegue.
      final rota = conFallos(2).sinRed();
      expect(rota.vaMal, isTrue);

      final conWifi = rota.conInterfaz();
      expect(conWifi.sinInterfaz, isFalse);
      expect(conWifi.fallosSeguidos, 2, reason: 'los fallos no se perdonan solos');
      expect(conWifi.vaMal, isFalse, reason: 'dos no llegan al umbral de tres');
    });

    test('con TRES fallos, volver la interfaz no quita el aviso', () {
      final mala = conFallos(3).sinRed();
      expect(mala.conInterfaz().vaMal, isTrue);
    });

    test('una petición que llega lo borra todo, también el sin interfaz', () {
      // Rápido en quitarse: basta UNA buena. Es la otra mitad de la regla.
      final buena = conFallos(3).sinRed().conUnaBuena(DateTime(2026, 9, 22));
      expect(buena.vaMal, isFalse);
      expect(buena.sinInterfaz, isFalse);
      expect(buena.fallosSeguidos, 0);
    });
  });

}
