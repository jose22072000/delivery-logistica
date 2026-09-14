// El pre-despacho: cuanto hay que sacar del almacen.
//
// Es la mitad del valor de la pantalla de Pedidos y es una suma que alguien va a
// comparar contra lo que de verdad saque del almacen. Por eso se comprueba contra
// un caso hecho a mano y no contra otra suma calculada en el propio test.

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

  test('el pre-despacho de lo marcado suma empaques, unidades y kilos', () async {
    // o1: Arroz 2 empaques / 20 uds (producto con 25 kg por empaque) + Frijol 1/10
    // o2: Arroz 3 empaques / 30 uds
    final totales = await consultas.preDespachoDe(['o1', 'o2']);

    expect(totales.lineas.length, 2);
    // Lo que mas empaques tiene, primero.
    final arroz = totales.lineas.first;
    expect(arroz.producto, 'Arroz');
    expect(arroz.empaques, 5);
    expect(arroz.unidades, 50);
    // 5 empaques × 25 kg = 125 kg, hecho a mano.
    expect(arroz.pesoKg, 125);

    final frijol = totales.lineas.last;
    expect(frijol.producto, 'Frijol');
    expect(frijol.empaques, 1);
    expect(frijol.unidades, 10);
    // Sin producto emparejado no hay peso resuelto: **null, no cero**. Un cero se
    // leeria como «no pesa» y la hoja del almacen cuadraria mal.
    expect(frijol.pesoKg, isNull);

    expect(totales.productos, 2);
    expect(totales.empaques, 6);
    expect(totales.unidades, 60);
    expect(totales.pesoKg, 125);
  });

  test('una linea sin empaques suma 0 empaques pero sus unidades enteras', () async {
    // El contrato del servidor dice `formatos: Σ packs`. La linea de o3 no trae
    // `packs`, asi que no suma empaques — pero sus 5 unidades si cuentan, o
    // desapareceria de la hoja un producto que hay que sacar.
    final totales = await consultas.preDespachoDe(['o3']);
    expect(totales.lineas.single.producto, 'Aceite');
    expect(totales.lineas.single.empaques, 0);
    expect(totales.lineas.single.unidades, 5);
  });

  test('el pre-despacho de lo filtrado usa el MISMO where que la lista', () async {
    // Con el arranque acotado, o3 (sin factura) queda fuera: su Aceite no puede
    // aparecer en la hoja de lo que sube al camion.
    final acotado = await consultas.preDespachoDeLoFiltrado(
      const FiltrosPedidos(),
    );
    expect(
      acotado.lineas.map((l) => l.producto),
      isNot(contains('Aceite')),
    );

    // Sin filtros, si sale.
    final todo = await consultas.preDespachoDeLoFiltrado(
      const FiltrosPedidos.sinNada(),
    );
    expect(todo.lineas.map((l) => l.producto), contains('Aceite'));
  });

  test('sin nada marcado no hay lineas ni consulta', () async {
    final totales = await consultas.preDespachoDe(const []);
    expect(totales.lineas, isEmpty);
    expect(totales.empaques, 0);
  });
}
