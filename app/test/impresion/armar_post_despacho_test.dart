/// La cuenta del post-despacho, que es la que decide si falta mercancia.
///
/// Se prueba aqui y no contra el PDF a proposito: si la resta esta bien, el
/// papel es solo dibujo. Casos del pliego (`../docs/reglas-negocio.md` §12 y
/// `../docs/pantallas.md` §10.2).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/impresion/armar_post_despacho.dart';
import 'package:reparto/impresion/hoja.dart';

const DatosDeRuta _ruta = DatosDeRuta(
  ruta: 'R-014',
  sucursal: 'Camagüey',
  vehiculo: 'Camión #1',
  salida: '14/9/2026, 7:30:00',
  regreso: '14/9/2026, 15:05:00',
);

ItemDePedido _item(String nombre, {num? packs, num? quantity}) =>
    ItemDePedido(name: nombre, packs: packs, quantity: quantity);

void main() {
  group('armarPostDespacho — el caso del pliego', () {
    // Una ruta de cuatro paradas: una entregada, una devuelta, una cancelada y
    // una que NADIE marco, que es el caso por el que existe esta hoja.
    final pedidos = <PedidoDeRuta>[
      PedidoDeRuta(
        customerName: 'Bodega La Plaza',
        resultado: 'entregado',
        items: <ItemDePedido>[
          _item('Arroz', packs: 10),
          _item('Aceite', packs: 4),
        ],
      ),
      PedidoDeRuta(
        customerName: 'Cafetería El Puente',
        resultado: 'devuelto',
        resultadoNota: 'Cerrado, nadie recibió',
        items: <ItemDePedido>[_item('Arroz', packs: 6)],
      ),
      PedidoDeRuta(
        customerName: 'Kiosco Norte',
        resultado: 'cancelado',
        items: <ItemDePedido>[_item('Azúcar', packs: 3)],
      ),
      PedidoDeRuta(
        customerName: 'Mercado Sur',
        // Sin resultado: nadie la toco al volver.
        items: <ItemDePedido>[
          _item('Arroz', packs: 2),
          _item('Azúcar', packs: 9),
        ],
      ),
    ];

    final hoja = armarPostDespacho(_ruta, pedidos);

    test('cuenta las paradas por resultado, y lo no marcado aparte', () {
      expect(hoja.entregadas, 1);
      expect(hoja.devueltas, 1);
      expect(hoja.canceladas, 1);
      // Lo que nadie marco NO se da por entregado: asi es justo como se pierde
      // mercancia sin que salte nada.
      expect(hoja.sinMarcar, 1);
    });

    test('la cabecera se copia tal cual', () {
      expect(hoja.ruta, 'R-014');
      expect(hoja.sucursal, 'Camagüey');
      expect(hoja.vehiculo, 'Camión #1');
      expect(hoja.salida, '14/9/2026, 7:30:00');
      expect(hoja.regreso, '14/9/2026, 15:05:00');
    });

    test('queda es TODO lo que no se entrego: devuelto, cancelado y sin marcar', () {
      final arroz = hoja.lineas.firstWhere((l) => l.producto == 'Arroz');
      expect(arroz.salio, 18); // 10 + 6 + 2
      expect(arroz.entregado, 10); // solo la parada entregada
      expect(arroz.queda, 8); // 6 devueltos + 2 sin marcar

      final azucar = hoja.lineas.firstWhere((l) => l.producto == 'Azúcar');
      expect(azucar.salio, 12);
      expect(azucar.entregado, 0);
      expect(azucar.queda, 12); // 3 cancelados + 9 sin marcar
    });

    test('se cumple la invariante salio == entregado + queda', () {
      for (final l in hoja.lineas) {
        expect(
          l.salio,
          l.entregado + l.queda,
          reason: 'la linea de ${l.producto} no cuadra',
        );
      }
    });

    test('un producto entregado entero NO sale en el papel', () {
      // El aceite se entrego completo: sigue en `lineas` (el cierre de ruta lo
      // usa) pero no en la tabla, que si no alarga la hoja y esconde las tres
      // lineas que importan.
      expect(hoja.lineas.map((l) => l.producto), contains('Aceite'));
      expect(hoja.lineasConResto.map((l) => l.producto), isNot(contains('Aceite')));
      expect(hoja.lineasConResto.map((l) => l.producto), <String>['Azúcar', 'Arroz']);
    });

    test('el pie suma LAS FILAS MOSTRADAS, no todas las lineas', () {
      final t = TotalesPostDespacho.de(hoja);
      // Sin el aceite (4 salio / 4 entregado), que no se imprime.
      expect(t.salio, 30); // 18 arroz + 12 azucar
      expect(t.entregado, 10);
      expect(t.queda, 20);

      // Y el pie tambien cuadra consigo mismo.
      expect(t.salio, t.entregado + t.queda);
    });

    test('las pendientes traen cliente, resultado, nota y productos', () {
      expect(hoja.pendientes.length, 3);
      // En el orden en que llegaron los pedidos, no reordenadas.
      expect(
        hoja.pendientes.map((p) => p.cliente),
        <String>['Cafetería El Puente', 'Kiosco Norte', 'Mercado Sur'],
      );

      final puente = hoja.pendientes.first;
      expect(puente.resultado, 'devuelto');
      expect(puente.nota, 'Cerrado, nadie recibió');
      expect(puente.productos.single.producto, 'Arroz');
      expect(puente.productos.single.formatos, 6);

      // La sin marcar llega con `null`, que es lo que la hoja pinta en ambar.
      expect(hoja.pendientes.last.resultado, isNull);
      expect(hoja.pendientes.last.nota, isNull);
    });

    test('la parada entregada no entra en pendientes', () {
      expect(
        hoja.pendientes.map((p) => p.cliente),
        isNot(contains('Bodega La Plaza')),
      );
    });
  });

  group('armarPostDespacho — el orden', () {
    test('por queda descendente y, a igualdad, por nombre', () {
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[
        const PedidoDeRuta(
          customerName: 'Sin marcar',
          items: <ItemDePedido>[
            ItemDePedido(name: 'Zumo', packs: 5),
            ItemDePedido(name: 'Arroz', packs: 5),
            ItemDePedido(name: 'Ñame', packs: 5),
            ItemDePedido(name: 'Ácido cítrico', packs: 5),
            ItemDePedido(name: 'Pan', packs: 40),
          ],
        ),
      ]);

      // Primero el que mas queda; el resto empatado a 5 y ordenado como lo
      // ordena el idioma: la tilde no manda, y la enye va detras de la n.
      expect(
        hoja.lineas.map((l) => l.producto),
        <String>['Pan', 'Ácido cítrico', 'Arroz', 'Ñame', 'Zumo'],
      );
    });

    test('comparaProductos ordena como el idioma y no como Unicode', () {
      // Con `compareTo` a secas, 'Ácido' caeria DETRAS de 'Zumo' porque la
      // tilde vive por encima de la Z en la tabla de codigos.
      expect(comparaProductos('Ácido', 'Zumo'), lessThan(0));
      expect('Ácido'.compareTo('Zumo'), greaterThan(0));

      // La enye es otra letra y va detras de toda la n.
      expect(comparaProductos('Nuez', 'Ñame'), lessThan(0));
      expect(comparaProductos('Ñame', 'Olivas'), lessThan(0));

      // Y no distingue mayusculas para ordenar.
      expect(comparaProductos('arroz', 'Azúcar'), lessThan(0));
    });
  });

  group('armarPostDespacho — de donde sale el numero de una linea', () {
    test('manda packs; si no los trae, cae a quantity', () {
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[
        const PedidoDeRuta(
          customerName: 'Uno',
          items: <ItemDePedido>[
            ItemDePedido(name: 'Con packs', packs: 3, quantity: 90),
            ItemDePedido(name: 'Sin packs', quantity: 12),
            ItemDePedido(name: 'Packs a cero', packs: 0, quantity: 7),
          ],
        ),
      ]);

      num de(String p) => hoja.lineas.firstWhere((l) => l.producto == p).queda;
      expect(de('Con packs'), 3, reason: 'los packs mandan sobre las unidades');
      expect(de('Sin packs'), 12);
      // Cero packs no es «cero mercancia»: es que la linea no los trae.
      expect(de('Packs a cero'), 7);
    });

    test('sin packs ni quantity el numero es cero, no revienta', () {
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[
        const PedidoDeRuta(
          customerName: 'Uno',
          items: <ItemDePedido>[ItemDePedido(name: 'Nada')],
        ),
      ]);
      expect(hoja.lineas.single.queda, 0);
      // Y con queda 0 no llega al papel.
      expect(hoja.lineasConResto, isEmpty);
    });

    test('el nombre sale de name y, si no hay, de description', () {
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[
        const PedidoDeRuta(
          customerName: 'Uno',
          items: <ItemDePedido>[
            ItemDePedido(description: '  Leche en polvo  ', packs: 2),
            ItemDePedido(name: '  Café  ', description: 'otro', packs: 1),
          ],
        ),
      ]);
      expect(
        hoja.lineas.map((l) => l.producto).toSet(),
        <String>{'Leche en polvo', 'Café'},
      );
    });

    test('las lineas sin nombre de producto se tiran', () {
      // En el papel serian una fila en blanco que nadie sabe contar.
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[
        const PedidoDeRuta(
          customerName: 'Uno',
          items: <ItemDePedido>[
            ItemDePedido(name: '   ', packs: 5),
            ItemDePedido(packs: 5),
            ItemDePedido(name: 'Sal', packs: 5),
          ],
        ),
      ]);
      expect(hoja.lineas.map((l) => l.producto), <String>['Sal']);
      expect(hoja.pendientes.single.productos.length, 1);
    });

    test('desde JSON los numeros en texto se leen igual', () {
      final it = ItemDePedido.deJson(<String, Object?>{
        'name': 'Arroz',
        'packs': '4',
        'quantity': 100,
      });
      expect(it.formatos, 4);

      // Y una basura no tumba la hoja: cae a las unidades.
      final malo = ItemDePedido.deJson(<String, Object?>{
        'name': 'Arroz',
        'packs': 'x',
        'quantity': '9',
      });
      expect(malo.formatos, 9);
    });
  });

  group('armarPostDespacho — los bordes', () {
    test('una ruta entregada entera no deja nada que contar', () {
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[
        const PedidoDeRuta(
          customerName: 'Uno',
          resultado: 'entregado',
          items: <ItemDePedido>[ItemDePedido(name: 'Arroz', packs: 10)],
        ),
      ]);
      expect(hoja.lineasConResto, isEmpty);
      expect(hoja.pendientes, isEmpty);

      final t = TotalesPostDespacho.de(hoja);
      expect(t.salio, 0);
      expect(t.entregado, 0);
      expect(t.queda, 0);
    });

    test('un resultado desconocido cuenta como sin marcar', () {
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[
        const PedidoDeRuta(customerName: 'Uno', resultado: 'reprogramado'),
      ]);
      expect(hoja.sinMarcar, 1);
      expect(hoja.entregadas, 0);
      expect(hoja.pendientes.single.resultado, 'reprogramado');
    });

    test('una ruta sin paradas da una hoja en cero', () {
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[]);
      expect(hoja.lineas, isEmpty);
      expect(hoja.pendientes, isEmpty);
      expect(hoja.entregadas + hoja.devueltas + hoja.canceladas + hoja.sinMarcar, 0);
    });

    test('un resto de coma flotante no ensucia el papel', () {
      // El umbral es `> 0.0001`, el mismo de la de Next: con empaques
      // fraccionados, restar 0.1 tres veces deja un pelo que no es mercancia.
      final hoja = armarPostDespacho(_ruta, <PedidoDeRuta>[
        const PedidoDeRuta(
          customerName: 'Uno',
          items: <ItemDePedido>[ItemDePedido(name: 'Polvo', packs: 0.00001)],
        ),
      ]);
      expect(hoja.lineas.single.queda, greaterThan(0));
      expect(hoja.lineasConResto, isEmpty);
    });
  });
}
