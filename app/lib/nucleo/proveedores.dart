import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'base/base.dart';
import 'cola/cola_salida.dart';
import 'cola/provisionales.dart';
import 'frescura/frescura.dart';
import 'identidad/almacen_sesion.dart';
import 'identidad/renovador.dart';
import 'red/cliente_api.dart';
import 'red/entorno.dart';
import 'reloj.dart';

/// El cableado de las cinco piezas transversales.
///
/// Todo lo de aqui es un `Provider` a mano y no generado: son objetos unicos de
/// la aplicacion, sin parametros, y el generador no anade nada. Lo generado se
/// reserva para los providers de pantalla, que si se parametrizan por sucursal y
/// por filtro.

/// La base local. Es LA fuente de verdad de la aplicacion: ninguna pantalla mira
/// la respuesta de una peticion, todas miran esto.
final baseProvider = Provider<BaseLocal>((ref) {
  final base = BaseLocal();
  ref.onDispose(base.close);
  return base;
});

/// El reloj del APARATO. Como provider para poder moverlo en los tests.
final relojProvider = Provider<Reloj>((ref) => relojDelAparato);

final almacenSesionProvider = Provider<AlmacenDeSesion>(
  (ref) => abrirAlmacenDeSesion(),
);

/// El Dio **crudo** de auth: sin `InterceptorSesion`, porque renovar no se
/// renueva a si mismo.
final dioAuthProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      baseUrl: Entorno.authUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
    ),
  ),
);

/// EL CANDADO. Uno solo en toda la aplicacion — dos instancias son dos candados
/// distintos, y dos candados no son ningun candado.
final renovadorProvider = Provider<Renovador>(
  (ref) => Renovador(ref.watch(dioAuthProvider), ref.watch(almacenSesionProvider)),
);

/// La sucursal que el Super Admin esta mirando. `null` = la suya.
///
/// Cambiarla **no recarga la pagina**: los providers de pantalla la miran, asi
/// que se reconstruyen solos y los numeros cambian en el sitio.
class SucursalMirada extends Notifier<String?> {
  @override
  String? build() => null;

  void mirar(String? sucursalId) => state = sucursalId;
}

final sucursalMiradaProvider = NotifierProvider<SucursalMirada, String?>(
  SucursalMirada.new,
);

ClienteApi _cliente(Ref ref, String baseUrl) => ClienteApi.montar(
  baseUrl: baseUrl,
  almacen: ref.watch(almacenSesionProvider),
  renovador: ref.watch(renovadorProvider),
  sucursalMirada: () => ref.read(sucursalMiradaProvider),
);

final clienteApiProvider = Provider<ClienteApi>(
  (ref) => _cliente(ref, Entorno.apiUrl),
);

final clienteSyncProvider = Provider<ClienteApi>(
  (ref) => _cliente(ref, Entorno.syncUrl),
);

final provisionalesProvider = Provider<Provisionales>(
  (ref) =>
      Provisionales(ref.watch(baseProvider), reloj: ref.watch(relojProvider)),
);

final colaProvider = Provider<ColaDeSalida>(
  (ref) => ColaDeSalida(
    ref.watch(baseProvider),
    reloj: ref.watch(relojProvider),
    provisionales: ref.watch(provisionalesProvider),
  ),
);

final frescuraProvider = Provider<RegistroDeFrescura>(
  (ref) => RegistroDeFrescura(
    ref.watch(baseProvider),
    reloj: ref.watch(relojProvider),
  ),
);

/// Cuantos apuntes quedan sin subir. Lo pinta el `RelojDeDatos`.
final sinSubirProvider = StreamProvider<int>(
  (ref) => ref.watch(colaProvider).pendientes().map((lista) => lista.length),
);
