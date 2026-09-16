import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/tablero/datos/consultas.dart';
import 'package:reparto/pantallas/tablero/datos/modelos.dart';
import 'package:reparto/pantallas/tablero/estado/filtros_en_la_url.dart';

import '../../apoyo/base_de_prueba.dart';
import 'apoyo.dart';

/// EL FILTRO DE COBRO DE DOMICILIO en la mitad de «sin colocar».
///
/// Pedido por Jose el 16/09/2026: «falta el filtro de el tablero falto poner los
/// pedidos con cobro de domicilio».
///
/// El costo lo pone el repartidor desde Entrega, y es lo que decide si un pedido
/// se puede meter en una ruta: sin él no se sabe lo que cuesta llevarlo. Las dos
/// preguntas hacen falta —«qué puedo repartir ya» y «qué está esperando a que le
/// pongan el costo»— y la segunda es una lista de trabajo para otra persona.
void main() {
  late BaseLocal base;
  late ConsultasTablero consultas;
  late AlmacenOrigen origen;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasTablero(base);
    await sembrarSucursal(base);
    await sembrarAlmacen(base);
    await sembrarPedido(base, id: 'con-cobro', cobroDomicilio: 12.5);
    await sembrarPedido(base, id: 'de-cero', cobroDomicilio: 0);
    await sembrarPedido(base, id: 'sin-poner');
    origen = await consultas.almacenDe(sucursalStg);
  });

  tearDown(() => base.close());

  Future<List<String>> conFiltro(bool? cobro) async {
    final mitad = await consultas.sinColocar(
      sucursalStg,
      origen,
      filtros: FiltrosSinColocar(conCobroDeDomicilio: cobro),
    );
    return mitad.pedidos.map((p) => p.pedidoId).toList()..sort();
  }

  test('sin el filtro salen los tres', () async {
    expect(await conFiltro(null), ['con-cobro', 'de-cero', 'sin-poner']);
  });

  test('«con cobro» incluye el de CERO, que no es un hueco', () async {
    // Un domicilio de cero es una decisión de alguien —se lleva gratis—, no un
    // dato que falte. Preguntar por «> 0» lo escondería, y ese pedido SÍ se
    // puede repartir hoy.
    expect(await conFiltro(true), ['con-cobro', 'de-cero']);
  });

  test('«sin cobro» es exactamente lo que espera a que se lo pongan', () async {
    expect(await conFiltro(false), ['sin-poner']);
  });

  test('el filtro viaja en la dirección, para poder mandar el enlace', () {
    expect(
      FiltrosEnLaUrl.escribir(
        const FiltrosSinColocar(conCobroDeDomicilio: true),
      )['cobro'],
      'si',
    );
    expect(
      FiltrosEnLaUrl.escribir(
        const FiltrosSinColocar(conCobroDeDomicilio: false),
      )['cobro'],
      'no',
    );
    expect(
      FiltrosEnLaUrl.escribir(const FiltrosSinColocar()).containsKey('cobro'),
      isFalse,
      reason: 'sin el parámetro son los dos',
    );
  });

  test('un enlace sin el parámetro NO se lee como «sin cobro»', () {
    // Leerlo como un booleano suelto convertiría «todos» en «sin cobro» al abrir
    // un enlace viejo, y quien lo abriera vería la lista vacía sin saber por qué.
    expect(
      FiltrosEnLaUrl.leer(const <String, String>{}).conCobroDeDomicilio,
      isNull,
    );
    expect(
      FiltrosEnLaUrl.leer(const {'cobro': 'si'}).conCobroDeDomicilio,
      isTrue,
    );
    expect(
      FiltrosEnLaUrl.leer(const {'cobro': 'no'}).conCobroDeDomicilio,
      isFalse,
    );
  });
}
