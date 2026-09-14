import 'package:flutter/material.dart';

import '../datos/almacen_api.dart';
import '../datos/coordenadas.dart';
import 'cajon.dart';

/// El editor de un almacen (cajon/modal `lg`). Pliego: `pantallas.md` §6.
///
/// Devuelve el almacen editado; quien compone la lista de la sucursal y la manda
/// a Accesos es la pantalla. La razon es la regla del principal: para desmarcar
/// a los demas hay que ver la lista entera, y este widget sólo ve uno.
class EditorAlmacen extends StatefulWidget {
  const EditorAlmacen({
    required this.sucursal,
    required this.guardando,
    required this.alGuardar,
    this.almacen,
    this.alQuitar,
    super.key,
  });

  /// `null` = almacen nuevo.
  final AlmacenDeAccesos? almacen;

  /// El nombre de la sucursal, que va de subtitulo.
  final String sucursal;
  final bool guardando;
  final ValueChanged<AlmacenDeAccesos> alGuardar;

  /// `null` en uno nuevo: no se puede quitar lo que aun no existe.
  final VoidCallback? alQuitar;

  @override
  State<EditorAlmacen> createState() => _EditorAlmacenState();
}

class _EditorAlmacenState extends State<EditorAlmacen> {
  late final TextEditingController _nombre;
  late final TextEditingController _direccion;
  late final TextEditingController _punto;

  late bool _principal;
  late bool _activo;

  @override
  void initState() {
    super.initState();
    final a = widget.almacen;
    _nombre = TextEditingController(text: a?.nombre ?? '');
    _direccion = TextEditingController(text: a?.direccion ?? '');
    _punto = TextEditingController(
      text: a == null || a.sinPunto ? '' : '${a.latitud}, ${a.longitud}',
    );
    _principal = a?.principal ?? false;
    _activo = a?.activo ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _direccion.dispose();
    _punto.dispose();
    super.dispose();
  }

  PuntoEnElMapa? get _coordenadas => _punto.text.trim().isEmpty
      ? null
      : leerCoordenadas(_punto.text);

  bool get _puntoMalEscrito =>
      _punto.text.trim().isNotEmpty && _coordenadas == null;

  bool get _leFaltaElNombre => _nombre.text.trim().isEmpty;

  Future<void> _confirmarQuitar() async {
    final nombre = widget.almacen?.titulo ?? '';
    final seguro = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        content: Text(
          '¿Quitar «$nombre»? Deja de poder medirse desde ahí.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (seguro ?? false) widget.alQuitar?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final punto = _coordenadas;

    return MarcoCajon(
      titulo: widget.almacen == null
          ? 'Nuevo almacén'
          : widget.almacen!.titulo,
      subtitulo: widget.sucursal,
      cuerpo: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nombre,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Nombre del almacén',
              border: OutlineInputBorder(),
            ),
          ),
          if (_leFaltaElNombre)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Le falta el nombre.',
                style: tema.textTheme.bodySmall?.copyWith(
                  color: tema.colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Tooltip(
                message: 'Desde éste se mide cuando nadie dice cuál',
                child: FilterChip(
                  selected: _principal,
                  label: const Text('Principal'),
                  avatar: Icon(
                    _principal ? Icons.star : Icons.star_border,
                    size: 18,
                  ),
                  onSelected: (v) => setState(() => _principal = v),
                ),
              ),
              FilterChip(
                selected: _activo,
                label: Text(_activo ? 'Activo' : 'Inactivo'),
                onSelected: (v) => setState(() => _activo = v),
              ),
              if (widget.alQuitar != null)
                IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.guardando ? null : _confirmarQuitar,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Dónde está', style: tema.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _direccion,
            decoration: const InputDecoration(
              labelText: 'Dirección',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _punto,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Coordenadas',
              hintText: '19.83, -75.82',
              border: const OutlineInputBorder(),
              errorText: _puntoMalEscrito
                  ? 'No se entiende. Escríbelo como «19.83, -75.82».'
                  : null,
            ),
          ),
          if (punto == null && !_puntoMalEscrito) ...[
            const SizedBox(height: 8),
            // El aviso del pliego. Un almacen sin punto entra igual —a veces no
            // se sabe todavia— pero desde el no se cotiza, y eso tiene que
            // estar dicho antes de guardar, no descubrirse al cotizar.
            Text(
              'Sin coordenadas: desde éste no se puede medir el domicilio.',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ],
      ),
      pie: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: widget.guardando
                ? null
                : () => Navigator.of(context).maybePop(),
            child: const Text('Cerrar'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _leFaltaElNombre || _puntoMalEscrito || widget.guardando
                ? null
                : () => widget.alGuardar(
                    AlmacenDeAccesos(
                      id: widget.almacen?.id,
                      nombre: _nombre.text.trim(),
                      direccion: _direccion.text.trim().isEmpty
                          ? null
                          : _direccion.text.trim(),
                      latitud: punto?.lat,
                      longitud: punto?.lng,
                      principal: _principal,
                      activo: _activo,
                    ),
                  ),
            child: Text(widget.guardando ? 'Guardando…' : 'Guardar'),
          ),
        ],
      ),
    );
  }
}
