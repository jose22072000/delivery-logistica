// BAJAR EL PAQUETE: una sola vez, entero, y reanudable.
//
// Jose: «que se descargue el mapa en la aplicación de Cuba para que tenga el
// mapa ya siempre funcional; cuando cargue sólo una vez, para que pueda
// trabajar».
//
// «Sólo una vez» tiene dos trampas y las dos ya nos han costado caro:
//
// ## 1. Una descarga que se corta y se da por buena
//
// Es el fallo de los 2.000 clientes otra vez (`CLAUDE.md` §3): se pidió un tope
// y nadie miró si se alcanzó. Aquí se mira **dos veces**, y las dos hacen falta:
//
//   - **los bytes**: al terminar tienen que ser exactamente los que anunció el
//     servidor. Ni uno menos.
//   - **el `sha256`**: porque los bytes pueden cuadrar y el contenido no. Un
//     proxy que devuelve una página de error de 26 MB es absurdo, pero un
//     reanudado que empieza en el sitio equivocado no lo es nada, y deja un
//     fichero del tamaño justo lleno de basura en medio.
//
// El `sha256` no es adorno: **es lo único que separa «bajado» de «bajado
// entero»**, y es lo que permite que el fichero se pueda colgar en un sitio
// cualquiera sin que haya que fiarse de él.
//
// ## 2. En la conexión de allá, 26 MB no entran de una vez
//
// Por eso lo bajado se guarda con otro nombre (`.parcial`) y se continúa con
// `Range`. Y por eso hay una comprobación que parece de más y es la importante:
// **cuando se pide reanudar, se comprueba que de verdad se reanudó**. Un
// servidor que ignora `Range` contesta `200 OK` con el fichero entero, y
// añadirlo detrás de lo que ya había deja un fichero del doble de tamaño. Con
// los bytes y el `sha256` se cazaría al final, pero después de haber gastado la
// descarga entera — que en Cuba es lo que hay que evitar.
//
// ## Lo que NO hace
//
// No baja nada solo. Lo mismo que el aviso de versión (`docs/actualizaciones.md`
// §1.2): **se avisa, decide la persona**. Quien usa esto está en el patio de un
// almacén con la señal justa; que la aplicación decida por él que ahora toca
// bajarse 26 MB es peor que cualquier mapa viejo.

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../nucleo/registro/registro.dart';
import '../nucleo/reloj.dart';
import 'anuncio_de_mapa.dart';
import 'carpeta_del_mapa.dart';

/// Cómo va la descarga. Se reporta hacia arriba para que la pantalla lo diga con
/// un número, no con una rueda.
typedef ComoVa = void Function({required int bajados, required int total});

/// Lo que sale de bajar.
sealed class ResultadoDeDescarga {
  const ResultadoDeDescarga();
}

class DescargaLista extends ResultadoDeDescarga {
  const DescargaLista(this.guardado);

  final PaqueteGuardado guardado;
}

/// FALLÓ, **y se dice qué faltó y qué se pierde sin ello** (`CLAUDE.md` §4).
class DescargaFallida extends ResultadoDeDescarga {
  const DescargaFallida(
    this.motivo, {
    required this.bajados,
    required this.total,
    required this.sePuedeReanudar,
  });

  /// El motivo literal, para la pantalla. «No se pudo descargar» no le dice a
  /// nadie qué hacer.
  final String motivo;
  final int bajados;
  final int total;

  /// `true` cuando lo bajado sigue sirviendo y la próxima vez continúa donde se
  /// quedó. `false` cuando hubo que tirarlo, y entonces la pantalla lo dice en
  /// vez de dejar creer que se conserva.
  final bool sePuedeReanudar;

  String get loQueFalta => 'Faltan ${enMegas(total - bajados)} de ${enMegas(total)}.';
}

/// QUIEN BAJA.
class DescargaDeMapa {
  DescargaDeMapa(this._cliente, this._carpeta, {Reloj? reloj})
    : _reloj = reloj ?? relojDelAparato;

  final Dio _cliente;
  final CarpetaDelMapa _carpeta;
  final Reloj _reloj;

  /// Baja [nivel] entero, continuando lo que hubiera.
  ///
  /// [cancelar] deja el `.parcial` donde está: cancelar no es tirar lo bajado.
  Future<ResultadoDeDescarga> bajar(
    NivelDeMapa nivel, {
    ComoVa? comoVa,
    CancelToken? cancelar,
  }) async {
    final parcial = nivel.ficheroParcial;
    var yaHay = await _carpeta.bytes(parcial);

    // Lo que hay es MÁS de lo que se anunció: es de otra versión, o de una
    // descarga que se fue de madre. No se puede reanudar encima.
    if (yaHay > nivel.bytes) {
      Registro.aviso(
        'el parcial de ${nivel.nivel} tiene $yaHay bytes y el paquete son '
        '${nivel.bytes}: se empieza de cero',
      );
      await _carpeta.borrar(parcial);
      yaHay = 0;
    }

    if (yaHay < nivel.bytes) {
      final fallo = await _traer(nivel, yaHay, comoVa, cancelar);
      if (fallo != null) return fallo;
    }

    // ── EL TOPE, COMPROBADO. Si se pide un tamaño, se mira si se alcanzó.
    final bajados = await _carpeta.bytes(parcial);
    if (bajados != nivel.bytes) {
      return DescargaFallida(
        'La descarga se cortó: llegaron ${enMegas(bajados)} de los '
        '${enMegas(nivel.bytes)} del mapa. Lo bajado se guarda; al volver a '
        'intentarlo continúa donde se quedó.',
        bajados: bajados,
        total: nivel.bytes,
        sePuedeReanudar: true,
      );
    }

    // ── Y LA HUELLA, que es lo otro. Los bytes pueden cuadrar y el contenido no.
    final huella = await _huellaDe(parcial);
    if (huella != nivel.sha256) {
      // Un fichero del tamaño justo y con otro contenido no se conserva: seguir
      // reanudando encima de él no arregla nada nunca.
      await _carpeta.borrar(parcial);
      return DescargaFallida(
        'El mapa llegó completo pero no es el que el servidor dice tener '
        '(la huella no cuadra). Se ha borrado lo bajado: hay que empezar de '
        'nuevo. Si vuelve a pasar, avisa a la oficina.',
        bajados: nivel.bytes,
        total: nivel.bytes,
        sePuedeReanudar: false,
      );
    }

    // Sólo AHORA se pisa el bueno. Hasta que la huella no cuadra, el mapa que ya
    // había sigue intacto: perder el mapa viejo por intentar bajar el nuevo, en
    // la conexión de allá, es exactamente el fallo que no puede pasar.
    await _carpeta.renombrar(parcial, nivel.fichero);
    final guardado = PaqueteGuardado(
      nivel: nivel.nivel,
      version: nivel.version,
      bytes: nivel.bytes,
      sha256: nivel.sha256,
      guardadoAt: _reloj(),
    );
    await _carpeta.escribirTexto(nivel.apunte, _comoJson(guardado));
    return DescargaLista(guardado);
  }

  /// La parte de red. Devuelve `null` si fue bien, o el fallo.
  Future<DescargaFallida?> _traer(
    NivelDeMapa nivel,
    int desde,
    ComoVa? comoVa,
    CancelToken? cancelar,
  ) async {
    Response<ResponseBody> r;
    try {
      r = await _cliente.get<ResponseBody>(
        nivel.url,
        cancelToken: cancelar,
        options: Options(
          responseType: ResponseType.stream,
          // `validateStatus` abierto para poder mirar el código nosotros: con el
          // de serie, un 416 llega como excepción y se pierde el motivo.
          validateStatus: (_) => true,
          headers: {if (desde > 0) 'Range': 'bytes=$desde-'},
          // Sin plazo de recepción: son 26 MB por una conexión que va y viene, y
          // cortar a los 30 s es garantizar que no termine nunca.
          receiveTimeout: null,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return DescargaFallida(
          'Descarga detenida. Lo bajado se guarda y continúa donde se quedó.',
          bajados: await _carpeta.bytes(nivel.ficheroParcial),
          total: nivel.bytes,
          sePuedeReanudar: true,
        );
      }
      return DescargaFallida(
        'No se pudo conectar para bajar el mapa: ${e.message ?? e.type.name}. '
        'Lo bajado se guarda.',
        bajados: desde,
        total: nivel.bytes,
        sePuedeReanudar: true,
      );
    }

    final codigo = r.statusCode ?? 0;
    if (codigo != 200 && codigo != 206) {
      return DescargaFallida(
        'El servidor contestó $codigo al pedir el mapa. Es un problema del '
        'servidor, no de la señal: avisa a la oficina.',
        bajados: desde,
        total: nivel.bytes,
        sePuedeReanudar: true,
      );
    }

    // ══ SE PIDIÓ REANUDAR: ¿SE REANUDÓ DE VERDAD? ══════════════════════════
    //
    // Es la misma regla de siempre: **si pides un tope, comprueba si lo
    // alcanzaste** (`CLAUDE.md` §3). Aquí el tope es «empieza en el byte N», y
    // hay dos formas de que el servidor no lo cumpla, con arreglos distintos:
    var escritos = desde;
    if (desde > 0 && codigo != 206) {
      // 1. IGNORA `Range` y manda el fichero ENTERO con un 200. Pegarlo detrás
      //    de lo que había deja un fichero del doble de tamaño. Como lo que
      //    viene es el fichero completo, se tira lo que había y se escribe éste
      //    desde cero: se gasta la descarga entera, pero termina bien.
      Registro.aviso(
        'se pidió Range desde $desde y el servidor contestó $codigo: no sabe '
        'reanudar, se empieza de cero',
      );
      await _carpeta.borrar(nivel.ficheroParcial);
      escritos = 0;
    } else if (desde > 0 && !_elRangoEmpiezaEn(r.headers.value('content-range'), desde)) {
      // 2. Contesta 206 pero **desde otro sitio**. Aquí lo que viene NO es el
      //    fichero entero: es un trozo que empieza donde le ha parecido, y
      //    pegarlo deja un agujero en medio. El fichero saldría del tamaño
      //    justo y roto, y lo cazaría el `sha256` — después de haber gastado la
      //    descarga. Así que no se escribe ni un byte: se tira el parcial y se
      //    dice, y el siguiente intento empieza limpio.
      final rango = r.headers.value('content-range');
      await _carpeta.borrar(nivel.ficheroParcial);
      return DescargaFallida(
        'El servidor no continuó donde se le pidió (mandó «$rango» y se le '
        'pidió desde $desde). Se ha descartado lo bajado; al volver a '
        'intentarlo empieza de cero.',
        bajados: 0,
        total: nivel.bytes,
        sePuedeReanudar: true,
      );
    }

    try {
      await for (final trozo in r.data!.stream) {
        // Se mira el botón de detener en cada trozo. No sobra: quien lo pulsa
        // está mirando una barra que no avanza, y que siga bajando después de
        // haberlo pulsado es lo que hace que nadie vuelva a fiarse del botón.
        if (cancelar?.isCancelled ?? false) {
          return DescargaFallida(
            'Descarga detenida. Lo bajado se guarda y continúa donde se quedó.',
            bajados: await _carpeta.bytes(nivel.ficheroParcial),
            total: nivel.bytes,
            sePuedeReanudar: true,
          );
        }
        await _carpeta.anadir(nivel.ficheroParcial, trozo);
        escritos += trozo.length;
        comoVa?.call(bajados: escritos, total: nivel.bytes);
      }
    } on Object catch (e) {
      final bajados = await _carpeta.bytes(nivel.ficheroParcial);
      final cancelado = e is DioException && CancelToken.isCancel(e);
      return DescargaFallida(
        cancelado
            ? 'Descarga detenida. Lo bajado se guarda y continúa donde se quedó.'
            : 'Se cortó la conexión bajando el mapa. Lo bajado se guarda y '
                  'continúa donde se quedó.',
        bajados: bajados,
        total: nivel.bytes,
        sePuedeReanudar: true,
      );
    }
    return null;
  }

  /// El `sha256` **por trozos**: cargarse 26 MB en la memoria de un teléfono
  /// para calcular una huella es la forma de que la aplicación muera justo al
  /// final de la descarga.
  Future<String> _huellaDe(String nombre) async {
    final recoge = _RecogeLaHuella();
    final entrada = sha256.startChunkedConversion(recoge);
    await for (final trozo in _carpeta.porTrozos(nombre)) {
      entrada.add(trozo);
    }
    entrada.close();
    return recoge.huella?.toString() ?? '';
  }
}

/// `Content-Range: bytes 1000-2000/3000` tiene que empezar donde se pidió.
bool _elRangoEmpiezaEn(String? cabecera, int desde) {
  if (cabecera == null) return false;
  final trozos = cabecera.trim().split(RegExp(r'[\s-]+'));
  if (trozos.length < 2 || trozos[0] != 'bytes') return false;
  return int.tryParse(trozos[1]) == desde;
}

String _comoJson(PaqueteGuardado g) {
  final m = g.aJson();
  final partes = m.entries.map((e) {
    final v = e.value;
    return '"${e.key}":${v is num ? v : '"$v"'}';
  });
  return '{${partes.join(',')}}';
}

class _RecogeLaHuella implements Sink<Digest> {
  Digest? huella;

  @override
  void add(Digest d) => huella = d;

  @override
  void close() {}
}

/// Para que las pruebas puedan inyectar bytes sin red.
Uint8List bytesDe(List<int> l) => Uint8List.fromList(l);
