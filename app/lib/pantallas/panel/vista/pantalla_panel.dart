import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/tarjeta.dart';
import '../../../diseno/tema.dart';
import 'estado_del_dia.dart';
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

    // `p-3 sm:p-6` de delivery: 12 px en el telefono, 24 en pantalla grande.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return ListView(
      padding: EdgeInsets.all(estrecho ? Aire.md : Aire.xl),
      children: [
        // EL ESTADO DEL DIA, lo primero de la pantalla y por encima de las
        // cifras. **Una sola pieza y no dos botones**: la pantalla ya sabe si
        // toca traer, enviar o solo decir que se esta trabajando sin conexion,
        // y eso es trabajo que no tiene por que hacer el logistico. El porque
        // de que este aqui y no en `/sync` esta en el propio widget.
        const EstadoDelDia(),
        const SizedBox(height: Aire.xl),
        _Cifras(c),
        // `mb-8`: las cuatro cifras de arriba respiran mas que el resto, que es
        // lo que las separa de «el detalle».
        const SizedBox(height: Aire.xxl),
        LayoutBuilder(
          builder: (context, medidas) {
            // Por debajo de 768 px las dos tarjetas de abajo se apilan: una
            // lista de sucursales a media anchura no deja sitio ni al nombre.
            if (medidas.maxWidth < Anchos.entrega) {
              return Column(
                children: [
                  _PendientePorSucursal(cifras: c),
                  const SizedBox(height: Aire.xl),
                  const _AccionesRapidas(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _PendientePorSucursal(cifras: c)),
                const SizedBox(width: Aire.xl),
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
      // Cada tarjeta con SU color de marca, como en la de Next: entregados en
      // el verde del `--secondary`, flota en el naranja del `--accent`. Cuatro
      // franjas azules iguales obligan a leer la etiqueta cada vez.
      TarjetaDeCifra(
        etiqueta: 'Entregados hoy',
        valor: Numeros.entero(c.entregadosHoy),
        color: Colores.secundario,
        icono: Icons.check_circle_outline,
      ),
      TarjetaDeCifra(
        etiqueta: 'Vehículos',
        valor: '${c.vehiculosEnRuta} / ${c.totalVehiculos}',
        subtexto: 'en ruta / total',
        color: Colores.acento,
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
                  padding: const EdgeInsets.only(bottom: Aire.lg),
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
                if (i > 0) const SizedBox(width: Aire.lg),
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
      icono: Icons.location_city_outlined,
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
                  // Cada sucursal, separada de la siguiente por la linea fina
                  // (`border-b last:border-0` de la de Next).
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colores.linea)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              f.sucursal,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Los kg y el conteo, EN COLUMNA: son dos numeros que
                          // se comparan de arriba abajo, no dos palabras.
                          SizedBox(
                            width: 90,
                            child: Text(
                              Numeros.kgRedondeado(f.pesoKg),
                              textAlign: TextAlign.right,
                              style: Tipos.mono(
                                tamano: 12,
                                color: Colores.tintaSuave,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              Numeros.entero(f.pedidos),
                              textAlign: TextAlign.right,
                              style: Tipos.mono(
                                tamano: 14,
                                peso: FontWeight.w600,
                                color: Colores.tinta,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            _ => const SizedBox(height: 48),
          },
          const Divider(height: Aire.xl, color: Colores.linea),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Domicilios cobrados',
                  style: tema.textTheme.bodyMedium?.copyWith(
                    color: Colores.tintaSuave,
                  ),
                ),
              ),
              // El dinero cobrado va en el verde de marca y en mono: es la
              // unica cifra de la tarjeta que se apunta.
              Text(
                Numeros.importe(cifras.totalDomicilios),
                style: Tipos.mono(
                  tamano: 14,
                  peso: FontWeight.w700,
                  color: Colores.secundario,
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
    icono: Icons.bolt_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        // Cada una con SU color, como los tres bloques tintados de la de Next
        // (`bg-blue-50`, `bg-green-50`, `bg-yellow-50`): tres filas grises
        // iguales no se distinguen y hay que leerlas cada vez.
        _Accion(
          'Planificar Rutas',
          '/routes',
          Icons.route_outlined,
          Colores.azul,
          Colores.azulFondo,
        ),
        SizedBox(height: Aire.md),
        _Accion(
          'Ver Reportes',
          '/reports',
          Icons.assessment_outlined,
          Colores.verde,
          Colores.verdeFondo,
        ),
        SizedBox(height: Aire.md),
        _Accion(
          'Gestionar Flota',
          '/vehicles',
          Icons.local_shipping_outlined,
          Colores.ambar,
          Colores.ambarFondo,
        ),
      ],
    ),
  );
}

class _Accion extends StatelessWidget {
  const _Accion(this.texto, this.ruta, this.icono, this.color, this.fondo);

  final String texto;
  final String ruta;
  final IconData icono;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) => Material(
    color: fondo,
    borderRadius: BorderRadius.circular(Radios.lg),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radios.lg),
      // `Ver Reportes` es una de las DOS puertas a `/reports`: la otra es
      // escribir la URL. Reportes no esta en el menu (§8.1), asi que si este
      // enlace se cae, la pantalla deja de existir para quien no sepa la
      // direccion.
      onTap: () => context.go(ruta),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Aire.md,
          vertical: Aire.md,
        ),
        child: Row(
          children: [
            Icon(icono, size: 20, color: color),
            const SizedBox(width: Aire.md),
            Expanded(
              child: Text(
                texto,
                style: Tipos.texto(
                  tamano: 14,
                  peso: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: color.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    ),
  );
}
