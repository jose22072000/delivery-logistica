// El asistente «Nueva Ruta»: cajon a pantalla completa con pie fijo y 4 pasos
// —Sucursal, Salida, Vehículo, Pedidos—.
//
// **Funciona entero sin conexion**, y eso no es un extra: armar la ruta pasa en
// el patio del almacen. Los pedidos elegibles salen de la base local, la
// capacidad se comprueba aqui, el orden de visita y los km los calcula el
// aparato (`geo.dart`) y la ruta se guarda con un id `local-…` y su propio
// codigo. Lo que el servidor diga llegara despues, y si dice que no, saldra en la
// bandeja de rechazos con su hora y su motivo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/estado/proveedores_pedidos.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../estado/proveedores_rutas.dart';

class AsistenteNuevaRuta extends ConsumerStatefulWidget {
  const AsistenteNuevaRuta({super.key});

  static const sinAlmacenes =
      'Esta sucursal no tiene ningún almacén con ubicación. Se pone en '
      'Almacenes, y hasta entonces no hay desde dónde medir.';

  static const sinVehiculos =
      'No hay vehículos disponibles. Crea o libera uno en Vehículos para poder '
      'crear la ruta.';

  static const sinPedidos = 'No hay pedidos disponibles para rutear.';

  static const preDespachoVacio =
      'Según vayas eligiendo pedidos, aquí sale cuánto hay que sacar de cada '
      'producto.';

  @override
  ConsumerState<AsistenteNuevaRuta> createState() => _AsistenteState();
}

class _AsistenteState extends ConsumerState<AsistenteNuevaRuta> {
  int _paso = 1;
  String? _sucursalId;
  Almacen? _salida;
  String? _vehiculoId;
  DateTime? _fechaDeEntrega;
  final _nombre = TextEditingController();
  final _elegidos = <String>{};
  bool _generando = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Vehiculo? get _vehiculo {
    final lista = ref.read(vehiculosProvider).value ?? const <Vehiculo>[];
    return lista.where((v) => v.id == _vehiculoId).firstOrNull;
  }

  double _pesoDe(List<Pedido> disponibles) => disponibles
      .where((p) => _elegidos.contains(p.id))
      .fold<double>(0, (suma, p) => suma + p.weight);

  @override
  Widget build(BuildContext context) {
    final sucursales =
        ref.watch(sucursalesProvider).value ?? const <Sucursal>[];
    final codigo = sucursales
        .where((s) => s.id == _sucursalId)
        .firstOrNull
        ?.externalId;
    final disponibles =
        ref
            .watch(
              disponiblesProvider(FiltrosDisponibles(sucursalId: _sucursalId)),
            )
            .value ??
        const <Pedido>[];
    final peso = _pesoDe(disponibles);
    final capacidad = _vehiculo?.capacity;
    final sobrepeso = capacidad != null && peso > capacidad;

    final puedeGenerar =
        _salida != null &&
        _vehiculoId != null &&
        _elegidos.isNotEmpty &&
        !sobrepeso &&
        !_generando;

    return Cajon(
      titulo: 'Nueva Ruta',
      subtitulo: 'Paso $_paso de 4',
      ancho: AnchoCajon.completo,
      pie: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cancelar'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: puedeGenerar ? () => _generar(disponibles) : null,
            child: Text(_generando ? 'Generando ruta...' : 'Generar Ruta'),
          ),
        ],
      ),
      cuerpo: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La barra de progreso: **un paso cada vez**, y se puede volver a
            // uno ya hecho pulsando su tramo.
            Wrap(
              spacing: 8,
              children: [
                for (final tramo in const [
                  (1, 'Sucursal'),
                  (2, 'Salida'),
                  (3, 'Vehículo'),
                  (4, 'Pedidos'),
                ])
                  TextButton(
                    onPressed: tramo.$1 <= _paso
                        ? () => setState(() => _paso = tramo.$1)
                        : null,
                    child: Text(
                      tramo.$2,
                      style: TextStyle(
                        fontWeight: tramo.$1 == _paso
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(),
            if (_paso == 1) _pasoSucursal(sucursales),
            if (_paso == 2) _pasoSalida(codigo),
            if (_paso == 3) _pasoVehiculo(),
            if (_paso == 4)
              _pasoPedidos(
                disponibles: disponibles,
                peso: peso,
                capacidad: capacidad,
              ),
          ],
        ),
      ),
    );
  }

  Widget _pasoSucursal(List<Sucursal> sucursales) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Selector<String>(
        titulo: 'Sucursal de la ruta',
        valor: _sucursalId ?? '',
        opciones: [
          const OpcionSelector('', 'Elige la sucursal…'),
          for (final s in sucursales)
            OpcionSelector(s.id, s.name, nota: s.externalId),
        ],
        alElegir: (id) => setState(() {
          _sucursalId = id.isEmpty ? null : id;
          // Cambiar de sucursal invalida la salida: un almacen de Holguin no es
          // punto de partida de una ruta de Camaguey.
          _salida = null;
          _elegidos.clear();
        }),
      ),
      const SizedBox(height: 8),
      const Text(
        'Los pedidos, los vehículos y el punto de partida serán los de esta '
        'sucursal.',
        style: TextStyle(color: Colores.gris),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _sucursalId == null ? null : () => setState(() => _paso = 2),
        child: const Text('Siguiente'),
      ),
    ],
  );

  Widget _pasoSalida(String? sucursalCodigo) {
    final almacenes = sucursalCodigo == null
        ? const <Almacen>[]
        : (ref.watch(almacenesProvider(sucursalCodigo)).value ??
              const <Almacen>[]);
    final conUbicacion = [
      for (final a in almacenes)
        if (a.lat != null && a.lng != null) a,
    ];

    if (conUbicacion.isEmpty) {
      return const EstadoVacio(AsistenteNuevaRuta.sinAlmacenes);
    }
    _salida ??= conUbicacion.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Selector<String>(
          titulo: 'Almacén del que sale el camión',
          valor: _salida?.id ?? '',
          opciones: [
            for (final a in conUbicacion)
              OpcionSelector(
                a.id,
                a.nombre,
                nota: a.principal ? 'principal' : null,
              ),
          ],
          alElegir: (id) => setState(
            () => _salida = conUbicacion.where((a) => a.id == id).first,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_salida?.direccion ?? ''}  '
          '${_salida?.lat?.toStringAsFixed(5) ?? ''}, '
          '${_salida?.lng?.toStringAsFixed(5) ?? ''}',
          style: const TextStyle(color: Colores.gris),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => setState(() => _paso = 3),
          child: const Text('Continuar →'),
        ),
      ],
    );
  }

  Widget _pasoVehiculo() {
    final vehiculos = ref.watch(vehiculosProvider).value ?? const <Vehiculo>[];
    if (vehiculos.isEmpty) {
      return const EstadoVacio(AsistenteNuevaRuta.sinVehiculos);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Selector<String>(
          titulo: 'Vehículo de la ruta',
          valor: _vehiculoId ?? '',
          opciones: [
            const OpcionSelector('', 'Elige el vehículo…'),
            // **Se ofrecen todos los vehiculos, tambien los ocupados**: la
            // pantalla no decide por nadie, sólo avisa de cual esta en ruta.
            for (final v in vehiculos)
              OpcionSelector(
                v.id,
                v.name,
                nota: v.status == EstadoVehiculo.enUso
                    ? '${v.capacity.toStringAsFixed(0)} kg · en ruta'
                    : '${v.capacity.toStringAsFixed(0)} kg',
              ),
          ],
          alElegir: (id) =>
              setState(() => _vehiculoId = id.isEmpty ? null : id),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nombre,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'Nombre (el código se genera solo)',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Fecha de entrega (opcional): '
                '${_fechaDeEntrega == null ? '—' : fechaCorta(_fechaDeEntrega)}',
              ),
            ),
            OutlinedButton(
              onPressed: () async {
                final hoy = DateTime.now();
                final elegida = await showDatePicker(
                  context: context,
                  firstDate: hoy.subtract(const Duration(days: 30)),
                  lastDate: hoy.add(const Duration(days: 365)),
                  initialDate: hoy,
                );
                if (elegida != null) {
                  setState(() => _fechaDeEntrega = elegida);
                }
              },
              child: const Text('Elegir'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _vehiculoId == null
              ? null
              : () => setState(() => _paso = 4),
          child: const Text('Siguiente'),
        ),
      ],
    );
  }

  Widget _pasoPedidos({
    required List<Pedido> disponibles,
    required double peso,
    required double? capacidad,
  }) {
    if (disponibles.isEmpty) {
      return const EstadoVacio(AsistenteNuevaRuta.sinPedidos);
    }
    final porcentaje = capacidad == null || capacidad == 0
        ? 0.0
        : (peso / capacidad) * 100;
    final color = porcentaje >= 100
        ? Colores.rojo
        : (porcentaje >= 80 ? Colores.ambar : Colores.verde);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pedidos de cliente (${disponibles.length})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (capacidad == null)
          const Text('Elige un vehículo para ver la capacidad')
        else ...[
          Text(
            '${peso.toStringAsFixed(1)} / ${capacidad.toStringAsFixed(0)} kg '
            '(${porcentaje.toStringAsFixed(0)}%)',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          if (porcentaje >= 100) ...[
            const Insignia('LLENO', color: Colores.rojo),
            const Text('Camión lleno — no cabe más'),
          ],
        ],
        const SizedBox(height: 8),
        for (final pedido in disponibles)
          _FilaDisponible(
            pedido: pedido,
            marcado: _elegidos.contains(pedido.id),
            // Lo que no cabe se deshabilita con el motivo a la vista, no se
            // esconde: esconderlo haria pensar que el pedido no existe.
            cabe:
                capacidad == null ||
                _elegidos.contains(pedido.id) ||
                peso + pedido.weight <= capacidad,
            alMarcar: () => setState(() {
              if (!_elegidos.remove(pedido.id)) _elegidos.add(pedido.id);
            }),
          ),
        const SizedBox(height: 8),
        Text(
          '${_elegidos.length} pedidos seleccionados'
          '${capacidad == null ? '' : '  ·  ${peso.toStringAsFixed(1)} / '
                    '${capacidad.toStringAsFixed(0)} kg'}',
        ),
        if (capacidad != null && peso > capacidad)
          Text(
            'Peso (${peso.toStringAsFixed(1)} kg) supera capacidad del '
            'vehículo (${capacidad.toStringAsFixed(0)} kg)',
            style: const TextStyle(color: Colores.rojo),
          ),
        const Divider(),
        _PreDespachoLateral(elegidos: _elegidos.toList()),
      ],
    );
  }

  Future<void> _generar(List<Pedido> disponibles) async {
    setState(() => _generando = true);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final navegador = Navigator.of(context);
    try {
      final rutaId = await ref
          .read(accionesDeRutaProvider)
          .armar(
            vehiculoId: _vehiculoId,
            pedidoIds: _elegidos.toList(),
            origenLat: _salida?.lat,
            origenLng: _salida?.lng,
            nombre: _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
            origenDireccion: _salida?.direccion ?? _salida?.nombre,
            sucursalId: _sucursalId,
            fechaDeEntrega: _fechaDeEntrega,
          );
      // Se selecciona sola, igual que en la de Next.
      ref.read(rutaElegidaProvider.notifier).elegir(rutaId);
      navegador.maybePop();
    } on RechazoLocal catch (fallo) {
      // Los errores del armado salen como aviso emergente, **no dentro del
      // cajon**, y con el texto literal del servidor.
      mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }
}

class _FilaDisponible extends StatelessWidget {
  const _FilaDisponible({
    required this.pedido,
    required this.marcado,
    required this.cabe,
    required this.alMarcar,
  });

  final Pedido pedido;
  final bool marcado;
  final bool cabe;
  final VoidCallback alMarcar;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: cabe ? '' : 'No cabe en el camión',
    child: CheckboxListTile(
      dense: true,
      value: marcado,
      onChanged: cabe ? (_) => alMarcar() : null,
      title: Text(pedido.customerName),
      subtitle: Text(
        '${pedido.endAddress ?? pedido.address} · ${kg(pedido.weight)} · '
        '${usd(pedido.pedidoCosto)}',
      ),
    ),
  );
}

/// El pre-despacho que se suma en vivo segun se van eligiendo pedidos.
class _PreDespachoLateral extends ConsumerWidget {
  const _PreDespachoLateral({required this.elegidos});

  final List<String> elegidos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (elegidos.isEmpty) {
      return const Text(
        AsistenteNuevaRuta.preDespachoVacio,
        style: TextStyle(color: Colores.gris),
      );
    }
    final clave = ([...elegidos]..sort()).join(',');
    final totales = ref
        .watch(preDespachoDeLoElegidoEnElAsistenteProvider(clave))
        .value;
    if (totales == null) return const Text('Cargando pedidos...');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pre-despacho',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final linea in totales.lineas)
          Text(
            '${linea.producto} · ${cantidad(linea.empaques)} emp. · '
            '${cantidad(linea.unidades)} uds.',
          ),
      ],
    );
  }
}

/// El pre-despacho del asistente.
///
/// El argumento es la lista de ids **ordenada y unida por comas**, y no la lista
/// suelta, porque un `family` compara sus argumentos con `==` y dos `List` con el
/// mismo contenido no son iguales en Dart: con la lista cruda se crearia un
/// provider nuevo en cada repintado y la suma se rehariaria sin que nada hubiera
/// cambiado.
final preDespachoDeLoElegidoEnElAsistenteProvider =
    FutureProvider.family<TotalesPreDespacho, String>(
      (ref, clave) => ref
          .watch(consultasPedidosProvider)
          .preDespachoDe(clave.isEmpty ? const [] : clave.split(',')),
    );
