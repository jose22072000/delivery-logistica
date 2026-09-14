import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/almacenes/datos/almacen_api.dart';
import 'package:reparto/pantallas/almacenes/estado/estado_almacenes.dart';

import '../../apoyo/servidor_falso.dart';
import 'apoyo_almacenes.dart';

/// Almacenes tambien es de sólo con conexion, y aqui mentir sale mas caro que en
/// ningun sitio: `Guardado en Accesos.` con el dato todavia en el telefono es
/// una frase falsa sobre un sistema que no se puede consultar desde la calle.
void main() {
  const almacenes = [
    AlmacenDeAccesos(
      id: 'w1',
      nombre: 'Almacén central',
      latitud: 20.0247,
      longitud: -75.8219,
      principal: true,
    ),
    AlmacenDeAccesos(id: 'w2', nombre: 'Patio sur'),
  ];

  test('sin conexión NO dice «Guardado en Accesos.» y no encola nada', () async {
    final banco = Banco.sinRed();
    addTearDown(banco.cerrar);

    final guardo = await banco.contenedor
        .read(controlAlmacenesProvider.notifier)
        .guardar('STG', almacenes);

    expect(guardo, isFalse);
    final aviso = banco.contenedor.read(controlAlmacenesProvider)!;
    expect(aviso.esFallo, isTrue);
    expect(aviso.texto, contains('Sin conexión'));
    expect(aviso.texto, contains('no se guardó nada en Accesos'));
    expect(aviso.texto, isNot(contains('Guardado en Accesos.')));

    // Ni cola ni copia local: el almacen vive en Accesos y hay UNA copia.
    expect(await banco.base.cuantosPendientes(), 0);
    expect(await banco.base.select(banco.base.warehouses).get(), isEmpty);
  });

  test('con conexión manda la LISTA COMPLETA de la sucursal', () async {
    final banco = Banco(
      (p) async => RespuestaFalsa(200, {
        'almacenes': [
          {'id': 'w1', 'nombre': 'Almacén central', 'principal': true},
          {'id': 'w2', 'nombre': 'Patio sur'},
        ],
        'aviso': '1 almacén(es) sin coordenadas: desde ésos no se puede medir '
            'el domicilio.',
      }),
    );
    addTearDown(banco.cerrar);

    final guardo = await banco.contenedor
        .read(controlAlmacenesProvider.notifier)
        .guardar('STG', almacenes);

    expect(guardo, isTrue);

    final peticion = banco.servidor.vistas.single;
    expect(peticion.metodo, 'PUT');
    expect(peticion.ruta, endsWith('/almacenes'));
    final cuerpo = peticion.cuerpo! as Map<String, Object?>;
    expect(cuerpo['codigo'], 'STG');
    // Los DOS, no el que se toco: el `PUT` sustituye la lista entera, asi que
    // mandar uno solo borraria el otro.
    expect((cuerpo['almacenes']! as List<Object?>).length, 2);

    final aviso = banco.contenedor.read(controlAlmacenesProvider)!;
    expect(aviso.esFallo, isFalse);
    expect(aviso.texto, startsWith('Guardado en Accesos.'));
    // El aviso de Accesos se ensena literal, detras de la confirmacion.
    expect(aviso.texto, contains('sin coordenadas'));
  });

  test('el rechazo de Accesos se enseña literal', () async {
    final banco = Banco(
      (p) async => RespuestaFalsa(403, {'error': 'Sin acceso a esa sucursal'}),
    );
    addTearDown(banco.cerrar);

    final guardo = await banco.contenedor
        .read(controlAlmacenesProvider.notifier)
        .guardar('HAB', almacenes);

    expect(guardo, isFalse);
    expect(
      banco.contenedor.read(controlAlmacenesProvider)!.texto,
      'Sin acceso a esa sucursal',
    );
  });
}
