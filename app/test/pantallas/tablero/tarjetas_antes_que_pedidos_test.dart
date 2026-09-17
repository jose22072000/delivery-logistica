import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/frescura/frescura.dart';
import 'package:reparto/nucleo/red/cliente_api.dart';
import 'package:reparto/pantallas/tablero/datos/esquema.dart';
import 'package:reparto/pantallas/tablero/datos/servicio.dart';

import '../../apoyo/base_de_prueba.dart';
import '../../apoyo/servidor_falso.dart';

/// LA FOTO LLEGA ANTES QUE LOS PEDIDOS, Y ESO NO SE PUEDE CALLAR.
///
/// Una colocacion apunta a un pedido (`order_id REFERENCES orders(id)`), asi que
/// no se puede escribir si ese pedido todavia no esta en esta base. La bajada lo
/// sabe y las salta, que es lo correcto — lo que estaba mal es que lo saltado se
/// contaba en una variable local, se escribia en el registro y **quien llamaba
/// se quedaba con un «bajado» limpio**.
///
/// Por que importa: en la web pasa CADA VEZ que se abre. La base del navegador
/// nace vacia, el tablero pide `/board` nada mas pintarse y los pedidos llegan
/// despues por el ciclo, que es otro camino. Las tarjetas llegan primero y se
/// caen todas; luego llegan los pedidos y la foto **ya no se vuelve a pedir**,
/// porque esta guardada para no bajar dos veces por sucursal.
///
/// Lo que se veia, 17/09/2026: la zona «Vista» con 6 pedidos en el telefono y en
/// el servidor, y «Vista (0)» en la web con esos 6 otra vez en «Sin colocar».
/// Sin un solo error en ningun registro.
void main() {
  late BaseLocal base;
  late ServicioTablero servicio;

  const sucursal = 'hab-1';
  const zona = '01a0afc9-2be4-7bf6-9bed-e962c212d62b';
  const pedido = '711fbf5a-a046-4d49-bd59-b30a8fa79fc2';

  setUp(() async {
    base = baseDePrueba();
    await EsquemaTablero.asegurar(base);
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = ServidorFalso(
        (p) async => RespuestaFalsa(200, const {
          'columnas': <Object?>[
            {'id': zona, 'branchId': sucursal, 'nombre': 'Vista', 'posicion': 1},
          ],
          'colocados': <Object?>[
            {'pedidoId': pedido, 'columnaId': zona, 'posicion': 1},
          ],
        }),
      );
    servicio = ServicioTablero(
      base,
      ClienteApi(dio: dio, esperas: const <Duration>[]),
      RegistroDeFrescura(base),
    );
  });

  tearDown(() => base.close());

  Future<int> cuantasTarjetas() async {
    final f = await base
        .customSelect('SELECT count(*) AS n FROM board_placements')
        .getSingle();
    return f.read<int>('n');
  }

  Future<void> sembrarElPedido() => base
      .into(base.orders)
      .insert(
        OrdersCompanion.insert(
          id: pedido,
          customerName: 'TCP ROLANDO',
          address: 'avenida del puerto y via blanca',
          branchId: const Value(sucursal),
        ),
      );

  test('sin el pedido, la tarjeta no se pone Y SE DICE cuántas se quedaron '
      'fuera', () async {
    final r = await servicio.descargar(sucursal);

    expect(await cuantasTarjetas(), 0, reason: 'no se puede: falta el pedido');
    expect(
      r.tarjetasSinPedido,
      1,
      reason:
          'esto es lo que faltaba. Sin este número, quien llama da la foto por '
          'buena y no vuelve a pedirla nunca: la zona se queda a cero para '
          'siempre y nadie se entera',
    );
    // Y la zona sí entró: el fallo no es que no baje nada, es que baja a medias
    // y lo llama completo.
    final zonas = await base
        .customSelect('SELECT count(*) AS n FROM board_columns')
        .getSingle();
    expect(zonas.read<int>('n'), 1);
  });

  test('con el pedido ya aquí, la tarjeta entra y no se queda nada fuera', () async {
    await sembrarElPedido();

    final r = await servicio.descargar(sucursal);

    expect(await cuantasTarjetas(), 1);
    expect(r.tarjetasSinPedido, 0);
    expect(r.seBajo, isTrue);
  });

  test('volver a pedirla cuando el pedido ya llegó la coloca: ésa es la '
      'salida del atasco', () async {
    // 1. Como abre la web: la foto primero, la base sin pedidos.
    final primera = await servicio.descargar(sucursal);
    expect(primera.tarjetasSinPedido, 1);
    expect(await cuantasTarjetas(), 0);

    // 2. Llegan los pedidos por el ciclo, que es el otro camino.
    await sembrarElPedido();

    // 3. Se vuelve a pedir —que es lo que hace ahora el tablero al ver que la
    //    tabla de pedidos cambió— y la tarjeta cae en su sitio.
    final segunda = await servicio.descargar(sucursal);

    expect(await cuantasTarjetas(), 1, reason: 'la zona recupera su pedido');
    expect(segunda.tarjetasSinPedido, 0, reason: 'y ya no falta nada');
  });
}
