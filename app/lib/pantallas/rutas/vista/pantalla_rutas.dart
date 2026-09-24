// La pantalla de Rutas. Es tres pantallas en una: lista y detalle, asistente de
// 4 pasos y cierre parada por parada.
//
// **Aqui vive el dia sin conexion.** Todo lo de esta pantalla —ver, filtrar,
// armar, iniciar, completar, eliminar y cerrar— funciona sin red: se escribe en
// la base local, se pinta como hecho y la cola sube por detras. Lo unico que no
// se puede hacer sin conexion es abrir el enlace de Google Maps, y los rechazos
// del servidor llegan tarde, al subir, y salen en la bandeja con su hora y su
// motivo. Nunca se descartan.
//
// ## PENDIENTE: los filtros de esta pantalla NO van en la dirección
//
// El contrato de `navegacion/pantalla_registrada.dart` dice que van:
//
// > **Los filtros van en la URL** (`estado.uri.queryParameters`) […] Lee de ahí
// > y escribe con `context.go(...)`; no guardes el filtro sólo en un `State`.
//
// `pantallas/rutas/registro.dart` tira el `GoRouterState` entero
// —`_construir` devuelve `const PantallaRutas()`— y la pestaña, el buscador, el
// vehículo y el rango de fechas viven sólo aquí dentro. En la web eso son dos
// cosas que se ven:
//
//  * mandar `/routes` a alguien no le lleva a lo que uno está mirando —ni
//    siquiera a la misma pestaña—, y
//  * **recargar borra los filtros sin decir nada**, que es el caso que el
//    encargo del 24/09/2026 manda probar («entrar por la URL de cada pantalla y
//    recargar estando dentro»).
//
// Hecho ya para Pedidos, y ahí está el molde entero, con el aviso de lo que un
// enlace trae y no se puede aplicar: `pantallas/pedidos/datos/filtros_en_la_url.dart`
// y su prueba `test/pantallas/pedidos/filtros_en_la_url_test.dart`.
//
// **Lo que cuesta traerlo aquí:** un fichero `datos/filtros_en_la_url.dart`
// propio (los filtros de Rutas son 5, no 11), una línea en `registro.dart`,
// pasar este widget a `ConsumerStatefulWidget` con su `initState` y su empuje
// de la dirección, y el par de pruebas. Medio día, del que la mitad es la
// pestaña: `Pestanas` guarda la suya en su propio estado y hay que dejarla
// leer de fuera sin perder el deslizamiento.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../diseno/caja_de_busqueda.dart';
import '../../../diseno/pestanas.dart';
import '../../../diseno/rango_de_fechas.dart';
import '../../../diseno/tema.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';
import 'asistente_nueva_ruta.dart';
import 'detalle_ruta.dart';
import 'lista_rutas.dart';

class PantallaRutas extends ConsumerWidget {
  const PantallaRutas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pestana = ref.watch(pestanaRutasProvider);
    final contadores = ref.watch(contadoresDePestanaProvider);
    final elegida = ref.watch(rutaElegidaProvider);
    final filtros = ref.watch(filtrosRutasProvider);

    // CAMBIAR DE PESTAÑA A MANO SUELTA LA RUTA ABIERTA.
    //
    // Medido el 22/09/2026 en un monitor: con `RT-…-002` abierta en el panel de
    // la derecha, pulsar `Historial` cambiaba la lista y **dejaba el panel
    // enseñando esa misma ruta**, que ya no estaba en la lista de al lado, con
    // su botón `Iniciar ruta` vivo. O sea, media pantalla hablando de una cosa y
    // la otra media de otra.
    //
    // El panel de la derecha es el detalle de algo de ESTA lista: si se cambia
    // de lista, no hay nada abierto.
    void irALaPestana(int i) {
      ref.read(pestanaRutasProvider.notifier).elegir(PestanaRutas.values[i]);
      ref.read(rutaElegidaProvider.notifier).elegir(null);
    }

    // Y LO MISMO DESLIZANDO, PERO SÓLO SI DE VERDAD LO MUEVE UNA PERSONA.
    //
    // El `PageView` avisa también cuando termina la animación de un cambio que
    // vino del código, y hay uno que NO puede soltar la ruta: `Iniciar ruta`
    // mueve la pestaña a `En curso` **y se lleva la ruta consigo** a propósito
    // (`detalle_ruta.dart`), para que no le desaparezca de delante a quien
    // acaba de arrancarla. En ese aviso el índice que llega ya es el que hay
    // puesto; en un deslizamiento de verdad, todavía no.
    void alDeslizar(int i) {
      if (PestanaRutas.values[i] == ref.read(pestanaRutasProvider)) return;
      irALaPestana(i);
    }

    // SIN `Scaffold` ni `AppBar` propios: los pone el armazon
    // (`navegacion/pantalla_registrada.dart`), que ya trae barra lateral, barra
    // superior con el titulo «Rutas» y franja de estado. Uno dentro de otro
    // apila dos superficies de Material y deja los avisos emergentes —los
    // rechazos del armado y el `Cierre guardado.`— colgando del de dentro.

    // EL BOTON DE ATRAS DEL SISTEMA TAMBIEN SUELTA LA RUTA.
    //
    // En un telefono ese es el primer gesto que hace la gente para salir de
    // algo, y aqui no servia: la ruta elegida es estado de un provider, no una
    // pagina del enrutador, asi que atras no la tocaba — se salia de Rutas
    // entera y al volver seguia elegida.
    //
    // `canPop: false` mientras haya una elegida: el primer atras la suelta y se
    // queda en Rutas; el segundo ya sale, como siempre.
    //
    // Desde el 22/09/2026 esto es la red de abajo, no la primera parada: en el
    // teléfono el detalle va en un cajón, que es una ruta del `Navigator` y se
    // come el «atrás» él mismo (y al cerrarse suelta la ruta). Esto sigue
    // sirviendo en escritorio, donde no hay cajón sino panel de al lado.
    return PopScope(
      canPop: elegida == null,
      onPopInvokedWithResult: (seFue, _) {
        if (seFue) return;
        ref.read(rutaElegidaProvider.notifier).elegir(null);
      },
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Aire.lg),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Planificador de Rutas',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // El reloj de datos de las colecciones de esta pantalla. La
                  // franja del armazon da la frescura global; esta da la de lo que
                  // se esta mirando.
                  const BarraDeDatos(colecciones: ColeccionesDePantalla.rutas),
                  FilledButton(
                    onPressed: () => abrirCajon<void>(
                      context,
                      (_) => const AsistenteNuevaRuta(),
                    ),
                    child: const Text('+ Nueva Ruta'),
                  ),
                ],
              ),
            ),
            // LAS TRES PESTANAS, SEGUN EL SITIO QUE HAYA: carrusel en un
            // teléfono, las tres a la vez en un monitor (ver
            // `PestanasQueCaben`).
            //
            // Antes eran tres botones sueltos dentro del `Wrap` del titulo, y
            // en un telefono las tres etiquetas con sus cuentas no caben en una
            // linea. Ahora sale el rotulo de la que se esta mirando y, debajo,
            // tres bolitas. Se cambia deslizando la lista, con las bolitas o
            // con las flechas.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Aire.sm),
              child: PestanasQueCaben(
                indice: pestana.index,
                etiquetas: [
                  for (final cual in PestanaRutas.values)
                    '${cual.etiqueta} (${contadores[cual] ?? 0})',
                ],
                alCambiar: irALaPestana,
              ),
            ),
            const _FiltrosDeLaLista(),
            if (filtros.hayAlguno)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      ref.read(filtrosRutasProvider.notifier).limpiar(),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Limpiar'),
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (contexto, medidas) {
                  final enEscritorio = medidas.maxWidth >= anchoEscritorio;
                  // LA LISTA, QUE SE CAMBIA DESLIZANDO EL DEDO.
                  //
                  // Las tres pestanas son tres listas del mismo tamano puestas en
                  // fila; deslizar a lo ancho pasa de una a la siguiente y el
                  // botoncito de arriba se enciende solo. El desplazamiento de
                  // cada lista es vertical, asi que los dos gestos no se pisan.
                  final lista = CuerpoDeslizable(
                    indice: pestana.index,
                    cuantas: PestanaRutas.values.length,
                    alCambiar: alDeslizar,
                    pagina: (contexto, i) =>
                        ListaDeRutas(deLaPestana: PestanaRutas.values[i]),
                  );

                  // EN MÓVIL, EL DETALLE VA EN UN CAJÓN Y NO AQUÍ DENTRO.
                  //
                  // Jose, 22/09/2026: «cuando estoy viendo un detalle de una
                  // ruta me puedo mover por los diferentes tabs eso no lo
                  // quiero ponlo en un drawer en el movil». El porqué entero
                  // está en `CajonDelDetalleDeRuta`; lo que hay que saber aquí
                  // es que **esta columna sigue siendo la lista y nada más**,
                  // pase lo que pase con la ruta elegida.
                  //
                  // Se mide con `medidas.maxWidth`, que es el ancho que de
                  // verdad le queda a la pantalla dentro del armazón, y no con
                  // el de la ventana: con la barra lateral fija puesta, los dos
                  // números no son el mismo y quien decide la forma tiene que
                  // ser el mismo que decide si hay sitio para dos columnas.
                  if (!enEscritorio) {
                    return _LaListaConSuCajon(lista: lista);
                  }

                  // En escritorio: 3 columnas (1 lista + 2 detalle), cada una con
                  // su propio desplazamiento.
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: lista),
                      const VerticalDivider(width: 1),
                      Expanded(
                        flex: 2,
                        child: elegida == null
                            ? const EstadoVacio(
                                'Selecciona una ruta para ver el detalle',
                              )
                            : DetalleDeRuta(rutaId: elegida),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// LA LISTA DEL MÓVIL, QUE ABRE EL DETALLE EN UN CAJÓN.
///
/// Lo único que pinta es la lista; lo que hace es **vigilar la ruta elegida** y
/// abrir [CajonDelDetalleDeRuta] en cuanto haya una.
///
/// Va atado a `rutaElegidaProvider` y no al gesto de tocar una tarjeta porque
/// tocar una tarjeta no es el único sitio que elige ruta: el asistente elige la
/// que acaba de armar (`asistente_nueva_ruta.dart`), y ésa también tiene que
/// abrirse en el teléfono. Una sola puerta, no dos.
///
/// **Después del fotograma, nunca dentro.** Dos motivos y los dos hacen daño:
/// meter una ruta en el `Navigator` en plena construcción del árbol es el
/// «markNeedsBuild called during build» de siempre, y además el asistente hace
/// `elegir(rutaId)` y a renglón seguido `maybePop()` para cerrarse él — si el
/// cajón del detalle se abriera en medio, ese `maybePop` cerraría el detalle
/// recién abierto en vez del asistente.
class _LaListaConSuCajon extends ConsumerStatefulWidget {
  const _LaListaConSuCajon({required this.lista});

  final Widget lista;

  @override
  ConsumerState<_LaListaConSuCajon> createState() => _LaListaConSuCajonState();
}

class _LaListaConSuCajonState extends ConsumerState<_LaListaConSuCajon> {
  /// Para no abrir dos cajones encima del mismo detalle. Pasa de verdad: cuando
  /// una ruta provisional sube, su id cambia con el cajón ya abierto
  /// (`RutaElegida`), y eso es otro aviso más del provider.
  bool _abierto = false;

  @override
  void initState() {
    super.initState();
    // `ref.listen` sólo cuenta los cambios de aquí en adelante, así que una ruta
    // que YA venía elegida —se encogió la ventana, o se llega desde el
    // asistente— no abriría nada.
    if (ref.read(rutaElegidaProvider) != null) _abrirElCajon();
  }

  void _abrirElCajon() {
    if (_abierto) return;
    _abierto = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Entre el aviso y el fotograma puede haberse soltado la ruta: un cajón
      // vacío es peor que ninguno.
      if (!mounted || ref.read(rutaElegidaProvider) == null) {
        _abierto = false;
        return;
      }
      unawaited(
        abrirCajon<void>(context, (_) => const CajonDelDetalleDeRuta()).then((
          _,
        ) {
          _abierto = false;
          // CERRAR EL CAJÓN ES SOLTAR LA RUTA. Da igual por dónde se haya
          // cerrado —la ✕, el velo, el botón de atrás del teléfono—: si no se
          // soltara, la tarjeta se quedaría marcada en la lista y volver a
          // tocarla no abriría nada, porque el provider no cambiaría de valor.
          if (mounted) ref.read(rutaElegidaProvider.notifier).elegir(null);
        }),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(rutaElegidaProvider, (_, ahora) {
      if (ahora != null) _abrirElCajon();
    });
    return widget.lista;
  }
}

class _FiltrosDeLaLista extends ConsumerWidget {
  const _FiltrosDeLaLista();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtros = ref.watch(filtrosRutasProvider);
    final notas = ref.read(filtrosRutasProvider.notifier);
    final vehiculos = ref.watch(vehiculosProvider).value ?? const <Vehiculo>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Igual que la de Pedidos: busca sola y **se vacia cuando
          // `Limpiar` vacia los filtros**, en vez de quedarse un texto
          // filtrando en silencio.
          CajaDeBusqueda(
            valor: filtros.q,
            ancho: 260,
            pista: 'Buscar por código, nombre, vehículo...',
            alBuscar: (t) => notas.poner(
              FiltrosRutas(
                q: t,
                vehiculoId: filtros.vehiculoId,
                desde: filtros.desde,
                hasta: filtros.hasta,
              ),
            ),
          ),
          Selector<String>(
            titulo: 'Rutas de un camión',
            valor: filtros.vehiculoId,
            opciones: [
              const OpcionSelector('', 'Cualquier vehículo'),
              for (final v in vehiculos)
                OpcionSelector(
                  v.id,
                  v.name,
                  nota: v.status == EstadoVehiculo.enUso ? 'en ruta' : null,
                ),
            ],
            alElegir: (id) => notas.poner(
              FiltrosRutas(
                q: filtros.q,
                vehiculoId: id,
                desde: filtros.desde,
                hasta: filtros.hasta,
              ),
            ),
          ),
          // Las dos fechas sobre `createdAt`. El filtro ya se aplicaba en
          // `filtrarRutas`; lo que faltaba era con que ponerlo. Sin `sólo ese
          // día`: eso es de Pedidos (pliego §2), aqui el pliego (§3) sólo pide
          // `Desde` y `Hasta`.
          RangoDeFechas(
            desde: filtros.desde,
            hasta: filtros.hasta,
            conSoloEseDia: false,
            // El reloj de la aplicacion, no el del sistema: el calendario se
            // abre por el mismo «hoy» que usa todo lo demas.
            hoy: ref.watch(relojProvider)(),
            alCambiar: (desde, hasta) => notas.poner(
              FiltrosRutas(
                q: filtros.q,
                vehiculoId: filtros.vehiculoId,
                desde: desde,
                hasta: hasta,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
