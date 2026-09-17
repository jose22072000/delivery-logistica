import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/pestanas.dart';
import '../../../nucleo/plataforma.dart';

import '../datos/modelos.dart';
import '../estado/filtros_en_la_url.dart';
import '../estado/proveedores.dart';
import 'acciones.dart';
import 'columna.dart';
import 'kit.dart';
import 'panel_sin_colocar.dart';
import 'tarjeta.dart';

/// EL TABLERO DE PREPARACION.
///
/// Entre «me han llegado 180 pedidos» y «sale este camion con estas 14 paradas»
/// hay un trabajo que hoy se hace en la cabeza del logistico y en un papel:
/// agrupar por zona. Esto es ese paso — columnas que pone el, tarjetas que
/// arrastra el.
///
/// Y es la pantalla que mas sentido tiene **sin red**: preparar es mover cosas
/// de sitio, y es justo lo que se hace durante el dia, que es cuando no hay
/// senal. No hay ningun «modo sin conexion» que encender: se guarda en el
/// aparato y se sube por detras.
///
/// **Sin `Scaffold` ni `AppBar`**: los pone el armazon
/// (`navegacion/pantalla_registrada.dart`). Devolver otro deja dos barras
/// superiores y rompe el selector de sucursal.
class PantallaTablero extends ConsumerStatefulWidget {
  const PantallaTablero({this.filtrosDeLaUrl, super.key});

  /// Los filtros que venian en la direccion. En web, mandar un enlace al
  /// tablero ya filtrado tiene que llevar al mismo sitio.
  final FiltrosSinColocar? filtrosDeLaUrl;

  @override
  ConsumerState<PantallaTablero> createState() => _PantallaTableroState();
}

class _PantallaTableroState extends ConsumerState<PantallaTablero> {
  /// EN EL MOVIL, EN QUE PAGINA SE ESTA.
  ///
  /// `0` es «sin colocar»; de `1` en adelante, las zonas una a una y al final la
  /// de crear otra. Es UN numero y no un si/no porque el gesto que pidio Jose es
  /// el mismo para las dos cosas: deslizar pasa de «sin colocar» a la primera
  /// zona igual que pasa de una zona a la siguiente.
  int _pagina = 0;

  /// La pagina de «sin colocar». Con nombre porque se lee en cuatro sitios y
  /// `0` suelto no dice cual de las dos mitades es.
  static const _sinColocar = 0;

  /// Por debajo de esto, las dos mitades no caben una al lado de la otra.
  static const _anchoDeDosMitades = anchoDeDosMitades;

  @override
  void initState() {
    super.initState();
    _adoptarLaUrl();
  }

  @override
  void didUpdateWidget(PantallaTablero anterior) {
    super.didUpdateWidget(anterior);
    _adoptarLaUrl();
  }

  /// Los filtros de la direccion mandan al entrar.
  ///
  /// Se hace fuera del `build` —despues del fotograma— porque tocar un provider
  /// mientras se construye es lo que Riverpod prohibe, con razon: dejaria el
  /// arbol a medio pintar con dos estados distintos.
  void _adoptarLaUrl() {
    final deLaUrl = widget.filtrosDeLaUrl;
    if (deLaUrl == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ahora = ref.read(filtrosTableroProvider);
      if (!FiltrosEnLaUrl.iguales(ahora, deLaUrl)) {
        ref.read(filtrosTableroProvider.notifier).poner(deLaUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asincrono = ref.watch(tableroProvider);
    return asincrono.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Problema(texto: _texto(e)),
      data: _conDatos,
    );
  }

  Widget _conDatos(Tablero tablero) {
    // Las dos situaciones normales que no son un tablero: sin sucursal elegida
    // y sin almacen con coordenadas. Se dicen con las palabras del pliego.
    final problema = tablero.problema;
    if (problema != null) return _Problema(texto: problema);
    return _cuerpo(tablero);
  }

  Widget _cuerpo(Tablero tablero) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (tablero.desaparecidos.isNotEmpty)
        _AvisoDesaparecidos(desaparecidos: tablero.desaparecidos),
      _BarraDeArriba(tablero: tablero),
      Expanded(
        child: LayoutBuilder(
          builder: (contexto, medidas) {
            if (medidas.maxWidth >= _anchoDeDosMitades) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 340,
                    child: PanelSinColocar(
                      tablero: tablero,
                      alPulsarTarjeta: (pedido) =>
                          _moverTarjeta(tablero, pedido),
                      alDevolver: _devolver,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _Tira(tablero: tablero)),
                ],
              );
            }
            // EL MOVIL: UNA SOLA TIRA DE PAGINAS.
            //
            // «Sin colocar» es la primera y DESPUES van las zonas, una a una.
            // Puestas en fila, el mismo gesto sirve para las dos cosas que
            // pidio Jose: pasar de una pestana a la otra, y ya dentro de zonas
            // ir de una zona a la siguiente sin volver a la pestana.
            //
            // Y por eso NO van anidadas —las pestanas por fuera, las zonas por
            // dentro—, que era lo primero que salia: dos deslizamientos en el
            // mismo eje no se turnan. Manda el de dentro, y cuando llega a su
            // extremo el de fuera no recoge el gesto: quedaria una zona de la
            // que no se puede salir con el dedo.
            final cuantas = 1 + _cuantasZonas(tablero);
            final pagina = _pagina.clamp(_sinColocar, cuantas - 1);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                  child: CarruselDePestanas(
                    indice: pagina,
                    cuantas: cuantas,
                    titulo: _tituloDePagina(tablero, pagina),
                    etiquetas: _nombresDePagina(tablero),
                    alCambiar: _irA,
                  ),
                ),
                Expanded(
                  child: CuerpoDeslizable(
                    indice: pagina,
                    cuantas: cuantas,
                    alCambiar: _irA,
                    pagina: (contexto, i) => _paginaDelMovil(tablero, i),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );

  /// EL ROTULO DE LA PAGINA EN LA QUE SE ESTA — el unico que se pinta.
  ///
  /// Es el de la MITAD en la que se esta, no el de la zona concreta: dentro de
  /// zonas pone «Zonas (12)» y no «Centro (3)», porque el nombre y la cuenta de
  /// la zona ya los dice a lo grande la cabecera de la propia columna, dos
  /// dedos mas abajo. Dos sitios con el mismo texto es el sitio perfecto para
  /// que un dia digan cosas distintas.
  ///
  /// Cual de las doce zonas es lo dicen las bolitas y la cabecera de la columna.
  String _tituloDePagina(Tablero tablero, int pagina) {
    if (pagina == _sinColocar) {
      return 'Sin colocar (${tablero.sinColocar.total})';
    }
    if (tablero.columnas.isNotEmpty && pagina - 1 >= tablero.columnas.length) {
      return 'Nueva columna';
    }
    return 'Zonas (${tablero.columnas.length})';
  }

  /// CUANTAS PAGINAS DE ZONAS HAY EN EL MOVIL: una por columna, mas la de crear
  /// otra. Sin ninguna columna es una sola, la que explica que las pone el.
  int _cuantasZonas(Tablero tablero) =>
      tablero.columnas.isEmpty ? 1 : tablero.columnas.length + 1;

  /// El nombre de cada pagina, que es lo que dice la flecha a donde lleva.
  List<String> _nombresDePagina(Tablero tablero) => [
    'Sin colocar',
    if (tablero.columnas.isEmpty)
      'Zonas'
    else ...[
      for (final columna in tablero.columnas) columna.nombre,
      'Nueva columna',
    ],
  ];

  Widget _paginaDelMovil(Tablero tablero, int i) {
    if (i == _sinColocar) {
      return PanelSinColocar(
        tablero: tablero,
        alPulsarTarjeta: (pedido) => _moverTarjeta(tablero, pedido),
        alDevolver: _devolver,
        // Sin rotulo: lo dice el carrusel, justo encima.
        conRotulo: false,
      );
    }
    if (tablero.columnas.isEmpty) return const _SinColumnas();
    final cual = i - 1;
    if (cual >= tablero.columnas.length) return const _PaginaNuevaColumna();
    // `ancho: null` = que ocupe la pagina entera, que es justo lo que hay.
    return _Zona(tablero: tablero, cual: cual);
  }

  void _irA(int pagina) {
    if (pagina == _pagina) return;
    setState(() => _pagina = pagina);
  }

  void _moverTarjeta(Tablero tablero, TarjetaPedido pedido) {
    unawaited(
      AccionesTablero.moverTarjeta(
        context,
        ref,
        pedido: pedido,
        tablero: tablero,
      ),
    );
  }

  void _devolver(TarjetaArrastrada datos) {
    // Arrastrar a la izquierda algo que ya estaba a la izquierda no es una
    // orden: es un dedo que se escapo.
    if (datos.desdeColumnaId == null) return;
    unawaited(ref.read(tableroProvider.notifier).quitar(datos.pedidoId));
  }
}

String _texto(Object fallo) => switch (fallo) {
  // No se ensena «todo», que es lo que pareceria razonable y seria lo peor.
  final FaltaElegirSucursal e => e.mensaje,
  // Se ordena desde el sitio del que sale la mercancia, o no se ordena.
  final SinAlmacenConCoordenadas e => e.mensaje,
  final RechazoDelTablero e => e.mensaje,
  _ => 'No se pudo abrir el tablero: $fallo',
};

/// La tira de columnas, que se desplaza a lo ancho, con el «+» al final.
///
/// **Solo en pantalla ancha.** En el movil las zonas ya no van en una tira que
/// se empuja: van una por pagina y se pasa deslizando (`_paginaDelMovil`). En
/// una tira, para llegar a la zona seis hay que arrastrar cinco veces sin que
/// nada enganche; en paginas, cada deslizamiento cae en una zona entera.
class _Tira extends ConsumerWidget {
  const _Tira({required this.tablero});

  final Tablero tablero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tablero.columnas.isEmpty) return const _SinColumnas();

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(4),
      // Una mas: el «+» del final, que es como dice el pliego que se crea una
      // columna.
      itemCount: tablero.columnas.length + 1,
      itemBuilder: (contexto, i) => i == tablero.columnas.length
          ? const _BotonNuevaColumna(ancho: 140)
          : _Zona(tablero: tablero, cual: i, ancho: 300),
    );
  }
}

/// UNA ZONA, con todo lo que se puede hacer sobre ella.
///
/// Vive suelta porque la usan los dos mundos: la tira de escritorio y la pagina
/// del movil. Tenerla dos veces era tener dos sitios donde arreglar la misma
/// regla de «soltar donde ya estaba no es una orden», y uno de los dos se
/// olvida.
class _Zona extends ConsumerWidget {
  const _Zona({required this.tablero, required this.cual, this.ancho});

  final Tablero tablero;

  /// Cual de `tablero.columnas`, por su sitio: hace falta el numero y no solo la
  /// columna, porque reordenar es «ponla donde esta esta».
  final int cual;

  /// `null` = que ocupe lo que le den. Es lo del movil, donde la zona es la
  /// pagina entera.
  final double? ancho;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columna = tablero.columnas[cual];
    return ColumnaDelTablero(
      columna: columna,
      ancho: ancho,
      tarjetas: tablero.deColumna(columna.id),
      alSoltar: (datos, posicion) {
        // Soltar una tarjeta donde ya estaba no es una orden: es un dedo que se
        // escapo. Sin esto, cada roce deja un apunte en la cola.
        if (datos.desdeColumnaId == columna.id && posicion == null) return;
        unawaited(
          ref
              .read(tableroProvider.notifier)
              .colocar(
                pedidoId: datos.pedidoId,
                columnaId: columna.id,
                posicion: posicion,
              ),
        );
      },
      alSoltarColumna: (arrastrada) {
        final ids = tablero.columnas.map((c) => c.id).toList()
          ..remove(arrastrada.columnaId);
        ids.insert(cual.clamp(0, ids.length), arrastrada.columnaId);
        unawaited(ref.read(tableroProvider.notifier).reordenar(ids));
      },
      alPulsarTarjeta: (tarjeta) => unawaited(
        AccionesTablero.moverTarjeta(
          context,
          ref,
          pedido: tarjeta.pedido,
          tablero: tablero,
          columnaActual: tarjeta.columnaId,
          posicionActual: tarjeta.posicion,
        ),
      ),
      alAbrirMenu: () => unawaited(
        AccionesTablero.menuDeColumna(
          context,
          ref,
          columna: columna,
          tablero: tablero,
        ),
      ),
    );
  }
}

/// Un tablero sin ninguna zona todavia.
class _SinColumnas extends ConsumerWidget {
  const _SinColumnas();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Las zonas las pones tú.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Cada sucursal divide su territorio a su manera: por distritos, '
            'por carreteras o por barrios de toda la vida. Crea la primera '
            'columna con el «+».',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () =>
                unawaited(AccionesTablero.crearColumna(context, ref)),
            icon: const Icon(Icons.add),
            label: const Text('Nueva columna'),
          ),
        ],
      ),
    ),
  );
}

/// LA ULTIMA PAGINA DEL MOVIL: crear otra zona.
///
/// En la tira de escritorio esto es el recuadro del «+» al final. En el movil,
/// donde cada zona ocupa una pagina, un recuadro estirado a pantalla completa
/// seria un boton gigante: se dice con palabras y ya.
class _PaginaNuevaColumna extends ConsumerWidget {
  const _PaginaNuevaColumna();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Fin de las zonas.', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Si el territorio se te queda corto, pon otra.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () =>
                unawaited(AccionesTablero.crearColumna(context, ref)),
            icon: const Icon(Icons.add),
            label: const Text('Nueva columna'),
          ),
        ],
      ),
    ),
  );
}

class _BotonNuevaColumna extends ConsumerWidget {
  const _BotonNuevaColumna({required this.ancho});

  final double ancho;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    width: ancho,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    child: OutlinedButton(
      onPressed: () => unawaited(AccionesTablero.crearColumna(context, ref)),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add),
          SizedBox(height: 4),
          Text('Columna', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

/// De donde se mide, de cuando son los datos y qué ha dejado de servir.
///
/// Lo que queda sin subir NO se pinta aqui: ya lo dice la franja del armazon,
/// en las siete pantallas. Dos contadores del mismo numero es el sitio perfecto
/// para que un dia digan cosas distintas.
class _BarraDeArriba extends ConsumerWidget {
  const _BarraDeArriba({required this.tablero});

  final Tablero tablero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final avisos = tablero.avisos;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      color: tema.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${tablero.sucursalNombre} · desde ${tablero.almacen.nombre}',
                  style: tema.textTheme.labelMedium,
                ),
                // Un tablero que parece vivo y lleva seis horas congelado es
                // peor que uno que avisa.
                //
                // Y si hay algo aqui que no esta arriba, eso manda sobre la
                // hora: refrescar borraria la foto de aqui y se lo llevaria por
                // delante, asi que la aplicacion se niega — y lo DICE, que es la
                // mitad que faltaba. Callarselo dejaba a quien pulsaba sin saber
                // si es que no habia cambios o que se estaba protegiendo su
                // trabajo.
                // EL GESTO QUE NO LLEGÓ AL SERVIDOR. Sólo en la web, donde
                // no hay cola que lo guarde para luego: si no subió, no está.
                // Va el PRIMERO de la franja porque es lo único de aquí que
                // exige hacer algo ahora mismo.
                // `watch` y no `read`: el rechazo llega DESPUES, con la
                // pantalla ya abierta, y con `read` no se repintaba nunca.
                if (ref.watch(loQueElServidorRechazoProvider).value
                    case final fallo?)
                  Text(
                    fallo,
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: ColoresTablero.ambar,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (ref.read(tableroProvider.notifier).porQueNoSeRefresca
                    case final pendiente?)
                  Text(
                    'No se actualiza: hay $pendiente. Se sube primero y '
                    'después se trae — así no se pierde nada.',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: ColoresTablero.ambar,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                // «Visto por ultima vez a las 10:41» — SOLO DONDE HAY UNA
                // COPIA QUE PUEDA ENVEJECER, o sea en la APK y el escritorio.
                //
                // En la web el tablero sale del servidor y se repinta solo en
                // cuanto algo cambia, asi que esa hora no avisa de nada: es la
                // hora de hace un segundo, puesta ahi para siempre. Y «Sin
                // descargar todavia» es directamente falso en un navegador.
                // Regla 1 del CLAUDE.md, y van cinco veces.
                else if (Destino.trabajaSinConexion)
                  Text(
                    tablero.vistoAt == null
                        ? 'Sin descargar todavía'
                        : 'Visto por última vez a las '
                              '${horaBonita(tablero.vistoAt!)}',
                    style: tema.textTheme.labelMedium?.copyWith(
                      color: tablero.vistoAt == null
                          ? ColoresTablero.ambar
                          : tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                // Tres contadores y no uno: se arreglan de tres maneras
                // distintas, y un numero unico obligaria a abrir las doce
                // columnas para saber cual es.
                if (avisos.archivados > 0)
                  insigniaGrave('${avisos.archivados} archivados en PEDIDO'),
                if (avisos.enOtraRuta > 0)
                  insigniaGrave('${avisos.enOtraRuta} ya en otra ruta'),
                if (avisos.sinFactura > 0)
                  insigniaGrave(
                    '${avisos.sinFactura} sin factura o sin cotejar',
                  ),
                if (avisos.cambiados > 0)
                  insigniaAviso('${avisos.cambiados} cambiaron en la factura'),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Traer lo del servidor',
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(
              ref.read(tableroProvider.notifier).bajarDelServidor(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Los que se llevo la cascada: se avisa UNA vez, con lo que se sabia de ellos
/// antes de que se fueran (§7.5).
class _AvisoDesaparecidos extends ConsumerWidget {
  const _AvisoDesaparecidos({required this.desaparecidos});

  final List<PedidoDesaparecido> desaparecidos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuantos = desaparecidos.length;
    final lista = desaparecidos
        .map(
          (d) =>
              '${d.operationNumber ?? d.pedidoId}'
              '${d.columna == null ? '' : ' (${d.columna})'}',
        )
        .join(', ');
    return MaterialBanner(
      backgroundColor: ColoresTablero.rojoFondo,
      content: Text(
        cuantos == 1
            ? '1 pedido que tenías puesto ya no está en PEDIDO: $lista'
            : '$cuantos pedidos que tenías puestos ya no están en PEDIDO: '
                  '$lista',
      ),
      actions: [
        TextButton(
          onPressed: () => unawaited(
            ref.read(tableroProvider.notifier).olvidarDesaparecidos(),
          ),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

/// Lo que no deja pintar el tablero, dicho con las palabras del pliego.
class _Problema extends StatelessWidget {
  const _Problema({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(texto, textAlign: TextAlign.center),
    ),
  );
}
