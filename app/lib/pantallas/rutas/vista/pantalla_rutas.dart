// La pantalla de Rutas. Es tres pantallas en una: lista y detalle, asistente de
// 4 pasos y cierre parada por parada.
//
// **Aqui vive el dia sin conexion.** Todo lo de esta pantalla —ver, filtrar,
// armar, iniciar, completar, eliminar y cerrar— funciona sin red: se escribe en
// la base local, se pinta como hecho y la cola sube por detras. Lo unico que no
// se puede hacer sin conexion es abrir el enlace de Google Maps, y los rechazos
// del servidor llegan tarde, al subir, y salen en la bandeja con su hora y su
// motivo. Nunca se descartan.

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

/// LA CLAVE DE LA BARRA DE VOLVER. Publica porque la prueba la pulsa.
const claveDeVolverALaLista = ValueKey('ruta-volver-a-la-lista');

class PantallaRutas extends ConsumerWidget {
  const PantallaRutas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pestana = ref.watch(pestanaRutasProvider);
    final contadores = ref.watch(contadoresDePestanaProvider);
    final elegida = ref.watch(rutaElegidaProvider);
    final filtros = ref.watch(filtrosRutasProvider);

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
                alCambiar: (i) => ref
                    .read(pestanaRutasProvider.notifier)
                    .elegir(PestanaRutas.values[i]),
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
                    alCambiar: (i) => ref
                        .read(pestanaRutasProvider.notifier)
                        .elegir(PestanaRutas.values[i]),
                    pagina: (contexto, i) =>
                        ListaDeRutas(deLaPestana: PestanaRutas.values[i]),
                  );
                  final detalle = elegida == null
                      ? const EstadoVacio(
                          'Selecciona una ruta para ver el detalle',
                        )
                      : DetalleDeRuta(rutaId: elegida);

                  // En escritorio: 3 columnas (1 lista + 2 detalle), cada una con
                  // su propio desplazamiento. En movil: una sola columna y la
                  // pagina se desplaza como cualquier otra —**sin** desplazamiento
                  // interno, para no tener dos scroll peleandose (§11).
                  if (!enEscritorio) {
                    if (elegida == null) return lista;
                    // LA SALIDA, FIJA Y ARRIBA DEL TODO.
                    //
                    // Jose, 17/09/2026: «toqué una ruta hecha para ver detalles
                    // y no puedo salir de esa ruta señalada». En el telefono el
                    // detalle SUSTITUYE a la lista, asi que si no hay un
                    // «volver» no queda nada a lo que volver — y hasta hoy la
                    // ruta elegida solo se soltaba al COMPLETARLA, que es algo
                    // que una ruta ya completada no puede hacer.
                    //
                    // Va aqui fuera y no dentro del detalle a proposito: el
                    // detalle es una lista que se desplaza, y una salida que se
                    // va hacia arriba al bajar dos dedos es una salida que no
                    // esta. Esta barra no se mueve.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _VolverALaLista(),
                        Divider(height: 1, thickness: 1, color: Colores.linea),
                        Expanded(child: detalle),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: lista),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 2, child: detalle),
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

/// LA BARRA DE VOLVER DEL MOVIL.
///
/// Un solo gesto y con su nombre escrito al lado: una flecha sola se confunde
/// con la del navegador, y la ✕ sola no dice a donde lleva.
class _VolverALaLista extends ConsumerWidget {
  const _VolverALaLista();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      key: claveDeVolverALaLista,
      onPressed: () => ref.read(rutaElegidaProvider.notifier).elegir(null),
      icon: const Icon(Icons.arrow_back, size: 18),
      label: const Text('Volver a la lista'),
    ),
  );
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
