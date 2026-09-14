import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/almacenes/datos/almacen_api.dart';

/// Sólo puede haber **un** principal. Si hay dos, el punto desde el que se mide
/// un domicilio depende del orden en que vuelvan de Accesos, y entonces el mismo
/// pedido cuesta dos precios distintos segun la hora.
void main() {
  const lista = [
    AlmacenDeAccesos(id: 'w1', nombre: 'Central', principal: true),
    AlmacenDeAccesos(id: 'w2', nombre: 'Patio sur'),
    AlmacenDeAccesos(id: 'w3', nombre: 'Nave 3'),
  ];

  test('marcar uno desmarca a los demás', () {
    final resultado = conUnSoloPrincipal(lista, 2);
    expect([for (final a in resultado) a.principal], [false, false, true]);
    // Lo demas no se toca.
    expect(
      [for (final a in resultado) a.nombre],
      ['Central', 'Patio sur', 'Nave 3'],
    );
    expect([for (final a in resultado) a.id], ['w1', 'w2', 'w3']);
  });

  test('«sin punto» es no tener coordenadas, no tenerlas en cero', () {
    const sinPunto = AlmacenDeAccesos(nombre: 'Nuevo');
    const enElGolfo = AlmacenDeAccesos(nombre: 'Cero', latitud: 0, longitud: 0);
    expect(sinPunto.sinPunto, isTrue);
    // 0,0 es un punto de verdad —en el golfo de Guinea— y como tal se trata:
    // el aviso que hay que dar entonces es otro.
    expect(enElGolfo.sinPunto, isFalse);
  });

  test('un almacén sin nombre se lee «(sin nombre)», no en blanco', () {
    expect(const AlmacenDeAccesos(nombre: '   ').titulo, '(sin nombre)');
    expect(const AlmacenDeAccesos(nombre: 'Central').titulo, 'Central');
  });

  test('`activo` ausente en el JSON se toma como activo', () {
    // Lo que Accesos no dijo no puede desactivar un almacen por el que hoy pasa
    // el camion.
    final a = AlmacenDeAccesos.deJson(const {'nombre': 'Central'});
    expect(a.activo, isTrue);
    final b = AlmacenDeAccesos.deJson(const {
      'nombre': 'Central',
      'activo': false,
    });
    expect(b.activo, isFalse);
  });

  test('el JSON de ida lleva las coordenadas en nulo cuando no hay punto', () {
    final j = const AlmacenDeAccesos(nombre: 'Nuevo').aJson();
    expect(j['latitud'], isNull);
    expect(j['longitud'], isNull);
    // Sin `id` en uno nuevo: el id lo pone Accesos.
    expect(j.containsKey('id'), isFalse);
  });
}
