import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cargando.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/selector.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tarjeta.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../../../nucleo/proveedores.dart';
import '../datos/consultas_informes.dart';
import '../estado/informes_estado.dart';

/// Textos que esta pantalla necesita y la de Next no tiene. Van juntos y
/// marcados para que se sepa siempre que se comparo con Next y que no
/// (PLAN.md §4.3, regla 5).
abstract final class TextosNuevosDeInformes {
  /// Cuando hay datos, pero salen del aparato.
  static String cuadradoConElAparato(String fecha) =>
      'Cuadrado con los datos del aparato, del $fecha. '
      'Con conexión sale el del servidor.';

  /// Cuando lo bajado tiene mas de un dia. **Aqui el informe ya no sirve para
  /// cerrar nada**, y hay que decirlo con esas palabras.
  static const noSirveSinEstarAlDia =
      'Estos datos tienen más de un día: el informe no cuadra con el servidor '
      'y no sirve para cerrar. Conéctate y deja que baje.';

  /// Cuando no se bajo nunca. No se pinta ninguna tabla: una tabla de ceros se
  /// lee como «no hubo ventas», que es lo contrario de lo que pasa.
  static const sinNadaQueCuadrar =
      'No hay nada descargado todavía, así que no hay nada que cuadrar. '
      'Con conexión baja sola.';
}

/// REPORTES (pliego §7). **No esta en el menu**: se llega por URL y desde las
/// acciones rapidas del Panel.
class PantallaInformes extends ConsumerWidget {
  const PantallaInformes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final informe = ref.watch(informeProvider);
    final bajada = ref.watch(frescuraGlobalProvider);
    final ahora = ref.watch(relojProvider)();

    final cuando = bajada.value;
    final sinDescargar = bajada.hasValue && cuando == null;
    final viejo =
        cuando != null && ahora.difference(cuando) > const Duration(hours: 24);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Filtros(),
        const SizedBox(height: 12),
        _Advertencia(
          sinDescargar: sinDescargar,
          viejo: viejo,
          cuando: cuando,
        ),
        const SizedBox(height: 12),
        if (sinDescargar)
          const PantallaSinDescargar()
        else
          switch (informe) {
            AsyncValue<Informe>(:final value?) => _Pestanas(informe: value),
            AsyncValue<Informe>(:final error?) => EstadoVacio('$error'),
            _ => const Cargando('Cargando reporte...'),
          },
      ],
    );
  }
}

/// Lo que dice la pantalla sobre de donde salen sus numeros.
///
/// El informe de verdad lo cuadra el servidor sobre TODO lo que tiene. Aqui solo
/// puede salir lo bajado, y callarlo seria dar por bueno un total al que le
/// faltan pedidos. El aviso no es opcional ni se cierra: es parte del dato.
class _Advertencia extends StatelessWidget {
  const _Advertencia({
    required this.sinDescargar,
    required this.viejo,
    required this.cuando,
  });

  final bool sinDescargar;
  final bool viejo;
  final DateTime? cuando;

  @override
  Widget build(BuildContext context) {
    if (sinDescargar) {
      return const AvisoAmbar(TextosNuevosDeInformes.sinNadaQueCuadrar);
    }
    if (cuando == null) return const SizedBox.shrink();

    final fecha = DateFormat('d/M/y, H:mm', 'es').format(cuando!);
    final texto = TextosNuevosDeInformes.cuadradoConElAparato(fecha);

    if (viejo) {
      return AvisoAmbar(
        '$texto\n${TextosNuevosDeInformes.noSirveSinEstarAlDia}',
      );
    }
    return Text(
      texto,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: Colores.gris),
    );
  }
}

class _Filtros extends ConsumerWidget {
  const _Filtros();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroDeInformesProvider);
    final vehiculos = ref.watch(vehiculosDelInformeProvider).value ?? const [];
    final notas = ref.read(filtroDeInformesProvider.notifier);

    return Tarjeta(
      titulo: 'Filtros',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Fecha(
            etiqueta: 'Desde',
            valor: filtro.desde,
            alElegir: (d) => notas.poner(
              d == null
                  ? filtro.copiar(quitarDesde: true)
                  : filtro.copiar(desde: d),
            ),
          ),
          _Fecha(
            etiqueta: 'Hasta',
            valor: filtro.hasta,
            alElegir: (d) => notas.poner(
              d == null
                  ? filtro.copiar(quitarHasta: true)
                  : filtro.copiar(hasta: d),
            ),
          ),
          Selector<String>(
            icono: Icons.local_shipping_outlined,
            tooltip: 'Vehículo',
            etiquetaVacia: 'Todos los vehículos',
            valor: filtro.vehiculoId ?? '',
            opciones: [
              const OpcionSelector<String>(
                valor: '',
                etiqueta: 'Todos los vehículos',
              ),
              for (final v in vehiculos)
                OpcionSelector<String>(
                  valor: v.id,
                  etiqueta: v.name,
                  nota: v.plate,
                ),
            ],
            alElegir: (v) => notas.poner(
              v.isEmpty
                  ? filtro.copiar(quitarVehiculo: true)
                  : filtro.copiar(vehiculoId: v),
            ),
          ),
          // `Limpiar` solo si hay algo puesto: un boton que no hace nada ensena
          // a no leer los botones.
          if (filtro.hayAlgoPuesto)
            TextButton(
              onPressed: notas.limpiar,
              child: const Text('Limpiar'),
            ),
          // `Exportar a Excel` va aqui. Todavia no esta: hacen falta los
          // paquetes `excel` y `file_saver`, que no estan en el pubspec. Un
          // boton que no exporta nada es peor que no tenerlo.
        ],
      ),
    );
  }
}

class _Fecha extends StatelessWidget {
  const _Fecha({
    required this.etiqueta,
    required this.valor,
    required this.alElegir,
  });

  final String etiqueta;
  final DateTime? valor;
  final ValueChanged<DateTime?> alElegir;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.calendar_today_outlined, size: 16),
    onPressed: () async {
      final hoy = DateTime.now();
      final elegida = await showDatePicker(
        context: context,
        initialDate: valor ?? hoy,
        firstDate: DateTime(hoy.year - 5),
        lastDate: DateTime(hoy.year + 1),
      );
      if (elegida != null) alElegir(elegida);
    },
    onLongPress: () => alElegir(null),
    label: Text(
      valor == null
          ? etiqueta
          : '$etiqueta: ${DateFormat('d/M/y', 'es').format(valor!)}',
    ),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Colores.borde),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.informe});

  final Informe informe;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Resumen'),
            const Tab(text: 'Por Vehículo'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Detalle de Órdenes'),
                  const SizedBox(width: 6),
                  Insignia(Numeros.entero(informe.filas.length)),
                ],
              ),
            ),
          ],
        ),
        // Alto fijo y no `Expanded`: la pantalla entera es un `ListView`, y un
        // `TabBarView` sin alto dentro de un scroll no se puede medir.
        SizedBox(
          height: 560,
          child: TabBarView(
            children: [
              SingleChildScrollView(child: _Resumen(informe: informe)),
              SingleChildScrollView(child: _PorVehiculo(informe: informe)),
              SingleChildScrollView(child: _Detalle(informe: informe)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.informe});

  final Informe informe;

  @override
  Widget build(BuildContext context) {
    if (informe.filas.isEmpty) {
      return const EstadoVacio('No hay órdenes para los filtros seleccionados.');
    }
    final r = informe.resumen;
    final tarjetas = <Widget>[
      TarjetaDeCifra(
        etiqueta: 'Total Órdenes',
        valor: Numeros.entero(r.totalOrdenes),
      ),
      TarjetaDeCifra(
        etiqueta: 'Ingresos Totales',
        valor: Numeros.importe(r.ingresos),
      ),
      TarjetaDeCifra(
        etiqueta: 'Precio Promedio',
        valor: Numeros.importe(r.precioPromedio),
      ),
      TarjetaDeCifra(etiqueta: 'Peso Total', valor: Numeros.kg(r.peso)),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, medidas) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final t in tarjetas)
                  SizedBox(
                    width: medidas.maxWidth < Anchos.entrega
                        ? medidas.maxWidth
                        : (medidas.maxWidth - 36) / 4,
                    child: t,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Top vehículos',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final v in informe.porVehiculo.take(3))
                SizedBox(
                  width: 260,
                  child: Tarjeta(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(v.nombre),
                        if (v.placa != null)
                          Text(
                            v.placa!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colores.gris),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '${Numeros.importe(v.ingresos)} · '
                          '${Numeros.entero(v.ordenes)} órdenes',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PorVehiculo extends StatelessWidget {
  const _PorVehiculo({required this.informe});

  final Informe informe;

  @override
  Widget build(BuildContext context) {
    if (informe.porVehiculo.isEmpty) {
      return const EstadoVacio(
        'No hay datos de vehículos para los filtros seleccionados.',
      );
    }
    var ordenes = 0;
    var ingresos = 0.0;
    var peso = 0.0;
    for (final v in informe.porVehiculo) {
      ordenes += v.ordenes;
      ingresos += v.ingresos;
      peso += v.peso;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TablaAncha(
        anchoMinimo: 720,
        child: _Tabla(
          cabeceras: const [
            'Vehículo',
            'Placa',
            'Órdenes',
            'Ingresos',
            'Peso Total',
            'Promedio/Orden',
          ],
          filas: [
            for (final v in informe.porVehiculo)
              [
                v.nombre,
                v.placa ?? '—',
                Numeros.entero(v.ordenes),
                Numeros.importe(v.ingresos),
                Numeros.kg(v.peso),
                Numeros.importe(v.promedioPorOrden),
              ],
          ],
          pie: [
            'Totales',
            '',
            Numeros.entero(ordenes),
            Numeros.importe(ingresos),
            Numeros.kg(peso),
            '',
          ],
        ),
      ),
    );
  }
}

class _Detalle extends StatelessWidget {
  const _Detalle({required this.informe});

  final Informe informe;

  @override
  Widget build(BuildContext context) {
    if (informe.filas.isEmpty) {
      return const EstadoVacio('No hay órdenes para los filtros seleccionados.');
    }
    var peso = 0.0;
    var importe = 0.0;
    for (final f in informe.filas) {
      peso += f.pesoKg;
      importe += f.importe;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TablaAncha(
        anchoMinimo: 860,
        child: _Tabla(
          cabeceras: const [
            'Fecha',
            'Cliente',
            'Ruta',
            'Destino',
            'Vehículo',
            'Peso',
            'Precio',
          ],
          filas: [
            for (final f in informe.filas)
              [
                f.fecha == null
                    ? '—'
                    : DateFormat('d/M/y', 'es').format(f.fecha!),
                f.cliente,
                f.ruta ?? '—',
                f.destino,
                f.vehiculo ?? '—',
                Numeros.kg(f.pesoKg),
                Numeros.importe(f.importe),
              ],
          ],
          pie: [
            'Totales:',
            '',
            '',
            '',
            '',
            Numeros.kg(peso),
            Numeros.importe(importe),
          ],
        ),
      ),
    );
  }
}

/// Una tabla sencilla de textos. No usa `DataTable` porque `DataTable` reparte
/// la anchura sobrante a su manera y aqui el ancho lo fija `TablaAncha`.
class _Tabla extends StatelessWidget {
  const _Tabla({required this.cabeceras, required this.filas, this.pie});

  final List<String> cabeceras;
  final List<List<String>> filas;
  final List<String>? pie;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Fila(celdas: cabeceras, estilo: tema.textTheme.labelMedium),
        const Divider(height: 1, color: Colores.borde),
        for (final f in filas) _Fila(celdas: f, estilo: tema.textTheme.bodySmall),
        if (pie != null) ...[
          const Divider(height: 1, color: Colores.borde),
          _Fila(
            celdas: pie!,
            estilo: tema.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.celdas, this.estilo});

  final List<String> celdas;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Row(
      children: [
        for (final c in celdas)
          Expanded(
            child: Text(c, style: estilo, overflow: TextOverflow.ellipsis),
          ),
      ],
    ),
  );
}
