// El asistente «Nueva Ruta»: cajon a pantalla completa con pie fijo y 4 pasos
// —Sucursal, Salida, Vehículo, Pedidos—.
//
// **Funciona entero sin conexion**, y eso no es un extra: armar la ruta pasa en
// el patio del almacen. Los pedidos elegibles salen de la base local, la
// capacidad se comprueba aqui, el orden de visita y los km los calcula el
// aparato (`geo.dart`) y la ruta se guarda con un id `local-…` y su propio
// codigo. Lo que el servidor diga llegara despues, y si dice que no, saldra en la
// bandeja de rechazos con su hora y su motivo.
//
// Pliego: `../../../../docs/pantallas.md` §3, «Asistente Nueva Ruta».

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../impresion/hoja.dart' as papel;
import '../../../impresion/pre_despacho.dart' show pdfPreDespacho;
import '../../../impresion/vista_previa.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/estado/proveedores_pedidos.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../datos/repositorio_rutas.dart';
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

  static const cargandoPedidos = 'Cargando pedidos...';

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
  final _buscador = TextEditingController();
  Timer? _espera;

  /// Lo elegido, **con el pedido dentro y no sólo su id**.
  ///
  /// Hace falta guardarlo entero porque un pedido elegido puede dejar de salir
  /// en la lista al cambiar de dia o de vendedor, y sigue contando: su peso
  /// sigue en el camion y tiene que seguir sumando en la barra de capacidad. Con
  /// un `Set<String>` el peso de esos se perdia y el camion parecia mas vacio de
  /// lo que iba a salir.
  final _elegidos = <String, Pedido>{};

  FiltrosDisponibles _filtros = const FiltrosDisponibles();

  /// Que el salto al paso 3 pase **una sola vez**. Sin esto, volver a mano al
  /// paso 1 rebotaria al 3 en el siguiente repintado y no habria forma de
  /// cambiar de sucursal.
  bool _arranqueResuelto = false;

  bool _generando = false;

  @override
  void dispose() {
    _espera?.cancel();
    _nombre.dispose();
    _buscador.dispose();
    super.dispose();
  }

  Vehiculo? get _vehiculo {
    final lista = ref.read(vehiculosProvider).value ?? const <Vehiculo>[];
    return lista.where((v) => v.id == _vehiculoId).firstOrNull;
  }

  double get _peso =>
      _elegidos.values.fold<double>(0, (suma, p) => suma + p.weight);

  void _ponerFiltros(FiltrosDisponibles nuevos) =>
      setState(() => _filtros = nuevos);

  /// 400 ms de espera antes de buscar. Sin ella, escribir «camagüey» son ocho
  /// consultas y ocho repintados con la lista entera de disponibles detras.
  void _buscar(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _ponerFiltros(_filtros.copiarCon(q: texto.trim()));
    });
  }

  /// La sucursal se autocompleta: la del selector de la barra superior, o la
  /// unica que haya (pliego §3, paso 1). Preguntar por algo que sólo tiene una
  /// respuesta posible es un paso de mas en el patio de un almacen.
  void _autocompletarSucursal(List<Sucursal> sucursales) {
    if (_sucursalId != null || sucursales.isEmpty) return;
    final deLaBarra = ref.read(sucursalMiradaProvider);
    final elegida =
        sucursales.where((s) => s.id == deLaBarra).firstOrNull ??
        (sucursales.length == 1 ? sucursales.single : null);
    if (elegida == null) return;
    _sucursalId = elegida.id;
    _filtros = _filtros.copiarCon(sucursalId: elegida.id);
  }

  void _cambiarSucursal(String id) => setState(() {
    _sucursalId = id.isEmpty ? null : id;
    // Cambiar de sucursal invalida la salida: un almacen de Holguin no es
    // punto de partida de una ruta de Camaguey. Y lo elegido tampoco vale,
    // porque eran pedidos de la otra.
    _salida = null;
    _elegidos.clear();
    _filtros = FiltrosDisponibles(sucursalId: _sucursalId);
  });

  @override
  Widget build(BuildContext context) {
    final sucursales =
        ref.watch(sucursalesProvider).value ?? const <Sucursal>[];
    _autocompletarSucursal(sucursales);

    final sucursal = sucursales.where((s) => s.id == _sucursalId).firstOrNull;
    final codigo = sucursal?.externalId;
    final almacenes = codigo == null
        ? const <Almacen>[]
        : (ref.watch(almacenesProvider(codigo)).value ?? const <Almacen>[]);
    final conUbicacion = [
      for (final a in almacenes)
        if (a.lat != null && a.lng != null) a,
    ];
    // El principal viene primero de la consulta, asi que el primero es el que
    // toca por defecto.
    _salida ??= conUbicacion.firstOrNull;

    // «Si la sucursal y la salida ya vienen resueltas, arranca directamente en
    // el paso 3» (pliego §3).
    if (!_arranqueResuelto && _sucursalId != null && _salida != null) {
      _arranqueResuelto = true;
      _paso = 3;
    }

    final lista = ref.watch(disponiblesProvider(_filtros));
    final disponibles = lista.value ?? const <Pedido>[];
    final peso = _peso;
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
            onPressed: puedeGenerar ? _generar : null,
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
            if (_paso == 2) _pasoSalida(conUbicacion),
            if (_paso == 3) _pasoVehiculo(),
            if (_paso == 4)
              _pasoPedidos(
                sucursales: sucursales,
                disponibles: disponibles,
                cargando: lista.isLoading,
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
        alElegir: _cambiarSucursal,
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

  Widget _pasoSalida(List<Almacen> conUbicacion) {
    if (conUbicacion.isEmpty) {
      return const EstadoVacio(AsistenteNuevaRuta.sinAlmacenes);
    }

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
        // El mapa de 220 px del pliego queda PENDIENTE: `lib/mapas/` (PLAN.md
        // §4.2) todavia no existe y el detalle de la ruta tampoco lo pinta. Se
        // dicen las coordenadas, que es el dato que el mapa ensenaria, en vez de
        // dejar un hueco gris que parece que algo se rompio.
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

  /// Los filtros de la lista de elegibles (pliego §3, paso 4).
  ///
  /// **El cuadre con la factura NO esta aqui a proposito**: siempre es `cuadra`,
  /// que es lo unico que el armado acepta. Ofrecer lo que luego se rechaza es
  /// fabricar rechazos tardios.
  Widget _barraDeFiltros(List<Sucursal> sucursales) {
    final opciones =
        ref.watch(opcionesDeDisponiblesProvider(_filtros)).value ??
        OpcionesDeDisponibles.vacias;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _buscador,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'Buscar pedido...',
            ),
            onChanged: _buscar,
          ),
        ),
        Selector<String>(
          titulo: 'Sucursal de la ruta',
          valor: _sucursalId ?? '',
          opciones: [
            const OpcionSelector('', 'Elige la sucursal…'),
            for (final s in sucursales)
              OpcionSelector(s.id, s.name, nota: s.externalId),
          ],
          alElegir: _cambiarSucursal,
        ),
        OutlinedButton(
          onPressed: () async {
            final hoy = DateTime.now();
            final dia = await showDatePicker(
              context: context,
              firstDate: hoy.subtract(const Duration(days: 365)),
              lastDate: hoy.add(const Duration(days: 365)),
              initialDate: _filtros.dia ?? hoy,
            );
            if (dia != null) _ponerFiltros(_filtros.copiarCon(dia: dia));
          },
          child: Text(
            'Día de los pedidos: ${_filtros.dia == null ? 'todos' : fechaCorta(_filtros.dia)}',
          ),
        ),
        // «Todos los días» es un boton propio y no la opcion vacia del anterior:
        // un selector de fecha no tiene forma de decir «ninguna».
        OutlinedButton(
          onPressed: _filtros.dia == null
              ? null
              : () => _ponerFiltros(_filtros.copiarCon(limpiarDia: true)),
          child: const Text('Todos los días'),
        ),
        Selector<String>(
          titulo: 'Vendedor del pedido',
          valor: _filtros.vendedor,
          // Con buscador SIEMPRE: en una sucursal grande son decenas de
          // vendedores y bajar la lista a mano no es buscar.
          buscadorSiempre: true,
          opciones: [
            const OpcionSelector('', 'Todos los vendedores'),
            for (final v in opciones.vendedores) OpcionSelector(v, v),
          ],
          alElegir: (v) => _ponerFiltros(_filtros.copiarCon(vendedor: v)),
        ),
        Selector<String>(
          titulo: 'Municipio del cliente',
          valor: _filtros.municipio,
          opciones: [
            const OpcionSelector('', 'Todos los municipios'),
            for (final m in opciones.municipios) OpcionSelector(m, m),
          ],
          alElegir: (m) => _ponerFiltros(_filtros.copiarCon(municipio: m)),
        ),
        SizedBox(
          width: 110,
          child: TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'km máx.',
            ),
            onSubmitted: (texto) => _ponerFiltros(
              _filtros.copiarCon(
                kmMax: double.tryParse(texto.trim()),
                limpiarKmMax: texto.trim().isEmpty,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 110,
          child: TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'costo mín.',
            ),
            onSubmitted: (texto) => _ponerFiltros(
              _filtros.copiarCon(
                costoMin: double.tryParse(texto.trim()),
                limpiarCostoMin: texto.trim().isEmpty,
              ),
            ),
          ),
        ),
        Selector<EstadoDelPedido>(
          titulo: 'Estado del pedido en PEDIDO',
          valor: _filtros.estado,
          opciones: [
            for (final e in EstadoDelPedido.values)
              OpcionSelector(e, e.etiqueta),
          ],
          alElegir: (e) => _ponerFiltros(_filtros.copiarCon(estado: e)),
        ),
        Selector<DomicilioFiltro>(
          titulo: 'Si el pedido lleva entrega a domicilio',
          valor: _filtros.domicilio,
          opciones: [
            for (final d in DomicilioFiltro.values)
              OpcionSelector(d, d.etiqueta),
          ],
          alElegir: (d) => _ponerFiltros(_filtros.copiarCon(domicilio: d)),
        ),
        Selector<CotizadoDelDomicilio>(
          titulo: 'Si Entrega ya le puso costo de domicilio',
          valor: _filtros.cotizado,
          opciones: [
            for (final c in CotizadoDelDomicilio.values)
              OpcionSelector(c, c.etiqueta),
          ],
          alElegir: (c) => _ponerFiltros(_filtros.copiarCon(cotizado: c)),
        ),
        TextButton(
          onPressed: () {
            _buscador.clear();
            // **Vuelve a `domicilio = 1`**, no a «sin nada»: una ruta se arma
            // con lo que hay que llevar a casa, y ese es el arranque del pliego.
            _ponerFiltros(_filtros.limpios());
          },
          child: const Text('Limpiar'),
        ),
      ],
    );
  }

  Widget _pasoPedidos({
    required List<Sucursal> sucursales,
    required List<Pedido> disponibles,
    required bool cargando,
    required double peso,
    required double? capacidad,
  }) {
    final renglones =
        ref.watch(renglonesDeDisponiblesProvider(_filtros)).value ??
        const <String, List<RenglonConPeso>>{};

    final visibles = {for (final p in disponibles) p.id};
    // Los elegidos que ya no salen con los filtros de ahora. Siguen contando: su
    // peso va en el camion igual.
    final fueraDeLaLista = _elegidos.keys
        .where((id) => !visibles.contains(id))
        .length;

    final porcentaje = capacidad == null || capacidad == 0
        ? 0.0
        : (peso / capacidad) * 100;
    final color = porcentaje >= 100
        ? Colores.rojo
        : (porcentaje >= 80 ? Colores.ambar : Colores.verde);

    final columnaLista = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pedidos de cliente (${disponibles.length})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _barraDeFiltros(sucursales),
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
        if (cargando && disponibles.isEmpty)
          const Text(AsistenteNuevaRuta.cargandoPedidos)
        else if (disponibles.isEmpty)
          const EstadoVacio(AsistenteNuevaRuta.sinPedidos)
        else
          for (final pedido in disponibles)
            _FilaDisponible(
              pedido: pedido,
              renglones: renglones[pedido.id] ?? const <RenglonConPeso>[],
              marcado: _elegidos.containsKey(pedido.id),
              // Lo que no cabe se deshabilita con el motivo a la vista, no se
              // esconde: esconderlo haria pensar que el pedido no existe.
              cabe:
                  capacidad == null ||
                  _elegidos.containsKey(pedido.id) ||
                  peso + pedido.weight <= capacidad,
              alMarcar: () => setState(() {
                if (_elegidos.remove(pedido.id) == null) {
                  _elegidos[pedido.id] = pedido;
                }
              }),
            ),
        const SizedBox(height: 8),
        Text(
          '${_elegidos.length} pedidos seleccionados'
          '${fueraDeLaLista == 0 ? '' : ' ($fueraDeLaLista de otro día o filtro, siguen contando)'}'
          '${capacidad == null ? '' : '  ·  ${peso.toStringAsFixed(1)} / '
                    '${capacidad.toStringAsFixed(0)} kg'}',
        ),
        if (capacidad != null && peso > capacidad)
          Text(
            'Peso (${peso.toStringAsFixed(1)} kg) supera capacidad del '
            'vehículo (${capacidad.toStringAsFixed(0)} kg)',
            style: const TextStyle(color: Colores.rojo),
          ),
      ],
    );

    final columnaPreDespacho = _PreDespachoLateral(
      elegidos: _elegidos.keys.toList(),
      pesoKg: peso,
      capacidad: capacidad,
      sucursal: sucursales.where((s) => s.id == _sucursalId).firstOrNull?.name,
      vehiculo: _vehiculo?.name,
      dia: _filtros.dia,
    );

    // Dos columnas en escritorio —lista a la izquierda, pre-despacho a la
    // derecha— y una sola en movil, donde no caben las dos sin partir palabras.
    return LayoutBuilder(
      builder: (contexto, medidas) {
        if (medidas.maxWidth < anchoEscritorio) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [columnaLista, const Divider(), columnaPreDespacho],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: columnaLista),
            const SizedBox(width: 16),
            Expanded(child: columnaPreDespacho),
          ],
        );
      },
    );
  }

  Future<void> _generar() async {
    setState(() => _generando = true);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final navegador = Navigator.of(context);
    try {
      final rutaId = await ref
          .read(accionesDeRutaProvider)
          .armar(
            vehiculoId: _vehiculoId,
            pedidoIds: _elegidos.keys.toList(),
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
    required this.renglones,
    required this.marcado,
    required this.cabe,
    required this.alMarcar,
  });

  final Pedido pedido;
  final List<RenglonConPeso> renglones;
  final bool marcado;
  final bool cabe;
  final VoidCallback alMarcar;

  /// Los articulos, resumidos: el primero con sus empaques y `+n` por el resto,
  /// y la lista entera en el tooltip. Es el mismo resumen de la tabla de
  /// Pedidos, para que el mismo pedido se lea igual en las dos pantallas.
  String get _articulos {
    if (renglones.isEmpty) return '';
    final primero = renglones.first;
    final resto = renglones.length - 1;
    return '${primero.renglon.description} ×${cantidad(primero.empaques)}'
        '${resto > 0 ? '  +$resto' : ''}';
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: cabe
        ? [
            for (final r in renglones)
              '${r.renglon.description} ×${cantidad(r.empaques)}',
          ].join('\n')
        : 'No cabe en el camión',
    child: CheckboxListTile(
      dense: true,
      value: marcado,
      onChanged: cabe ? (_) => alMarcar() : null,
      title: Text(pedido.customerName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pedido.endAddress ?? pedido.address} · ${kg(pedido.weight)} · '
            // `usd` ya dice `sin cotizar` cuando no hay precio: un `$0.00`
            // seria «este domicilio es gratis», que es otra cosa.
            '${usd(pedido.pedidoCosto)}',
          ),
          if (_articulos.isNotEmpty)
            Text(
              _articulos,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colores.gris, fontSize: 12),
            ),
        ],
      ),
    ),
  );
}

/// El pre-despacho que se suma en vivo segun se van eligiendo pedidos.
class _PreDespachoLateral extends ConsumerWidget {
  const _PreDespachoLateral({
    required this.elegidos,
    required this.pesoKg,
    required this.capacidad,
    required this.sucursal,
    required this.vehiculo,
    required this.dia,
  });

  final List<String> elegidos;
  final double pesoKg;
  final double? capacidad;
  final String? sucursal;
  final String? vehiculo;
  final DateTime? dia;

  /// El dia tal y como lo escribe la hoja de Next: `AAAA-MM-DD`. Se compara
  /// caracter a caracter con la suya, asi que no pasa por `DateFormat` local.
  String? get _diaDeLaHoja => dia == null
      ? null
      : '${dia!.year.toString().padLeft(4, '0')}-'
            '${dia!.month.toString().padLeft(2, '0')}-'
            '${dia!.day.toString().padLeft(2, '0')}';

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
    if (totales == null) {
      return const Text(AsistenteNuevaRuta.cargandoPedidos);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Pre-despacho',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            OutlinedButton(
              onPressed: () => _verEImprimir(context, totales),
              child: const Text('Ver e imprimir'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // La tabla va dentro de su propio desplazamiento lateral: en un telefono
        // tres columnas con nombres de producto largos no caben, y lo que no
        // cabe tiene que poder alcanzarse, no recortarse.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Producto')),
              DataColumn(label: Text('Emp.')),
              DataColumn(label: Text('Uds.')),
            ],
            rows: [
              for (final linea in totales.lineas)
                DataRow(
                  cells: [
                    DataCell(Text(linea.producto)),
                    DataCell(Text(cantidad(linea.empaques))),
                    DataCell(Text(cantidad(linea.unidades))),
                  ],
                ),
            ],
          ),
        ),
        const Divider(),
        Text('Pedidos: ${elegidos.length}'),
        Text('Empaques: ${cantidad(totales.empaques)}'),
        Text('Unidades: ${cantidad(totales.unidades)}'),
        Text(
          'Peso: ${pesoKg.toStringAsFixed(1)} / '
          '${capacidad?.toStringAsFixed(0) ?? '—'} kg',
        ),
      ],
    );
  }

  /// La hoja con la que alguien baja al almacen. Se mira primero y se imprime
  /// desde la propia vista previa: es el orden que tenia la de Next y el que
  /// tiene sentido cuando el que saca la mercancia es otra persona.
  void _verEImprimir(BuildContext context, TotalesPreDespacho totales) {
    final hoja = papel.HojaPreDespacho(
      sucursal: sucursal ?? '',
      vehiculo: vehiculo ?? '',
      dia: _diaDeLaHoja,
      pedidos: elegidos.length,
      pesoKg: pesoKg,
      lineas: [
        for (final linea in totales.lineas)
          papel.LineaPreDespacho(
            producto: linea.producto,
            formatos: linea.empaques,
            unidades: linea.unidades,
            // En el papel el peso es un numero: un producto sin peso resuelto
            // suma cero kilos a la hoja, que es lo que pesa lo que no sabemos.
            pesoKg: linea.pesoKg ?? 0,
          ),
      ],
    );

    abrirCajon<void>(
      context,
      (_) => Cajon(
        titulo: 'Pre-despacho',
        subtitulo:
            '${elegidos.length} pedido(s) · '
            '${pesoKg.toStringAsFixed(1)} kg',
        ancho: AnchoCajon.xl,
        cuerpo: SizedBox(
          height: 640,
          child: VistaPreviaPdf(
            armar: (formato) => pdfPreDespacho(hoja, impresoEn: DateTime.now()),
            nombreDeFichero: 'pre-despacho.pdf',
          ),
        ),
      ),
    );
  }
}

/// El pre-despacho del asistente.
///
/// El argumento es la lista de ids **ordenada y unida por comas**, y no la lista
/// suelta, porque un `family` compara sus argumentos con `==` y dos `List` con el
/// mismo contenido no son iguales en Dart: con la lista cruda se crearia un
/// provider nuevo en cada repintado y la suma se reharia sin que nada hubiera
/// cambiado.
final preDespachoDeLoElegidoEnElAsistenteProvider =
    FutureProvider.family<TotalesPreDespacho, String>(
      (ref, clave) => ref
          .watch(consultasPedidosProvider)
          .preDespachoDe(clave.isEmpty ? const [] : clave.split(',')),
    );
