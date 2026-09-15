import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navegacion/portero.dart';
import 'actualizacion/comprobador.dart';
import 'base/base.dart';
import 'cola/cola_salida.dart';
import 'cola/provisionales.dart';
import 'frescura/frescura.dart';
import 'identidad/almacen_sesion.dart';
import 'identidad/renovador.dart';
import 'red/cliente_api.dart';
import 'red/entorno.dart';
import 'reloj.dart';
import 'sincro/bajada.dart';

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
///
/// La base lleva `/api/auth` puesto, que es donde viven las tres puertas de
/// verdad: `POST /api/auth/token`, `/api/auth/refresh` y `/api/auth/logout`
/// (repo `procovar-auth`). `Entorno.authUrl` es el dominio a secas porque auth
/// es de toda Procovar y puede mudarse sin las otras dos.
final dioAuthProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      baseUrl: '${Entorno.authUrl}/api/auth',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
    ),
  ),
);

/// EL CANDADO. Uno solo en toda la aplicacion — dos instancias son dos candados
/// distintos, y dos candados no son ningun candado.
final renovadorProvider = Provider<Renovador>(
  (ref) =>
      Renovador(ref.watch(dioAuthProvider), ref.watch(almacenSesionProvider)),
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
  // Un 401 que sigue siendo 401 despues de renovar es lo UNICO que echa a
  // alguien a la pantalla de acceso. Un fallo de red, no.
  alMorirLaSesion: () => ref.read(porteroProvider).murio(),
);

final clienteApiProvider = Provider<ClienteApi>(
  (ref) => _cliente(ref, Entorno.apiUrl),
);

final clienteSyncProvider = Provider<ClienteApi>(
  (ref) => _cliente(ref, Entorno.syncUrl),
);

/// LA BAJADA DEL DIA. Se dispara al entrar y despues de subir la cola.
final bajadaProvider = Provider<Bajada>(
  (ref) => Bajada(
    cliente: ref.watch(clienteApiProvider),
    base: ref.watch(baseProvider),
    frescura: ref.watch(frescuraProvider),
    reloj: ref.watch(relojProvider),
  ),
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

/// El cliente con el que se mira la versión, aparte del de las pantallas.
///
/// Es OTRO `ClienteApi` y no el de siempre por una sola razón: `sinEsperas`. El
/// de las pantallas reintenta 1 s, 4 s, 15 s y 60 s, que es lo correcto para el
/// trabajo de alguien y lo peor posible para una comprobación de versión al
/// arrancar — ochenta segundos de espera para averiguar algo que puede esperar a
/// mañana.
final clienteVersionProvider = Provider<ClienteApi>(
  (ref) => ClienteApi.montar(
    baseUrl: Entorno.apiUrl,
    almacen: ref.watch(almacenSesionProvider),
    renovador: ref.watch(renovadorProvider),
    esperas: ComprobadorDeActualizacion.sinEsperas,
  ),
);

final comprobadorProvider = Provider<ComprobadorDeActualizacion>(
  (ref) => ComprobadorDeActualizacion(
    cliente: ref.watch(clienteVersionProvider),
    base: ref.watch(baseProvider),
  ),
);

/// El aviso de versión nueva, para que lo mire la pantalla.
///
/// `FutureProvider` y no algo que se dispare solo: se comprueba cuando alguien
/// lo mira, UNA vez por arranque. Para volver a mirar —después de subir la cola,
/// por ejemplo— se invalida este provider. Ver `docs/actualizaciones.md`.
final actualizacionProvider = FutureProvider<EstadoDeActualizacion>(
  (ref) => ref.watch(comprobadorProvider).comprobar(),
);
