import 'package:flutter/material.dart';

import '../pantallas/almacenes/registro.dart';
import '../pantallas/clientes/registro.dart';
import '../pantallas/vehiculos/registro.dart';
import '../pantallas/informes/registro.dart';
import '../pantallas/panel/registro.dart';
import '../pantallas/tablero/registro.dart';
import 'pantalla_registrada.dart';

/// EL REGISTRO. Una linea por pantalla, en el orden en que salen en el menu.
///
/// Este es el unico fichero que un agente de pantalla toca fuera de su carpeta,
/// y toca **una sola linea**: sustituye su `_pendiente(...)` por la llamada a su
/// `registrarX()` y anade el import. El contrato entero esta explicado en
/// `pantalla_registrada.dart`.
///
/// Las que todavia no estan escritas entran como `_pendiente`: asi la
/// aplicacion **compila y se navega desde el primer dia**, el menu esta
/// completo, y quien abre una pantalla sin montar lee por que no hay nada en vez
/// de encontrarse un 404 que parece un fallo.
List<PantallaRegistrada> pantallasDeLaAplicacion() => <PantallaRegistrada>[
  registrarPanel(),

  // DECISION A CONFIRMAR CON JOSE: el tablero es una pantalla NUEVA
  // (`docs/tablero.md`, 14/09/2026) y por eso no esta en las 6 entradas del
  // pliego §8.1, que describe la de Next. Se pone en el menu porque es la
  // pantalla del dia del logistico y sin entrada no se llega a ella; si se
  // decide lo contrario, es cambiar `enElMenu` a false.
  registrarTablero(),

  _pendiente('/routes', 'Rutas', Icons.route_outlined),
  _pendiente('/orders', 'Pedidos', Icons.inventory_2_outlined),
  registrarClientes(),
  registrarVehiculos(),
  registrarAlmacenes(),

  // Reportes NO va en el menu (pliego §8.1): se llega por URL y desde las
  // acciones rapidas del Panel.
  registrarInformes(),
];

/// Una pantalla que todavia no existe. Ocupa su sitio en el menu y dice lo que
/// pasa, que es mas honesto que una ruta que no resuelve.
PantallaRegistrada _pendiente(String ruta, String titulo, IconData icono) =>
    PantallaRegistrada(
      ruta: ruta,
      titulo: titulo,
      icono: icono,
      enElMenu: true,
      construir: (contexto, estado) => _EnConstruccion(titulo: titulo),
    );

class _EnConstruccion extends StatelessWidget {
  const _EnConstruccion({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        '«$titulo» todavía no está montada.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}
