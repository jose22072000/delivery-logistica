import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reparto/nucleo/frescura/reloj_de_datos.dart';
import 'package:reparto/nucleo/proveedores.dart';

import '../datos/repositorio_clientes.dart';
import '../estado/estado_clientes.dart';
import 'paginacion.dart';
import 'selector.dart';
import 'tabla_clientes.dart';

/// Clientes — `/customers`. Pliego: `pantallas.md` §4.
///
/// **Se mira sin conexion.** Todo lo que hay aqui sale de la base local,
/// incluida la distancia al almacen, que se calcula en el aparato. Lo unico que
/// cambia sin red es lo que dice el `RelojDeDatos` de arriba: de que hora es la
/// foto que se esta mirando. No escribe nada, asi que no hay nada que encolar.
class PantallaClientes extends ConsumerStatefulWidget {
  const PantallaClientes({super.key});

  static const ruta = '/customers';

  @override
  ConsumerState<PantallaClientes> createState() => _PantallaClientesState();
}

class _PantallaClientesState extends ConsumerState<PantallaClientes> {
  final _buscador = TextEditingController();
  Timer? _espera;

  @override
  void dispose() {
    _espera?.cancel();
    _buscador.dispose();
    super.dispose();
  }

  /// 400 ms de espera antes de buscar (§4). Sin ella, escribir «camagüey» son
  /// ocho consultas y ocho repintados, y en un telefono se nota.
  void _buscar(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 400), () {
      final filtros = ref.read(filtrosClientesProvider);
      ref
          .read(filtrosClientesProvider.notifier)
          .poner(filtros.copiar(q: texto.trim().isEmpty ? null : texto.trim()));
    });
  }

  void _cambiar(FiltrosClientes nuevos) =>
      ref.read(filtrosClientesProvider.notifier).poner(nuevos);

  @override
  Widget build(BuildContext context) {
    final pagina = ref.watch(clientesProvider);
    final filtros = ref.watch(filtrosClientesProvider);
    final frescura = ref.watch(frescuraClientesProvider);
    final sinSubir = ref.watch(sinSubirProvider).value ?? 0;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Cabecera(
              // Mientras no hay dato todavia no se sabe de cuando es: se dice
              // «sin descargar» y no una hora inventada.
              estado: frescura.value ?? const SinDescargar(),
              cargando: pagina.isLoading,
              sinSubir: sinSubir,
              pagina: pagina.value,
              alIr: (n) => ref.read(filtrosClientesProvider.notifier).aPagina(n),
            ),
            const SizedBox(height: 12),
            _Filtros(
              filtros: filtros,
              datos: pagina.value,
              buscador: _buscador,
              alBuscar: _buscar,
              alCambiar: _cambiar,
              alQuitar: () {
                _buscador.clear();
                ref.read(filtrosClientesProvider.notifier).quitar();
              },
            ),
            const SizedBox(height: 12),
            // El dato viejo NO se borra mientras refresca: el giro de
            // `actualizando…` ya lo dice arriba, y quitar la lista de golpe deja
            // a alguien mirando un hueco con el dedo en la fila que iba a leer.
            if (pagina.error case final fallo?)
              _Aviso(texto: 'No se pudo leer la lista local. $fallo')
            else if (pagina.value case final datos?)
              _Lista(
                datos: datos,
                filtros: filtros,
                alIr: (n) =>
                    ref.read(filtrosClientesProvider.notifier).aPagina(n),
              )
            else
              const _Aviso(texto: 'Cargando…'),
          ],
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.estado,
    required this.cargando,
    required this.sinSubir,
    required this.pagina,
    required this.alIr,
  });

  final EstadoFrescura estado;
  final bool cargando;
  final int sinSubir;
  final PaginaClientes? pagina;
  final ValueChanged<int> alIr;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final total = pagina?.total ?? 0;
    final paginas = pagina?.paginas ?? 1;
    final subtitulo = StringBuffer(
      'Clientes de PEDIDO (sincronizados, sólo con geo) + los manuales de '
      'delivery. $total en total',
    );
    if (paginas > 1) {
      subtitulo.write(' · página ${pagina!.pagina} de $paginas.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Clientes', style: tema.textTheme.headlineSmall)),
            // Siempre visible, en las 7 pantallas (caso S8): sin esto, unos
            // datos de anteayer son indistinguibles de unos al dia.
            RelojDeDatos(
              estado: estado,
              actualizando: cargando,
              sinSubir: sinSubir,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(subtitulo.toString(), style: tema.textTheme.bodySmall),
            if (pagina != null)
              PaginacionCorta(
                pagina: pagina!.pagina,
                paginas: paginas,
                alIr: alIr,
              ),
          ],
        ),
      ],
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.filtros,
    required this.datos,
    required this.buscador,
    required this.alBuscar,
    required this.alCambiar,
    required this.alQuitar,
  });

  final FiltrosClientes filtros;
  final PaginaClientes? datos;
  final TextEditingController buscador;
  final ValueChanged<String> alBuscar;
  final ValueChanged<FiltrosClientes> alCambiar;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    final municipios = datos?.municipios ?? const <Faceta>[];
    final zonas = datos?.zonas ?? const <Faceta>[];
    final vendedores = datos?.vendedores ?? const <Faceta>[];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: buscador,
            onChanged: alBuscar,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Buscar por nombre, dirección o municipio…',
            ),
          ),
        ),
        // Los selectores de la base sólo aparecen si tienen mas de una opcion:
        // un desplegable con una sola opcion no filtra nada y ocupa sitio.
        if (municipios.length > 1)
          SelectorFiltro<String>(
            titulo: 'Municipio del cliente',
            textoTodos: 'Todos los municipios',
            icono: Icons.location_city,
            valor: filtros.municipio,
            opciones: [
              for (final f in municipios)
                OpcionSelector(
                  valor: f.valor,
                  etiqueta: f.valor,
                  nota: '${f.clientes}',
                ),
            ],
            alElegir: (v) => alCambiar(filtros.copiar(municipio: v)),
          ),
        if (vendedores.length > 1)
          SelectorFiltro<String>(
            titulo: 'Vendedor que lo atiende',
            textoTodos: 'Todos los vendedores (${vendedores.length})',
            icono: Icons.person,
            valor: filtros.vendedor,
            opciones: [
              for (final f in vendedores)
                OpcionSelector(
                  valor: f.valor,
                  etiqueta: f.valor,
                  nota: '${f.clientes}',
                ),
            ],
            alElegir: (v) => alCambiar(filtros.copiar(vendedor: v)),
          ),
        SelectorFiltro<double>(
          titulo: 'A qué distancia del almacén',
          textoTodos: 'A cualquier distancia',
          icono: Icons.straighten,
          valor: filtros.kmMax,
          opciones: const [
            OpcionSelector(valor: 5.0, etiqueta: 'Hasta 5 km'),
            OpcionSelector(valor: 10.0, etiqueta: 'Hasta 10 km'),
            OpcionSelector(valor: 20.0, etiqueta: 'Hasta 20 km'),
            OpcionSelector(valor: 50.0, etiqueta: 'Hasta 50 km'),
          ],
          alElegir: (v) => alCambiar(filtros.copiar(kmMax: v)),
        ),
        SelectorFiltro<bool>(
          titulo: 'Si tiene teléfono',
          textoTodos: 'Con y sin teléfono',
          icono: Icons.phone,
          valor: filtros.telefono,
          opciones: [
            const OpcionSelector(valor: true, etiqueta: 'Con teléfono'),
            OpcionSelector(
              valor: false,
              etiqueta: 'Sin teléfono',
              nota: '${datos?.sinTelefono ?? 0}',
            ),
          ],
          alElegir: (v) => alCambiar(filtros.copiar(telefono: v)),
        ),
        if (zonas.length > 1)
          SelectorFiltro<String>(
            titulo: 'Zona de reparto',
            textoTodos: 'Todas las zonas',
            icono: Icons.map,
            valor: filtros.zona,
            opciones: [
              for (final f in zonas)
                OpcionSelector(
                  valor: f.valor,
                  etiqueta: f.valor,
                  nota: '${f.clientes}',
                ),
            ],
            alElegir: (v) => alCambiar(filtros.copiar(zona: v)),
          ),
        SelectorFiltro<OrigenCliente>(
          titulo: 'De dónde salió el cliente',
          textoTodos: 'De PEDIDO y manuales',
          icono: Icons.input,
          valor: filtros.origen,
          opciones: const [
            OpcionSelector(
              valor: OrigenCliente.pedido,
              etiqueta: 'Sólo los de PEDIDO',
            ),
            OpcionSelector(
              valor: OrigenCliente.manual,
              etiqueta: 'Sólo los manuales',
            ),
          ],
          alElegir: (v) => alCambiar(filtros.copiar(origen: v)),
        ),
        if (filtros.hayQueQuitar)
          TextButton.icon(
            onPressed: alQuitar,
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('Quitar filtros'),
          ),
      ],
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.datos,
    required this.filtros,
    required this.alIr,
  });

  final PaginaClientes datos;
  final FiltrosClientes filtros;
  final ValueChanged<int> alIr;

  @override
  Widget build(BuildContext context) {
    if (datos.clientes.isEmpty) {
      // Tres vacios distintos y se confunden con facilidad. El de «no se ha
      // descargado» va primero porque es el unico que NO es un dato: es un
      // fallo disfrazado de lista vacia (caso S7).
      if (!datos.seDescargo) {
        return const _Aviso(texto: SinDescargar.textoDeLaPantallaVacia);
      }
      if (filtros.hayQueQuitar ||
          filtros.kmMax != null ||
          filtros.telefono != null ||
          filtros.vendedor != null) {
        return const _Aviso(texto: 'Sin resultados.');
      }
      return const _Aviso(
        texto: 'Sin clientes todavía. Los de PEDIDO aparecen solos cuando '
            'tengan geolocalización.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (datos.almacenDeReferencia == null)
          const _Aviso(
            texto: 'Esta sucursal no tiene ningún almacén con coordenadas: '
                'aquí no se puede medir la distancia.',
          ),
        TablaClientes(
          clientes: datos.clientes,
          conDistancia: filtros.kmMax != null,
        ),
        PaginacionLarga(
          pagina: datos.pagina,
          paginas: datos.paginas,
          desde: datos.desde,
          hasta: datos.hasta,
          total: datos.total,
          alIr: alIr,
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(texto, textAlign: TextAlign.center),
  );
}
