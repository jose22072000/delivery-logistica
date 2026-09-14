// El detalle de la ruta elegida: la columna derecha.
//
// Todo sale de la base local, asi que sin red se ve entero: paradas, carga total,
// km, peso, importe y duracion. Lo unico que no se puede hacer sin conexion es
// abrir el enlace de Google Maps, y eso se dice con el motivo a la vista —nunca
// en silencio.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';
import 'cierre_de_ruta.dart';

/// Google admite 25 paradas en un enlace. Mas alla se recortan y se dice
/// cuantas quedan fuera.
const topeDeParadasEnElEnlace = 25;

class DetalleDeRuta extends ConsumerWidget {
  const DetalleDeRuta({required this.rutaId, super.key});

  final String rutaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruta = ref.watch(rutaConTodoProvider(rutaId)).value;
    if (ruta == null) return const EstadoVacio('Cargando...');

    final paradas =
        ref.watch(paradasDeRutaProvider(rutaId)).value ?? ruta.paradas;
    final conTodo = RutaConTodo(
      ruta: ruta.ruta,
      paradas: paradas,
      vehiculo: ruta.vehiculo,
      sucursal: ruta.sucursal,
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _Cabecera(ruta: conTodo),
        const SizedBox(height: 8),
        _Acciones(ruta: conTodo),
        const SizedBox(height: 12),
        _LineaDeDatos(ruta: conTodo),
        const SizedBox(height: 12),
        _Compartir(ruta: conTodo),
        const SizedBox(height: 12),
        _Paradas(ruta: conTodo),
      ],
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.ruta});

  final RutaConTodo ruta;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ruta.ruta.routeCode ?? ruta.ruta.id,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (ruta.ruta.name != null) Text(ruta.ruta.name!),
          ],
        ),
      ),
      if (ruta.sucursal != null)
        Insignia(ruta.sucursal!.name, color: Colores.gris),
    ],
  );
}

class _Acciones extends ConsumerWidget {
  const _Acciones({required this.ruta});

  final RutaConTodo ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acciones = ref.read(accionesDeRutaProvider);
    final estado = ruta.ruta.status;

    Future<void> hacer(Future<void> Function() que) async {
      final mensajero = ScaffoldMessenger.maybeOf(context);
      try {
        await que();
      } on RechazoLocal catch (fallo) {
        mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton(
          onPressed: () => _verParadas(context, ruta),
          child: Text('Ver paradas (${ruta.paradas.length})'),
        ),
        if (estado == EstadoRuta.planificada)
          FilledButton(
            onPressed: () => hacer(() => acciones.iniciar(ruta.ruta.id)),
            child: const Text('Iniciar ruta'),
          ),
        // El `Cierre` esta disponible en `in_progress` **y** en `completed`:
        // el camion vuelve al patio despues de que alguien haya dado la ruta
        // por completada, y ahi es cuando se cuadra lo que baja.
        if (estado == EstadoRuta.enCurso || estado == EstadoRuta.completada)
          OutlinedButton(
            onPressed: () => abrirCajon<void>(
              context,
              (_) => CierreDeRuta(rutaId: ruta.ruta.id),
            ),
            child: Text(
              ruta.sinMarcar > 0 ? 'Cierre (${ruta.sinMarcar})' : 'Cierre',
            ),
          ),
        if (estado == EstadoRuta.enCurso)
          FilledButton(
            onPressed: () => hacer(() => acciones.completar(ruta.ruta.id)),
            child: const Text('Marcar como completada'),
          ),
        if (ruta.sobrepeso)
          Insignia(
            'Peso total (${ruta.pesoTotal.toStringAsFixed(1)} kg) supera '
            'capacidad (${ruta.vehiculo!.capacity.toStringAsFixed(0)} kg)',
            color: Colores.ambar,
          ),
      ],
    );
  }

  void _verParadas(BuildContext context, RutaConTodo ruta) {
    abrirCajon<void>(
      context,
      (_) => Cajon(
        titulo: 'Paradas y precio por cliente (${ruta.paradas.length})',
        subtitulo: ruta.ruta.routeCode ?? ruta.ruta.id,
        cuerpo: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < ruta.paradas.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${ruta.paradas[i].stopOrder ?? i + 1}. '
                    '${ruta.paradas[i].customerName} — '
                    '${ruta.paradas[i].endAddress ?? ruta.paradas[i].address} · '
                    '${kg(ruta.paradas[i].weight)} · '
                    '${km(ruta.paradas[i].segmentKm)} desde partida · '
                    '${usd(ruta.paradas[i].pedidoCosto)}',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineaDeDatos extends StatelessWidget {
  const _LineaDeDatos({required this.ruta});

  final RutaConTodo ruta;

  @override
  Widget build(BuildContext context) {
    final r = ruta.ruta;
    final estado = switch (r.status) {
      EstadoRuta.planificada => 'Planificada',
      EstadoRuta.enCurso => 'En curso',
      EstadoRuta.completada => 'Completada',
      _ => r.status,
    };
    return Text(
      '$estado · ${r.totalDistance.toStringAsFixed(1)} km (incl. regreso) · '
      '${kg(r.totalWeight)} · ${usd(r.totalPrice)} · '
      '${ruta.vehiculo?.name ?? '—'}'
      '${ruta.vehiculo?.plate == null ? '' : ' · ${ruta.vehiculo!.plate}'} · '
      '${fechaCorta(r.deliveryDate)} · '
      'Carga total: ${ruta.paradas.length} · '
      '${duracion(r.startedAt, r.finishedAt)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

/// El enlace de Google Maps: origen = almacen, paradas en orden y **destino = el
/// mismo almacen**, porque el camion vuelve.
String enlaceDeGoogleMaps(RutaConTodo ruta) {
  final origen = '${ruta.ruta.originLat},${ruta.ruta.originLng}';
  final puntos = [
    for (final parada in ruta.paradas.take(topeDeParadasEnElEnlace))
      if (parada.endLat != null && parada.endLng != null)
        '${parada.endLat},${parada.endLng}',
  ];
  return 'https://www.google.com/maps/dir/?api=1'
      '&origin=$origen'
      '&destination=$origen'
      '&waypoints=${puntos.join('|')}'
      '&travelmode=driving&dir_action=navigate';
}

class _Compartir extends StatefulWidget {
  const _Compartir({required this.ruta});

  final RutaConTodo ruta;

  @override
  State<_Compartir> createState() => _CompartirState();
}

class _CompartirState extends State<_Compartir> {
  bool _copiado = false;

  @override
  Widget build(BuildContext context) {
    final sobran = widget.ruta.paradas.length - topeDeParadasEnElEnlace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // `Abrir en Google Maps` necesita `url_launcher`, que hoy no esta en
            // el `pubspec.yaml` y anadirlo es tocar fuera de esta pantalla. Se
            // deja el enlace copiable, que hace el mismo trabajo y ademas
            // funciona para mandarselo al chofer por WhatsApp.
            OutlinedButton(
              onPressed: widget.ruta.paradas.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: enlaceDeGoogleMaps(widget.ruta)),
                      );
                      if (!mounted) return;
                      setState(() => _copiado = true);
                      await Future<void>.delayed(
                        const Duration(milliseconds: 2500),
                      );
                      if (mounted) setState(() => _copiado = false);
                    },
              child: Text(_copiado ? 'copiado' : 'copiar enlace'),
            ),
            if (sobran > 0)
              Text(
                '(Google admite 25 paradas: $sobran quedan fuera del enlace)',
                style: const TextStyle(color: Colores.gris),
              ),
          ],
        ),
        if (widget.ruta.ruta.originLat == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Sin coordenadas GPS para esta ruta'),
          ),
      ],
    );
  }
}

class _Paradas extends ConsumerWidget {
  const _Paradas({required this.ruta});

  final RutaConTodo ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renglones =
        ref.watch(renglonesDeParadasProvider(ruta.ruta.id)).value ??
        const <String, List<RenglonConPeso>>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Carga total',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entrada in _cargaTotal(renglones).entries)
              Insignia(
                '${entrada.key} ×${cantidad(entrada.value)}',
                color: Colores.azul,
              ),
          ],
        ),
      ],
    );
  }

  Map<String, double> _cargaTotal(Map<String, List<RenglonConPeso>> renglones) {
    final total = <String, double>{};
    for (final parada in ruta.paradas) {
      for (final r in renglones[parada.id] ?? const <RenglonConPeso>[]) {
        final nombre = r.renglon.description.trim();
        if (nombre.isEmpty) continue;
        total[nombre] = (total[nombre] ?? 0) + r.empaques;
      }
    }
    return total;
  }
}
