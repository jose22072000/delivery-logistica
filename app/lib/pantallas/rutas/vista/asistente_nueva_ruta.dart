// El asistente «Nueva Ruta»: cajon a pantalla completa con pie fijo y 4 pasos
// —Sucursal, Salida, Vehículo, Pedidos—.
//
// **Funciona entero sin conexion**, y eso no es un extra: armar la ruta pasa en
// el patio del almacen. Los pedidos elegibles salen de la base local, la
// capacidad se comprueba aqui, el orden de visita y los km los calcula el
// aparato (`geo.dart`) y la ruta se guarda con un id `local-…` y su propio
// codigo. Lo que el servidor diga llegara despues, y si dice que no, saldra en la
// bandeja de rechazos con su hora y su motivo.
//
// Pliego: `../../../../docs/pantallas.md` §3, «Asistente Nueva Ruta».

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../impresion/hoja.dart' as papel;
import '../../../impresion/pre_despacho.dart' show pdfPreDespacho;
import '../../../impresion/vista_previa.dart';
import '../../../diseno/anchos.dart';
import '../../../diseno/tema.dart';
import '../../../nucleo/base/base.dart';
import '../../../nucleo/proveedores.dart';
import '../../pedidos/datos/formato.dart';
import '../../pedidos/datos/repositorio_pedidos.dart';
import '../../pedidos/estado/proveedores_pedidos.dart';
import '../../pedidos/vista/kit.dart';
import '../datos/acciones_rutas.dart';
import '../datos/meter_la_zona.dart';
import '../datos/repositorio_rutas.dart';
import '../../tablero/estado/proveedores.dart';
import '../estado/proveedores_rutas.dart';

class AsistenteNuevaRuta extends ConsumerStatefulWidget {
  const AsistenteNuevaRuta({super.key});

  static const sinAlmacenes =
      'Esta sucursal no tiene ningún almacén con ubicación. Se pone en '
      'Almacenes, y hasta entonces no hay desde dónde medir.';

  static const sinVehiculos =
      'No hay vehículos disponibles. Crea o libera uno en Vehículos para poder '
      'crear la ruta.';

  /// Los dos botones que sacan del callejón. Un paso que no se puede terminar
  /// **tiene que llevar al sitio donde se arregla**: nombrar la pantalla y
  /// dejar ahí a alguien es obligarle a salir, buscarla en el menú, hacerlo y
  /// volver a empezar el asistente desde el paso 1.
  static const irAVehiculos = 'Agregar el primer vehículo';
  static const irAAlmacenes = 'Poner el almacén';

  static const sinPedidos = 'No hay pedidos disponibles para rutear.';

  static const cargandoPedidos = 'Cargando pedidos...';

  static const preDespachoVacio =
      'Según vayas eligiendo pedidos, aquí sale cuánto hay que sacar de cada '
      'producto.';

  /// LOS CUATRO PASOS, con el nombre que sale bajo su tramo de la barra.
  static const pasos = <int, String>{
    1: 'Sucursal',
    2: 'Salida',
    3: 'Vehículo',
    4: 'Pedidos',
  };

  /// La tarjeta del paso `n`. La usan las pruebas para decir «estoy en el 2»
  /// sin depender del texto del título, que es lo que más se retoca.
  static Key claveDelPaso(int n) => ValueKey('paso-$n');

  /// El tramo `n` de la barra de progreso, el que se pulsa para volver.
  static Key claveDelTramo(int n) => ValueKey('tramo-$n');

  /// LA CAJA DE LA LISTA DE PEDIDOS.
  ///
  /// Es la pieza que arregla la queja de Jose del 17/09/2026: «no me digas que
  /// está abajo del todo y tengo que bajar por todos los pedidos, que es una
  /// lista larga a la cual no me le has puesto ni paginación». La lista estaba
  /// suelta dentro del desplazamiento del cajón, así que con 295 pedidos el
  /// resumen y el botón de generar quedaban a cientos de píxeles hacia abajo.
  ///
  /// Con la caja acotada **la lista se desplaza dentro de ella** y lo de debajo
  /// —el resumen y el pie— no se mueve de sitio. Por eso la de Next no necesita
  /// paginación: `max-h-64 overflow-y-auto`, lo mismo que esto.
  static const claveDeLaLista = ValueKey('caja-de-la-lista');

  /// La línea fija de debajo de la lista: cuántos van y cuánto pesan.
  static const claveDelResumen = ValueKey('resumen-de-lo-elegido');

  /// La caja del pre-despacho. En escritorio va al lado de la lista; por debajo
  /// de [anchoDosColumnas], debajo.
  static const claveDelPreDespacho = ValueKey('caja-del-pre-despacho');

  /// El alto de la caja de la lista. El `max-h-64` de la de Next son 256 px;
  /// aquí hay 320 porque las filas llevan una línea más (los artículos).
  static const altoDeLaLista = 320.0;

  /// Por debajo de este ancho **dentro de la tarjeta** el pre-despacho cae
  /// debajo de la lista. No es el ancho de la pantalla: la tarjeta vive dentro
  /// del cajón y con sus márgenes, y lo que decide si caben dos columnas es lo
  /// que mide ELLA.
  static const anchoDosColumnas = 900.0;

  /// El ancho de la columna del pre-despacho: las `22rem` de la de Next.
  static const anchoPreDespacho = 352.0;

  /// EL ANCHO DE CADA FILTRO, y es el mismo para todos a propósito.
  ///
  /// Eran un `Wrap` de pastillas de anchos distintos —220 el buscador, 110 los
  /// números, y cada selector lo que midiera su texto—, y eso en pantalla se
  /// desmigaja: filas con tres cachos de distinto tamaño, huecos irregulares y
  /// la altura saltando al cambiar un texto. Palabras de Jose: «las cajas no
  /// uniformes, los cuerpos se deforman». Con un ancho único las filas salen
  /// en columnas alineadas a la izquierda y se recorren de un vistazo.
  static const anchoFiltro = 220.0;

  @override
  ConsumerState<AsistenteNuevaRuta> createState() => _AsistenteState();
}

class _AsistenteState extends ConsumerState<AsistenteNuevaRuta> {
  int _paso = 1;
  String? _sucursalId;
  Almacen? _salida;
  String? _vehiculoId;
  DateTime? _fechaDeEntrega;
  final _nombre = TextEditingController();
  final _buscador = TextEditingController();
  Timer? _espera;

  /// EL DESPLAZAMIENTO DE LA CAJA DE LA LISTA, y es SUYO.
  ///
  /// Dos cosas a la vez. La primera: sin un controlador propio la lista se
  /// engancha al `PrimaryScrollController`, que ya es el del cuerpo del cajón, y
  /// entonces son dos desplazamientos peleándose por el mismo gesto. La segunda:
  /// marcar un pedido es un `setState`, y con el controlador aquí la lista se
  /// queda donde estaba en vez de volverse al principio en cada clic.
  final _desplazamientoDeLaLista = ScrollController();

  /// Lo elegido, **con el pedido dentro y no sólo su id**.
  ///
  /// Hace falta guardarlo entero porque un pedido elegido puede dejar de salir
  /// en la lista al cambiar de dia o de vendedor, y sigue contando: su peso
  /// sigue en el camion y tiene que seguir sumando en la barra de capacidad. Con
  /// un `Set<String>` el peso de esos se perdia y el camion parecia mas vacio de
  /// lo que iba a salir.
  final _elegidos = <String, Pedido>{};

  FiltrosDisponibles _filtros = const FiltrosDisponibles();

  /// Que el salto al paso 3 pase **una sola vez**. Sin esto, volver a mano al
  /// paso 1 rebotaria al 3 en el siguiente repintado y no habria forma de
  /// cambiar de sucursal.
  bool _arranqueResuelto = false;

  bool _generando = false;

  @override
  void dispose() {
    _espera?.cancel();
    _nombre.dispose();
    _buscador.dispose();
    _desplazamientoDeLaLista.dispose();
    super.dispose();
  }

  Vehiculo? get _vehiculo {
    final lista = ref.read(vehiculosProvider).value ?? const <Vehiculo>[];
    return lista.where((v) => v.id == _vehiculoId).firstOrNull;
  }

  double get _peso =>
      _elegidos.values.fold<double>(0, (suma, p) => suma + p.weight);

  void _ponerFiltros(FiltrosDisponibles nuevos) =>
      setState(() => _filtros = nuevos);

  /// 400 ms de espera antes de buscar. Sin ella, escribir «camagüey» son ocho
  /// consultas y ocho repintados con la lista entera de disponibles detras.
  void _buscar(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _ponerFiltros(_filtros.copiarCon(q: texto.trim()));
    });
  }

  /// La sucursal se autocompleta: la del selector de la barra superior, o la
  /// unica que haya (pliego §3, paso 1). Preguntar por algo que sólo tiene una
  /// respuesta posible es un paso de mas en el patio de un almacen.
  void _autocompletarSucursal(List<Sucursal> sucursales) {
    if (_sucursalId != null || sucursales.isEmpty) return;
    final deLaBarra = ref.read(sucursalMiradaProvider);
    final elegida =
        sucursales.where((s) => s.id == deLaBarra).firstOrNull ??
        (sucursales.length == 1 ? sucursales.single : null);
    if (elegida == null) return;
    _sucursalId = elegida.id;
    _filtros = _filtros.copiarCon(sucursalId: elegida.id);
  }

  void _cambiarSucursal(String id) => setState(() {
    // EL ATAJO DE ARRANQUE SE DESARMA EN CUANTO LA PERSONA ELIGE.
    //
    // A partir de aquí el asistente va paso a paso, porque ya no está
    // «resuelto por el alcance»: lo está resolviendo alguien, y el siguiente
    // que le toca decidir es de qué almacén sale el camión.
    _arranqueResuelto = true;
    _sucursalId = id.isEmpty ? null : id;
    // Cambiar de sucursal invalida la salida: un almacen de Holguin no es
    // punto de partida de una ruta de Camaguey. Y lo elegido tampoco vale,
    // porque eran pedidos de la otra.
    _salida = null;
    _elegidos.clear();
    _filtros = FiltrosDisponibles(sucursalId: _sucursalId);
  });

  @override
  Widget build(BuildContext context) {
    final sucursales =
        ref.watch(sucursalesProvider).value ?? const <Sucursal>[];
    _autocompletarSucursal(sucursales);

    final sucursal = sucursales.where((s) => s.id == _sucursalId).firstOrNull;
    final codigo = sucursal?.externalId;
    final almacenes = codigo == null
        ? const <Almacen>[]
        : (ref.watch(almacenesProvider(codigo)).value ?? const <Almacen>[]);
    final conUbicacion = [
      for (final a in almacenes)
        if (a.lat != null && a.lng != null) a,
    ];
    // El principal viene primero de la consulta, asi que el primero es el que
    // toca por defecto.
    _salida ??= conUbicacion.firstOrNull;

    // «Si la sucursal y la salida ya vienen resueltas, arranca directamente en
    // el paso 3» (pliego §3). ES UN ATAJO DE ARRANQUE, para quien abre el
    // asistente con todo ya decidido por su alcance.
    //
    // Lo que lo desarma es que la persona elija: ver `_cambiarSucursal`. Sin
    // eso, para un Super Admin —que abre sin sucursal, mirando «todas»— el
    // atajo se quedaba armado, y en cuanto elegía sucursal en el paso 1 la
    // salida se rellenaba sola con la primera y el asistente **saltaba el paso
    // 2**. Visto por Jose el 16/09/2026: «de sucursal pasa directamente a
    // vehiculo me salta salida».
    //
    // Y eso no es una comodidad: es quitarle una decisión. «recuerda q son
    // varios almacenes», y la salida decide desde dónde se miden los kilómetros
    // de toda la ruta.
    if (!_arranqueResuelto && _sucursalId != null && _salida != null) {
      _arranqueResuelto = true;
      _paso = 3;
    }

    final lista = ref.watch(disponiblesProvider(_filtros));
    final disponibles = lista.value ?? const <Pedido>[];
    final peso = _peso;
    final capacidad = _vehiculo?.capacity;
    final sobrepeso = capacidad != null && peso > capacidad;

    final puedeGenerar =
        _salida != null &&
        _vehiculoId != null &&
        _elegidos.isNotEmpty &&
        !sobrepeso &&
        !_generando;

    // Lo que ya está resuelto, que es lo que pinta un tramo de verde y lo que
    // deja volver a él. Un paso «hecho» es uno que tiene respuesta, no uno por
    // el que se pasó: si alguien vuelve al 1 y deja la sucursal en blanco, ese
    // tramo deja de estar hecho y el de después tampoco.
    final hechos = <int, bool>{
      1: _sucursalId != null,
      2: _salida != null,
      3: _vehiculoId != null,
      4: _elegidos.isNotEmpty,
    };

    return Cajon(
      titulo: 'Nueva Ruta',
      // DEBAJO DEL TÍTULO, LA SUCURSAL. Es el dato que manda sobre todo lo
      // demás —los pedidos, los camiones y el punto de partida son los de esa
      // sucursal— y quien abre el asistente tiene que verlo sin buscarlo. En el
      // sitio donde ponía «Paso 3 de 4», que es lo que ya dice la barra de
      // progreso con mucho más detalle.
      subtitulo: sucursal?.name ?? 'Elige la sucursal',
      ancho: AnchoCajon.completo,
      // LA BARRA DE PASOS, PEGADA BAJO LA CABECERA Y FUERA DEL DESPLAZAMIENTO.
      //
      // Es el armazón, no el contenido. En un teléfono el paso 4 no cabe de una
      // vez, y con la barra dentro del cuerpo había que subir por toda la lista
      // de pedidos para poder volver al paso anterior. Jose, 17/09/2026, sobre
      // esta misma trampa en el detalle de ruta: «me corta parte de abajo […]
      // no puedo ver el final». Aquí se desplaza el paso; el marco no.
      bajoLaCabecera: Center(
        child: ConstrainedBox(
          // El mismo ancho máximo que las tarjetas, para que los cuatro tramos
          // caigan justo encima de ellas y no de oreja a oreja del monitor.
          constraints: const BoxConstraints(maxWidth: 1152),
          child: _BarraDePasos(
            actual: _paso,
            hechos: hechos,
            // VIAJAR ENTRE LOS PASOS. Como sólo se pinta el que toca, ésta es
            // la única forma de corregir el anterior sin cancelar y empezar de
            // cero, y lo elegido se conserva: aquí no se limpia nada, sólo se
            // cambia qué tarjeta se enseña.
            alIr: (n) => setState(() => _paso = n),
          ),
        ),
      ),
      // EL PIE, PEGADO ABAJO Y SIEMPRE A LA VISTA. Lo sostiene el `Cajon`; lo
      // que hacía falta era que el cuerpo no creciera sin freno, y eso lo
      // arregla la caja de la lista del paso 4.
      //
      // `spaceBetween` + `Flexible`, y no `Spacer`: a 390 px los dos botones
      // pedían 354 px dentro de 342 y el pie se pasaba 12 px por la derecha —el
      // «Generar Ruta» cortado, que es lo mismo que no estar—. Con `Spacer` no
      // se arregla: el hueco es un hijo flexible más y el botón se quedaría a
      // media anchura también en un monitor.
      pie: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: Aire.sm),
          Flexible(
            child: FilledButton(
              onPressed: puedeGenerar ? _generar : null,
              child: Text(
                _generando ? 'Generando ruta...' : 'Generar Ruta',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
      cuerpo: Center(
        // El `mx-auto max-w-6xl` de la de Next: el cajón va a pantalla completa
        // y sin esto, en un monitor ancho, una frase de ayuda se estira a 1.800
        // px y deja de leerse como un párrafo.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1152),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_paso == 1)
                _Tarjeta(
                  key: AsistenteNuevaRuta.claveDelPaso(1),
                  numero: 1,
                  titulo: 'Sucursal',
                  hecho: hechos[1]!,
                  hijo: _pasoSucursal(sucursales),
                ),
              if (_paso == 2)
                _Tarjeta(
                  key: AsistenteNuevaRuta.claveDelPaso(2),
                  numero: 2,
                  titulo: 'Punto de partida',
                  hecho: hechos[2]!,
                  hijo: _pasoSalida(conUbicacion),
                ),
              if (_paso == 3)
                _Tarjeta(
                  key: AsistenteNuevaRuta.claveDelPaso(3),
                  numero: 3,
                  titulo: 'Vehículo',
                  hecho: hechos[3]!,
                  hijo: _pasoVehiculo(),
                ),
              if (_paso == 4)
                _Tarjeta(
                  key: AsistenteNuevaRuta.claveDelPaso(4),
                  numero: 4,
                  titulo: 'Pedidos de cliente (${_elegidos.length})',
                  hecho: hechos[4]!,
                  hijo: _pasoPedidos(
                    sucursales: sucursales,
                    disponibles: disponibles,
                    cargando: lista.isLoading,
                    peso: peso,
                    capacidad: capacidad,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pasoSucursal(List<Sucursal> sucursales) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Selector<String>(
        titulo: 'Sucursal de la ruta',
        valor: _sucursalId ?? '',
        opciones: [
          const OpcionSelector('', 'Elige la sucursal…'),
          for (final s in sucursales)
            OpcionSelector(s.id, s.name, nota: s.externalId),
        ],
        alElegir: _cambiarSucursal,
      ),
      const SizedBox(height: 8),
      Text(
        'Los pedidos, los vehículos y el punto de partida serán los de esta '
        'sucursal.',
        style: TextStyle(color: Colores.gris),
      ),
      const SizedBox(height: 12),
      // El «Siguiente» va DENTRO de la tarjeta, abajo a la derecha: los pasos
      // 1-3 son cortos y el botón del pie es el de generar la ruta entera, que
      // todavía no se puede. Dos botones de avanzar en la misma pantalla, uno
      // arriba y otro abajo, es lo que hacía dudar de cuál era cuál.
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: _sucursalId == null
              ? null
              : () => setState(() => _paso = 2),
          child: const Text('Siguiente'),
        ),
      ),
    ],
  );

  Widget _pasoSalida(List<Almacen> conUbicacion) {
    if (conUbicacion.isEmpty) {
      return const _SinSalida(
        texto: AsistenteNuevaRuta.sinAlmacenes,
        boton: AsistenteNuevaRuta.irAAlmacenes,
        adonde: '/warehouses',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Selector<String>(
          titulo: 'Almacén del que sale el camión',
          valor: _salida?.id ?? '',
          opciones: [
            for (final a in conUbicacion)
              OpcionSelector(
                a.id,
                a.nombre,
                nota: a.principal ? 'principal' : null,
              ),
          ],
          alElegir: (id) => setState(
            () => _salida = conUbicacion.where((a) => a.id == id).first,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_salida?.direccion ?? ''}  '
          '${_salida?.lat?.toStringAsFixed(5) ?? ''}, '
          '${_salida?.lng?.toStringAsFixed(5) ?? ''}',
          style: TextStyle(color: Colores.gris),
        ),
        // El mapa de 220 px del pliego queda PENDIENTE: `lib/mapas/` (PLAN.md
        // §4.2) todavia no existe y el detalle de la ruta tampoco lo pinta. Se
        // dicen las coordenadas, que es el dato que el mapa ensenaria, en vez de
        // dejar un hueco gris que parece que algo se rompio.
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: () => setState(() => _paso = 3),
            child: const Text('Siguiente'),
          ),
        ),
      ],
    );
  }

  Widget _pasoVehiculo() {
    final todos = ref.watch(vehiculosProvider).value ?? const <Vehiculo>[];

    // Sólo los de la sucursal del paso 1. El porqué, en `vehiculosDeLaSucursal`.
    final vehiculos = vehiculosDeLaSucursal(todos, _sucursalId);

    if (vehiculos.isEmpty) {
      // Se distingue «esta sucursal no tiene camiones» de «no hay ninguno»:
      // lo primero se arregla dando de alta uno EN ESA sucursal, y lo segundo
      // dando de alta el primero. Decir lo mismo en los dos casos manda a
      // buscar donde no es.
      return _SinSalida(
        texto: todos.isEmpty
            ? AsistenteNuevaRuta.sinVehiculos
            : 'Esta sucursal no tiene ningún vehículo dado de alta. Los que '
                  'hay son de otras sucursales, y un camión de otra sucursal no '
                  'está donde sale esta ruta.',
        boton: AsistenteNuevaRuta.irAVehiculos,
        adonde: '/vehicles',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Selector<String>(
          titulo: 'Vehículo de la ruta',
          valor: _vehiculoId ?? '',
          opciones: [
            const OpcionSelector('', 'Elige el vehículo…'),
            // **Se ofrecen todos los vehiculos, tambien los ocupados**: la
            // pantalla no decide por nadie, sólo avisa de cual esta en ruta.
            for (final v in vehiculos)
              OpcionSelector(
                v.id,
                v.name,
                nota: v.status == EstadoVehiculo.enUso
                    ? '${v.capacity.toStringAsFixed(0)} kg · en ruta'
                    : '${v.capacity.toStringAsFixed(0)} kg',
              ),
          ],
          alElegir: (id) =>
              setState(() => _vehiculoId = id.isEmpty ? null : id),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nombre,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'Nombre (el código se genera solo)',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Fecha de entrega (opcional): '
                '${_fechaDeEntrega == null ? '—' : fechaCorta(_fechaDeEntrega)}',
              ),
            ),
            OutlinedButton(
              onPressed: () async {
                final hoy = DateTime.now();
                final elegida = await showDatePicker(
                  context: context,
                  firstDate: hoy.subtract(const Duration(days: 30)),
                  lastDate: hoy.add(const Duration(days: 365)),
                  initialDate: hoy,
                );
                if (elegida != null) {
                  setState(() => _fechaDeEntrega = elegida);
                }
              },
              child: const Text('Elegir'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _vehiculoId == null
                ? null
                : () => setState(() => _paso = 4),
            child: const Text('Siguiente'),
          ),
        ),
      ],
    );
  }

  /// Los filtros de la lista de elegibles (pliego §3, paso 4).
  ///
  /// **El cuadre con la factura NO esta aqui a proposito**: siempre es `cuadra`,
  /// que es lo unico que el armado acepta. Ofrecer lo que luego se rechaza es
  /// fabricar rechazos tardios.
  /// METE UNA ZONA ENTERA del tablero en la seleccion.
  ///
  /// No mete lo que no puede: un pedido que ya no esta disponible —porque entro
  /// en otra ruta, o porque se archivo desde que se armo el tablero— no se
  /// puede repartir hoy, y meterlo seria fabricar un rechazo al guardar. El que
  /// no cabe en el camion tampoco entra.
  ///
  /// **Lo que se queda fuera se DICE, con el numero y el motivo.** Meter nueve
  /// de doce en silencio es la peor version de esto: quien pulsa la zona cree
  /// que lleva la zona entera y se entera en el almacen, cargando.
  void _meterLaZona(String nombre, List<String> ids, List<Pedido> disponibles) {
    final reparto = repartirLaZona(
      ids: ids,
      disponibles: disponibles,
      yaElegidos: _elegidos.keys.toSet(),
      pesoActual: _peso,
      capacidad: _vehiculo?.capacity,
    );

    setState(() {
      for (final pedido in reparto.entran) {
        _elegidos[pedido.id] = pedido;
      }
    });

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(parteDeLaZona(nombre, ids.length, reparto))),
      );
  }

  Widget _barraDeFiltros(List<Sucursal> sucursales) {
    final opciones =
        ref.watch(opcionesDeDisponiblesProvider(_filtros)).value ??
        OpcionesDeDisponibles.vacias;

    // EN UN TELEFONO, UN CAMPO POR LINEA.
    //
    // Esto era un `Wrap` con anchos fijos —220 px el buscador, y cada selector
    // lo que ocupara su texto—. En un escritorio se lee como una barra; en 390
    // px se convierte en un revoltijo de cachos de distinto tamano, con dos
    // controles apretados en una fila y uno solo en la siguiente, y la altura
    // saltando cada vez que un texto crece. Palabras de Jose, 16/09/2026:
    // «esta maldito la organizacion esa de campos ahi para el movil».
    //
    // Por debajo del ancho de la tabla de Pedidos (`Anchos.entrega`, §11) cada
    // control ocupa la linea entera. No es por gusto: un selector a ancho
    // completo se pulsa con el pulgar sin mirar, y ocho controles alineados a
    // la izquierda se recorren de un vistazo. Lo que se gasta es sitio
    // vertical, que en una lista con desplazamiento es lo que sobra.
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.entrega;

    // TODOS LOS CONTROLES, EL MISMO ANCHO. El porqué, en `anchoFiltro`.
    final ancho = estrecho ? double.infinity : AsistenteNuevaRuta.anchoFiltro;
    Widget caja(Widget control) => SizedBox(width: ancho, child: control);

    // La sucursal, a ancho completo y encima de todo lo demás: es la que decide
    // qué pedidos hay, no un filtro más de la fila.
    final deQueSucursal = SizedBox(
      width: double.infinity,
      child: Selector<String>(
        titulo: 'Sucursal de la ruta',
        valor: _sucursalId ?? '',
        opciones: [
          const OpcionSelector('', 'Elige la sucursal…'),
          for (final s in sucursales)
            OpcionSelector(s.id, s.name, nota: s.externalId),
        ],
        alElegir: _cambiarSucursal,
      ),
    );

    final controles = <Widget>[
      OutlinedButton(
        onPressed: () async {
          final hoy = DateTime.now();
          final dia = await showDatePicker(
            context: context,
            firstDate: hoy.subtract(const Duration(days: 365)),
            lastDate: hoy.add(const Duration(days: 365)),
            initialDate: _filtros.dia ?? hoy,
          );
          if (dia != null) _ponerFiltros(_filtros.copiarCon(dia: dia));
        },
        child: Text(
          'Día de los pedidos: ${_filtros.dia == null ? 'todos' : fechaCorta(_filtros.dia)}',
        ),
      ),
      // «Todos los días» es un boton propio y no la opcion vacia del anterior:
      // un selector de fecha no tiene forma de decir «ninguna».
      OutlinedButton(
        onPressed: _filtros.dia == null
            ? null
            : () => _ponerFiltros(_filtros.copiarCon(limpiarDia: true)),
        child: const Text('Todos los días'),
      ),
      TextField(
        controller: _buscador,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          hintText: 'Buscar pedido...',
        ),
        onChanged: _buscar,
      ),
      Selector<String>(
        titulo: 'Vendedor del pedido',
        valor: _filtros.vendedor,
        // Con buscador SIEMPRE: en una sucursal grande son decenas de
        // vendedores y bajar la lista a mano no es buscar.
        buscadorSiempre: true,
        opciones: [
          const OpcionSelector('', 'Todos los vendedores'),
          for (final v in opciones.vendedores) OpcionSelector(v, v),
        ],
        alElegir: (v) => _ponerFiltros(_filtros.copiarCon(vendedor: v)),
      ),
      Selector<String>(
        titulo: 'Municipio del cliente',
        valor: _filtros.municipio,
        opciones: [
          const OpcionSelector('', 'Todos los municipios'),
          for (final m in opciones.municipios) OpcionSelector(m, m),
        ],
        alElegir: (m) => _ponerFiltros(_filtros.copiarCon(municipio: m)),
      ),
      TextField(
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          hintText: 'km máx.',
        ),
        onSubmitted: (texto) => _ponerFiltros(
          _filtros.copiarCon(
            kmMax: double.tryParse(texto.trim()),
            limpiarKmMax: texto.trim().isEmpty,
          ),
        ),
      ),
      TextField(
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          hintText: 'costo mín.',
        ),
        onSubmitted: (texto) => _ponerFiltros(
          _filtros.copiarCon(
            costoMin: double.tryParse(texto.trim()),
            limpiarCostoMin: texto.trim().isEmpty,
          ),
        ),
      ),
      Selector<EstadoDelPedido>(
        titulo: 'Estado del pedido en PEDIDO',
        valor: _filtros.estado,
        opciones: [
          for (final e in EstadoDelPedido.values) OpcionSelector(e, e.etiqueta),
        ],
        alElegir: (e) => _ponerFiltros(_filtros.copiarCon(estado: e)),
      ),
      Selector<DomicilioFiltro>(
        titulo: 'Si el pedido lleva entrega a domicilio',
        valor: _filtros.domicilio,
        opciones: [
          for (final d in DomicilioFiltro.values) OpcionSelector(d, d.etiqueta),
        ],
        alElegir: (d) => _ponerFiltros(_filtros.copiarCon(domicilio: d)),
      ),
      Selector<CotizadoDelDomicilio>(
        titulo: 'Si Entrega ya le puso costo de domicilio',
        valor: _filtros.cotizado,
        opciones: [
          for (final c in CotizadoDelDomicilio.values)
            OpcionSelector(c, c.etiqueta),
        ],
        alElegir: (c) => _ponerFiltros(_filtros.copiarCon(cotizado: c)),
      ),
      OutlinedButton(
        onPressed: () {
          _buscador.clear();
          // **Vuelve a `domicilio = 1`**, no a «sin nada»: una ruta se arma
          // con lo que hay que llevar a casa, y ese es el arranque del pliego.
          _ponerFiltros(_filtros.limpios());
        },
        child: const Text('Limpiar'),
      ),
    ];

    // Un `Wrap` con TODOS los hijos del mismo ancho sale en columnas
    // alineadas, no en pedazos. En un teléfono ese ancho es la línea entera y
    // el mismo `Wrap` da una fila por control, que es lo que ya hacía falta
    // allí.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        deQueSucursal,
        const SizedBox(height: Aire.sm),
        Wrap(
          spacing: Aire.sm,
          runSpacing: Aire.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final control in controles) caja(control)],
        ),
      ],
    );
  }

  Widget _pasoPedidos({
    required List<Sucursal> sucursales,
    required List<Pedido> disponibles,
    required bool cargando,
    required double peso,
    required double? capacidad,
  }) {
    final renglones =
        ref.watch(renglonesDeDisponiblesProvider(_filtros)).value ??
        const <String, List<RenglonConPeso>>{};

    final visibles = {for (final p in disponibles) p.id};
    // Los elegidos que ya no salen con los filtros de ahora. Siguen contando: su
    // peso va en el camion igual.
    final fueraDeLaLista = _elegidos.keys
        .where((id) => !visibles.contains(id))
        .length;

    // EL CUERPO DE LA CAJA DE LA LISTA. Los tres casos van DENTRO de la caja,
    // no en su lugar: si el vacío o el «Cargando…» se pintaran fuera, la caja
    // aparecería y desaparecería y lo de debajo daría saltos.
    final Widget dentroDeLaCaja;
    if (cargando && disponibles.isEmpty) {
      dentroDeLaCaja = const Padding(
        padding: EdgeInsets.all(Aire.lg),
        child: Text(AsistenteNuevaRuta.cargandoPedidos),
      );
    } else if (disponibles.isEmpty) {
      dentroDeLaCaja = const EstadoVacio(AsistenteNuevaRuta.sinPedidos);
    } else {
      // `ListView` y no una `Column`: con 295 pedidos una `Column` construye
      // las 295 filas para enseñar seis. Y `shrinkWrap` para que con tres
      // pedidos la caja mida lo que miden los tres, no los 320 px del tope.
      dentroDeLaCaja = ListView.builder(
        controller: _desplazamientoDeLaLista,
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: Aire.xs),
        shrinkWrap: true,
        itemCount: disponibles.length,
        itemBuilder: (contexto, i) {
          final pedido = disponibles[i];
          return _FilaDisponible(
            pedido: pedido,
            renglones: renglones[pedido.id] ?? const <RenglonConPeso>[],
            marcado: _elegidos.containsKey(pedido.id),
            // Lo que no cabe se deshabilita con el motivo a la vista, no se
            // esconde: esconderlo haria pensar que el pedido no existe.
            cabe:
                capacidad == null ||
                _elegidos.containsKey(pedido.id) ||
                peso + pedido.weight <= capacidad,
            alMarcar: () => setState(() {
              if (_elegidos.remove(pedido.id) == null) {
                _elegidos[pedido.id] = pedido;
              }
            }),
          );
        },
      );
    }

    final columnaLista = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LAS ZONAS DEL TABLERO, ANTES QUE LOS FILTROS.
        //
        // Para eso se arma el tablero: el estudio de que va junto con que ya se
        // hizo alli, con el mapa, los kilometros al almacen y el peso delante.
        // Volver a elegir los mismos pedidos uno a uno aqui es hacer dos veces
        // el mismo trabajo, y la segunda vez peor, porque aqui no se ve la
        // cercania.
        //
        // Palabras de Jose, 16/09/2026: «no me deja elegir lo q tengo en el
        // tablero q para eso es para yo hacer el tablero con los pedidos... sin
        // necesidad de estar eligiendolos en uno a uno y ya se hizo el estudio
        // antes».
        _ZonasDelTablero(
          sucursalId: _sucursalId,
          yaElegidos: _elegidos.keys.toSet(),
          disponibles: disponibles,
          alElegirZona: _meterLaZona,
        ),
        _barraDeFiltros(sucursales),
        const SizedBox(height: Aire.md),
        _BarraDePeso(peso: peso, capacidad: capacidad),
        const SizedBox(height: Aire.md),
        Text(
          'Pedidos disponibles (${disponibles.length})',
          style: Tipos.texto(tamano: 13, peso: FontWeight.w600),
        ),
        const SizedBox(height: Aire.xs),
        // LA LISTA, EN SU PROPIA CAJA Y CON SU PROPIO DESPLAZAMIENTO.
        //
        // Ésta es la pieza que arregla la queja entera. Antes las filas colgaban
        // de esta misma columna, así que la columna medía lo que midieran los
        // pedidos: con 295, el resumen de debajo quedaba a tres pantallas de
        // distancia y había que recorrerlas para llegar a él. Acotada, la lista
        // se desplaza DENTRO y todo lo que va debajo se queda donde está.
        Container(
          key: AsistenteNuevaRuta.claveDeLaLista,
          constraints: const BoxConstraints(
            maxHeight: AsistenteNuevaRuta.altoDeLaLista,
          ),
          decoration: BoxDecoration(
            color: Colores.blanco,
            border: Border.all(color: Colores.linea),
            borderRadius: BorderRadius.circular(Radios.lg),
          ),
          clipBehavior: Clip.antiAlias,
          // El `Material` es obligatorio, no decorativo: un `CheckboxListTile`
          // pinta su fondo y su onda en el `Material` más cercano, y sin éste
          // ese más cercano queda DETRÁS del recuadro de la caja, así que la
          // fila marcada no se vería marcada. Flutter lo dice en voz alta.
          child: Material(
            type: MaterialType.transparency,
            child: dentroDeLaCaja,
          ),
        ),
        const SizedBox(height: Aire.sm),
        // LA LÍNEA DE RESUMEN, justo debajo de la caja y siempre en el mismo
        // sitio: cuántos van a la izquierda y cuánto pesan a la derecha.
        Row(
          key: AsistenteNuevaRuta.claveDelResumen,
          children: [
            Expanded(
              child: Text(
                '${_elegidos.length} pedidos seleccionados'
                '${fueraDeLaLista == 0 ? '' : ' ($fueraDeLaLista de otro día o filtro, siguen contando)'}',
                style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
              ),
            ),
            const SizedBox(width: Aire.sm),
            Text(
              '${peso.toStringAsFixed(1)} / '
              '${capacidad?.toStringAsFixed(0) ?? '—'} kg',
              style: Tipos.mono(
                tamano: 12,
                peso: FontWeight.w600,
                color: capacidad != null && peso > capacidad
                    ? Colores.rojo
                    : Colores.tintaSuave,
              ),
            ),
          ],
        ),
        if (capacidad != null && peso > capacidad)
          Text(
            'Peso (${peso.toStringAsFixed(1)} kg) supera capacidad del '
            'vehículo (${capacidad.toStringAsFixed(0)} kg)',
            style: TextStyle(color: Colores.rojo),
          ),
      ],
    );

    final columnaPreDespacho = _PreDespachoLateral(
      elegidos: _elegidos.keys.toList(),
      pesoKg: peso,
      capacidad: capacidad,
      sucursal: sucursales.where((s) => s.id == _sucursalId).firstOrNull?.name,
      vehiculo: _vehiculo?.name,
      dia: _filtros.dia,
    );

    // Dos columnas —lista a la izquierda, pre-despacho a la derecha— y una sola
    // cuando no caben las dos sin partir palabras. Lo que se mide es el ancho
    // DE LA TARJETA, no el de la pantalla: la tarjeta vive dentro del cajón y
    // con sus márgenes, y en un portátil de 1.100 px la pantalla dice
    // «escritorio» mientras aquí dentro quedan 900 y pico.
    return LayoutBuilder(
      builder: (contexto, medidas) {
        if (medidas.maxWidth < AsistenteNuevaRuta.anchoDosColumnas) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              columnaLista,
              const SizedBox(height: Aire.lg),
              Divider(height: 1, thickness: 1, color: Colores.linea),
              const SizedBox(height: Aire.lg),
              columnaPreDespacho,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: columnaLista),
            const SizedBox(width: Aire.xl),
            SizedBox(
              width: AsistenteNuevaRuta.anchoPreDespacho,
              child: columnaPreDespacho,
            ),
          ],
        );
      },
    );
  }

  Future<void> _generar() async {
    setState(() => _generando = true);
    final mensajero = ScaffoldMessenger.maybeOf(context);
    final navegador = Navigator.of(context);
    try {
      final rutaId = await ref
          .read(accionesDeRutaProvider)
          .armar(
            vehiculoId: _vehiculoId,
            pedidoIds: _elegidos.keys.toList(),
            origenLat: _salida?.lat,
            origenLng: _salida?.lng,
            nombre: _nombre.text.trim().isEmpty ? null : _nombre.text.trim(),
            origenDireccion: _salida?.direccion ?? _salida?.nombre,
            sucursalId: _sucursalId,
            fechaDeEntrega: _fechaDeEntrega,
          );
      // Se selecciona sola, igual que en la de Next.
      ref.read(rutaElegidaProvider.notifier).elegir(rutaId);
      navegador.maybePop();
    } on RechazoLocal catch (fallo) {
      // Los errores del armado salen como aviso emergente, **no dentro del
      // cajon**, y con el texto literal del servidor.
      mensajero?.showSnackBar(SnackBar(content: Text(fallo.mensaje)));
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }
}

/// LA BARRA DE PROGRESO: cuatro tramos a lo ancho, uno por paso.
///
/// No es adorno. Con un paso a la vista, sin esto no se sabe si quedan dos o
/// siete; y sobre todo, **es por donde se vuelve atrás**. Eran cuatro enlaces
/// de texto en un `Wrap` —«eso que hay ahí es un wizard, no la mierda que
/// hiciste tú»—, y un enlace de texto no dice ni cuánto llevas ni cuánto falta.
///
/// Los colores dicen tres cosas distintas: **verde** lo que ya tiene respuesta,
/// el color de la marca el paso en el que estás si todavía no la tiene, y gris
/// lo que ni siquiera se puede pulsar. Un tramo hecho se pulsa y se vuelve a él.
class _BarraDePasos extends StatelessWidget {
  const _BarraDePasos({
    required this.actual,
    required this.hechos,
    required this.alIr,
  });

  final int actual;
  final Map<int, bool> hechos;
  final void Function(int) alIr;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final paso in AsistenteNuevaRuta.pasos.entries) ...[
        if (paso.key > 1) const SizedBox(width: Aire.xs),
        Expanded(child: _tramo(paso.key, paso.value)),
      ],
    ],
  );

  Widget _tramo(int numero, String nombre) {
    final hecho = hechos[numero] ?? false;
    final esElActual = numero == actual;
    // Se puede pulsar lo que ya está resuelto y el paso en el que se está. Un
    // paso de más adelante sin resolver no lleva a ninguna parte: saltar al 4
    // sin camión elegido es una pantalla que no se puede terminar.
    final sePuedePulsar = hecho || esElActual;
    final color = hecho
        ? Colores.verde
        : (esElActual ? Colores.primario : Colores.linea);

    return Tooltip(
      message: hecho ? 'Volver a $nombre' : nombre,
      child: InkWell(
        key: AsistenteNuevaRuta.claveDelTramo(numero),
        onTap: sePuedePulsar ? () => alIr(numero) : null,
        borderRadius: BorderRadius.circular(Radios.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(Radios.pastilla),
              ),
            ),
            const SizedBox(height: Aire.xs),
            Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tipos.texto(
                tamano: 11,
                peso: esElActual ? FontWeight.w700 : FontWeight.w400,
                color: esElActual ? Colores.tinta : Colores.tintaSuave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// LA TARJETA DEL PASO: el número en su círculo, el título, y dentro el paso.
///
/// Una sola, la del paso que toca. Estaban las cuatro a la vez —tres apagadas y
/// sin poder pulsarse— y eran cuatro cajas grises que no decían qué hacer.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.numero,
    required this.titulo,
    required this.hecho,
    required this.hijo,
    super.key,
  });

  final int numero;
  final String titulo;
  final bool hecho;
  final Widget hijo;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colores.blanco,
      border: Border.all(color: Colores.linea),
      borderRadius: BorderRadius.circular(Radios.xl),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Aire.md),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hecho ? Colores.verde : Colores.primario,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$numero',
                  style: Tipos.texto(
                    tamano: 12,
                    peso: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: Aire.sm),
              Expanded(
                child: Text(
                  titulo,
                  style: Tipos.texto(
                    tamano: 15,
                    peso: FontWeight.w700,
                    color: Colores.tinta,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: Colores.linea),
        Padding(padding: const EdgeInsets.all(Aire.md), child: hijo),
      ],
    ),
  );
}

/// LA BARRA DE PESO: `115.6 / 10000 kg (1%)` y debajo la barra de verdad.
///
/// El número solo no se lee de un vistazo cuando uno está cargando un camión;
/// la barra sí, y es la misma de la de Next: verde hasta el 80 %, ámbar entre
/// el 80 y el 100, y roja con su «LLENO» al pasarse.
class _BarraDePeso extends StatelessWidget {
  const _BarraDePeso({required this.peso, required this.capacidad});

  final double peso;
  final double? capacidad;

  @override
  Widget build(BuildContext context) {
    final capacidad = this.capacidad;
    if (capacidad == null) {
      return Text(
        'Elige un vehículo para ver la capacidad',
        style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
      );
    }
    final porcentaje = capacidad == 0 ? 0.0 : (peso / capacidad) * 100;
    final color = porcentaje >= 100
        ? Colores.rojo
        : (porcentaje >= 80 ? Colores.ambar : Colores.verde);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${peso.toStringAsFixed(1)} / ${capacidad.toStringAsFixed(0)} '
                'kg (${porcentaje.toStringAsFixed(0)}%)',
                style: Tipos.mono(
                  tamano: 12,
                  peso: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (porcentaje >= 100) Insignia('LLENO', color: Colores.rojo),
          ],
        ),
        const SizedBox(height: Aire.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radios.pastilla),
          child: LinearProgressIndicator(
            value: (porcentaje / 100).clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: Colores.grisFondo,
            color: color,
          ),
        ),
        if (porcentaje >= 100)
          Padding(
            padding: const EdgeInsets.only(top: Aire.xs),
            child: Text(
              'Camión lleno — no cabe más',
              style: Tipos.texto(tamano: 12, color: Colores.rojo),
            ),
          ),
      ],
    );
  }
}

class _FilaDisponible extends StatelessWidget {
  const _FilaDisponible({
    required this.pedido,
    required this.renglones,
    required this.marcado,
    required this.cabe,
    required this.alMarcar,
  });

  final Pedido pedido;
  final List<RenglonConPeso> renglones;
  final bool marcado;
  final bool cabe;
  final VoidCallback alMarcar;

  /// Los articulos, resumidos: el primero con sus empaques y `+n` por el resto,
  /// y la lista entera en el tooltip. Es el mismo resumen de la tabla de
  /// Pedidos, para que el mismo pedido se lea igual en las dos pantallas.
  String get _articulos {
    if (renglones.isEmpty) return '';
    final primero = renglones.first;
    final resto = renglones.length - 1;
    return '${primero.renglon.description} ×${cantidad(primero.empaques)}'
        '${resto > 0 ? '  +$resto' : ''}';
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: cabe
        ? [
            for (final r in renglones)
              '${r.renglon.description} ×${cantidad(r.empaques)}',
          ].join('\n')
        : 'No cabe en el camión',
    child: CheckboxListTile(
      dense: true,
      value: marcado,
      onChanged: cabe ? (_) => alMarcar() : null,
      title: Text(pedido.customerName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${pedido.endAddress ?? pedido.address} · ${kg(pedido.weight)} · '
            // `usd` ya dice `sin cotizar` cuando no hay precio: un `$0.00`
            // seria «este domicilio es gratis», que es otra cosa.
            '${usd(pedido.pedidoCosto)}',
          ),
          if (_articulos.isNotEmpty)
            Text(
              _articulos,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colores.gris, fontSize: 12),
            ),
        ],
      ),
    ),
  );
}

/// El pre-despacho que se suma en vivo segun se van eligiendo pedidos.
class _PreDespachoLateral extends ConsumerWidget {
  const _PreDespachoLateral({
    required this.elegidos,
    required this.pesoKg,
    required this.capacidad,
    required this.sucursal,
    required this.vehiculo,
    required this.dia,
  });

  final List<String> elegidos;
  final double pesoKg;
  final double? capacidad;
  final String? sucursal;
  final String? vehiculo;
  final DateTime? dia;

  /// El dia tal y como lo escribe la hoja de Next: `AAAA-MM-DD`. Se compara
  /// caracter a caracter con la suya, asi que no pasa por `DateFormat` local.
  String? get _diaDeLaHoja => dia == null
      ? null
      : '${dia!.year.toString().padLeft(4, '0')}-'
            '${dia!.month.toString().padLeft(2, '0')}-'
            '${dia!.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La caja está SIEMPRE, con su título y su botón: es el sitio donde se mira
    // lo que hay que sacar del almacén, y un sitio que aparece y desaparece
    // según lo que lleves elegido no se aprende. Lo que cambia es lo de dentro.
    final totales = elegidos.isEmpty
        ? null
        : ref
              .watch(
                preDespachoDeLoElegidoEnElAsistenteProvider(
                  ([...elegidos]..sort()).join(','),
                ),
              )
              .value;

    final Widget dentro;
    if (elegidos.isEmpty) {
      dentro = Text(
        AsistenteNuevaRuta.preDespachoVacio,
        style: TextStyle(color: Colores.gris),
      );
    } else if (totales == null) {
      dentro = const Text(AsistenteNuevaRuta.cargandoPedidos);
    } else {
      dentro = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // La tabla va dentro de su propio desplazamiento lateral: en un
          // telefono tres columnas con nombres de producto largos no caben, y lo
          // que no cabe tiene que poder alcanzarse, no recortarse.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Producto')),
                DataColumn(label: Text('Emp.')),
                DataColumn(label: Text('Uds.')),
              ],
              rows: [
                for (final linea in totales.lineas)
                  DataRow(
                    cells: [
                      DataCell(Text(linea.producto)),
                      DataCell(Text(cantidad(linea.empaques))),
                      DataCell(Text(cantidad(linea.unidades))),
                    ],
                  ),
              ],
            ),
          ),
          Divider(height: Aire.lg, thickness: 1, color: Colores.linea),
          Text('Pedidos: ${elegidos.length}'),
          Text('Empaques: ${cantidad(totales.empaques)}'),
          Text('Unidades: ${cantidad(totales.unidades)}'),
          Text(
            'Peso: ${pesoKg.toStringAsFixed(1)} / '
            '${capacidad?.toStringAsFixed(0) ?? '—'} kg',
          ),
        ],
      );
    }

    return Container(
      key: AsistenteNuevaRuta.claveDelPreDespacho,
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        border: Border.all(color: Colores.linea),
        borderRadius: BorderRadius.circular(Radios.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pre-despacho',
                  style: Tipos.texto(tamano: 13, peso: FontWeight.w700),
                ),
              ),
              OutlinedButton(
                onPressed: totales == null
                    ? null
                    : () => _verEImprimir(context, totales),
                child: const Text('Ver e imprimir'),
              ),
            ],
          ),
          const SizedBox(height: Aire.sm),
          dentro,
        ],
      ),
    );
  }

  /// La hoja con la que alguien baja al almacen. Se mira primero y se imprime
  /// desde la propia vista previa: es el orden que tenia la de Next y el que
  /// tiene sentido cuando el que saca la mercancia es otra persona.
  void _verEImprimir(BuildContext context, TotalesPreDespacho totales) {
    final hoja = papel.HojaPreDespacho(
      sucursal: sucursal ?? '',
      vehiculo: vehiculo ?? '',
      dia: _diaDeLaHoja,
      pedidos: elegidos.length,
      pesoKg: pesoKg,
      lineas: [
        for (final linea in totales.lineas)
          papel.LineaPreDespacho(
            producto: linea.producto,
            formatos: linea.empaques,
            unidades: linea.unidades,
            // En el papel el peso es un numero: un producto sin peso resuelto
            // suma cero kilos a la hoja, que es lo que pesa lo que no sabemos.
            pesoKg: linea.pesoKg ?? 0,
          ),
      ],
    );

    abrirCajon<void>(
      context,
      (contexto) => Cajon(
        titulo: 'Pre-despacho',
        subtitulo:
            '${elegidos.length} pedido(s) · '
            '${pesoKg.toStringAsFixed(1)} kg',
        ancho: AnchoCajon.xl,
        // EL ALTO SALE DE LA PANTALLA, NO DE UN NÚMERO ESCRITO A MANO.
        //
        // La vista previa quiere todo el alto que le den y el cuerpo del cajón
        // es un desplazable, así que hay que darle uno concreto o la hoja no se
        // pinta. Aquí había un `640` fijo, y a 390x844 el cuerpo útil del cajón
        // ronda los 635: la caja no cabía, y entonces son dos desplazamientos
        // verticales, uno dentro del otro. Con el dedo encima manda el de
        // dentro, el de fuera no se mueve nunca, y la parte de abajo de la hoja
        // **no se alcanza jamás**. El mismo `0.75` que usan las otras dos hojas
        // (Pedidos y el post-despacho del cierre).
        cuerpo: SizedBox(
          height: MediaQuery.sizeOf(contexto).height * 0.75,
          child: VistaPreviaPdf(
            armar: (formato) => pdfPreDespacho(hoja, impresoEn: DateTime.now()),
            nombreDeFichero: 'pre-despacho.pdf',
          ),
        ),
      ),
    );
  }
}

/// UN PASO QUE NO SE PUEDE TERMINAR, CON SU SALIDA.
///
/// Dice qué falta y **lleva al sitio donde se arregla**, cerrando el asistente
/// antes: dejarlo abierto encima de la pantalla a la que se acaba de ir es un
/// cajón tapando justo lo que se venía a hacer.
///
/// Es el mismo criterio del paso a paso del Panel
/// (`lib/pantallas/panel/vista/paso_a_paso.dart`): **botón sólo cuando lleva a
/// donde el problema de verdad se toca**. Lo que no se arregla desde esta
/// aplicación —la tasa, que la mantiene Accesos— no lleva botón, se dice a
/// quién pedírselo; un botón que lleva a un sitio donde el problema no se
/// arregla es peor que no tenerlo.
///
/// **Y no da de alta el camión aquí mismo**, aunque el cajón de Vehículos
/// exista: esa pantalla vive de la red (`POST /api/vehicles`) y el asistente
/// lee la flota de la BASE LOCAL, la que deja la bajada del día. Un camión
/// creado desde aquí no aparecería en el desplegable de al lado hasta la
/// siguiente sincronización, o sea que el paso seguiría sin poder terminarse y
/// encima sin decir por qué.
class _SinSalida extends StatelessWidget {
  const _SinSalida({
    required this.texto,
    required this.boton,
    required this.adonde,
  });

  final String texto;
  final String boton;
  final String adonde;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(texto, style: TextStyle(color: Colores.gris)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () {
          // El router se coge ANTES de cerrar: despues de `pop` este
          // `context` ya no esta montado y `context.go` reventaria.
          final ir = GoRouter.of(context);
          Navigator.of(context).maybePop();
          ir.go(adonde);
        },
        child: Text(boton),
      ),
    ],
  );
}

/// El pre-despacho del asistente.
///
/// El argumento es la lista de ids **ordenada y unida por comas**, y no la lista
/// suelta, porque un `family` compara sus argumentos con `==` y dos `List` con el
/// mismo contenido no son iguales en Dart: con la lista cruda se crearia un
/// provider nuevo en cada repintado y la suma se reharia sin que nada hubiera
/// cambiado.
final preDespachoDeLoElegidoEnElAsistenteProvider =
    FutureProvider.family<TotalesPreDespacho, String>(
      (ref, clave) => ref
          .watch(consultasPedidosProvider)
          .preDespachoDe(clave.isEmpty ? const [] : clave.split(',')),
    );

/// LAS ZONAS DEL TABLERO, para meterlas de una en la ruta.
///
/// El tablero es donde se decide QUE VA JUNTO, con el mapa y los kilometros al
/// almacen delante. Este atajo es lo que hace que ese trabajo sirva para algo
/// aqui; sin el, armar la ruta es repetirlo a mano y a ciegas.
///
/// Sale SOLO si el tablero cargado es el de la sucursal que se eligio en el
/// paso 1. Ensenar las zonas de Santiago mientras se arma una ruta de La Habana
/// seria ofrecer pedidos que no son de esta ruta, y aceptarlos es un rechazo al
/// guardar.
class _ZonasDelTablero extends ConsumerWidget {
  const _ZonasDelTablero({
    required this.sucursalId,
    required this.yaElegidos,
    required this.disponibles,
    required this.alElegirZona,
  });

  final String? sucursalId;
  final Set<String> yaElegidos;
  final List<Pedido> disponibles;
  final void Function(String nombre, List<String> ids, List<Pedido> disponibles)
  alElegirZona;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablero = ref.watch(tableroProvider).value;
    if (tablero == null ||
        tablero.problema != null ||
        tablero.columnas.isEmpty ||
        sucursalId == null ||
        tablero.sucursalId != sucursalId) {
      return const SizedBox.shrink();
    }

    final hayDisponible = {for (final p in disponibles) p.id};

    final fichas = <Widget>[];
    for (final zona in tablero.columnas) {
      final ids = [
        for (final t in tablero.deColumna(zona.id)) t.pedido.pedidoId,
      ];
      if (ids.isEmpty) continue;
      // El numero es «cuantos de esta zona se pueden meter AHORA», no cuantos
      // tiene: los que ya no estan disponibles no van a entrar, y ensenar el
      // total prometeria de mas.
      final entran = ids
          .where((id) => hayDisponible.contains(id) && !yaElegidos.contains(id))
          .length;
      fichas.add(
        ActionChip(
          avatar: const Icon(Icons.dashboard_customize_outlined, size: 16),
          label: Text(
            '${zona.nombre} · $entran/${ids.length}'
            '  ${zona.pesoKg.toStringAsFixed(0)} kg',
          ),
          onPressed: () => alElegirZona(zona.nombre, ids, disponibles),
        ),
      );
    }
    if (fichas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: Aire.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zonas del tablero',
            style: Tipos.texto(tamano: 12, peso: FontWeight.w700),
          ),
          Text(
            'Lo que ya organizaste. Pulsa una y entran sus pedidos de una vez.',
            style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: fichas),
        ],
      ),
    );
  }
}
