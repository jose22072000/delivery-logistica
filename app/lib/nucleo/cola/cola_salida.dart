import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../base/base.dart';
import '../registro/registro.dart';
import '../reloj.dart';
import 'apunte.dart';
import 'provisionales.dart';

/// LA COLA DE SALIDA. Es la pieza que hace verdad la regla 2: toda accion se
/// guarda en el aparato y se pinta como hecha; la subida va por detras.
///
/// No hay un «modo sin conexion» que se encienda. La aplicacion se comporta
/// igual siempre: quien tenga red todo el dia simplemente sube a medida que
/// trabaja.
class ColaDeSalida {
  ColaDeSalida(
    this._base, {
    Reloj reloj = relojDelAparato,
    Provisionales? provisionales,
  }) : _reloj = reloj,
       _provisionales = provisionales ?? Provisionales(_base, reloj: reloj);

  final BaseLocal _base;
  final Reloj _reloj;
  final Provisionales _provisionales;

  /// Cuanto se conserva un apunte ya aplicado. Borrarlo al momento deja sin
  /// rastro una subida que el usuario jura que hizo.
  static const conservarAplicados = Duration(days: 7);

  /// Guarda una accion. Devuelve la `clave` (ULID) con la que se la reconoce.
  ///
  /// La clave la pone el APARATO y no el servidor, y ahi esta la idempotencia:
  /// si la subida se corta despues de que el servidor guardara, el reintento
  /// llega con la misma clave y vuelve `repetido` en vez de duplicar la ruta.
  Future<String> encolar({
    required String metodo,
    required String ruta,
    required Map<String, Object?> cuerpo,
    String? provisional,
  }) async {
    final clave = Ulid().toString();
    await _base
        .into(_base.apuntes)
        .insert(
          ApuntesCompanion.insert(
            clave: clave,
            // La hora del APARATO, escrita AHORA. No se toca al subir.
            hechoAt: _reloj(),
            metodo: metodo,
            ruta: ruta,
            cuerpo: jsonEncode(cuerpo),
            provisional: Value(provisional),
          ),
        );
    return clave;
  }

  /// Lo que queda por subir, en el orden en que se hizo.
  ///
  /// `orden` y no `hechoAt`: marcar una parada y luego corregirla son dos
  /// apuntes sobre el mismo pedido, y subirlos al reves deja puesta la primera
  /// marca. Un reloj que se movio no puede provocar eso (caso S3).
  Stream<List<Apunte>> pendientes() =>
      (_base.select(_base.apuntes)
            ..where((a) => a.estado.equalsValue(EstadoApunte.pendiente))
            ..orderBy([(a) => OrderingTerm.asc(a.orden)]))
          .watch();

  /// La bandeja de rechazos. Nada se descarta en silencio (regla 6).
  Stream<List<Apunte>> rechazados() =>
      (_base.select(_base.apuntes)
            ..where((a) => a.estado.equalsValue(EstadoApunte.rechazado))
            ..orderBy([(a) => OrderingTerm.desc(a.orden)]))
          .watch();

  /// El lote que sale en la proxima `POST /sync/subida`.
  ///
  /// Veinte apuntes NO son veinte peticiones en paralelo: son una peticion con
  /// los veinte dentro, en orden. Veinte peticiones a la vez al recuperar la
  /// senal es justo lo que dispara veinte renovaciones (caso I1).
  Future<List<Apunte>> lote({int maximo = 200}) =>
      (_base.select(_base.apuntes)
            ..where((a) => a.estado.equalsValue(EstadoApunte.pendiente))
            ..orderBy([(a) => OrderingTerm.asc(a.orden)])
            ..limit(maximo))
          .get();

  Future<Apunte?> porClave(String clave) => (_base.select(
    _base.apuntes,
  )..where((a) => a.clave.equals(clave))).getSingleOrNull();

  /// El cuerpo del apunte, ya decodificado.
  static Object? cuerpoDe(Apunte a) => jsonDecode(a.cuerpo);

  /// Aplica lo que el servidor contesto de UN apunte.
  ///
  /// Va entero en una transaccion con la sustitucion del `local-…`: si el apunte
  /// quedara marcado como aplicado y la sustitucion fallara, el cierre de la
  /// tarde se iria a una ruta que no existe y nadie volveria a mirar ese apunte.
  Future<void> resolver(String clave, ResultadoApunte resultado) async {
    await _base.transaction(() async {
      final apunte = await (_base.select(
        _base.apuntes,
      )..where((a) => a.clave.equals(clave))).getSingleOrNull();
      if (apunte == null) {
        Registro.aviso('resultado de un apunte que no esta en la cola: $clave');
        return;
      }
      if (apunte.estado != EstadoApunte.pendiente) {
        // Ya estaba resuelto. Volver a aplicarlo reescribiria el motivo o
        // repetiria una sustitucion ya hecha.
        return;
      }

      if (resultado.seAplico) {
        final provisional = apunte.provisional;
        final real = resultado.id;
        if (provisional != null && real != null) {
          await _provisionales.sustituir(provisional, real);
        } else if (provisional != null) {
          // Un apunte que CREA algo y vuelve sin id deja el `local-…` puesto
          // para siempre. No se calla.
          Registro.fallo(
            'el servidor aplico $clave pero no devolvio id para $provisional',
          );
        }
        await (_base.update(
          _base.apuntes,
        )..where((a) => a.clave.equals(clave))).write(
          ApuntesCompanion(
            estado: const Value(EstadoApunte.aplicado),
            resueltoAt: Value(_reloj()),
          ),
        );
      } else {
        // Rechazado: se queda, con su motivo y su hora, hasta que una persona
        // decida. No se reintenta y no se borra (regla 6, caso S6).
        await (_base.update(
          _base.apuntes,
        )..where((a) => a.clave.equals(clave))).write(
          ApuntesCompanion(
            estado: const Value(EstadoApunte.rechazado),
            motivo: Value(resultado.motivo),
            resueltoAt: Value(_reloj()),
          ),
        );
      }
    });
  }

  /// Los resultados de una subida entera, en el mismo orden que se mandaron.
  Future<void> resolverLote(Map<String, ResultadoApunte> porClave) async {
    for (final entrada in porClave.entries) {
      await resolver(entrada.key, entrada.value);
    }
  }

  /// Un intento mas para todo el lote. Se cuenta para poder decir en el panel
  /// que un aparato lleva reintentando desde el martes.
  Future<void> anotarIntento(Iterable<String> claves) async {
    if (claves.isEmpty) return;
    await (_base.update(
      _base.apuntes,
    )..where((a) => a.clave.isIn(claves.toList()))).write(
      ApuntesCompanion.custom(
        intentos: _base.apuntes.intentos + const Constant(1),
      ),
    );
  }

  /// Cuantos apuntes quedarian pendientes DESPUES de subir un lote de [enElLote].
  ///
  /// Va en el cuerpo de `POST /sync/subida` porque la cola vive en el telefono:
  /// lo que no ha subido no existe en el servidor, y sin este numero el panel de
  /// control ensenaria a Palma en verde justo el dia que se le corto la subida a
  /// la mitad (`sync/internal/sincro/subida.go`).
  Future<int> cuantosQuedanTras(int enElLote) async {
    final quedan = await _base.cuantosPendientes() - enElLote;
    return quedan > 0 ? quedan : 0;
  }

  /// LO QUE DECIDE UNA PERSONA SOBRE UN RECHAZADO: descartarlo o reintentarlo.
  ///
  /// El pliego dice que un apunte rechazado «se queda a la vista con su motivo
  /// **hasta que una persona decida**», y hasta hoy faltaba justo eso: la
  /// decision. No habia forma de quitarlos ni de volver a intentarlos, asi que
  /// se quedaban en la pantalla para siempre. Jose, 16/09/2026: «no puedo borrar
  /// esas notificaciones».
  ///
  /// Un aparato lo usan VARIAS personas y hay diez repartiendo: una bandeja que
  /// solo crece deja de leerse a la tercera semana, y entonces el rechazo que SI
  /// importaba se pierde entre los viejos.
  ///
  /// Las dos decisiones son distintas a proposito:
  ///
  ///  * **Descartar** borra el apunte. Se usa cuando ya no aplica —el pedido
  ///    entro en otra ruta, la zona se hizo a mano en la web— o cuando el
  ///    rechazo fue culpa nuestra y ya esta arreglado.
  ///  * **Reintentar** lo devuelve a la cola. Se usa cuando lo que lo tumbaba ya
  ///    no esta: un despliegue que faltaba, un permiso que se dio.
  ///
  /// Ninguna de las dos pasa sola. Eso es lo que no se toca del pliego.
  Future<void> descartar(String clave) async {
    final borradas =
        await (_base.delete(_base.apuntes)..where(
              (a) =>
                  a.clave.equals(clave) &
                  a.estado.equalsValue(EstadoApunte.rechazado),
            ))
            .go();
    if (borradas > 0) {
      // Queda dicho: si manana alguien pregunta por que no llego un cierre,
      // esto es lo unico que lo explica.
      Registro.aviso('rechazo descartado a mano: $clave');
    }
  }

  /// Devuelve un rechazado a la cola. Vuelve a salir en el proximo envio.
  Future<void> reintentar(String clave) async {
    final tocadas =
        await (_base.update(_base.apuntes)..where(
              (a) =>
                  a.clave.equals(clave) &
                  a.estado.equalsValue(EstadoApunte.rechazado),
            ))
            .write(
              ApuntesCompanion(
                estado: const Value(EstadoApunte.pendiente),
                motivo: const Value(null),
                resueltoAt: const Value(null),
                intentos: const Value(0),
              ),
            );
    if (tocadas > 0) {
      Registro.aviso('rechazo devuelto a la cola a mano: $clave');
    }
  }

  /// Poda los aplicados viejos. Los rechazados NO se podan nunca: son la unica
  /// constancia de algo que no llego a pasar.
  Future<int> podar() {
    final limite = _reloj().subtract(conservarAplicados);
    return (_base.delete(_base.apuntes)..where(
          (a) =>
              a.estado.equalsValue(EstadoApunte.aplicado) &
              a.resueltoAt.isSmallerThanValue(limite),
        ))
        .go();
  }
}
