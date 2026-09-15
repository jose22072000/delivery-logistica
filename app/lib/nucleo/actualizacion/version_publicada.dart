import 'package:flutter/foundation.dart';

/// Las plataformas en las que corre esto, para elegir QUÉ fichero se baja.
///
/// `web` está en la lista y no sobra: es la que hace que la comprobación entera
/// no se haga. La web se actualiza sola al recargar, no descarga nada y no tiene
/// cola que se pueda perder.
enum Plataforma {
  android('android'),
  windows('windows'),
  linux('linux'),

  /// Web, o cualquier otra en la que no se publica nada (macOS, iOS).
  ninguna('');

  const Plataforma(this.clave);

  /// La clave con la que viene en `descargas` (`docs/actualizaciones.md`).
  final String clave;

  /// La de ESTE aparato.
  ///
  /// `kIsWeb` se mira PRIMERO: en web `defaultTargetPlatform` devuelve el sistema
  /// del navegador —`android` en un teléfono, `linux` en este portátil— y sin
  /// esta línea la web de un móvil se creería una APK y pediría instalar un APK
  /// encima de una pestaña.
  static Plataforma deEsteAparato() {
    if (kIsWeb) return Plataforma.ninguna;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => Plataforma.android,
      TargetPlatform.windows => Plataforma.windows,
      TargetPlatform.linux => Plataforma.linux,
      _ => Plataforma.ninguna,
    };
  }
}

/// La versión que hay INSTALADA en este aparato.
///
/// Sale de `package_info_plus`, que lee lo que puso el compilador: en Android es
/// el `versionName`/`versionCode` del APK, y los dos salen de `pubspec.yaml`
/// (`version: 1.0.0+1` → `1.0.0` y `1`).
@immutable
class VersionInstalada {
  const VersionInstalada({required this.version, required this.compilacion});

  final String version;

  /// El `versionCode`. Cero si no se pudo leer.
  final int compilacion;

  @override
  String toString() => '$version+$compilacion';
}

/// La última versión que el servidor dice que está colgada.
///
/// `null` en `descargas` no existe: si una plataforma no tiene fichero colgado,
/// su clave no viene. Un enlace vacío en la pantalla de alguien es peor que no
/// enseñar nada.
@immutable
class VersionPublicada {
  const VersionPublicada({
    required this.version,
    this.compilacion,
    this.notas,
    this.publicadaAt,
    this.descargas = const <String, String>{},
  });

  final String version;
  final int? compilacion;
  final String? notas;
  final DateTime? publicadaAt;
  final Map<String, String> descargas;

  /// De dónde se baja para esta plataforma, o `null` si no hay nada colgado.
  String? descargaPara(Plataforma plataforma) {
    final url = descargas[plataforma.clave];
    return (url == null || url.isEmpty) ? null : url;
  }

  /// Lee el bloque `ultima` de `GET /api/version`.
  ///
  /// Devuelve `null` en vez de lanzar cuando el cuerpo no es lo que se espera.
  /// Esto se llama al arrancar: una respuesta rara de un proxy que se metió por
  /// medio no puede impedir que alguien entre a trabajar.
  static VersionPublicada? deJson(Object? crudo) {
    if (crudo is! Map) return null;
    final version = crudo['version'];
    if (version is! String || version.isEmpty) return null;

    final descargas = <String, String>{};
    final sueltas = crudo['descargas'];
    if (sueltas is Map) {
      for (final entrada in sueltas.entries) {
        final clave = entrada.key;
        final url = entrada.value;
        if (clave is String && url is String && url.isNotEmpty) {
          descargas[clave] = url;
        }
      }
    }

    final notas = crudo['notas'];
    final fecha = crudo['publicadaAt'];

    return VersionPublicada(
      version: version,
      compilacion: switch (crudo['compilacion']) {
        final int n when n > 0 => n,
        final String s => int.tryParse(s),
        _ => null,
      },
      notas: (notas is String && notas.isNotEmpty) ? notas : null,
      publicadaAt: fecha is String ? DateTime.tryParse(fecha) : null,
      descargas: descargas,
    );
  }

  @override
  String toString() =>
      'VersionPublicada($version, ${descargas.keys.join(",")})';
}

/// ¿Lo publicado es MÁS NUEVO que lo instalado?
///
/// Manda la **compilación** cuando se sabe la de los dos, porque es lo único que
/// Android compara de verdad al instalar encima. El número de versión es para
/// enseñárselo a una persona y se puede escribir de cualquier manera.
///
/// Sin compilación se comparan los números del `1.5.0`, tramo a tramo. Nunca se
/// comparan como TEXTO: `"1.10.0" < "1.9.0"` en orden alfabético, y eso haría que
/// la versión 1.10 no se anunciara nunca.
///
/// **Ante la duda, `false`.** Un `true` de más es un aviso que manda a alguien a
/// reinstalar lo que ya tiene; un `false` de más es un aviso que llega mañana.
bool hayQueActualizar(VersionInstalada instalada, VersionPublicada publicada) {
  final suya = publicada.compilacion;
  if (suya != null && suya > 0 && instalada.compilacion > 0) {
    return suya > instalada.compilacion;
  }
  return _compararVersiones(publicada.version, instalada.version) > 0;
}

/// >0 si `a` es posterior a `b`, 0 si son la misma, <0 si es anterior.
///
/// Lo que no sea un número se descarta: `1.5.0-rc.2` se compara como `1.5.0`,
/// que es lo correcto para decidir si hay que avisar.
int _compararVersiones(String a, String b) {
  final ta = _tramos(a);
  final tb = _tramos(b);
  for (var i = 0; i < (ta.length > tb.length ? ta.length : tb.length); i++) {
    final va = i < ta.length ? ta[i] : 0;
    final vb = i < tb.length ? tb[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

List<int> _tramos(String version) {
  // El `+1` de `1.0.0+1` no entra: eso es la compilación y se compara aparte.
  // El `-rc.2` tampoco, y se corta ANTES de partir por puntos: si no, `1.5.0-rc.2`
  // daría cuatro tramos (1.5.0.2) y se leería como posterior a `1.5.0`.
  final sinCompilacion = version.split('+').first.split('-').first;
  return <int>[
    for (final tramo in sinCompilacion.split('.'))
      int.tryParse(RegExp(r'^\d+').stringMatch(tramo.trim()) ?? '') ?? 0,
  ];
}
