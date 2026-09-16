// La columna izquierda: filtros y lista de rutas.
//
// Los filtros se aplican EN EL CLIENTE sobre las rutas ya traidas, como en la de
// Next, y las rutas ya traidas son las de la base local. Resultado: sin conexion
// se filtra y se pagina igual que con ella.

import 'package:flutter/material.dart';

import '../../../diseno/tema.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';

class ListaDeRutas extends ConsumerWidget {
  const ListaDeRutas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pestana = ref.watch(pestanaRutasProvider);
    final rutas = ref.watch(rutasDeLaPestanaProvider);
    final pagina = ref.watch(paginaRutasProvider);
    final descargadas = ref.watch(rutasDescargadasProvider).value;
    final vehiculos = {
      for (final v in ref.watch(vehiculosProvider).value ?? const <Vehiculo>[])
        v.id: v,
    };
    final sucursales = {
      for (final s in ref.watch(sucursalesProvider).value ?? const <Sucursal>[])
        s.id: s,
    };

    // Una lista vacia de una coleccion que nunca se bajo NO es «no hay rutas».
    if (descargadas == false) {
      return const EstadoVacio(
        'Esta pantalla no se ha descargado todavía. Con conexión baja sola.',
      );
    }
    if (rutas.isEmpty) return EstadoVacio(pestana.vacio);

    final desde = (pagina - 1) * ConsultasRutas.porPagina;
    final visibles = rutas.skip(desde).take(ConsultasRutas.porPagina).toList();

    // Se agrupa por sucursal **sólo si en la pagina hay mas de una**: con una
    // sola, repetir su nombre en cada encabezado es ruido.
    final conVariasSucursales =
        visibles.map((r) => r.branchId).toSet().length > 1;

    return ListView(
      children: [
        for (final grupo in _agrupar(visibles, conVariasSucursales)) ...[
          if (grupo.titulo != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                '${sucursales[grupo.titulo]?.name ?? 'Sin sucursal'} '
                '(${sucursales[grupo.titulo]?.externalId ?? '—'}) · '
                '${grupo.rutas.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          for (final ruta in grupo.rutas)
            _TarjetaDeRuta(ruta: ruta, vehiculo: vehiculos[ruta.vehicleId]),
        ],
        Paginacion(
          pagina: pagina,
          porPagina: ConsultasRutas.porPagina,
          total: rutas.length,
          alIr: (n) => ref.read(paginaRutasProvider.notifier).ir(n),
        ),
      ],
    );
  }

  List<_Grupo> _agrupar(List<Ruta> rutas, bool agrupar) {
    if (!agrupar) return [_Grupo(null, rutas)];
    final porSucursal = <String?, List<Ruta>>{};
    for (final ruta in rutas) {
      porSucursal.putIfAbsent(ruta.branchId, () => <Ruta>[]).add(ruta);
    }
    return [
      for (final entrada in porSucursal.entries)
        _Grupo(entrada.key, entrada.value),
    ];
  }
}

class _Grupo {
  const _Grupo(this.titulo, this.rutas);

  final String? titulo;
  final List<Ruta> rutas;
}

class _TarjetaDeRuta extends ConsumerWidget {
  const _TarjetaDeRuta({required this.ruta, required this.vehiculo});

  final Ruta ruta;
  final Vehiculo? vehiculo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegida = ref.watch(rutaElegidaProvider) == ruta.id;
    final sobrepeso = vehiculo != null && ruta.totalWeight > vehiculo!.capacity;

    // La elegida se tine de primario y coge su borde: con el gris de antes, con
    // ocho rutas seguidas, no se veia cual estaba abierta a la derecha.
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      color: elegida ? Colores.primarioTenue : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
        side: BorderSide(
          color: elegida
              ? Colores.primario.withValues(alpha: 0.4)
              : Colores.linea,
        ),
      ),
      child: InkWell(
        onTap: () => ref.read(rutaElegidaProvider.notifier).elegir(ruta.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Insignia(ruta.routeCode ?? ruta.id, color: Colores.enCurso),
                  const SizedBox(width: 8),
                  Expanded(child: Text(ruta.name ?? '')),
                  Insignia(
                    switch (ruta.status) {
                      EstadoRuta.planificada => 'Planificada',
                      EstadoRuta.enCurso => 'En curso',
                      EstadoRuta.completada => 'Completada',
                      _ => ruta.status,
                    },
                    color: switch (ruta.status) {
                      EstadoRuta.planificada => Colores.ambar,
                      EstadoRuta.enCurso => Colores.enCurso,
                      EstadoRuta.completada => Colores.verde,
                      _ => Colores.gris,
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${ruta.totalDistance.toStringAsFixed(1)} km · '
                '${vehiculo == null ? '—' : '${vehiculo!.name}'
                          '${vehiculo!.plate == null ? '' : ' (${vehiculo!.plate})'}'} · '
                '${ruta.originAddress ?? '—'} · '
                '${fechaCorta(ruta.deliveryDate)} · ${usd(ruta.totalPrice)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (sobrepeso)
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Insignia('Sobrepeso', color: Colores.ambar),
                ),
              if (ruta.status != EstadoRuta.completada)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      final mensajero = ScaffoldMessenger.maybeOf(context);
                      try {
                        await ref
                            .read(accionesDeRutaProvider)
                            .eliminar(ruta.id);
                      } on RechazoLocal catch (fallo) {
                        mensajero?.showSnackBar(
                          SnackBar(content: Text(fallo.mensaje)),
                        );
                      }
                    },
                    child: const Text('Eliminar'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
