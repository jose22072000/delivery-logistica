import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:reparto/nucleo/base/base.dart';

import 'geo.dart';

/// De donde salio el cliente. `manual` es `source IS NULL`: los clientes que se
/// dieron de alta a mano antes del 03/09/2026, cuando se retiro el alta.
enum OrigenCliente { pedido, manual }

/// Los 6 filtros del pliego (`pantallas.md` §4) mas la pagina.
///
/// Es inmutable y con `copiar` porque cualquier cambio de filtro vuelve a la
/// pagina 1, y eso es mucho mas facil de no olvidar en un sitio que en seis.
class FiltrosClientes {
  const FiltrosClientes({
    this.q,
    this.municipio,
    this.zona,
    this.vendedor,
    this.telefono,
    this.kmMax,
    this.origen,
    this.pagina = 1,
  });

  final String? q;
  final String? municipio;
  final String? zona;
  final String? vendedor;

  /// `true` = con telefono, `false` = sin telefono, `null` = con y sin.
  final bool? telefono;
  final double? kmMax;
  final OrigenCliente? origen;
  final int pagina;

  /// `Quitar filtros` aparece si hay municipio, zona, origen o busqueda.
  /// Distancia y telefono NO lo disparan: es lo que hace la de Next.
  bool get hayQueQuitar =>
      municipio != null ||
      zona != null ||
      origen != null ||
      (q != null && q!.trim().isNotEmpty);

  FiltrosClientes copiar({
    Object? q = _sinTocar,
    Object? municipio = _sinTocar,
    Object? zona = _sinTocar,
    Object? vendedor = _sinTocar,
    Object? telefono = _sinTocar,
    Object? kmMax = _sinTocar,
    Object? origen = _sinTocar,
    int? pagina,
  }) => FiltrosClientes(
    q: q == _sinTocar ? this.q : q as String?,
    municipio: municipio == _sinTocar ? this.municipio : municipio as String?,
    zona: zona == _sinTocar ? this.zona : zona as String?,
    vendedor: vendedor == _sinTocar ? this.vendedor : vendedor as String?,
    telefono: telefono == _sinTocar ? this.telefono : telefono as bool?,
    kmMax: kmMax == _sinTocar ? this.kmMax : kmMax as double?,
    origen: origen == _sinTocar ? this.origen : origen as OrigenCliente?,
    // Sin `pagina` explicita se vuelve a la 1: cambiar un filtro y quedarse en
    // la pagina 7 ensena una lista vacia que parece «no hay clientes».
    pagina: pagina ?? 1,
  );

  static const _sinTocar = Object();

  @override
  bool operator ==(Object other) =>
      other is FiltrosClientes &&
      other.q == q &&
      other.municipio == municipio &&
      other.zona == zona &&
      other.vendedor == vendedor &&
      other.telefono == telefono &&
      other.kmMax == kmMax &&
      other.origen == origen &&
      other.pagina == pagina;

  @override
  int get hashCode => Object.hash(
    q,
    municipio,
    zona,
    vendedor,
    telefono,
    kmMax,
    origen,
    pagina,
  );
}

/// Una opcion de un selector, con su conteo a la derecha.
class Faceta {
  const Faceta(this.valor, this.clientes);
  final String valor;
  final int clientes;
}

/// Un cliente con la distancia ya medida. `km` es `null` cuando la sucursal no
/// tiene ningun almacen con coordenadas: eso **no es cero**, es que no se sabe.
class ClienteConKm {
  const ClienteConKm(this.cliente, this.km);
  final Cliente cliente;
  final double? km;
}

/// Lo que pinta la pantalla de una vez.
class PaginaClientes {
  const PaginaClientes({
    required this.clientes,
    required this.total,
    required this.pagina,
    required this.paginas,
    required this.almacenDeReferencia,
    required this.municipios,
    required this.zonas,
    required this.vendedores,
    required this.sinTelefono,
    required this.seDescargo,
  });

  final List<ClienteConKm> clientes;

  /// Los que cuadran con los filtros, no los de esta pagina.
  final int total;
  final int pagina;
  final int paginas;

  /// Desde donde se miden los km. `null` = la sucursal no tiene punto.
  final Almacen? almacenDeReferencia;

  final List<Faceta> municipios;
  final List<Faceta> zonas;
  final List<Faceta> vendedores;
  final int sinTelefono;

  /// ¿Se bajo alguna vez la coleccion? Una lista vacia sin esto se lee como un
  /// dato cuando en realidad es un fallo (caso S7).
  final bool seDescargo;

  static const porPagina = 50;

  int get desde => clientes.isEmpty ? 0 : (pagina - 1) * porPagina + 1;
  int get hasta => (pagina - 1) * porPagina + clientes.length;
}

/// Lee clientes de la BASE LOCAL. Nunca de la red.
///
/// Esta pantalla es de las que **se miran sin conexion**: lo que se ve es la
/// foto de la ultima bajada, y de que hora es lo dice el `RelojDeDatos` de
/// arriba. Aqui no hay ni un `ClienteApi`, a proposito.
class RepositorioClientes {
  RepositorioClientes(this._base);

  final BaseLocal _base;

  /// El codigo de sucursal que usan los clientes (`sucursalCodigo`) no es el id
  /// de la sucursal: es su `externalId`. Traducirlo aqui evita que cada filtro
  /// tenga que acordarse.
  Future<String?> codigoDeSucursal(String? sucursalId) async {
    if (sucursalId == null) return null;
    final sucursal = await (_base.select(
      _base.branches,
    )..where((b) => b.id.equals(sucursalId))).getSingleOrNull();
    return sucursal?.externalId;
  }

  /// El almacen desde el que se mide: el **principal** con coordenadas, y si no
  /// hay, el primero con coordenadas (`contratos-api.md`, `GET /api/customers`).
  Future<Almacen?> almacenDeReferencia(String? codigo) async {
    if (codigo == null) return null;
    final lista =
        await (_base.select(_base.warehouses)
              ..where(
                (w) =>
                    w.sucursalCodigo.equals(codigo) &
                    w.lat.isNotNull() &
                    w.lng.isNotNull(),
              )
              // `principal` primero: en SQLite es 1/0, asi que descendente.
              ..orderBy([
                (w) => OrderingTerm.desc(w.principal),
                (w) => OrderingTerm.asc(w.nombre),
              ])
              ..limit(1))
            .get();
    return lista.isEmpty ? null : lista.first;
  }

  Expression<bool> _alcance($CustomersTable c, String? codigo) => codigo == null
      ? const Constant(true)
      // Los clientes manuales no llevan codigo y **se ven siempre**: si se
      // filtraran por sucursal desaparecerian de todas.
      : c.sucursalCodigo.equals(codigo) | c.sucursalCodigo.isNull();

  Expression<bool> _donde(
    $CustomersTable c,
    FiltrosClientes f,
    String? codigo,
    Almacen? almacen,
  ) {
    var e = _alcance(c, codigo);

    if (f.municipio != null) e = e & c.municipio.equals(f.municipio!);
    if (f.zona != null) e = e & c.zona.equals(f.zona!);
    if (f.vendedor != null) e = e & c.vendedor.equals(f.vendedor!);

    switch (f.origen) {
      case OrigenCliente.pedido:
        e = e & c.source.equals('pedido');
      case OrigenCliente.manual:
        e = e & c.source.isNull();
      case null:
        break;
    }

    // Calcado del servidor, con su asimetria incluida: `1` es `phone != null` y
    // `0` es `null` o vacio. Un telefono guardado como cadena vacia cae en los
    // dos lados. Se copia tal cual porque el criterio de terminado es dar el
    // MISMO numero que la de Next, no uno mejor.
    if (f.telefono == true) e = e & c.phone.isNotNull();
    if (f.telefono == false) e = e & (c.phone.isNull() | c.phone.equals(''));

    final q = f.q?.trim();
    if (q != null && q.isNotEmpty) {
      final patron = '%${q.toLowerCase()}%';
      Expression<bool> contiene(GeneratedColumn<String> col) =>
          col.lower().like(patron);
      e =
          e &
          (contiene(c.name) |
              contiene(c.address) |
              contiene(c.municipio) |
              contiene(c.zona) |
              contiene(c.phone) |
              contiene(c.codigo) |
              contiene(c.vendedor));
    }

    // La caja previa de la distancia, la misma del servidor. Es un filtro que
    // el indice sabe resolver; la distancia exacta se mide despues y sólo sobre
    // la pagina, porque el haversine no se puede meter en un indice.
    final kmMax = f.kmMax;
    if (kmMax != null && kmMax > 0 && almacen?.lat != null) {
      final lat0 = almacen!.lat!;
      final lng0 = almacen.lng!;
      final gradosLat = kmMax / 111;
      final gradosLng =
          kmMax / (111 * math.max(0.1, math.cos(lat0 * math.pi / 180)));
      e =
          e &
          c.lat.isBetweenValues(lat0 - gradosLat, lat0 + gradosLat) &
          c.lng.isBetweenValues(lng0 - gradosLng, lng0 + gradosLng);
    }

    return e;
  }

  Future<List<Faceta>> _faceta(
    GeneratedColumn<String> columna,
    String? codigo,
  ) async {
    final cuenta = _base.customers.id.count();
    final filas =
        await (_base.selectOnly(_base.customers)
              ..addColumns([columna, cuenta])
              ..where(_alcance(_base.customers, codigo) & columna.isNotNull())
              ..groupBy([columna])
              ..orderBy([OrderingTerm.asc(columna)]))
            .get();
    return [
      for (final fila in filas)
        Faceta(fila.read(columna) ?? '', fila.read(cuenta) ?? 0),
    ];
  }

  Future<int> _sinTelefono(String? codigo) async {
    final c = _base.customers;
    final cuenta = c.id.count();
    final fila =
        await (_base.selectOnly(c)
              ..addColumns([cuenta])
              ..where(
                _alcance(c, codigo) & (c.phone.isNull() | c.phone.equals('')),
              ))
            .getSingle();
    return fila.read(cuenta) ?? 0;
  }

  /// La consulta entera de la pantalla.
  Future<PaginaClientes> consultar(
    FiltrosClientes f, {
    String? sucursalId,
  }) async {
    final codigo = await codigoDeSucursal(sucursalId);
    final almacen = await almacenDeReferencia(codigo);
    final c = _base.customers;
    final donde = _donde(c, f, codigo, almacen);

    final cuenta = c.id.count();
    final filaTotal =
        await (_base.selectOnly(c)
              ..addColumns([cuenta])
              ..where(donde))
            .getSingle();
    final total = filaTotal.read(cuenta) ?? 0;
    final paginas = math.max(1, (total / PaginaClientes.porPagina).ceil());
    final pagina = f.pagina.clamp(1, paginas);

    final filas =
        await (_base.select(c)
              ..where((_) => donde)
              ..orderBy([(t) => OrderingTerm.asc(t.name)])
              ..limit(
                PaginaClientes.porPagina,
                offset: (pagina - 1) * PaginaClientes.porPagina,
              ))
            .get();

    // La distancia exacta, sólo sobre la pagina. Igual que el servidor: `total`
    // es el de la caja previa, asi que puede sobrar alguno y por eso la ultima
    // pagina a veces trae menos de 50. Es lo que hace la de Next.
    final conKm = <ClienteConKm>[];
    for (final cliente in filas) {
      double? km;
      if (almacen?.lat != null) {
        km = Geo.km2(
          Geo.haversineKm(
            almacen!.lat!,
            almacen.lng!,
            cliente.lat,
            cliente.lng,
          ),
        );
        if (f.kmMax != null && f.kmMax! > 0 && km > f.kmMax!) continue;
      }
      conKm.add(ClienteConKm(cliente, km));
    }

    return PaginaClientes(
      clientes: conKm,
      total: total,
      pagina: pagina,
      paginas: paginas,
      almacenDeReferencia: almacen,
      municipios: await _faceta(c.municipio, codigo),
      zonas: await _faceta(c.zona, codigo),
      vendedores: await _faceta(c.vendedor, codigo),
      sinTelefono: await _sinTelefono(codigo),
      seDescargo:
          (await (_base.select(_base.frescura)
                    ..where((fr) => fr.coleccion.equals(Colecciones.clientes)))
                  .getSingleOrNull())
              ?.bajadaAt !=
          null,
    );
  }
}
