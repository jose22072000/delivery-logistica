import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tarjeta.dart';
import '../datos/consultas_panel.dart';
import '../estado/panel_estado.dart';

/// EL PANEL — la pantalla de la manana (pliego §1).
///
/// Dice cuanto hay pendiente de repartir y por donde empezar. Todo sale de la
/// base local, asi que sirve igual sin conexion; lo unico que cambia es lo que
/// diga la franja de estado de arriba.
class PantallaPanel extends ConsumerWidget {
  const PantallaPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cifras = ref.watch(cifrasDelPanelProvider);
    // Mientras carga, ceros: es lo que hace la de Next y evita que la pantalla
    // salte de vacia a llena cambiando de altura debajo del dedo.
    final c = cifras.value ?? CifrasDelPanel.cero;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Cifras(c),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, medidas) {
            // Por debajo de 768 px las dos tarjetas de abajo se apilan: una
            // lista de sucursales a media anchura no deja sitio ni al nombre.
            if (medidas.maxWidth < Anchos.entrega) {
              return Column(
                children: [
                  _PendientePorSucursal(cifras: c),
                  const SizedBox(height: 16),
                  const _AccionesRapidas(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _PendientePorSucursal(cifras: c)),
                const SizedBox(width: 16),
                const Expanded(child: _AccionesRapidas()),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Las 4 tarjetas: en fila en escritorio, **1 columna en movil** (§1).
class _Cifras extends StatelessWidget {
  const _Cifras(this.c);

  final CifrasDelPanel c;

  @override
  Widget build(BuildContext context) {
    final tarjetas = <Widget>[
      TarjetaDeCifra(
        etiqueta: 'Pedidos sin ruta',
        valor: Numeros.entero(c.sinRuta),
        subtexto: '${Numeros.kgRedondeado(c.pesoPendiente)} por mover',
        // Ambar con > 0: hay trabajo parado. Con 0, primario: no hay nada que
        // mirar y pintarlo en ambar seria gastar la senal.
        color: c.sinRuta > 0 ? Colores.ambar : null,
        icono: Icons.inventory_2_outlined,
      ),
      TarjetaDeCifra(
        etiqueta: 'Rutas en marcha',
        valor: Numeros.entero(c.rutasActivas),
        icono: Icons.route_outlined,
      ),
      TarjetaDeCifra(
        etiqueta: 'Entregados hoy',
        valor: Numeros.entero(c.entregadosHoy),
        icono: Icons.check_circle_outline,
      ),
      TarjetaDeCifra(
        etiqueta: 'Vehículos',
        valor: '${c.vehiculosEnRuta} / ${c.totalVehiculos}',
        subtexto: 'en ruta / total',
        icono: Icons.local_shipping_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, medidas) {
        if (medidas.maxWidth < Anchos.entrega) {
          return Column(
            children: [
              for (final t in tarjetas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(width: double.infinity, child: t),
                ),
            ],
          );
        }
        // `IntrinsicHeight` para que las cuatro midan lo mismo aunque solo una
        // tenga subtexto. Sin el, `stretch` dentro de un `ListView` pide altura
        // infinita y la pantalla no llega a pintarse.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tarjetas.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: tarjetas[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PendientePorSucursal extends ConsumerWidget {
  const _PendientePorSucursal({required this.cifras});

  final CifrasDelPanel cifras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final filas = ref.watch(pendientePorSucursalProvider);
    // El importe va en USD, que es como esta guardado. La conversion a CUP entra
    // con `nucleo/formato/dinero.dart`, que trae la tasa por sucursal; hasta
    // entonces no se inventa ninguna.

    return Tarjeta(
      titulo: 'Pendiente por sucursal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          switch (filas) {
            AsyncValue<List<PendienteDeSucursal>>(:final value?)
                when value.isEmpty =>
              const EstadoVacio('No queda nada sin ruta.'),
            AsyncValue<List<PendienteDeSucursal>>(:final value?) => Column(
              children: [
                for (final f in value)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(f.sucursal)),
                        SizedBox(
                          width: 90,
                          child: Text(
                            Numeros.kgRedondeado(f.pesoKg),
                            textAlign: TextAlign.right,
                            style: tema.textTheme.bodySmall?.copyWith(
                              color: Colores.gris,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 56,
                          child: Text(
                            Numeros.entero(f.pedidos),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            _ => const SizedBox(height: 48),
          },
          const Divider(height: 24, color: Colores.borde),
          Row(
            children: [
              const Expanded(child: Text('Domicilios cobrados')),
              Text(
                Numeros.importe(cifras.totalDomicilios),
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: Colores.verde,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccionesRapidas extends StatelessWidget {
  const _AccionesRapidas();

  @override
  Widget build(BuildContext context) => Tarjeta(
    titulo: 'Acciones Rápidas',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _Accion('Planificar Rutas', '/routes', Icons.route_outlined),
        _Accion('Ver Reportes', '/reports', Icons.assessment_outlined),
        _Accion('Gestionar Flota', '/vehicles', Icons.local_shipping_outlined),
      ],
    ),
  );
}

class _Accion extends StatelessWidget {
  const _Accion(this.texto, this.ruta, this.icono);

  final String texto;
  final String ruta;
  final IconData icono;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icono, color: Theme.of(context).colorScheme.primary),
    title: Text(texto),
    trailing: const Icon(Icons.chevron_right, color: Colores.gris),
    // `Ver Reportes` es una de las DOS puertas a `/reports`: la otra es escribir
    // la URL. Reportes no esta en el menu (§8.1), asi que si este enlace se cae,
    // la pantalla deja de existir para quien no sepa la direccion.
    onTap: () => context.go(ruta),
  );
}
