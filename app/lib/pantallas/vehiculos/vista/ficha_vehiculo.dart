import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';

import 'package:flutter/services.dart';

import '../../../diseno/cajon.dart';
import '../datos/costo_km.dart';
import '../datos/vehiculo_api.dart';

/// La ficha de vehiculo (cajon/modal `lg`). Pliego: `pantallas.md` §5.
///
/// Lo que se devuelve al cerrar son los `DatosVehiculo`; quien guarda es la
/// pantalla. Asi este widget no sabe nada de red y el eje de la prueba a mano
/// —«abrir una ficha y guardar sin tocar nada la deja igual»— se puede
/// comprobar mirando lo que sale de aqui.
class FichaVehiculo extends StatefulWidget {
  const FichaVehiculo({
    required this.tipos,
    required this.cupRate,
    required this.guardando,
    required this.alGuardar,
    this.vehiculo,
    this.alCrearTipo,
    super.key,
  });

  /// `null` = ficha vacia.
  final VehiculoDeLaApi? vehiculo;
  final List<TipoDeVehiculo> tipos;
  final double cupRate;
  final bool guardando;
  final ValueChanged<DatosVehiculo> alGuardar;

  /// GUARDA el tipo nuevo en el catalogo (`PUT /api/settings`) y contesta si se
  /// aplico. Quien guarda es la pantalla, como con el vehiculo.
  ///
  /// Sin esto el tipo nuevo vivia sólo en el `setState` de esta ficha y se
  /// perdia al cerrarla, **sin un solo error** —lo mismo que ya paso en
  /// delivery y esta contado en `docs/esquema-cambios.md`—. `null` sólo en las
  /// pruebas que no miran esto.
  final Future<bool> Function(TipoDeVehiculo)? alCrearTipo;

  @override
  State<FichaVehiculo> createState() => _FichaVehiculoState();
}

class _FichaVehiculoState extends State<FichaVehiculo> {
  late final TextEditingController _nombre;
  late final TextEditingController _placa;
  late final TextEditingController _capacidad;
  late final TextEditingController _costo;
  late final TextEditingController _notas;

  late String _tipo;
  late String _estado;
  late bool _domicilio;

  bool _creandoTipo = false;
  bool _guardandoTipo = false;
  final _tipoNuevo = TextEditingController();
  final _tipoCosto = TextEditingController();

  bool _ayudanteAbierto = false;
  final _cobro = TextEditingController();
  final _km = TextEditingController();

  @override
  void initState() {
    super.initState();
    final v = widget.vehiculo;
    _nombre = TextEditingController(text: v?.nombre ?? '');
    _placa = TextEditingController(text: v?.placa ?? '');
    // Los defectos exactos del pliego: `truck`, 1000 kg, `available`.
    _capacidad = TextEditingController(
      text: '${(v?.capacidad ?? 1000).toInt()}',
    );
    _costo = TextEditingController(
      text: v?.costoKmUsd == null ? '' : '${v!.costoKmUsd}',
    );
    _notas = TextEditingController(text: v?.notas ?? '');
    _tipo = v?.tipo ?? 'truck';
    _estado = v?.estado ?? 'available';
    _domicilio = v?.usarParaDomicilio ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _placa,
      _capacidad,
      _costo,
      _notas,
      _tipoNuevo,
      _tipoCosto,
      _cobro,
      _km,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _esNuevo => widget.vehiculo == null;

  void _elegirTipo(String? nombre) {
    if (nombre == null) return;
    setState(() {
      _tipo = nombre;
      // Al elegir un tipo se HEREDA su costo/km, y queda editable: el tipo es
      // el punto de partida, no una atadura.
      final tipo = widget.tipos.where((t) => t.nombre == nombre).firstOrNull;
      if (tipo?.costoKmUsd != null) _costo.text = '${tipo!.costoKmUsd}';
    });
  }

  /// El ayudante **rellena el campo**, no propone.
  ///
  /// Antes dejaba el numero a un lado y pedia pulsar `Usar este costo`: un paso
  /// de mas que la de Next no tiene y que se olvida, y entonces el vehiculo se
  /// guarda sin costo por km aunque el numero estuviera en pantalla. Y va con
  /// **2 decimales**, los del Excel del pliego; los 4 de antes eran una
  /// precision que nadie tecleó y que no cabe en la ficha.
  void _calcular() {
    final valor = CostoPorKm.calcular(
      cobroCup: double.tryParse(_cobro.text.trim()),
      km: double.tryParse(_km.text.trim()),
      tasa: widget.cupRate,
    );
    // Sin un dato no se toca el campo: dejarlo en blanco borraria un costo que
    // alguien habia puesto a mano.
    if (valor == null) return;
    setState(() => _costo.text = valor.toStringAsFixed(2));
  }

  Future<void> _crearTipoNuevo() async {
    final nombre = _tipoNuevo.text.trim();
    if (nombre.isEmpty) return;
    final costo = double.tryParse(_tipoCosto.text.trim());
    final guardar = widget.alCrearTipo;

    if (guardar != null) {
      setState(() => _guardandoTipo = true);
      final bien = await guardar(
        TipoDeVehiculo(nombre: nombre, costoKmUsd: costo),
      );
      if (!mounted) return;
      setState(() => _guardandoTipo = false);
      // No se aplico: el aviso ya lo pinta la pantalla. Lo escrito se queda
      // donde estaba para poder reintentar; cerrar el formulario aqui seria
      // dar por hecho que el tipo existe.
      if (!bien) return;
    }

    setState(() {
      _tipo = nombre;
      if (costo != null) _costo.text = '$costo';
      _creandoTipo = false;
      _tipoNuevo.clear();
      _tipoCosto.clear();
    });
  }

  void _guardar() => widget.alGuardar(
    DatosVehiculo(
      nombre: _nombre.text.trim(),
      tipo: _tipo,
      placa: _placa.text.trim().isEmpty
          ? null
          : _placa.text.trim().toUpperCase(),
      capacidad: double.tryParse(_capacidad.text.trim()) ?? 1000,
      estado: _estado,
      notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
      costoKmUsd: double.tryParse(_costo.text.trim()),
      usarParaDomicilio: _domicilio,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Cajon(
      titulo: _esNuevo ? 'Nuevo Vehículo' : 'Editar Vehículo',
      pie: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: widget.guardando
                ? null
                : () => Navigator.of(context).maybePop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            // Sin nombre no se guarda: el servidor contestaria
            // `Vehicle name is required`, en ingles, y eso no se le ensena a
            // nadie pudiendo evitarlo aqui.
            onPressed: _nombre.text.trim().isEmpty || widget.guardando
                ? null
                : _guardar,
            child: Text(_esNuevo ? 'Agregar Vehículo' : 'Actualizar'),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nombre,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nombre del Vehículo *',
                hintText: 'Ej: Camión #1, Furgoneta Azul',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _desplegableDeTipo(),
            if (_creandoTipo) _crearTipoEnLinea(),
            const SizedBox(height: 12),
            TextField(
              controller: _placa,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_AMayusculas()],
              decoration: const InputDecoration(
                labelText: 'Placa (opcional)',
                hintText: 'ABC-1234',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacidad,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacidad Máx. (kg)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _estado,
              decoration: const InputDecoration(
                labelText: 'Estado del vehículo',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'available', child: Text('Disponible')),
                DropdownMenuItem(value: 'in_route', child: Text('En ruta')),
                DropdownMenuItem(
                  value: 'maintenance',
                  child: Text('En mantenimiento'),
                ),
              ],
              onChanged: (v) => setState(() => _estado = v ?? 'available'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costo,
              // Para que el eco del ayudante siga a lo que se teclea aqui.
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Costo por km (USD)',
                hintText: '1.65',
                border: OutlineInputBorder(),
              ),
            ),
            _ayudante(tema),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _domicilio,
              onChanged: (v) => setState(() => _domicilio = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Usar este vehículo para calcular el domicilio',
              ),
              subtitle: const Text('Solo un vehículo por TIPO.'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notas,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Información relevante del vehículo...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(Aire.md),
              decoration: BoxDecoration(
                color: Colores.enCursoFondo,
                border: Border.all(
                  color: Colores.primario.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(Radios.md),
              ),
              child: const Text(
                'Las tarifas de precios se configuran globalmente en '
                'Configuración.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _crearTipo = '__crear__';

  /// El desplegable de `Tipo`.
  ///
  /// **Un tipo heredado se pinta igual aunque no este en ajustes.** Antes el
  /// desplegable se abria EN BLANCO en cuanto el vehiculo traia un tipo que el
  /// catalogo no tenia —`truck`, el de todos los vehiculos nuevos, es
  /// justamente ese caso—, y en blanco parece que el vehiculo no tiene tipo
  /// cuando si lo tiene. Guardar desde ahi no lo borraba, pero nadie podia
  /// saberlo mirando.
  Widget _desplegableDeTipo() {
    final enElCatalogo = widget.tipos.any((t) => t.nombre == _tipo);
    final heredado = !enElCatalogo && _tipo.trim().isNotEmpty;

    return DropdownButtonFormField<String>(
      initialValue: _creandoTipo
          ? _crearTipo
          : (enElCatalogo || heredado ? _tipo : null),
      decoration: const InputDecoration(
        labelText: 'Tipo',
        border: OutlineInputBorder(),
      ),
      items: [
        // El heredado va primero y con su nombre a secas: no tiene costo en el
        // catalogo porque no esta en el catalogo.
        if (heredado) DropdownMenuItem(value: _tipo, child: Text(_tipo)),
        for (final t in widget.tipos)
          DropdownMenuItem(
            value: t.nombre,
            child: Text(
              t.costoKmUsd == null
                  ? t.nombre
                  : '${t.nombre} · \$${t.costoKmUsd}/km',
            ),
          ),
        if (widget.tipos.isEmpty && !heredado)
          const DropdownMenuItem(
            enabled: false,
            child: Text('Sin tipos configurados'),
          ),
        const DropdownMenuItem(
          value: _crearTipo,
          child: Text('+ Crear tipo nuevo…'),
        ),
      ],
      onChanged: (valor) {
        if (valor == _crearTipo) {
          setState(() => _creandoTipo = true);
          return;
        }
        setState(() => _creandoTipo = false);
        _elegirTipo(valor);
      },
    );
  }

  Widget _crearTipoEnLinea() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _tipoNuevo,
          decoration: const InputDecoration(
            labelText: 'Nombre del tipo',
            hintText: 'Camión',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tipoCosto,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Costo por km (USD)',
            hintText: '1.65',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _guardandoTipo
                  ? null
                  : () => setState(() {
                      _creandoTipo = false;
                      _tipoNuevo.clear();
                      _tipoCosto.clear();
                    }),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _guardandoTipo ? null : _crearTipoNuevo,
              child: Text(_guardandoTipo ? '...' : 'Crear tipo'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _ayudante(ThemeData tema) => Theme(
    data: tema.copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: _ayudanteAbierto,
      onExpansionChanged: (abierto) =>
          setState(() => _ayudanteAbierto = abierto),
      title: const Text('¿No sabes el costo por km?'),
      children: [
        TextField(
          controller: _cobro,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'El camionero cobra (CUP)',
            hintText: '180000',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _km,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'hasta ___ km (ida)',
            hintText: '72',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: _calcular,
              child: const Text('Calcular'),
            ),
            const SizedBox(width: 12),
            // El eco de lo que ya esta EN EL CAMPO, como la de Next: no es una
            // propuesta a la espera de que alguien la acepte.
            if (_costo.text.trim().isNotEmpty)
              Expanded(child: Text('= \$${_costo.text.trim()}/km')),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Tipo de cambio: ${widget.cupRate.toStringAsFixed(0)} CUP/USD. '
            'Se divide entre 2×km (ida y vuelta).',
            style: tema.textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

/// La placa se escribe en mayusculas mientras se teclea, como la de Next.
class _AMayusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue viejo,
    TextEditingValue nuevo,
  ) => nuevo.copyWith(text: nuevo.text.toUpperCase());
}
