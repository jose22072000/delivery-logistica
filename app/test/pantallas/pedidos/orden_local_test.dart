// El orden de `Cómo se ordena esta página`.
//
// **Ordena SÓLO la pagina visible.** Es lo que hace la de Next y es deliberado:
// si ordenara la consulta, la pagina 2 podria repetir pedidos que ya salieron en
// la 1. Por eso se prueba como funcion pura sobre una lista, y ademas se
// comprueba que la consulta paginada sigue saliendo en el orden del servidor.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/pantallas/pedidos/datos/filtros_pedidos.dart';
import 'package:reparto/pantallas/pedidos/datos/repositorio_pedidos.dart';

import '../../apoyo/base_de_prueba.dart';
import 'sembrar.dart';

void main() {
  late BaseLocal base;
  late ConsultasPedidos consultas;

  setUp(() async {
    base = baseDePrueba();
    consultas = ConsultasPedidos(base);
    await sembrarLosOnce(base);
  });

  tearDown(() => base.close());

  Future<List<Pedido>> todos() =>
      consultas.pagina(const FiltrosPedidos.sinNada()).first;

  test('la consulta sale en el orden del SERVIDOR, con los sin fecha al final', () async {
    final pagina = await todos();
    expect(pagina.first.id, 'o10'); // 10 de septiembre, el mas nuevo
    // o11 no tiene `orderDate`: SQLite pone los NULL al final en DESC, que es el
    // `nulls last` del servidor.
    expect(pagina.last.id, 'o11');
  });

  test('los seis ordenes reordenan la lista que se les da', () async {
    final pagina = await todos();

    expect(ordenarPagina(pagina, OrdenLocal.recientes).first.id, 'o10');
    expect(ordenarPagina(pagina, OrdenLocal.antiguos).first.id, 'o11');
    expect(ordenarPagina(pagina, OrdenLocal.precioDesc).first.id, 'o10');
    // o2 no tiene precio: sin precio se va al FINAL en los dos sentidos, porque
    // «no cotizado» no es «el mas barato».
    expect(ordenarPagina(pagina, OrdenLocal.precioAsc).first.id, 'o11');
    expect(ordenarPagina(pagina, OrdenLocal.precioAsc).last.id, 'o2');
    expect(ordenarPagina(pagina, OrdenLocal.distanciaDesc).first.id, 'o4');
    expect(ordenarPagina(pagina, OrdenLocal.pesoDesc).first.id, 'o2');
  });

  test('ordenar no toca la lista que entra', () async {
    final pagina = await todos();
    final antes = [for (final p in pagina) p.id];
    ordenarPagina(pagina, OrdenLocal.pesoDesc);
    expect([for (final p in pagina) p.id], antes);
  });

  test('la paginacion es de 50 y la fija el servidor', () {
    expect(ConsultasPedidos.porPagina, 50);
  });
}
