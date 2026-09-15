import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navegacion/estado_navegacion.dart';
import '../navegacion/portero.dart';
import 'registro/registro.dart';
import 'actualizacion/comprobador.dart';
import 'base/base.dart';
import 'cola/cola_salida.dart';
import 'cola/provisionales.dart';
import 'frescura/frescura.dart';
import 'identidad/almacen_sesion.dart';
import 'identidad/renovador.dart';
import 'red/cliente_api.dart';
import 'red/entorno.dart';
import 'red/fallos.dart';
import 'red/salud.dart';
import 'reloj.dart';
import 'sincro/bajada.dart';
import 'sincro/ciclo.dart';
import 'sincro/identidad_del_aparato.dart';
import 'sincro/recuento.dart';
import 'sincro/subida.dart';
import 'sincro/vigia.dart';

/// El cableado de las cinco piezas transversales.
///
/// Todo lo de aqui es un `Provider` a mano y no generado: son objetos unicos de
/// la aplicacion, sin parametros, y el generador no anade nada. Lo generado se
/// reserva para los providers de pantalla, que si se parametrizan por sucursal y
/// por filtro.

/// DE QUIEN ES LA BASE que esta abierta: el `sub` del token, o `null` si no ha
/// entrado nadie todavia.
///
/// Lo pone el arranque en cuanto lee la sesion guardada, y la pantalla de acceso
/// en cuanto alguien entra. Cambiarlo **cambia de copia**: `baseProvider` lo
/// mira, asi que al moverlo se cierra la base de quien se va y se abre la de
/// quien llega, con su cola y sus datos dentro. El porque, entero, en
/// `nucleo/base/conexion/nombre.dart`.
class DuenoDeLaBase extends Notifier<String?> {
  @override
  String? build() => null;

  /// Se llama ANTES de tocar la base. Poner el mismo que ya estaba no hace nada
  /// —ni cierra ni reabre— porque si no, cada ciclo reabriria el fichero.
  void es(String? sub) {
    final limpio = (sub == null || sub.trim().isEmpty) ? null : sub.trim();
    if (state == limpio) return;
    Registro.info('la base pasa a ser de ${limpio ?? "nadie"}');
    state = limpio;
  }
}

final duenoDeLaBaseProvider = NotifierProvider<DuenoDeLaBase, String?>(
  DuenoDeLaBase.new,
);

/// La base local. Es LA fuente de verdad de la aplicacion: ninguna pantalla mira
/// la respuesta de una peticion, todas miran esto.
///
/// **Una por persona.** El `watch` de [duenoDeLaBaseProvider] es lo que hace que
/// cerrar sesion no borre nada: cambia el dueno, esta base se cierra, se abre la
/// del siguiente y todo lo que cuelga de aqui —la cola, la frescura, la bajada,
/// el ciclo— se rehace apuntando a la copia nueva.
final baseProvider = Provider<BaseLocal>((ref) {
  final base = BaseLocal(dueno: ref.watch(duenoDeLaBaseProvider));
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

/// El alta de ESTA instalacion. Va contra `sync` porque el alta la da `sync`
/// (`POST /sync/aparato`) y el identificador lo pone el servidor, no el aparato.
final identidadDelAparatoProvider = Provider<IdentidadDelAparato>(
  (ref) => IdentidadDelAparato(
    ref.watch(baseProvider),
    sync: ref.watch(clienteSyncProvider),
  ),
);

/// LA SUBIDA DE LA COLA. Va contra `sync`, que es otro servicio y otra URL.
final subidaProvider = Provider<Subida>(
  (ref) => Subida(
    cliente: ref.watch(clienteSyncProvider),
    cola: ref.watch(colaProvider),
    aparato: ref.watch(identidadDelAparatoProvider),
    // Los dos siguientes son LA GUARDA de «la cola de A no sube con el token de
    // B». En web la sesion es la cookie y el almacen devuelve `null` siempre:
    // ahi no hay con que comparar y la guarda deja pasar, que es lo correcto
    // porque en un navegador no hay dos personas compartiendo una base.
    base: ref.watch(baseProvider),
    quienEsta: () async => (await ref.read(almacenSesionProvider).leer())?.sub,
  ),
);

/// Lo que hay en la base, contado. **De aqui salen los numeros que se ensenan
/// al acabar de traer el dia**, y no de lo que contesto el servidor.
final recontadorProvider = Provider<Recontador>(
  (ref) => Recontador(ref.watch(baseProvider), ref.watch(frescuraProvider)),
);

/// La PISTA de que hay red. Como provider para poder ponerla a `false` en una
/// prueba sin tocar el plugin.
final pistaDeRedProvider = Provider<PistaDeRed>((ref) => hayPistaDeRed);

/// El aviso de red, como provider para poder inyectarlo.
final avisosDeRedProvider = Provider<Stream<bool> Function()>(
  (ref) => avisosDeConnectivityPlus,
);

/// SI EL APARATO CREE QUE HAY RED, en vivo.
///
/// Sirve **para decidir que ensenar**, no para decidir si se sale a la red. La
/// regla de `pubspec.yaml` no cambia —«PISTA de que hay red, nunca la verdad»—:
/// en Cuba el telefono ensena el wifi conectado y no sale un paquete. Lo que
/// esto permite es no ofrecerle a alguien, en el patio del almacen, un boton que
/// no puede funcionar; y cuando la pista se equivoque por el otro lado, el cajon
/// sigue estando a un toque y desde ahi se intenta de verdad.
///
/// Empieza por la pregunta de una vez y sigue con los avisos: sin lo primero, la
/// pantalla se quedaria sin saber nada hasta que la red cambiara.
final hayRedProvider = StreamProvider<bool>((ref) async* {
  yield await ref.watch(pistaDeRedProvider)();
  yield* ref.watch(avisosDeRedProvider)();
});

/// SI LAS PETICIONES ESTAN LLEGANDO. Es lo que decide el estado que se pinta,
/// y **no** `connectivity_plus` (ver `red/salud.dart`).
class LaSalud extends Notifier<SaludDeLaRed> {
  @override
  SaludDeLaRed build() => SaludDeLaRed.bienDeSalida;

  /// Lo llama el ciclo al acabar, TODOS los ciclos — tambien los que dispara el
  /// vigia sin que nadie mire, que son los que de verdad dicen si la conexion
  /// sirve.
  void anotar(ResumenDelCiclo resumen) {
    // Sin sesion no se intento nada: eso no dice nada de la red.
    if (resumen.sinSesion) return;
    // Y solo cuenta el fallo DE RED. Una sesion muerta o un rechazo del
    // servidor significan que la peticion SI llego.
    state = resumen.fallo is FalloDeRed
        ? state.conUnaMala()
        : state.conUnaBuena(ref.read(relojProvider)());
  }
}

final saludDeLaRedProvider = NotifierProvider<LaSalud, SaludDeLaRed>(
  LaSalud.new,
);

/// POR DONDE VA el ciclo que corre ahora, para quien lo este mirando.
///
/// Lo alimenta [cicloProvider] y lo mira el boton de traer el dia. Esta aqui
/// —y no en la pantalla— porque el candado de «uno en vuelo» hace que el ciclo
/// que mira el boton pueda ser uno que arranco el vigia: si la pantalla se
/// inventara su propia marcha, ese ciclo correria sin que se viera.
class MarchaDelCiclo extends Notifier<Marcha> {
  @override
  Marcha build() => Marcha.quieto;

  void empieza(DateTime cuando) {
    // Si ya hay uno en vuelo **no se reinicia el cronometro**: el segundo aviso
    // se engancha al ciclo que ya va (el candado esta en `ciclo.dart`), y poner
    // la cuenta a cero enseñaria 2 s de algo que lleva cuarenta.
    if (state.enVuelo) return;
    state = Marcha(empezadoA: cuando);
  }

  void avanza(AvanceDelCiclo avance) =>
      state = Marcha(empezadoA: state.empezadoA, avance: avance);

  void termina() => state = Marcha.quieto;
}

final marchaDelCicloProvider = NotifierProvider<MarchaDelCiclo, Marcha>(
  MarchaDelCiclo.new,
);

/// EL CICLO: renovar → subir → bajar. Uno solo en toda la aplicacion, porque el
/// candado de «un solo ciclo en vuelo» vive dentro: dos instancias son dos
/// candados, y dos candados no son ninguno.
final cicloProvider = Provider<CicloDeSincronizacion>(
  (ref) => CicloDeSincronizacion(
    almacen: ref.watch(almacenSesionProvider),
    renovador: ref.watch(renovadorProvider),
    subida: ref.watch(subidaProvider),
    bajada: ref.watch(bajadaProvider),
    // Quien sabe si hay sesion es el portero, y no el almacen: en web el almacen
    // devuelve `null` SIEMPRE porque alli la sesion es la cookie. Preguntarle a
    // el dejaria la web sin sincronizar nunca.
    haySesion: () => ref.read(porteroProvider).estado == EstadoDeAcceso.dentro,
    alMorirLaSesion: () => ref.read(porteroProvider).murio(),
    // El giro de la barra superior. Es un contador, asi que dos ciclos
    // solapados no se apagan el uno al otro.
    alEmpezar: () {
      ref.read(enVueloProvider.notifier).empieza();
      ref
          .read(marchaDelCicloProvider.notifier)
          .empieza(ref.read(relojProvider)());
    },
    alTerminar: () {
      ref.read(enVueloProvider.notifier).termina();
      ref.read(marchaDelCicloProvider.notifier).termina();
    },
    alAvanzar: (avance) =>
        ref.read(marchaDelCicloProvider.notifier).avanza(avance),
    alAcabar: (resumen) =>
        ref.read(saludDeLaRedProvider.notifier).anotar(resumen),
  ),
);

/// EL VIGIA: el aviso de red y el reloj. Lo arranca y lo para `app.dart` segun
/// lo que diga el portero — nada vivo sin sesion.
final vigiaProvider = Provider<VigiaDeSincronizacion>((ref) {
  final vigia = VigiaDeSincronizacion(
    ciclo: (motivo) => ref.read(cicloProvider).ahora(motivo: motivo),
  );
  ref.onDispose(vigia.parar);
  return vigia;
});

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
