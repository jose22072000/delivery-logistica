import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/plataforma.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
import 'package:reparto/pantallas/tablero/datos/servicio.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// LA WEB LEE DEL SERVIDOR. No tiene trabajo que proteger porque no trabaja sin conexión.
///
/// Toda la guarda de `descargar` existe para que la foto del servidor no borre lo que se
/// hizo sin señal y todavía no ha subido. **En un navegador ese trabajo no existe**: la web
/// está en el servidor y siempre tiene conexión.
///
/// Dejarle la guarda no la protegía de nada y sí la rompía: un solo apunte atascado
/// congelaba el tablero indefinidamente. El 16/09/2026 estuvo hora y media enseñando una
/// foto de las 16:13 mientras el teléfono subía zonas que no aparecían nunca.
///
/// Jose, ese día, después de haberlo dicho ya tres veces: «el desktop y las apks tienen su
/// propia base de datos para trabajar sin conexión; la web siempre está con conexión porque
/// está en el servidor».
void main() {
  late BaseLocal base;
  late ServicioTablero servicio;
  var llamadas = 0;

  const sucursal = 'hab-1';

  setUp(() async {
    base = baseDePrueba();
    await EsquemaTablero.asegurar(base);
    llamadas = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = ServidorFalso((p) async {
        llamadas++;
        return RespuestaFalsa(200, const {
          'columnas': <Object?>[],
          'colocados': <Object?>[],
        });
      });
    servicio = ServicioTablero(
      base,
      ClienteApi(dio: dio, esperas: const <Duration>[]),
      RegistroDeFrescura(base),
    );
  });

  tearDown(() => base.close());

  Future<int> cuantasZonas() async {
    final f = await base
        .customSelect('SELECT count(*) AS n FROM board_columns')
        .getSingle();
    return f.read<int>('n');
  }

  test('en la APK, con trabajo sin subir, NO se baja', () async {
    // El contrato del aparato, intacto: ahí sí hay un día entero sin señal que proteger.
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, nacio_aqui) '
      "VALUES ('c1', ?1, 'Vista', 1, 1)",
      [sucursal],
    );

    final r = await servicio.descargar(sucursal);

    expect(
      r.seBajo,
      isFalse,
      reason: 'en la APK el trabajo manda sobre la foto',
    );
    expect(await cuantasZonas(), 1);
    expect(llamadas, 0);
  });

  test('en la WEB se baja igual: no hay nada que proteger', () async {
    // Mismo estado, otra plataforma. Aquí ese 1 no puede existir —en la web no se trabaja
    // sin conexión— y tratarlo como trabajo a proteger es lo que congelaba la pantalla.
    await base.customStatement(
      'INSERT INTO board_columns (id, branch_id, nombre, posicion, nacio_aqui) '
      "VALUES ('c1', ?1, 'Vista', 1, 1)",
      [sucursal],
    );

    final r = await Destino.comoSiFueraWeb(() => servicio.descargar(sucursal));

    expect(
      r.seBajo,
      isTrue,
      reason: 'un apunte atascado no puede congelar el tablero de la web',
    );
    expect(llamadas, 1, reason: 'le pregunta al servidor, que es la verdad');
    expect(
      await cuantasZonas(),
      0,
      reason: 'lo que manda es la foto de la nube',
    );
  });

  test('y con la cola llena, en la WEB, también', () async {
    await ColaDeSalida(base).encolar(
      metodo: 'POST',
      ruta: '/board/columns?branchId=$sucursal',
      cuerpo: const {'nombre': 'Vista'},
    );

    final r = await Destino.comoSiFueraWeb(() => servicio.descargar(sucursal));

    expect(r.seBajo, isTrue);
    expect(llamadas, 1);
  });
}
