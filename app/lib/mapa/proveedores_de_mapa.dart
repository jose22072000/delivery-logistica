// EL CABLEADO del mapa sin conexión.
//
// Todo lo de aquí está **apagado en la web**, y no por rendimiento: es la regla
// 1. Quien abre un navegador tiene servidor detrás, siempre, así que guardarse
// 26 MB de Cuba en el navegador no le ahorra nada a nadie. `Destino
// .trabajaSinConexion` es el único sitio donde se pregunta.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nucleo/plataforma.dart';
import '../nucleo/red/entorno.dart';
import '../nucleo/registro/registro.dart';
import '../pantallas/rutas/datos/mapa_en_vivo.dart';
import 'anuncio_de_mapa.dart';
import 'carpeta_del_mapa.dart';
import 'carpeta_en_disco.dart';
import 'descarga_de_mapa.dart';
import 'fondo_del_paquete.dart';
import 'pmtiles.dart';

/// La carpeta del aparato. `null` en la web.
final carpetaDelMapaProvider = FutureProvider<CarpetaDelMapa?>((ref) async {
  if (!ref.watch(trabajaSinConexionProvider)) return null;
  return abrirLaCarpetaDelMapa();
});

/// El cliente con el que se baja el fichero.
///
/// **Es uno propio y no el de las pantallas**, por la misma razón por la que la
/// comprobación de versión monta el suyo (`docs/actualizaciones.md` §5): el de
/// las pantallas reintenta a 1 s, 4 s, 15 s y 60 s, que aquí sería esperar
/// ochenta segundos antes de enterarse de que no hay señal. Y además éste no
/// lleva la sesión: el fichero del mapa es público, y mandarle el token a un
/// servidor de estáticos es regalar un token.
final dioDelMapaProvider = Provider<Dio>((ref) {
  final cliente = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      // Sin plazo de recepción: son decenas de MB por una conexión que va y
      // viene. Ver `descarga_de_mapa.dart`.
      receiveTimeout: null,
    ),
  );
  ref.onDispose(cliente.close);
  return cliente;
});

final anuncioDeMapaProvider = Provider<AnuncioDeMapa>(
  (ref) => AnuncioDeMapa(ref.watch(dioDelMapaProvider), Entorno.apiUrl),
);

final descargaDeMapaProvider = Provider<DescargaDeMapa?>((ref) {
  final carpeta = ref.watch(carpetaDelMapaProvider).value;
  if (carpeta == null) return null;
  return DescargaDeMapa(ref.watch(dioDelMapaProvider), carpeta);
});

/// LO QUE HAY GUARDADO en el aparato, leído del apunte que deja la descarga.
///
/// Se comprueba que el fichero **esté de verdad**: un apunte que dice «tienes el
/// completo» encima de una carpeta vacía es peor que no tener nada, porque la
/// pantalla diría que está al día y el mapa saldría en blanco.
final paqueteGuardadoProvider = FutureProvider<PaqueteGuardado?>((ref) async {
  final carpeta = ref.watch(carpetaDelMapaProvider).value;
  if (carpeta == null) return null;
  for (final nivel in const ['detallado', 'completo', 'basico']) {
    final apunte = PaqueteGuardado.deJson(
      await carpeta.leerTexto('cuba-$nivel.json'),
    );
    if (apunte == null) continue;
    final bytes = await carpeta.bytes('cuba-$nivel.pmtiles');
    if (bytes == apunte.bytes) return apunte;
    Registro.aviso(
      'el apunte de $nivel dice ${apunte.bytes} bytes y el fichero tiene '
      '$bytes: se ignora',
    );
  }
  return null;
});

/// EL ESTADO, que es lo que mira la pantalla. Los cinco casos, sellados.
final estadoDelMapaProvider = FutureProvider<EstadoDelMapa>((ref) async {
  if (!ref.watch(trabajaSinConexionProvider)) return const MapaNoAplica();
  final tengo = await ref.watch(paqueteGuardadoProvider.future);
  try {
    final hay = await ref.watch(anuncioDeMapaProvider).loQueHay();
    return compararElMapa(
      tengo: tengo,
      colgados: hay.niveles,
      ilegibles: hay.ilegibles,
    );
  } on Object catch (e) {
    // No saber si hay mapa nuevo NO es una noticia para quien está trabajando:
    // se mira mañana. Lo que sí sigue estando es lo guardado.
    return NoSeSupoDelMapa(tengo, '$e');
  }
});

/// EL PAQUETE ABIERTO, listo para dar teselas. `null` cuando no hay ninguno.
final paqueteAbiertoProvider = FutureProvider<PaqueteDeTeselas?>((ref) async {
  final carpeta = ref.watch(carpetaDelMapaProvider).value;
  final guardado = await ref.watch(paqueteGuardadoProvider.future);
  if (carpeta == null || guardado == null) return null;
  try {
    final paquete = await PaqueteDeTeselas.abrir(
      await carpeta.porRangos('cuba-${guardado.nivel}.pmtiles'),
    );
    ref.onDispose(paquete.cerrar);
    return paquete;
  } on PaqueteIlegible catch (e) {
    // Se anota con su motivo y se sigue sin paquete. El croquis se dibuja igual:
    // **el paquete es una mejora, nunca un requisito.**
    Registro.aviso('el paquete de mapa guardado no se puede leer: $e');
    return null;
  }
});

/// EL FONDO DE CALLES QUE HAY QUE ENCHUFAR AL MAPA DE LA RUTA.
///
/// Es el mismo puerto que ya usa `croquis_de_ruta.dart`, así que **no hay que
/// tocar ni una línea del mapa que ya está escrito**: basta con sobrescribir
/// `fondoDeCallesProvider` con éste en el `ProviderScope` de `main.dart`. La
/// línea exacta está en `docs/mapa-sin-conexion.md` §10.
///
/// El orden es paquete → red, y no al revés: el paquete es instantáneo, no gasta
/// datos y es lo único que hay en el patio de un almacén.
///
/// ## POR QUÉ LA RED SE CONSTRUYE AQUÍ Y NO SE PIDE POR `ref.watch`
///
/// Porque **éste es el que sustituye a `fondoDeCallesProvider`**. Si además lo
/// mirase para sacar el respaldo, se estaría mirando a sí mismo: Riverpod entra
/// en una dependencia circular y la pantalla de la ruta revienta al abrirse —no
/// al arrancar, que sería visible, sino al abrir una ruta, que es lo que hace el
/// logístico a las siete de la mañana. Se descubrió al escribir la línea de
/// `main.dart`, no al probar.
final fondoConPaqueteProvider = Provider<FondoDeCalles>((ref) {
  // El de OSM, montado aquí mismo. Es el mismo que monta `fondoDeCallesProvider`
  // por defecto (`pantallas/rutas/datos/mapa_en_vivo.dart`).
  final red = CallesDeOsm();
  final paquete = ref.watch(paqueteAbiertoProvider).value;
  if (paquete == null) return red;
  return FondoDelPaquete(paquete, respaldo: red);
});
