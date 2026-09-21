// UN 404 NO BASTA PARA TIRAR EL IDENTIFICADOR DEL APARATO.
//
// Medido en producción el 21/09/2026: **12 aparatos para un solo teléfono**, once de
// ellos fantasmas, dos dados de alta de madrugada sin nadie delante. Y cada fantasma se
// queda en el panel de Sincronización marcado en rojo como «lleva 4 días sin subir», que
// es justo lo único que ese panel sirve para ver. Con diez repartidores, la lista es
// inservible en una semana y **el que de verdad está atascado no se distingue**.
//
// La causa: `subida.dart` trataba **cualquier** 404 como «este aparato ya no está
// registrado», olvidaba su identificador y se daba de alta otra vez. Pero un 404 también
// lo devuelve Traefik durante un redespliegue, o un camino mal escrito, o un proxy por el
// medio — y ésos ni siquiera son JSON nuestro.
//
// Es la misma trampa que el servidor ya tenía resuelta en el otro sentido
// (`sync/internal/reparto/reparto.go`: «UN 404 QUE NO VIENE DEL REPARTO ES NUESTRO, NO UN
// RECHAZO»). Ahora el 404 del aparato viaja con una marca, y sin ella **se falla cerrado**.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/identidad/almacen_sesion.dart';
import 'package:reparto/nucleo/identidad/renovador.dart';
import 'package:reparto/nucleo/identidad/sesion.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/nucleo/red/fallos.dart';
import 'package:reparto/nucleo/sincro/identidad_del_aparato.dart';
import 'package:reparto/nucleo/sincro/subida.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/reloj_falso.dart';
import '../../apoyo/servidor_falso.dart';

void main() {
  late BaseLocal base;
  late ColaDeSalida cola;
  late RelojFalso reloj;

  setUp(() {
    base = baseDePrueba();
    reloj = RelojFalso(DateTime(2026, 9, 14, 16));
    cola = ColaDeSalida(base, reloj: reloj.leer);
  });
  setUp(() => aparatoYaDeAlta(base));
  tearDown(() => base.close());

  ({Subida subida, IdentidadDelAparato aparato}) montar(
    Future<RespuestaFalsa?> Function(PeticionVista) responder,
  ) {
    final servidor = ServidorFalso(responder);
    final almacen = AlmacenEnMemoria(
      const Sesion(token: 't', refresh: 'r0', sub: 'u1'),
    );
    final auth = Dio()..httpClientAdapter = servidor;
    final cliente = ClienteApi.montar(
      baseUrl: 'https://sync.test',
      almacen: almacen,
      renovador: Renovador(auth, almacen),
      esperar: (_) async {},
    );
    cliente.dio.httpClientAdapter = servidor;
    final aparato = IdentidadDelAparato(base, sync: cliente);
    return (
      subida: Subida(
        cliente: cliente,
        cola: cola,
        aparato: aparato,
        base: base,
        quienEsta: () async => (await almacen.leer())?.sub,
      ),
      aparato: aparato,
    );
  }

  Future<void> unApunte() => cola.encolar(
    metodo: 'PATCH',
    ruta: '/routes/r-1',
    cuerpo: <String, Object?>{'status': 'completed'},
  );

  test('un 404 SIN marca no tira el aparato: es de otro', () async {
    await unApunte();
    var altas = 0;
    final m = montar((p) async {
      if (p.ruta.endsWith('/aparato')) {
        altas++;
        return RespuestaFalsa(200, <String, Object?>{'aparato': 'nuevo-$altas'});
      }
      // El 404 de un proxy: ni marca, ni JSON nuestro.
      return RespuestaFalsa(404, '<html>404 Not Found</html>');
    });

    final antes = await m.aparato.leer();

    // Y SE NOTA: el fallo sale hacia arriba en vez de tragarse. Un 404 que no
    // entendemos no se convierte en «ya está, me doy de alta otra vez»; se
    // relanza, el apunte se queda en la cola y se reintenta. Eso es fallar
    // cerrado.
    await expectLater(m.subida.ciclo(), throwsA(isA<Rechazo>()));

    expect(
      await m.aparato.leer(),
      antes,
      reason:
          'EL APARATO TIRÓ SU IDENTIFICADOR POR UN 404 QUE NO ERA SUYO. Un 404 '
          'de Traefik durante un redespliegue no dice nada del registro, y '
          'darse de alta otra vez deja un fantasma más en el panel.',
    );
    expect(altas, 0, reason: 'no se pidió ningún alta nueva');
  });

  test('un 404 CON la marca sí lo tira, que para eso está', () async {
    await unApunte();
    var altas = 0;
    var subidas = 0;
    final m = montar((p) async {
      if (p.ruta.endsWith('/aparato')) {
        altas++;
        return RespuestaFalsa(200, <String, Object?>{'aparato': 'nuevo-$altas'});
      }
      subidas++;
      // La primera vez, el servidor dice que este aparato no está; la segunda,
      // ya con el alta nueva, acepta.
      if (subidas == 1) {
        return RespuestaFalsa(404, <String, Object?>{
          'error': 'Ese aparato no está registrado. Vuelve a darlo de alta.',
          'codigo': marcaDeAparatoNoRegistrado,
        });
      }
      return RespuestaFalsa(200, <String, Object?>{'resultados': <Object?>[]});
    });

    await m.subida.ciclo();

    expect(altas, 1, reason: 'con la marca sí se vuelve a dar de alta');
    expect(await m.aparato.leer(), 'nuevo-1');
  });
}
