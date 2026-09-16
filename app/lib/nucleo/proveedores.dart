import 'dart:async';

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
import 'plataforma.dart';
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
  ref.onDispose(() => cerrarLaBaseSinRuido(base));
  return base;
});

/// CERRAR LA BASE SIN QUE UN FALLO DE DRIFT DEJE A NADIE EN LA PUERTA.
///
/// Esto se llama en el momento exacto en el que alguien ENTRA: el portero pone
/// el nuevo dueno (`duenoDeLaBaseProvider.es(sesion.sub)`), Riverpod tira el
/// `baseProvider` anterior y este `onDispose` cierra la base de antes.
///
/// `GeneratedDatabase.close()` recorre sus consultas vivas para cerrarlas. En
/// ese mismo instante las pantallas se estan rehaciendo contra la copia nueva y
/// alguna se apunta mientras el cierre recorre, asi que revienta con:
///
/// ```
/// Unhandled Exception: Concurrent modification during iteration: _Map len:4.
///   StreamQueryStore.close   GeneratedDatabase.close
/// ```
///
/// **Y eso tiraba a la persona de vuelta a la pantalla de acceso.** Visto el
/// 16/09/2026 en un Galaxy A16, y lo peor era como se veia: el registro de
/// Accesos decia `auth.apk.login` —la contrasena estaba bien y el par de tokens
/// se habia entregado— y en el telefono el formulario se vaciaba SIN UN SOLO
/// MENSAJE. Desde fuera parecia una contrasena mal escrita; era un fallo
/// nuestro al cambiar de base.
///
/// Se traga a proposito. Aqui no hay ningun dato en juego: lo que se estaba
/// cerrando es la copia ANTERIOR, ya escrita en disco y con sus transacciones
/// cerradas —lo pendiente de subir vive en su tabla, no en memoria—. El sistema
/// suelta el fichero igual. Dejar que el fallo suba, en cambio, rompe
/// justamente el gesto de entrar.
Future<void> cerrarLaBaseSinRuido(BaseLocal base) async {
  try {
    await base.close();
  } on Object catch (e) {
    Registro.aviso('la base anterior no cerro limpia: $e');
  }
}

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
  (ref) =>
      Dio(
          BaseOptions(
            baseUrl: '${Entorno.authUrl}/api/auth',
            // Los mismos plazos que el resto (`red/cliente_api.dart`), y aqui aprieta
            // mas que en ningun sitio: esta es la peticion del ARRANQUE, la que se
            // hace antes de pintar nada. Con los 30 s de antes, abrir la aplicacion
            // con senal mala eran 30 s de pantalla de espera antes de entrar con lo
            // guardado. Renovar no reintenta, asi que este numero ES el peor caso.
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            contentType: Headers.jsonContentType,
          ),
        )
        ..interceptors.add(
          // ESTE CLIENTE TAMBIEN CUENTA PARA LA SALUD DE LA RED, y es el que mas.
          //
          // Renovar es el PRIMER paso del ciclo, antes de subir y de bajar. Sin
          // conexion el ciclo muere aqui, asi que las peticiones de `ClienteApi` —las
          // unicas que contaban intentos— **no llegan a hacerse nunca**. El resultado
          // era el de siempre: la franja tardaba minutos en decir «sin conexion»,
          // porque volvia a depender de contar ciclos enteros.
          //
          // Visto en el Galaxy A16 el 16/09/2026, con el telefono sin salida a
          // internet comprobada: 35 s despues de abrir, la franja seguia callada.
          //
          // Va como interceptor y no envolviendo el cliente porque este Dio es crudo
          // a proposito —renovar no se renueva a si mismo— y eso no se toca.
          InterceptorDeSalud(
            alIntentar: ({required bool llego}) => ref
                .read(saludDeLaRedProvider.notifier)
                .anotarIntento(llego: llego),
          ),
        ),
);

/// Cuenta cada intento de un Dio crudo para la salud de la red.
///
/// Un error de red cuenta como «no llego». Cualquier respuesta del servidor
/// —incluido un 401 o un 404— cuenta como que SI llego: el servidor contesto.
class InterceptorDeSalud extends Interceptor {
  InterceptorDeSalud({required this.alIntentar});

  final void Function({required bool llego}) alIntentar;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    alIntentar(llego: true);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Con respuesta, el servidor contesto: la red esta bien aunque el codigo
    // sea malo. Sin respuesta, la peticion no salio.
    alIntentar(llego: err.response != null);
    handler.next(err);
  }
}

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
///
/// ## Y SE RECUERDA AL CERRAR LA APLICACION — 16/09/2026
///
/// Antes no. Arrancaba en `null` y se perdia en cada arranque, asi que quien ve
/// las ocho volvia siempre a «Todas». Eso no es solo una molestia: con «Todas»
/// puesto, el Panel dice «Falta configurar esta sucursal, 3 de 4» y los
/// importes no se convierten —la tasa es POR SUCURSAL—, de modo que la
/// aplicacion se abre pareciendo a medio configurar cuando no lo esta. Jose lo
/// vio en su telefono ese dia, con La Habana ya elegida y completa.
///
/// Se guarda en `preferencias`, que es del APARATO: la sucursal que se mira es
/// donde uno esta, no quien uno es.
class SucursalMirada extends Notifier<String?> {
  @override
  String? build() => null;

  void mirar(String? sucursalId) {
    state = sucursalId;
    // Sin esperarlo: quien acaba de tocar el selector ya esta viendo los
    // numeros de la otra sucursal, y una escritura en disco no puede meterse
    // por medio. Si falla, lo peor que pasa es que el proximo arranque abra
    // donde abria antes.
    unawaited(
      _guardar(ClaveDePreferencia.sucursalMirada, sucursalId),
    );
  }

  /// Vuelve a poner lo ultimo que se eligio. Se llama al entrar, con la base de
  /// esa persona ya abierta.
  Future<void> restaurar() async {
    try {
      state = await ref
          .read(baseProvider)
          .preferencia(ClaveDePreferencia.sucursalMirada);
    } on Object catch (e) {
      Registro.aviso('no se pudo recordar la sucursal mirada: $e');
    }
  }

  Future<void> _guardar(String clave, String? valor) async {
    try {
      await ref.read(baseProvider).anotarPreferencia(clave, valor);
    } on Object catch (e) {
      Registro.aviso('no se pudo anotar la sucursal mirada: $e');
    }
  }
}

final sucursalMiradaProvider = NotifierProvider<SucursalMirada, String?>(
  SucursalMirada.new,
);

ClienteApi _cliente(Ref ref, String baseUrl) => ClienteApi.montar(
  baseUrl: baseUrl,
  almacen: ref.watch(almacenSesionProvider),
  renovador: ref.watch(renovadorProvider),
  sucursalMirada: () => ref.read(sucursalMiradaProvider),
  // Cada intento cuenta para la salud de la red. Ver `anotarIntento`.
  alIntentar: ({required bool llego}) =>
      ref.read(saludDeLaRedProvider.notifier).anotarIntento(llego: llego),
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
    // Para quien no tiene sucursal propia —el Super Admin—, la del selector de
    // arriba. Se lee al llamar y no al construir: el alta puede pasar mucho
    // despues de que se monte esto.
    sucursalElegida: () => ref.read(sucursalMiradaProvider),
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

  /// UN INTENTO SUELTO, no un ciclo entero.
  ///
  /// Lo llama `ClienteApi` en cada peticion. Contando ciclos hacian falta
  /// minutos para decir «sin conexion»; contando intentos, los tres que hacen
  /// falta caben dentro de UN ciclo, porque cada peticion reintenta a 1 s, 4 s
  /// y 10 s. El aviso pasa de varios minutos a menos de medio.
  ///
  /// El motivo por el que hacen falta tres y no uno sigue en pie y esta escrito
  /// en `SaludDeLaRed.fallosParaDarlaPorMala`: un aviso que parpadea con cada
  /// paquete perdido deja de leerse.
  void anotarIntento({required bool llego}) {
    state = llego
        ? state.conUnaBuena(ref.read(relojProvider)())
        : state.conUnaMala();
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

/// EL LATIDO DEL INTENTO: un tic mientras hay un ciclo en vuelo, y nada cuando
/// no lo hay.
///
/// Existe por un motivo concreto. La tarjeta del Panel deja de decir «Enviando
/// datos...» cuando el intento pasa de medio minuto (`pacienciaDelIntento`),
/// pero eso es una comparacion contra el reloj: **sin nada que redibuje, la
/// pantalla no se entera de que el tiempo paso**. Y justo en ese caso no hay
/// nada que la redibuje, porque un ciclo atascado contra una red muerta no
/// avanza de coleccion ni de tanda.
///
/// Cinco segundos: bastante fino para que el aviso salga a los 30 s y no a los
/// 60, y bastante grueso para no repintar por gusto. **No corre cuando no hay
/// ciclo**: un temporizador eterno en una aplicacion que vive todo el dia
/// abierta en el patio de un almacen se nota en la bateria.
final latidoDelIntentoProvider = StreamProvider<DateTime>((ref) {
  if (!ref.watch(marchaDelCicloProvider).enVuelo) {
    return const Stream<DateTime>.empty();
  }
  final reloj = ref.watch(relojProvider);
  return Stream<DateTime>.periodic(const Duration(seconds: 5), (_) => reloj());
});

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
    //
    // La regla de QUE estados cuentan vive en `haySesionParaSincronizar`, con
    // nombre y probada suelta: escrita a mano aqui ya costo un fallo que dejaba
    // la configuracion inicial en el 0 % para siempre.
    haySesion: () => haySesionParaSincronizar(ref.read(porteroProvider).estado),
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
    // EL RITMO, segun el destino. En web es lo UNICO que trae los cambios —alli
    // no queda ni un gesto para traer el dia a mano—, asi que va mas seguido; en
    // la APK cada tic se paga en bateria y datos por la conexion de alla. El
    // porque de cada numero, en `vigia.dart`.
    periodo: ref.read(trabajaSinConexionProvider)
        ? VigiaDeSincronizacion.periodoPorDefecto
        : VigiaDeSincronizacion.periodoEnWeb,
    reloj: ref.read(relojProvider),
    // LO QUE ACOTA EL VOLVER AL PRIMER PLANO. Sin esto, cada alt-tab es un ciclo
    // entero y la barra superior dice «actualizando…» sin parar.
    //
    // Las dos preguntas son de una sola consulta cada una y ninguna es un
    // stream: aqui no hay nada que pintar, y un `await` sobre el primer valor de
    // un stream de Drift lo deja abierto detras.
    loQueHay: () async => EstadoDeLoQueHay(
      bajadaAt: await ref.read(frescuraProvider).laMasViejaAhora(),
      sinSubir: await ref.read(colaProvider).cuantosQuedanTras(0),
    ),
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
