// La columna izquierda: filtros y lista de rutas.
//
// Los filtros se aplican EN EL CLIENTE sobre las rutas ya traidas, como en la de
// Next, y las rutas ya traidas son las de la base local. Resultado: sin conexion
// se filtra y se pagina igual que con ella.

import 'package:flutter/material.dart';

import '../../../diseno/tema.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../nucleo/frescura/primera_bajada.dart';
import '../../../nucleo/frescura/reloj_de_datos.dart';
import '../../../nucleo/base/base.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';

class ListaDeRutas extends ConsumerWidget {
  const ListaDeRutas({this.deLaPestana, super.key});

  /// DE QUE PESTANA es esta lista. `null` = la que este elegida, que es lo de
  /// siempre.
  ///
  /// Se pide desde fuera porque en el movil las tres van en un `PageView`: la
  /// que se ve por el borde mientras el dedo arrastra **no** es la elegida
  /// todavia, y si se la preguntara al provider pintaria la que se esta
  /// dejando.
  final PestanaRutas? deLaPestana;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El tipo, escrito: sin el, `??` le da contexto anulable al `watch` y
    // Riverpod se lo cree.
    final PestanaRutas pestana = deLaPestana ?? ref.watch(pestanaRutasProvider);
    final rutas = ref.watch(rutasDePestanaProvider(pestana));
    final pagina = ref.watch(paginaRutasProvider);
    final descargadas = ref.watch(rutasDescargadasProvider).value;
    final vehiculos = {
      for (final v in ref.watch(vehiculosProvider).value ?? const <Vehiculo>[])
        v.id: v,
    };
    final sucursales = {
      for (final s in ref.watch(sucursalesProvider).value ?? const <Sucursal>[])
        s.id: s,
    };
    // UNA sola consulta agrupada para las veinte tarjetas, no una por tarjeta.
    // Mientras no llegue es `null`, y entonces la tarjeta **no escribe un
    // cero**: «0 paradas» se lee como «esta ruta va vacia», que es un
    // diagnostico y no un «todavia no se sabe».
    final paradasPorRuta = ref.watch(paradasPorRutaProvider).value;

    // Una lista vacia de una coleccion que nunca se bajo NO es «no hay rutas».
    //
    // Y en la web son TRES casos, no uno. Esta pantalla se quedo fuera de la
    // pasada que separo los tres —el aviso lo dejo escrito quien la hizo— y sin
    // esto la web ensena «Esta pantalla no se ha descargado todavia. Con
    // conexion baja sola» durante el primer segundo de cada carga, que es un
    // diagnostico falso y ademas en el idioma del aparato. Regla 1.
    //
    // La constante, no el literal: la misma frase escrita a mano en dos sitios
    // se separa en cuanto alguien cambie uno, y esta es la que ya usa Pedidos.
    if (descargadas == false) {
      return switch (ref.watch(porQueEstaVacioProvider)) {
        // El aparato: ahi «no se ha descargado» es un estado de verdad.
        PorQueEstaVacio.noSeDescargo => const EstadoVacio(
          SinDescargar.textoDeLaPantallaVacia,
        ),
        // La web, el primer segundo: cargando y nada mas.
        PorQueEstaVacio.todaviaBajando => EstadoVacio(
          TextosDeLaWeb.cargando('las rutas'),
        ),
        // Y si no llego, se dice y se deja entrar.
        PorQueEstaVacio.noPudoBajar => EstadoVacio(
          TextosDeLaWeb.noPudoBajar('las rutas'),
        ),
      };
    }
    if (rutas.isEmpty) return EstadoVacio(pestana.vacio);

    final desde = (pagina - 1) * ConsultasRutas.porPagina;
    final visibles = rutas.skip(desde).take(ConsultasRutas.porPagina).toList();

    // Se agrupa por sucursal **sólo si en la pagina hay mas de una**: con una
    // sola, repetir su nombre en cada encabezado es ruido.
    final conVariasSucursales =
        visibles.map((r) => r.branchId).toSet().length > 1;

    return ListView(
      // AIRE ABAJO. Era el unico `ListView` de la casa sin el —la columna del
      // tablero ya lleva 48—, y sin el la ultima tarjeta y la paginacion se
      // quedan pegadas al borde de la pantalla.
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        for (final grupo in _agrupar(visibles, conVariasSucursales)) ...[
          if (grupo.titulo != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                '${sucursales[grupo.titulo]?.name ?? 'Sin sucursal'} '
                '(${sucursales[grupo.titulo]?.externalId ?? '—'}) · '
                '${grupo.rutas.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          for (final ruta in grupo.rutas)
            _TarjetaDeRuta(
              ruta: ruta,
              vehiculo: vehiculos[ruta.vehicleId],
              paradas: paradasPorRuta == null
                  ? null
                  : (paradasPorRuta[ruta.id] ?? 0),
            ),
        ],
        Paginacion(
          pagina: pagina,
          porPagina: ConsultasRutas.porPagina,
          total: rutas.length,
          alIr: (n) => ref.read(paginaRutasProvider.notifier).ir(n),
        ),
      ],
    );
  }

  List<_Grupo> _agrupar(List<Ruta> rutas, bool agrupar) {
    if (!agrupar) return [_Grupo(null, rutas)];
    final porSucursal = <String?, List<Ruta>>{};
    for (final ruta in rutas) {
      porSucursal.putIfAbsent(ruta.branchId, () => <Ruta>[]).add(ruta);
    }
    return [
      for (final entrada in porSucursal.entries)
        _Grupo(entrada.key, entrada.value),
    ];
  }
}

class _Grupo {
  const _Grupo(this.titulo, this.rutas);

  final String? titulo;
  final List<Ruta> rutas;
}

/// LA TARJETA DE UNA RUTA, EN RENGLONES FIJOS.
///
/// Jose, 17/09/2026, comparando con el patrón: «ves, está más limpio, más
/// organizado, más uniformes, todas las cajas misma altura, los cuerpos no se
/// desintegran ni nada de eso ni se deforman».
///
/// Antes esto era **un solo párrafo** con los cinco datos pegados por puntos:
/// «68.0 km · camion (P-123) · 2da Paralela… · 12/06 · 5212,78 USD». Un párrafo
/// envuelve según lo largo que sea el nombre del camión y lo larga que sea la
/// dirección, así que cada tarjeta salía de una altura distinta y la columna
/// entera se veía temblando. De ahí lo de «se desintegran».
///
/// Ahora son **renglones fijos, uno por cosa, y cada uno de una sola línea**
/// (`maxLines: 1` + `ellipsis`). Con eso todas las tarjetas miden lo mismo
/// aunque un cliente se llame como para llenar dos renglones, y lo que no cabe
/// se corta con puntos suspensivos en vez de empujar lo de abajo.
///
/// El importe va solo y en grande al final, como en el patrón: es el dato que
/// se busca de un vistazo cuando se recorre la lista.
class _TarjetaDeRuta extends ConsumerWidget {
  const _TarjetaDeRuta({
    required this.ruta,
    required this.vehiculo,
    required this.paradas,
  });

  final Ruta ruta;
  final Vehiculo? vehiculo;

  /// Cuantas paradas lleva. `null` = todavia no ha llegado la cuenta; entonces
  /// **no se escribe un cero**, que se leeria como «esta ruta va vacia».
  final int? paradas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegida = ref.watch(rutaElegidaProvider) == ruta.id;
    final sobrepeso = vehiculo != null && ruta.totalWeight > vehiculo!.capacity;

    // La elegida se tine de primario y coge su borde: con el gris de antes, con
    // ocho rutas seguidas, no se veia cual estaba abierta a la derecha.
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      color: elegida ? Colores.primarioTenue : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radios.xl),
        side: BorderSide(
          color: elegida
              ? Colores.primario.withValues(alpha: 0.4)
              : Colores.linea,
        ),
      ),
      child: InkWell(
        onTap: () => ref.read(rutaElegidaProvider.notifier).elegir(ruta.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. El codigo y como esta. Los dos extremos del renglon, que es
              //    donde los busca el ojo al recorrer la columna.
              Row(
                children: [
                  Flexible(
                    child: Insignia(
                      ruta.routeCode ?? ruta.id,
                      color: Colores.enCurso,
                    ),
                  ),
                  const Spacer(),
                  Insignia(
                    switch (ruta.status) {
                      EstadoRuta.planificada => 'Planificada',
                      EstadoRuta.enCurso => 'En curso',
                      EstadoRuta.completada => 'Completada',
                      _ => ruta.status,
                    },
                    color: switch (ruta.status) {
                      EstadoRuta.planificada => Colores.ambar,
                      EstadoRuta.enCurso => Colores.enCurso,
                      EstadoRuta.completada => Colores.verde,
                      _ => Colores.gris,
                    },
                  ),
                ],
              ),
              // 2. El tamano de la ruta: cuantas paradas y cuanto se anda.
              const SizedBox(height: 6),
              _Renglon(
                texto: [
                  if (paradas != null) '$paradas ${paradas == 1 ? 'parada' : 'paradas'}',
                  '${ruta.totalDistance.toStringAsFixed(1)} km',
                  fechaCorta(ruta.deliveryDate),
                ].join(' · '),
                peso: FontWeight.w600,
              ),
              // 3. El camion. 4. De donde sale. Cada uno con su icono y en una
              //    sola linea: son los dos datos que mas se alargan.
              _Renglon(
                icono: Icons.local_shipping_outlined,
                texto: vehiculo == null
                    ? 'Sin vehículo'
                    : '${vehiculo!.name}'
                          '${vehiculo!.plate == null ? '' : ' (${vehiculo!.plate})'}',
              ),
              _Renglon(
                icono: Icons.place_outlined,
                texto: ruta.originAddress ?? 'Sin punto de partida',
              ),
              if (sobrepeso)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Insignia('Sobrepeso', color: Colores.ambar),
                ),
              // 5. El importe, solo y en grande. Y `Eliminar` a su derecha, en
              //    un renglon de alto fijo: sin eso, una ruta completada —que no
              //    lleva boton— saldria mas baja que la de al lado, que es
              //    justo lo que se venia a arreglar.
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Text(
                      usd(ruta.totalPrice),
                      style: Tipos.mono(
                        tamano: 15,
                        peso: FontWeight.w700,
                        color: Colores.primario,
                      ),
                    ),
                    const Spacer(),
                    if (ruta.status != EstadoRuta.completada)
                      TextButton(
                        onPressed: () async {
                          final mensajero = ScaffoldMessenger.maybeOf(context);
                          try {
                            await ref
                                .read(accionesDeRutaProvider)
                                .eliminar(ruta.id);
                          } on RechazoLocal catch (fallo) {
                            mensajero?.showSnackBar(
                              SnackBar(content: Text(fallo.mensaje)),
                            );
                          }
                        },
                        child: const Text('Eliminar'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// UN RENGLON DE LA TARJETA. Una sola linea, siempre, pase lo que pase con lo
/// que le metan: es lo unico que garantiza que dos tarjetas midan lo mismo.
///
/// **El que sujeta esto es `overflow: ellipsis`, no `maxLines: 1`.** Medido el
/// 17/09/2026 al mutarlo: quitando solo `maxLines` las dos tarjetas seguian
/// midiendo 152; quitando los dos, la de la direccion larga se iba a 216 — 64
/// pixeles de diferencia con la de al lado, que es justo lo que se ve como que
/// la columna tiembla. Se dejan los dos escritos porque juntos dicen la
/// intencion, pero **quien mute esto tiene que quitar los dos**: romper solo
/// `maxLines` sale verde y no prueba nada.
class _Renglon extends StatelessWidget {
  const _Renglon({required this.texto, this.icono, this.peso});

  final String texto;
  final IconData? icono;
  final FontWeight? peso;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        if (icono != null) ...[
          Icon(icono, size: 14, color: Colores.gris),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: peso),
          ),
        ),
      ],
    ),
  );
}
