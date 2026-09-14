import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/red/fallos.dart';

import '../datos/almacen_api.dart';
import '../estado/estado_almacenes.dart';
import 'cajon.dart';
import 'editor_almacen.dart';

/// Almacenes — `/warehouses`. Pliego: `pantallas.md` §6.
///
/// **Sólo con conexion, y se dice.** El almacen vive en Accesos y hay una sola
/// copia: no se encola. Se configura una vez, en la oficina. Sin red la pantalla
/// avisa y no acepta cambios, en vez de guardar algo que nadie va a poder
/// cotizar.
class PantallaAlmacenes extends ConsumerStatefulWidget {
  const PantallaAlmacenes({super.key});

  static const ruta = '/warehouses';

  @override
  ConsumerState<PantallaAlmacenes> createState() => _PantallaAlmacenesState();
}

class _PantallaAlmacenesState extends ConsumerState<PantallaAlmacenes> {
  bool _guardando = false;

  SucursalDeAccesos? _sucursal(List<SucursalDeAccesos> todas) {
    if (todas.isEmpty) return null;
    final elegida = ref.watch(sucursalElegidaProvider);
    return todas.where((s) => s.codigo == elegida).firstOrNull ?? todas.first;
  }

  /// Guarda **la lista completa** de la sucursal. Todo cambio pasa por aqui:
  /// alta, edicion y baja son la misma llamada con una lista distinta.
  Future<bool> _mandar(
    SucursalDeAccesos sucursal,
    List<AlmacenDeAccesos> lista,
  ) async {
    setState(() => _guardando = true);
    final bien = await ref
        .read(controlAlmacenesProvider.notifier)
        .guardar(sucursal.codigo, lista);
    if (mounted) setState(() => _guardando = false);
    return bien;
  }

  Future<void> _abrirEditor(
    SucursalDeAccesos sucursal, {
    int? indice,
  }) async {
    final almacen = indice == null ? null : sucursal.almacenes[indice];
    await abrirCajon<void>(
      context: context,
      constructor: (contexto) => StatefulBuilder(
        builder: (contexto, repintar) => EditorAlmacen(
          almacen: almacen,
          sucursal: sucursal.nombre,
          guardando: _guardando,
          alQuitar: indice == null
              ? null
              : () async {
                  final quedan = [...sucursal.almacenes]..removeAt(indice);
                  final bien = await _mandar(sucursal, quedan);
                  if (bien && contexto.mounted) Navigator.of(contexto).pop();
                },
          alGuardar: (editado) async {
            repintar(() {});
            var lista = [...sucursal.almacenes];
            if (indice == null) {
              lista.add(editado);
            } else {
              lista[indice] = editado;
            }
            // Un solo principal: al marcar uno se desmarcan los demas, sobre la
            // lista entera y antes de mandarla.
            if (editado.principal) {
              lista = conUnSoloPrincipal(
                lista,
                indice ?? lista.length - 1,
              );
            }
            final bien = await _mandar(sucursal, lista);
            if (bien && contexto.mounted) Navigator.of(contexto).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final datos = ref.watch(almacenesProvider);

    ref.listen<AvisoAlmacenes?>(controlAlmacenesProvider, (_, aviso) {
      if (aviso == null) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(aviso.texto),
            backgroundColor: aviso.esFallo ? tema.colorScheme.error : null,
          ),
        );
    });

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Almacenes', style: tema.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'El punto desde el que se mide cada domicilio. Un almacén sin '
              'coordenadas no sirve para cotizar: la distancia se mide desde '
              'aquí.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (datos.error case final fallo?)
              _Fallo(
                fallo: fallo,
                alReintentar: () => ref.invalidate(almacenesProvider),
              )
            else if (datos.value case final sucursales?)
              _Contenido(
                sucursales: sucursales,
                sucursal: _sucursal(sucursales),
                alElegirSucursal: (codigo) =>
                    ref.read(sucursalElegidaProvider.notifier).poner(codigo),
                alAbrir: _abrirEditor,
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Cargando…')),
              ),
          ],
        ),
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({
    required this.sucursales,
    required this.sucursal,
    required this.alElegirSucursal,
    required this.alAbrir,
  });

  final List<SucursalDeAccesos> sucursales;
  final SucursalDeAccesos? sucursal;
  final ValueChanged<String> alElegirSucursal;
  final void Function(SucursalDeAccesos sucursal, {int? indice}) alAbrir;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    if (sucursales.isEmpty || sucursal == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('No hay ninguna sucursal a la vista con código en Accesos.'),
      );
    }

    final actual = sucursal!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Con una sola sucursal se pinta su nombre sin desplegable: un
            // selector de una opcion no elige nada.
            if (sucursales.length == 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.store, size: 18),
                  const SizedBox(width: 6),
                  Text(actual.nombre),
                ],
              )
            else
              DropdownButton<String>(
                value: actual.codigo,
                icon: const Icon(Icons.store),
                items: [
                  for (final s in sucursales)
                    DropdownMenuItem(
                      value: s.codigo,
                      child: Text(
                        s.almacenes.isEmpty
                            ? '${s.nombre} · sin almacenes'
                            : '${s.nombre} · ${s.almacenes.length}',
                      ),
                    ),
                ],
                onChanged: (v) => v == null ? null : alElegirSucursal(v),
              ),
            FilledButton(
              onPressed: () => alAbrir(actual),
              child: const Text('Nuevo almacén'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (actual.almacenes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Esta sucursal no tiene ninguno: sus domicilios no se pueden '
              'cotizar.',
              style: tema.textTheme.bodyMedium,
            ),
          )
        else
          for (final (indice, a) in actual.almacenes.indexed)
            ListTile(
              leading: Icon(
                a.principal ? Icons.star : Icons.warehouse,
                color: a.principal ? const Color(0xFFB45309) : null,
              ),
              title: Text(a.titulo),
              subtitle: Text(
                [
                  a.direccion?.trim().isNotEmpty ?? false
                      ? a.direccion!.trim()
                      : 'sin dirección',
                  if (a.sinPunto) 'sin punto',
                  if (!a.activo) 'inactivo',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => alAbrir(actual, indice: indice),
            ),
      ],
    );
  }
}

class _Fallo extends StatelessWidget {
  const _Fallo({required this.fallo, required this.alReintentar});

  final Object fallo;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final texto = switch (fallo) {
      // Literal NUEVO. Lo importante es la segunda frase: aqui no hay copia
      // local que editar, asi que sin red no hay nada que hacer en esta
      // pantalla y mas vale decirlo que dejar a alguien tecleando.
      FalloDeRed() =>
        'Sin conexión. Los almacenes viven en Accesos y se configuran con '
            'conexión: aquí no se guarda nada en el aparato. Vuelve a '
            'intentarlo cuando haya red.',
      // El literal del pliego cuando Accesos contesta que no.
      final FalloApi f => f.mensaje,
      _ =>
        'No se pudieron traer los almacenes de Accesos. Lo de abajo está vacío '
            'por eso, no porque no haya ninguno.',
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
