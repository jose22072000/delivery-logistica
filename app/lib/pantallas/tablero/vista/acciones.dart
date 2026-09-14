import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datos/modelos.dart';
import '../estado/proveedores.dart';
import 'kit.dart';

/// Los gestos que no son arrastrar.
///
/// **Existen para el dedo.** Arrastrar una tarjeta de una punta a otra de un
/// telefono, con la mitad izquierda y las doce columnas en pantallas distintas,
/// no se puede hacer; asi que tocar la tarjeta abre «moverla a», que hace
/// exactamente lo mismo y llama al mismo sitio. En el escritorio estan las dos
/// maneras y cada cual usa la que quiera.
abstract final class AccionesTablero {
  /// Toca una tarjeta: a que columna va, o de vuelta a «sin colocar».
  static Future<void> moverTarjeta(
    BuildContext context,
    WidgetRef ref, {
    required TarjetaPedido pedido,
    required Tablero tablero,
    String? columnaActual,
    int? posicionActual,
  }) async {
    await mostrarCajon<void>(
      context: context,
      titulo: pedido.operationNumber ?? pedido.customerName,
      contenido: (contexto) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${pedido.customerName} · ${pesoBonito(pedido.weight)}'
            '${pedido.kmAlAlmacen.isFinite ? ' · ${kmBonito(pedido.kmAlAlmacen)}' : ''}',
            style: Theme.of(contexto).textTheme.bodySmall,
          ),
          // Lo que dejo de servir se dice tambien aqui, no sólo en la tarjeta:
          // es el momento en el que alguien esta decidiendo que hacer con el.
          for (final marca in pedido.marcas)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Insignia(
                  marca.texto,
                  color: marca.grave
                      ? ColoresTablero.rojo
                      : ColoresTablero.ambar,
                ),
              ),
            ),
          const Divider(height: 24),
          if (columnaActual != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Subir una posición'),
              enabled: (posicionActual ?? 1) > 1,
              onTap: () {
                Navigator.of(contexto).pop();
                _hacer(
                  context,
                  ref,
                  () => ref
                      .read(tableroProvider.notifier)
                      .colocar(
                        pedidoId: pedido.pedidoId,
                        columnaId: columnaActual,
                        posicion: (posicionActual ?? 2) - 1,
                      ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Bajar una posición'),
              onTap: () {
                Navigator.of(contexto).pop();
                _hacer(
                  context,
                  ref,
                  () => ref
                      .read(tableroProvider.notifier)
                      .colocar(
                        pedidoId: pedido.pedidoId,
                        columnaId: columnaActual,
                        posicion: (posicionActual ?? 0) + 1,
                      ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.undo),
              title: const Text('Devolver a sin colocar'),
              onTap: () {
                Navigator.of(contexto).pop();
                _hacer(
                  context,
                  ref,
                  () => ref
                      .read(tableroProvider.notifier)
                      .quitar(pedido.pedidoId),
                );
              },
            ),
            const Divider(height: 24),
          ],
          for (final columna in tablero.columnas)
            if (columna.id != columnaActual)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.view_column_outlined),
                title: Text('Colocar en «${columna.nombre}»'),
                subtitle: Text(
                  '${columna.pedidos} pedidos · '
                  '${pesoBonito(columna.pesoKg)}',
                ),
                onTap: () {
                  Navigator.of(contexto).pop();
                  _hacer(
                    context,
                    ref,
                    () => ref
                        .read(tableroProvider.notifier)
                        .colocar(
                          pedidoId: pedido.pedidoId,
                          columnaId: columna.id,
                        ),
                  );
                },
              ),
          if (tablero.columnas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Todavía no hay ninguna columna. Créala con el «+» del tablero '
                'y ponle el nombre de la zona.',
              ),
            ),
        ],
      ),
    );
  }

  /// El menu de la columna: renombrar, camion, vaciar, mover todo, borrar y
  /// armar la ruta.
  static Future<void> menuDeColumna(
    BuildContext context,
    WidgetRef ref, {
    required ColumnaTablero columna,
    required Tablero tablero,
  }) async {
    await mostrarCajon<void>(
      context: context,
      titulo: columna.nombre,
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Renombrar'),
            onTap: () async {
              Navigator.of(contexto).pop();
              final nombre = await _pedirNombre(context, columna.nombre);
              if (nombre == null || !context.mounted) return;
              await _hacer(
                context,
                ref,
                () => ref
                    .read(tableroProvider.notifier)
                    .renombrar(columna.id, nombre),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_shipping_outlined),
            title: const Text('Camión previsto'),
            subtitle: Text(columna.vehiculoNombre ?? 'Sin elegir'),
            onTap: () {
              Navigator.of(contexto).pop();
              _elegirCamion(context, ref, columna);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.layers_clear_outlined),
            title: const Text('Vaciar'),
            subtitle: const Text('Las tarjetas vuelven a «sin colocar»'),
            onTap: () {
              Navigator.of(contexto).pop();
              _hacer(
                context,
                ref,
                () => ref.read(tableroProvider.notifier).vaciar(columna.id),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.drive_file_move_outlined),
            title: const Text('Mover todo a otra columna'),
            onTap: () {
              Navigator.of(contexto).pop();
              _elegirDestino(
                context,
                ref,
                columna: columna,
                tablero: tablero,
                borrarDespues: false,
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: const Text('Borrar la columna'),
            onTap: () {
              Navigator.of(contexto).pop();
              _borrar(context, ref, columna: columna, tablero: tablero);
            },
          ),
          const Divider(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.route_outlined),
            label: const Text('Armar la ruta de esta zona'),
            onPressed: () {
              Navigator.of(contexto).pop();
              _hacer(
                context,
                ref,
                () => ref.read(tableroProvider.notifier).armarRuta(columna.id),
                exito:
                    'Ruta armada con lo que se puede repartir de '
                    '«${columna.nombre}».',
              );
            },
          ),
        ],
      ),
    );
  }

  /// Crear una columna. El nombre lo pone la persona: las zonas son suyas.
  static Future<void> crearColumna(BuildContext context, WidgetRef ref) async {
    final nombre = await _pedirNombre(context, '');
    if (nombre == null || !context.mounted) return;
    await _hacer(
      context,
      ref,
      () => ref.read(tableroProvider.notifier).crearColumna(nombre),
    );
  }

  static Future<void> _elegirCamion(
    BuildContext context,
    WidgetRef ref,
    ColumnaTablero columna,
  ) async {
    final camiones = await ref.read(camionesProvider.future);
    if (!context.mounted) return;
    await mostrarCajon<void>(
      context: context,
      titulo: 'Camión previsto para «${columna.nombre}»',
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.not_interested),
            title: const Text('Sin camión'),
            onTap: () {
              Navigator.of(contexto).pop();
              _hacer(
                context,
                ref,
                () => ref
                    .read(tableroProvider.notifier)
                    .elegirCamion(columna.id, null),
              );
            },
          ),
          for (final camion in camiones)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(camion.name),
              subtitle: Text(
                '${pesoBonito(camion.capacity)}'
                '${camion.plate == null ? '' : ' · ${camion.plate}'}',
              ),
              onTap: () {
                Navigator.of(contexto).pop();
                _hacer(
                  context,
                  ref,
                  () => ref
                      .read(tableroProvider.notifier)
                      .elegirCamion(columna.id, camion.id),
                );
              },
            ),
        ],
      ),
    );
  }

  static Future<void> _elegirDestino(
    BuildContext context,
    WidgetRef ref, {
    required ColumnaTablero columna,
    required Tablero tablero,
    required bool borrarDespues,
  }) async {
    final otras = tablero.columnas.where((c) => c.id != columna.id).toList();
    if (otras.isEmpty) {
      _decir(context, 'No hay otra columna a la que mandarlos.');
      return;
    }
    await mostrarCajon<void>(
      context: context,
      titulo: 'Mandar lo de «${columna.nombre}» a…',
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final destino in otras)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.view_column_outlined),
              title: Text(destino.nombre),
              subtitle: Text('${destino.pedidos} pedidos'),
              onTap: () {
                Navigator.of(contexto).pop();
                _hacer(
                  context,
                  ref,
                  () async {
                    final mando = ref.read(tableroProvider.notifier);
                    if (borrarDespues) {
                      await mando.borrarColumna(
                        columna.id,
                        destinoId: destino.id,
                      );
                    } else {
                      await mando.moverTodo(columna.id, destino.id);
                    }
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  /// Borrar.
  ///
  /// Con pedidos dentro **la base se niega**, y lo que se hace no es insistir:
  /// se pregunta que pasa con lo de dentro. Deshacer el trabajo de alguien en
  /// silencio es la unica cosa que este tablero no puede hacer (§7.6).
  static Future<void> _borrar(
    BuildContext context,
    WidgetRef ref, {
    required ColumnaTablero columna,
    required Tablero tablero,
  }) async {
    if (columna.pedidos == 0) {
      await _hacer(
        context,
        ref,
        () => ref.read(tableroProvider.notifier).borrarColumna(columna.id),
      );
      return;
    }
    await mostrarCajon<void>(
      context: context,
      titulo: '«${columna.nombre}» tiene ${columna.pedidos} pedidos puestos',
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('¿Qué se hace con ellos?'),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.undo),
            title: const Text('Devolverlos a «sin colocar» y borrar'),
            onTap: () {
              Navigator.of(contexto).pop();
              _hacer(
                context,
                ref,
                () => ref
                    .read(tableroProvider.notifier)
                    .borrarColumna(columna.id, vaciar: true),
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.drive_file_move_outlined),
            title: const Text('Mandarlos a otra columna y borrar'),
            onTap: () {
              Navigator.of(contexto).pop();
              _elegirDestino(
                context,
                ref,
                columna: columna,
                tablero: tablero,
                borrarDespues: true,
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<String?> _pedirNombre(
    BuildContext context,
    String inicial,
  ) async {
    final control = TextEditingController(text: inicial);
    final nombre = await mostrarCajon<String>(
      context: context,
      titulo: inicial.isEmpty ? 'Nueva columna' : 'Renombrar «$inicial»',
      contenido: (contexto) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: control,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre de la zona',
              hintText: 'Centro, Vista Alegre, Carretera…',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (texto) => Navigator.of(contexto).pop(texto),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(control.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    control.dispose();
    return (nombre == null || nombre.trim().isEmpty) ? null : nombre.trim();
  }

  /// Hace algo y **ensena el motivo literal si sale que no**.
  ///
  /// Sin envolver en «Ha ocurrido un error»: ««Centro» tiene 8 pedidos puestos»
  /// le dice a alguien que hacer; «Ha ocurrido un error», no.
  static Future<void> _hacer(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() que, {
    String? exito,
  }) async {
    try {
      await que();
      if (exito != null && context.mounted) _decir(context, exito);
    } on RechazoDelTablero catch (e) {
      if (!context.mounted) return;
      _decir(
        context,
        [e.mensaje, ...e.detalles].join('\n'),
        problema: true,
      );
    }
  }

  static void _decir(
    BuildContext context,
    String texto, {
    bool problema = false,
  }) {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    if (mensajero == null) return;
    mensajero
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: problema ? ColoresTablero.rojo : null,
          duration: Duration(seconds: problema ? 6 : 3),
        ),
      );
  }
}
