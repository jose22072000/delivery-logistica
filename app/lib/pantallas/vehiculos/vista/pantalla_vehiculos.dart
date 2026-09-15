import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../../../diseno/cajon.dart';
import '../datos/vehiculo_api.dart';
import '../estado/estado_vehiculos.dart';
import 'ficha_vehiculo.dart';
import 'tarjeta_vehiculo.dart';
import 'tipos_vehiculo.dart';

/// Vehiculos — `/vehicles`. Pliego: `pantallas.md` §5.
///
/// **Sólo con conexion, y se dice.** La flota se configura una vez, en la
/// oficina: no hay base local ni cola. Sin red esta pantalla no ensena una
/// flota vieja ni acepta cambios que luego se perderian — avisa y se queda
/// quieta.
class PantallaVehiculos extends ConsumerStatefulWidget {
  const PantallaVehiculos({super.key});

  static const ruta = '/vehicles';

  @override
  ConsumerState<PantallaVehiculos> createState() => _PantallaVehiculosState();
}

class _PantallaVehiculosState extends ConsumerState<PantallaVehiculos> {
  final _buscador = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  AjustesDeLaApi get _ajustes =>
      ref.read(ajustesVehiculosProvider).value ??
      const AjustesDeLaApi(tipos: [], cupRate: 320);

  Future<void> _abrirFicha([VehiculoDeLaApi? vehiculo]) async {
    final ajustes = _ajustes;
    await abrirPanel<void>(
      context,
      (contexto) => StatefulBuilder(
        builder: (contexto, repintar) => FichaVehiculo(
          vehiculo: vehiculo,
          tipos: ajustes.tipos,
          cupRate: ajustes.cupRate,
          guardando: _guardando,
          alGuardar: (datos) async {
            repintar(() => _guardando = true);
            final control = ref.read(controlVehiculosProvider.notifier);
            final bien = vehiculo == null
                ? await control.crear(datos)
                : await control.editar(vehiculo.id, datos);
            if (!contexto.mounted) return;
            repintar(() => _guardando = false);
            // Sólo se cierra si de verdad se guardo. Si no hubo red, el panel
            // se queda con lo escrito y el aviso lo explica: cerrarlo seria
            // dar por hecho que se guardo.
            if (bien) Navigator.of(contexto).pop();
          },
        ),
      ),
    );
    _guardando = false;
  }

  Future<void> _abrirTipos() async {
    final ajustes = _ajustes;
    await abrirPanel<void>(
      context,
      (contexto) => StatefulBuilder(
        builder: (contexto, repintar) => TiposDeVehiculo(
          tipos: ajustes.tipos,
          guardando: _guardando,
          alGuardar: (tipos) async {
            repintar(() => _guardando = true);
            final bien = await ref
                .read(controlVehiculosProvider.notifier)
                .guardarTipos(tipos);
            if (!contexto.mounted) return;
            repintar(() => _guardando = false);
            if (bien) Navigator.of(contexto).pop();
          },
        ),
      ),
    );
    _guardando = false;
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(vehiculosProvider);
    final busqueda = ref.watch(busquedaVehiculosProvider);
    final porPagina = ref.watch(porPaginaVehiculosProvider);
    final pagina = ref.watch(paginaVehiculosProvider);

    // Los avisos de escritura salen en la barra de abajo, no en el sitio de la
    // lista: la lista no cambio.
    ref.listen<AvisoVehiculos?>(controlVehiculosProvider, (_, aviso) {
      if (aviso == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(aviso.texto),
            backgroundColor: aviso.esFallo
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        );
    });

    // SIN `Scaffold` propio: lo pone el armazon.
    //
    // Esta pantalla se escribio antes de que existiera el armazon, que ya trae barra
    // lateral, barra superior con el titulo y la franja de estado. Un `Scaffold` dentro de
    // otro apila dos superficies de Material y deja los avisos emergentes colgando del de
    // dentro, que es el que no se ve entero.
    //
    // Ver el contrato en `lib/navegacion/pantalla_registrada.dart`.
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Vehículos', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Gestiona tu flota. Las tarifas se configuran globalmente en '
            'Configuración.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // En movil el grupo buscador + 2 botones ENVUELVE; sin esto se sale
          // por la derecha y el boton de agregar queda fuera de pantalla.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _buscador,
                  onChanged: (t) {
                    ref.read(busquedaVehiculosProvider.notifier).poner(t);
                    ref.read(paginaVehiculosProvider.notifier).poner(1);
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Buscar',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: _abrirTipos,
                child: const Text('Tipos de vehículo'),
              ),
              FilledButton(
                onPressed: () => _abrirFicha(),
                child: const Text('Agregar Vehículo'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (lista.error case final fallo?)
            _Fallo(
              fallo: fallo,
              alReintentar: () => ref.invalidate(vehiculosProvider),
            )
          else if (lista.value case final vehiculos?)
            _Rejilla(
              vehiculos: vehiculos.where((v) => v.cuadraCon(busqueda)).toList(),
              pagina: pagina,
              porPagina: porPagina,
              alAgregar: () => _abrirFicha(),
              alEditar: _abrirFicha,
              alIr: (n) => ref.read(paginaVehiculosProvider.notifier).poner(n),
              alCambiarTamano: (n) {
                ref.read(porPaginaVehiculosProvider.notifier).poner(n);
                ref.read(paginaVehiculosProvider.notifier).poner(1);
              },
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Cargando vehículos...')),
            ),
        ],
      ),
    );
  }
}

/// Lo que se ve cuando la lista no pudo bajar.
///
/// Un `FalloDeRed` no es «no hay vehiculos»: son dos cosas distintas y pintarlas
/// igual hace que alguien crea que la flota se borro.
class _Fallo extends StatelessWidget {
  const _Fallo({required this.fallo, required this.alReintentar});

  final Object fallo;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final texto = switch (fallo) {
      // Literal NUEVO: dice que es de ahora y que no se guarda nada aqui, para
      // que nadie se ponga a dar de alta camiones que no van a existir.
      FalloDeRed() =>
        'Sin conexión. Los vehículos se configuran con conexión: aquí no se '
            'guarda nada en el aparato. Vuelve a intentarlo cuando haya red.',
      final FalloApi f => f.mensaje,
      _ => 'No se pudo traer la flota. $fallo',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(texto, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: alReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _Rejilla extends ConsumerWidget {
  const _Rejilla({
    required this.vehiculos,
    required this.pagina,
    required this.porPagina,
    required this.alAgregar,
    required this.alEditar,
    required this.alIr,
    required this.alCambiarTamano,
  });

  final List<VehiculoDeLaApi> vehiculos;
  final int pagina;
  final int porPagina;
  final VoidCallback alAgregar;
  final ValueChanged<VehiculoDeLaApi> alEditar;
  final ValueChanged<int> alIr;
  final ValueChanged<int> alCambiarTamano;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (vehiculos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const Text('Sin vehículos'),
            const SizedBox(height: 4),
            Text(
              'Agrega tu primer vehículo para asignarlo a rutas',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: alAgregar,
              child: const Text('Agregar Vehículo'),
            ),
          ],
        ),
      );
    }

    final paginas = math.max(1, (vehiculos.length / porPagina).ceil());
    final actual = pagina.clamp(1, paginas);
    final desde = (actual - 1) * porPagina;
    final trozo = vehiculos.skip(desde).take(porPagina).toList();
    final control = ref.read(controlVehiculosProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, medidas) {
            // 1 / 2 / 3 columnas, como el pliego.
            final columnas = medidas.maxWidth >= 1024
                ? 3
                : medidas.maxWidth >= 640
                ? 2
                : 1;
            const hueco = 12.0;
            final ancho =
                (medidas.maxWidth - hueco * (columnas - 1)) / columnas;
            // `Wrap` y no `GridView`: las tarjetas no miden todas lo mismo
            // —las que estan en uso traen la caja de `Ruta activa` y algunas
            // llevan notas—, y una rejilla de alto fijo recorta justo eso. Con
            // `Wrap` cada una ocupa lo que necesita y no se pierde nada por
            // debajo del borde.
            return Wrap(
              spacing: hueco,
              runSpacing: hueco,
              children: [
                for (final v in trozo)
                  SizedBox(
                    width: ancho,
                    child: TarjetaVehiculo(
                      vehiculo: v,
                      alEditar: () => alEditar(v),
                      alEliminar: () => control.eliminar(v.id),
                      alMarcarDisponible: () => control.marcarDisponible(v.id),
                      alUsarParaDomicilio: () =>
                          control.usarParaDomicilio(v.id),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Mostrando ${desde + 1}–${desde + trozo.length} de '
              '${vehiculos.length}',
            ),
            DropdownButton<int>(
              value: porPagina,
              items: const [
                DropdownMenuItem(value: 25, child: Text('25 / pág.')),
                DropdownMenuItem(value: 50, child: Text('50 / pág.')),
                DropdownMenuItem(value: 100, child: Text('100 / pág.')),
              ],
              onChanged: (v) => alCambiarTamano(v ?? 25),
            ),
            if (paginas > 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Primera',
                    onPressed: actual > 1 ? () => alIr(1) : null,
                    icon: const Text('«'),
                  ),
                  IconButton(
                    tooltip: 'Anterior',
                    onPressed: actual > 1 ? () => alIr(actual - 1) : null,
                    icon: const Text('‹'),
                  ),
                  Text('$actual / $paginas'),
                  IconButton(
                    tooltip: 'Siguiente',
                    onPressed: actual < paginas ? () => alIr(actual + 1) : null,
                    icon: const Text('›'),
                  ),
                  IconButton(
                    tooltip: 'Última',
                    onPressed: actual < paginas ? () => alIr(paginas) : null,
                    icon: const Text('»'),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
