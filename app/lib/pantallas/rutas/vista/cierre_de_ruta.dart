// El cierre parada por parada. **Es el caso de uso principal del proyecto.**
//
// El camion vuelve al patio del almacen, donde no hay senal, y hay que cuadrar lo
// que baja. Asi que aqui no se espera a nadie: se marca, se guarda en la base
// local con la hora del aparato, se encola el apunte y la pantalla se pinta como
// hecha. Si hay red, sube por detras; si no, sube manana y sigue diciendo la hora
// de hoy.
//
// Pliego: `../../../../docs/pantallas.md` §9.1.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../impresion/armar_post_despacho.dart' as papel;
import '../../../impresion/post_despacho.dart' show pdfPostDespacho;
import '../../../impresion/vista_previa.dart';
import '../../../nucleo/base/base.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../datos/post_despacho.dart';
import '../datos/repositorio_rutas.dart';
import '../estado/proveedores_rutas.dart';

/// EN QUE MOMENTO SE ABRE EL CIERRE. Son tres, y no es lo mismo.
enum ModoDelCierre {
  /// La ruta esta EN CURSO y se va marcando parada a parada segun se reparte.
  /// Es el modo de siempre: se guarda lo marcado y la ruta sigue en curso.
  marcar,

  /// Se acaba de pulsar `Marcar como completada` y **quedan paradas sin
  /// marcar**. Aqui se pregunta como acabaron y, al guardar, la ruta se da por
  /// completada en el mismo gesto.
  alCompletar,

  /// La ruta ya esta COMPLETADA: el cierre solo se mira.
  soloLectura,
}

class CierreDeRuta extends ConsumerStatefulWidget {
  const CierreDeRuta({
    required this.rutaId,
    this.modo = ModoDelCierre.marcar,
    this.alCompletar,
    super.key,
  });

  final String rutaId;

  /// Ver `ModoDelCierre`.
  final ModoDelCierre modo;

  /// Lo que hace la pantalla DESPUES de completar, en el modo `alCompletar`:
  /// soltar la ruta elegida e irse al Historial. Vive fuera porque es
  /// navegacion de la pantalla de Rutas, no del cajon.
  final VoidCallback? alCompletar;

  /// La cabecera, literal. Explica la regla que mas se malinterpreta: lo que no
  /// se entrego sigue arriba, y lo devuelto no toca inventario —eso lo hace
  /// Ventra—, aqui queda la constancia.
  static const cabecera =
      'Marca cada parada según cómo acabó. De aquí sale el post-despacho: lo que '
      'tiene que quedar en el camión es todo lo que no se entregó. Lo devuelto y '
      'lo cancelado no tocan el inventario —eso lo hace Ventra—: aquí queda la '
      'constancia y el control de lo que baja.';

  static const exito =
      'Cierre guardado. En PEDIDO cada pedido ya dice si se entregó o volvió.';

  /// LA CABECERA DEL MODO `alCompletar`, literal.
  ///
  /// Jose, 17/09/2026, mirando el cierre de una ruta ya completada: «ese estado
  /// se pone cuando están en ruta, no completados; ahí el cierre ya viene con el
  /// estado de cuando le van a dar a completado, es que se pregunta ese estado».
  static const cabeceraAlCompletar =
      'Antes de dar la ruta por completada: ¿cómo acabó cada parada? Lo que '
      'dejes sin marcar se da por no entregado y cuenta como que sigue en el '
      'camión.';

  /// LA CABECERA DEL MODO `soloLectura`, literal. Una ruta completada ya no se
  /// marca: lo que se ve es como acabo.
  static const cabeceraSoloLectura =
      'La ruta ya está completada: así acabó cada parada. Para corregir algo, '
      'hay que hacerlo en PEDIDO.';

  static const exitoAlCompletar =
      'Cierre guardado y ruta completada. En PEDIDO cada pedido ya dice si se '
      'entregó o volvió.';

  @override
  ConsumerState<CierreDeRuta> createState() => _CierreDeRutaState();
}

class _CierreDeRutaState extends ConsumerState<CierreDeRuta> {
  /// Lo marcado en esta sesion. `null` en el mapa = sin marcar.
  final _resultados = <String, String?>{};
  final _notas = <String, TextEditingController>{};
  bool _partidoDeLoGuardado = false;
  bool _guardando = false;

  @override
  void dispose() {
    for (final control in _notas.values) {
      control.dispose();
    }
    super.dispose();
  }

  /// **Al abrir se parte de lo ya guardado en cada parada** (resultado y nota).
  /// Sin esto, reabrir el cierre para corregir una parada borraria las otras
  /// veinte de la vista y habria que marcarlas otra vez.
  void _partirDeLoGuardado(List<Pedido> paradas) {
    // **`paradas.isEmpty` no es «ninguna parada»: casi siempre es «todavia no han
    // llegado».** Las paradas vienen de un flujo de la base y el primer
    // fotograma se pinta con la lista vacia. Dandolo por bueno se marcaba el
    // arranque como hecho contra cero paradas, y cuando llegaban de verdad ya no
    // se volvia a mirar: reabrir el cierre para corregir UNA parada ensenaba las
    // otras veinte sin marcar, como si no se hubiera guardado nada.
    if (_partidoDeLoGuardado || paradas.isEmpty) return;
    _partidoDeLoGuardado = true;
    for (final parada in paradas) {
      _resultados[parada.id] = parada.resultado;
      _notas[parada.id] = TextEditingController(
        text: parada.resultadoNota ?? '',
      );
    }
  }

  TextEditingController _nota(String pedidoId) =>
      _notas.putIfAbsent(pedidoId, TextEditingController.new);

  int get _marcadas => _resultados.values.where((r) => r != null).length;

  bool get _soloLectura => widget.modo == ModoDelCierre.soloLectura;
  bool get _completando => widget.modo == ModoDelCierre.alCompletar;

  void _marcar(String pedidoId, String resultado) => setState(() {
    // **Pulsar el mismo boton dos veces desmarca.** Es como se corrige un dedazo
    // sin tener que recargar nada.
    _resultados[pedidoId] = _resultados[pedidoId] == resultado
        ? null
        : resultado;
  });

  void _todas(String resultado, List<Pedido> paradas) => setState(() {
    for (final parada in paradas) {
      _resultados[parada.id] = resultado;
    }
  });

  Future<void> _guardar(List<Pedido> paradas) async {
    final marcas = <MarcaDeParada>[
      for (final parada in paradas)
        if (_resultados[parada.id] != null)
          MarcaDeParada(
            pedidoId: parada.id,
            resultado: _resultados[parada.id]!,
            nota: _nota(parada.id).text,
          ),
    ];
    final completando = widget.modo == ModoDelCierre.alCompletar;
    // Sin nada marcado no hay nada que guardar **y no pasa nada**: se puede dar
    // una ruta por completada dejando paradas sin marcar, que es como se dice
    // «eso siguio en el camion». Lo que no se puede es salir sin hacer nada,
    // por eso el `return` solo vale fuera del modo de completar.
    if (marcas.isEmpty && !completando) return;

    setState(() => _guardando = true);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final navegador = Navigator.of(context);
    try {
      // Sin `await` a ninguna red: esto escribe en la base y encola. Lo que
      // tarda es un `INSERT`.
      final acciones = ref.read(accionesDeRutaProvider);
      if (marcas.isNotEmpty) {
        await acciones.cerrar(widget.rutaId, marcas);
      }
      // **Completar va DESPUES de guardar, y solo si guardar salio bien.** Al
      // reves, un rechazo del cierre dejaria la ruta dada por cerrada con las
      // paradas sin marcar.
      if (completando) await acciones.completar(widget.rutaId);
      mensajero?.showSnackBar(
        SnackBar(
          content: Text(
            completando ? CierreDeRuta.exitoAlCompletar : CierreDeRuta.exito,
          ),
        ),
      );
      navegador.maybePop();
      if (completando) widget.alCompletar?.call();
    } on RechazoLocal catch (fallo) {
      // El mensaje del servidor, literal y sin envolver.
      mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ruta = ref.watch(rutaConTodoProvider(widget.rutaId)).value;
    final paradas =
        ref.watch(paradasDeRutaProvider(widget.rutaId)).value ??
        const <Pedido>[];
    final renglones =
        ref.watch(renglonesDeParadasProvider(widget.rutaId)).value ??
        const <String, List<RenglonConPeso>>{};

    _partirDeLoGuardado(paradas);

    final sinMarcar = paradas.where((p) => _resultados[p.id] == null).length;
    final hoja = armarPostDespacho([
      for (final parada in paradas)
        ParadaDelCierre(
          pedidoId: parada.id,
          cliente: parada.customerName,
          resultado: _resultados[parada.id],
          lineas: [
            for (final r in renglones[parada.id] ?? const <RenglonConPeso>[])
              LineaDeParada(r.renglon.description, r.empaques),
          ],
        ),
    ]);

    return Cajon(
      titulo: 'Cierre de ruta',
      subtitulo:
          '${ruta?.ruta.routeCode ?? ruta?.ruta.name ?? widget.rutaId} · '
          '${paradas.length} parada(s)',
      ancho: AnchoCajon.xl,
      pie: Row(
        children: [
          OutlinedButton(
            onPressed: () => _verPostDespacho(
              ruta: ruta,
              paradas: paradas,
              renglones: renglones,
            ),
            child: const Text('Post-despacho'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cerrar'),
          ),
          // **En una ruta completada no hay boton de guardar.** No es que este
          // apagado: no esta. Un boton apagado invita a buscar como encenderlo.
          if (!_soloLectura) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _guardando || (_marcadas == 0 && !_completando)
                  ? null
                  : () => _guardar(paradas),
              child: Text(
                _guardando
                    ? 'Guardando…'
                    : _completando
                    ? 'Guardar y completar'
                    : 'Guardar $_marcadas marcada(s)',
              ),
            ),
          ],
        ],
      ),
      cuerpo: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(switch (widget.modo) {
              ModoDelCierre.marcar => CierreDeRuta.cabecera,
              ModoDelCierre.alCompletar => CierreDeRuta.cabeceraAlCompletar,
              ModoDelCierre.soloLectura => CierreDeRuta.cabeceraSoloLectura,
            }),
            const SizedBox(height: 12),
            if (!_soloLectura)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Todas:'),
                  for (final atajo in const [
                    (ResultadoParada.entregado, 'Entregado'),
                    (ResultadoParada.devuelto, 'Devuelto'),
                    (ResultadoParada.cancelado, 'Cancelado'),
                  ])
                    OutlinedButton(
                      onPressed: () => _todas(atajo.$1, paradas),
                      child: Text(atajo.$2),
                    ),
                ],
              ),
            if (sinMarcar > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '$sinMarcar sin marcar · cuentan como que siguen en el camión',
                  style: TextStyle(color: Colores.ambar),
                ),
              ),
            const SizedBox(height: 12),
            for (var i = 0; i < paradas.length; i++)
              _Parada(
                numero: paradas[i].stopOrder ?? (i + 1),
                pedido: paradas[i],
                resultado: _resultados[paradas[i].id],
                nota: _nota(paradas[i].id),
                soloLectura: _soloLectura,
                alMarcar: (cual) => _marcar(paradas[i].id, cual),
              ),
            const SizedBox(height: 16),
            _QuedaEnElCamion(hoja: hoja),
          ],
        ),
      ),
    );
  }

  /// La hoja imprimible del post-despacho, **con lo marcado en este momento**
  /// aunque todavia no se haya guardado: es lo que quien descarga tiene en la
  /// mano mientras cuenta, y esperar a guardar seria pedirle que cuente de
  /// memoria.
  ///
  /// Aqui estaba el hueco: la cuenta y el PDF existian los dos y estaban
  /// probados, pero el boton abria una tabla en un cajon. Sin papel no hay
  /// firma del chofer de lo que volvio en el camion.
  ///
  /// La cuenta se rehace con `armarPostDespacho` de `lib/impresion/`, que es el
  /// que come la hoja: es la MISMA regla de `reglas-negocio.md` §12 que la de
  /// `datos/post_despacho.dart` —empaques con respaldo a unidades, lo sin
  /// marcar cuenta como que sigue arriba—, y las dos estan probadas contra los
  /// mismos numeros.
  void _verPostDespacho({
    required RutaConTodo? ruta,
    required List<Pedido> paradas,
    required Map<String, List<RenglonConPeso>> renglones,
  }) {
    final hoja = papel.armarPostDespacho(
      papel.DatosDeRuta(
        ruta: ruta?.ruta.routeCode ?? ruta?.ruta.name ?? widget.rutaId,
        sucursal: ruta?.sucursal?.name ?? '',
        vehiculo: ruta?.vehiculo?.name ?? '',
        // Sin salida no se escribe linea de horario, y el regreso no va solo:
        // igual que en la de Next.
        salida: ruta?.ruta.startedAt == null
            ? null
            : fechaYHora(ruta!.ruta.startedAt),
        regreso: ruta?.ruta.finishedAt == null
            ? null
            : fechaYHora(ruta!.ruta.finishedAt),
      ),
      <papel.PedidoDeRuta>[
        for (final parada in paradas)
          papel.PedidoDeRuta(
            customerName: parada.customerName,
            resultado: _resultados[parada.id],
            resultadoNota: _notas[parada.id]?.text,
            items: <papel.ItemDePedido>[
              for (final r in renglones[parada.id] ?? const <RenglonConPeso>[])
                papel.ItemDePedido(
                  description: r.renglon.description,
                  packs: r.renglon.packs,
                  quantity: r.renglon.quantity,
                ),
            ],
          ),
      ],
    );

    abrirCajon<void>(
      context,
      (contexto) => Cajon(
        titulo: 'Post-despacho',
        subtitulo:
            '${hoja.entregadas} entregadas · ${hoja.devueltas} devueltas · '
            '${hoja.canceladas} canceladas · ${hoja.sinMarcar} sin marcar',
        ancho: AnchoCajon.xl,
        // El cuerpo del cajon se desplaza, asi que no tiene alto que dar; la
        // vista previa necesita uno concreto para pintar la hoja.
        cuerpo: SizedBox(
          height: MediaQuery.sizeOf(contexto).height * 0.75,
          child: VistaPreviaPdf(
            armar: (formato) =>
                pdfPostDespacho(hoja, impresoEn: DateTime.now()),
            nombreDeFichero: 'post-despacho.pdf',
          ),
        ),
      ),
    );
  }
}

class _Parada extends StatelessWidget {
  const _Parada({
    required this.numero,
    required this.pedido,
    required this.resultado,
    required this.nota,
    required this.soloLectura,
    required this.alMarcar,
  });

  final int numero;
  final Pedido pedido;
  final String? resultado;
  final TextEditingController nota;

  /// La ruta ya esta completada: como acabo esta parada se mira, no se toca.
  final bool soloLectura;
  final void Function(String) alMarcar;

  /// Como se llama cada resultado y de que color va, en un solo sitio: la
  /// insignia de solo lectura y los tres botones decian lo mismo por separado.
  static final nombres = <String, (String, Color)>{
    ResultadoParada.entregado: ('Entregado', Colores.verde),
    ResultadoParada.devuelto: ('Devuelto', Colores.rojo),
    ResultadoParada.cancelado: ('Cancelado', Colores.gris),
  };

  /// LO QUE DICE UNA PARADA SIN MARCAR EN UNA RUTA YA CERRADA. No es «nada»:
  /// es que ese bulto volvio al almacen, que es lo que cuadra el post-despacho.
  static const sinMarcarEnCerrada = 'Sin marcar · siguió en el camión';

  @override
  Widget build(BuildContext context) {
    final pideMotivo =
        resultado == ResultadoParada.devuelto ||
        resultado == ResultadoParada.cancelado;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 14, child: Text('$numero')),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pedido.customerName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        pedido.endAddress ?? pedido.address,
                        style: TextStyle(color: Colores.gris),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (soloLectura)
              // SIN BOTONES, NI SIQUIERA APAGADOS. En una ruta completada el
              // resultado es un dato, no una eleccion.
              Insignia(
                nombres[resultado]?.$1 ?? sinMarcarEnCerrada,
                color: nombres[resultado]?.$2 ?? Colores.ambar,
              )
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final cual in const [
                    ResultadoParada.entregado,
                    ResultadoParada.devuelto,
                    ResultadoParada.cancelado,
                  ])
                    _BotonResultado(
                      texto: nombres[cual]!.$1,
                      color: nombres[cual]!.$2,
                      elegido: resultado == cual,
                      alPulsar: () => alMarcar(cual),
                    ),
                ],
              ),
            if (soloLectura) ...[
              // La nota tambien se mira: es el «por que volvio», y en una ruta
              // cerrada es la unica explicacion que queda de lo que paso.
              if (nota.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(nota.text.trim(), style: TextStyle(color: Colores.gris)),
              ],
            ] else if (pideMotivo) ...[
              const SizedBox(height: 8),
              TextField(
                controller: nota,
                maxLength: AccionesDeRuta.topeDeNota,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText:
                      '¿Por qué volvió? (el cliente cerró, no lo quiso, '
                      'no había nadie…)',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BotonResultado extends StatelessWidget {
  const _BotonResultado({
    required this.texto,
    required this.color,
    required this.elegido,
    required this.alPulsar,
  });

  final String texto;
  final Color color;
  final bool elegido;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) => elegido
      ? FilledButton(
          onPressed: alPulsar,
          style: FilledButton.styleFrom(backgroundColor: color),
          child: Text(texto),
        )
      : OutlinedButton(
          onPressed: alPulsar,
          style: OutlinedButton.styleFrom(foregroundColor: color),
          child: Text(texto),
        );
}

/// La vista previa en vivo de lo que baja del camion. Se recalcula con cada
/// marca, sin guardar nada: es la comprobacion que hace quien descarga antes de
/// firmar.
class _QuedaEnElCamion extends StatelessWidget {
  const _QuedaEnElCamion({required this.hoja});

  final HojaPostDespacho hoja;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Queda en el camión',
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      if (hoja.lineas.isEmpty)
        const Text('Nada: se entregó todo lo que salió.')
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final linea in hoja.lineas)
              Insignia(
                '${linea.producto} ×${cantidad(linea.queda)}',
                color: Colores.ambar,
              ),
          ],
        ),
    ],
  );
}
