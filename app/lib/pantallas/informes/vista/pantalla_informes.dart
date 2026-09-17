import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../diseno/anchos.dart';
import '../../../diseno/cargando.dart';
import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../diseno/estado_vacio.dart';
import '../../../diseno/insignia.dart';
import '../../../diseno/numeros.dart';
import '../../../diseno/selector.dart';
import '../../../diseno/tabla_ancha.dart';
import '../../../diseno/tarjeta.dart';
import '../../../navegacion/estado_navegacion.dart';
import '../../../nucleo/frescura/primera_bajada.dart';
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

  /// LO MISMO, EN LA WEB. Ni «aparato» ni «con conexión»: en un navegador no
  /// hay aparato del que sacar nada y la conexión la da por hecha la propia
  /// página, que cargó.
  ///
  /// Jose, 17/09/2026, viendo el texto de arriba en `reparto.procovar.cloud`:
  /// era el mundo de la APK asomando en la web.
  static String cuadradoConLoQueBajo(String fecha) =>
      'Cuadrado con lo último que bajó, de las $fecha.';

  /// Cuando lo bajado tiene mas de un dia. **Aqui el informe ya no sirve para
  /// cerrar nada**, y hay que decirlo con esas palabras.
  static const noSirveSinEstarAlDia =
      'Estos datos tienen más de un día: el informe no cuadra con el servidor '
      'y no sirve para cerrar. Conéctate y deja que baje.';

  /// Y EN LA WEB. Que los datos tengan un dia en un navegador no se arregla
  /// conectandose —ya lo esta—: significa que la sincronizacion no esta
  /// llegando, y eso lo arregla la oficina.
  static const noSirveSinEstarAlDiaEnWeb =
      'Estos datos tienen más de un día: el informe no cuadra con el servidor '
      'y no sirve para cerrar. Recarga la página y, si sigue igual, avisa a la '
      'oficina.';

  /// Cuando no se bajo nunca. No se pinta ninguna tabla: una tabla de ceros se
  /// lee como «no hubo ventas», que es lo contrario de lo que pasa.
  static const sinNadaQueCuadrar =
      'No hay nada descargado todavía, así que no hay nada que cuadrar. '
      'Con conexión baja sola.';

  /// Lo que se dice en la web mientras la primera bajada va en camino.
  static const cargandoElReporte = 'Cargando reporte...';

  /// Y lo que se dice en la web cuando esa bajada no llego.
  static final noLlegoElReporte = TextosDeLaWeb.noPudoBajar(
    'los datos del reporte',
  );
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

    // LA MONEDA, PARA TODA LA PANTALLA. Se resuelve una vez aqui y baja como
    // parametro: si cada tabla la mirara por su cuenta podrian pintar dos
    // monedas distintas en la misma vista mientras la tasa se recarga.
    //
    // `monedaEfectivaProvider` ya se cae a USD cuando la sucursal que se mira
    // no tiene tasa, y `TasaDeLaMirada.importe` no usa NUNCA la de otra. El
    // porque —sin tasa, con todas las sucursales, tasa vieja— lo dice la barra
    // de arriba; aqui sólo se pinta.
    final tasa = ref.watch(tasaDeLaMiradaProvider);
    final moneda = ref.watch(monedaEfectivaProvider);
    String importe(double? usd) => tasa.importe(usd, moneda);

    final cuando = bajada.value;
    final sinDescargar = bajada.hasValue && cuando == null;
    final viejo =
        cuando != null && ahora.difference(cuando) > const Duration(hours: 24);
    // POR QUE ESTA VACIO, que no es lo mismo que «esta vacio».
    //
    // En la web la base nace vacia en cada carga de la pagina, asi que el primer
    // segundo esto decia «No hay nada descargado todavía… Con conexión baja
    // sola»: dos frases del mundo de la APK delante de alguien sentado en la
    // oficina con internet, acusando de un problema que no existia.
    final porQue = ref.watch(porQueEstaVacioProvider);

    // `p-3 sm:p-6` de delivery.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return ListView(
      padding: EdgeInsets.all(estrecho ? Aire.md : Aire.xl),
      children: [
        const _Filtros(),
        const SizedBox(height: Aire.lg),
        _Advertencia(
          sinDescargar: sinDescargar,
          viejo: viejo,
          cuando: cuando,
          porQue: porQue,
        ),
        const SizedBox(height: Aire.lg),
        if (sinDescargar)
          switch (porQue) {
            // El aparato: es un estado de verdad y se dice como siempre.
            PorQueEstaVacio.noSeDescargo => const PantallaSinDescargar(),
            // La web, el primer segundo: **cargando, y nada mas**. Sin
            // diagnostico, porque no se ha mirado nada todavia.
            PorQueEstaVacio.todaviaBajando => const Cargando(
              TextosNuevosDeInformes.cargandoElReporte,
            ),
            // La web cuando la bajada no llego: se dice, y se deja entrar. Los
            // filtros de arriba siguen ahi y la pagina se puede recargar.
            PorQueEstaVacio.noPudoBajar => EstadoVacio(
              TextosNuevosDeInformes.noLlegoElReporte,
              icono: Icons.cloud_off_outlined,
            ),
          }
        else
          switch (informe) {
            AsyncValue<Informe>(:final value?) => _Pestanas(
              informe: value,
              importe: importe,
            ),
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
    required this.porQue,
  });

  final bool sinDescargar;
  final bool viejo;
  final DateTime? cuando;
  final PorQueEstaVacio porQue;

  @override
  Widget build(BuildContext context) {
    final enWeb = porQue != PorQueEstaVacio.noSeDescargo;

    if (sinDescargar) {
      return switch (porQue) {
        PorQueEstaVacio.noSeDescargo => const AvisoAmbar(
          TextosNuevosDeInformes.sinNadaQueCuadrar,
        ),
        // MIENTRAS BAJA NO SE ACUSA A NADIE. El recuadro ambar de «no hay nada
        // que cuadrar» delante de alguien cuyos datos entran un segundo despues
        // es exactamente el mensaje falso del 17/09/2026. Lo que toca es
        // esperar, y de decirlo se ocupa el cargando de abajo.
        PorQueEstaVacio.todaviaBajando => const SizedBox.shrink(),
        PorQueEstaVacio.noPudoBajar => AvisoAmbar(
          TextosNuevosDeInformes.noLlegoElReporte,
        ),
      };
    }
    if (cuando == null) return const SizedBox.shrink();

    final fecha = DateFormat('d/M/y, H:mm', 'es').format(cuando!);
    final hora = DateFormat('H:mm', 'es').format(cuando!);
    final texto = enWeb
        ? TextosNuevosDeInformes.cuadradoConLoQueBajo(hora)
        : TextosNuevosDeInformes.cuadradoConElAparato(fecha);

    if (viejo) {
      return AvisoAmbar(
        '$texto\n'
        '${enWeb ? TextosNuevosDeInformes.noSirveSinEstarAlDiaEnWeb : TextosNuevosDeInformes.noSirveSinEstarAlDia}',
      );
    }
    return Text(
      texto,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Colores.gris),
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
            TextButton(onPressed: notas.limpiar, child: const Text('Limpiar')),
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
      side: BorderSide(color: Colores.borde),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
  );
}

class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.informe, required this.importe});

  final Informe informe;
  final PintarImporte importe;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Las pestanas, con el subrayado en primario y sin el tinte morado que
        // Material les pone por defecto.
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colores.primario,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colores.linea,
          labelColor: Colores.primario,
          unselectedLabelColor: Colores.tintaSuave,
          labelStyle: Tipos.texto(tamano: 14, peso: FontWeight.w600),
          unselectedLabelStyle: Tipos.texto(tamano: 14, peso: FontWeight.w500),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
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
              SingleChildScrollView(
                child: _Resumen(informe: informe, importe: importe),
              ),
              SingleChildScrollView(
                child: _PorVehiculo(informe: informe, importe: importe),
              ),
              SingleChildScrollView(
                child: _Detalle(informe: informe, importe: importe),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.informe, required this.importe});

  final Informe informe;
  final PintarImporte importe;

  @override
  Widget build(BuildContext context) {
    if (informe.filas.isEmpty) {
      return const EstadoVacio(
        'No hay órdenes para los filtros seleccionados.',
      );
    }
    final r = informe.resumen;
    final tarjetas = <Widget>[
      TarjetaDeCifra(
        etiqueta: 'Total Órdenes',
        valor: Numeros.entero(r.totalOrdenes),
      ),
      TarjetaDeCifra(etiqueta: 'Ingresos Totales', valor: importe(r.ingresos)),
      TarjetaDeCifra(
        etiqueta: 'Precio Promedio',
        valor: importe(r.precioPromedio),
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
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
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
                          '${importe(v.ingresos)} · '
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
  const _PorVehiculo({required this.informe, required this.importe});

  final Informe informe;
  final PintarImporte importe;

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
                importe(v.ingresos),
                Numeros.kg(v.peso),
                importe(v.promedioPorOrden),
              ],
          ],
          pie: [
            'Totales',
            '',
            Numeros.entero(ordenes),
            importe(ingresos),
            Numeros.kg(peso),
            '',
          ],
        ),
      ),
    );
  }
}

class _Detalle extends StatelessWidget {
  const _Detalle({required this.informe, required this.importe});

  final Informe informe;
  final PintarImporte importe;

  @override
  Widget build(BuildContext context) {
    if (informe.filas.isEmpty) {
      return const EstadoVacio(
        'No hay órdenes para los filtros seleccionados.',
      );
    }
    var peso = 0.0;
    var total = 0.0;
    for (final f in informe.filas) {
      peso += f.pesoKg;
      total += f.importe;
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
                importe(f.importe),
              ],
          ],
          pie: ['Totales:', '', '', '', '', Numeros.kg(peso), importe(total)],
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
        // La cabecera en versalitas sobre papel, como todas las de delivery.
        _Fila(
          celdas: cabeceras,
          estilo: Tipos.texto(
            tamano: 11,
            peso: FontWeight.w600,
            color: Colores.tintaSuave,
            interletra: 0.4,
          ),
          fondo: Colores.papel,
        ),
        Divider(height: 1, thickness: 1, color: Colores.linea),
        for (final f in filas)
          _Fila(celdas: f, estilo: tema.textTheme.bodySmall, conLinea: true),
        if (pie != null) ...[
          Divider(height: 1, thickness: 1, color: Colores.linea),
          _Fila(
            celdas: pie!,
            estilo: Tipos.texto(
              tamano: 13,
              peso: FontWeight.w700,
              color: Colores.tinta,
            ),
            fondo: Colores.papel,
          ),
        ],
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.celdas,
    this.estilo,
    this.fondo,
    this.conLinea = false,
  });

  final List<String> celdas;
  final TextStyle? estilo;
  final Color? fondo;

  /// La linea fina de abajo, la que separa una fila de la siguiente.
  final bool conLinea;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: fondo,
      border: conLinea
          ? Border(bottom: BorderSide(color: Colores.linea))
          : null,
    ),
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: Aire.sm),
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
