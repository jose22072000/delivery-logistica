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

    // SIN `Scaffold` ni `AppBar` propios: los pone el armazon
    // (`navegacion/pantalla_registrada.dart`), que ya trae barra lateral, barra
    // superior con el titulo «Rutas» y franja de estado. Uno dentro de otro
    // apila dos superficies de Material y deja los avisos emergentes —los
    // rechazos del armado y el `Cierre guardado.`— colgando del de dentro.
    return SafeArea(
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
                for (final cual in PestanaRutas.values)
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(pestanaRutasProvider.notifier).elegir(cual),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cual == pestana
                          ? Colores.azul
                          : Colores.gris,
                    ),
                    child: Text('${cual.etiqueta} (${contadores[cual] ?? 0})'),
                  ),
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
                final lista = const ListaDeRutas();
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
                  return elegida == null ? lista : detalle;
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
    );
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
