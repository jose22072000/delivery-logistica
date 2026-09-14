// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'textos.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class TextosEn extends Textos {
  TextosEn([String locale = 'en']) : super(locale);

  @override
  String get ajustesAgregarMoneda => '+ Add currency';

  @override
  String get ajustesAjustesGuardados => 'Settings saved';

  @override
  String get ajustesAyudaDomicilio =>
      'The ONLY pricing formula in the system. What the customer is charged is set by the courier in the APK; this is what delivery uses to split truck load across orders.';

  @override
  String get ajustesAyudaMonedas =>
      'USD is the base currency (=1). Add other currencies with their rate: how many units equal 1 USD. In the top bar you choose which currency to view all prices in.';

  @override
  String get ajustesCodigo => 'Code';

  @override
  String get ajustesDomicilioGuardado => 'Home delivery prices saved';

  @override
  String ajustesEjemplo(Object km, Object kg) {
    return 'Example with $km km and $kg kg:';
  }

  @override
  String get ajustesGuardando => 'Saving...';

  @override
  String get ajustesGuardarAjustes => 'Save settings';

  @override
  String get ajustesGuardarDomicilio => 'Save home delivery prices';

  @override
  String get ajustesGuardarMonedas => 'Save currencies';

  @override
  String get ajustesMonedasGuardadas => 'Currencies updated';

  @override
  String get ajustesNotaFormula =>
      'The ×2 covers the round trip. Each client pays by their distance to the start point, not to the previous stop.';

  @override
  String get ajustesPistaCostoPorKm => '(applied ×2 for round trip)';

  @override
  String get ajustesTitulo => 'Settings';

  @override
  String get ajustesTituloDomicilio => 'Home delivery cost';

  @override
  String get ajustesTituloFormula => 'Per-client pricing formula';

  @override
  String get ajustesTituloMonedas => 'Currencies and exchange rates';

  @override
  String get ajustesTituloPrecios => 'Pricing Settings (USD)';

  @override
  String get ajustesUnidadesPorUsd => 'Units per 1 USD';

  @override
  String get barraIdioma => 'Language';

  @override
  String get barraMoneda => 'Display currency';

  @override
  String get comunAcciones => 'Actions';

  @override
  String get comunActualizar => 'Update';

  @override
  String get comunBuscar => 'Search';

  @override
  String get comunCancelar => 'Cancel';

  @override
  String get comunCargando => 'Loading...';

  @override
  String get comunCrear => 'Create';

  @override
  String get comunDesde => 'From';

  @override
  String get comunEditar => 'Edit';

  @override
  String get comunEliminar => 'Delete';

  @override
  String get comunEstado => 'Status';

  @override
  String get comunFecha => 'Date';

  @override
  String get comunGuardar => 'Save';

  @override
  String get comunHasta => 'To';

  @override
  String get comunKg => 'kg';

  @override
  String get comunKm => 'km';

  @override
  String get comunLimpiar => 'Clear';

  @override
  String get comunNombre => 'Name';

  @override
  String get comunOpcional => '(optional)';

  @override
  String get comunPeso => 'Weight';

  @override
  String get comunPrecio => 'Price';

  @override
  String get comunQuitar => 'Remove';

  @override
  String get comunTodos => 'All';

  @override
  String get excelFiltroFecha => 'Date filter';

  @override
  String get excelGenerado => 'Generated';

  @override
  String get excelKmDesdePartida => 'Km from start';

  @override
  String get excelMoneda => 'Currency';

  @override
  String get excelTituloReporte => 'Transportation report — ProCovar';

  @override
  String get loginContrasena => 'Password';

  @override
  String get loginCorreo => 'Email';

  @override
  String get loginEntrando => 'Signing in...';

  @override
  String get loginEntrar => 'Sign In';

  @override
  String get loginFallo => 'Login failed';

  @override
  String get loginNotaAdmin => 'User accounts are managed by an administrator.';

  @override
  String get loginSubtitulo => 'Delivery Route Optimization';

  @override
  String get navAlmacenes => 'Warehouses';

  @override
  String get navCerrarSesion => 'Log out';

  @override
  String get navClientes => 'Customers';

  @override
  String get navConfiguracion => 'Settings';

  @override
  String get navPanel => 'Dashboard';

  @override
  String get navPedidos => 'Orders';

  @override
  String get navPlataforma => 'Delivery Platform';

  @override
  String get navProductos => 'Products';

  @override
  String get navReportes => 'Reports';

  @override
  String get navRutas => 'Routes';

  @override
  String get navSucursales => 'Branches';

  @override
  String get navUsuarios => 'Users';

  @override
  String get navVehiculos => 'Vehicles';

  @override
  String get panelAccionesRapidas => 'Quick Actions';

  @override
  String get panelFilaIngresos => 'Total revenue';

  @override
  String get panelFilaOrdenes => 'Total orders';

  @override
  String get panelFilaPeso => 'Total weight delivered';

  @override
  String get panelFilaPromedio => 'Average price per order';

  @override
  String get panelGestionarFlota => 'Manage Fleet';

  @override
  String get panelIngresosTotales => 'Total Revenue';

  @override
  String panelPesoTotalEntregado(Object v) {
    return '$v kg total weight delivered';
  }

  @override
  String get panelPlanificarRutas => 'Plan Routes';

  @override
  String panelPromedioPorOrden(Object v) {
    return 'Average $v per order';
  }

  @override
  String get panelResumen => 'Summary';

  @override
  String get panelTitulo => 'Dashboard';

  @override
  String get panelTotalPedidos => 'Total Orders';

  @override
  String get panelVehiculosRegistrados => 'Registered Vehicles';

  @override
  String get panelVerReportes => 'View Reports';

  @override
  String get pedidoManualAgregarEste => '+ Add this order';

  @override
  String get pedidoManualCliente => 'Client name *';

  @override
  String get pedidoManualDireccion => 'Delivery address *';

  @override
  String get pedidoManualMarcadorCliente => 'e.g. John Doe';

  @override
  String get pedidoManualPeso => 'Weight (kg) *';

  @override
  String get pedidosColArticulos => 'Items';

  @override
  String get pedidosColCliente => 'Client';

  @override
  String get pedidosColDireccion => 'Address';

  @override
  String get pedidosColEntrega => 'Delivery';

  @override
  String get pedidosColRuta => 'Route';

  @override
  String get pedidosColVehiculo => 'Vehicle';

  @override
  String get pedidosSubtitulo => 'All accumulated orders across every route';

  @override
  String get pedidosTitulo => 'Orders';

  @override
  String pedidosTotalPedidos(Object n) {
    return 'Total orders: $n';
  }

  @override
  String get pedidosVacio => 'No orders yet. Create a route with orders.';

  @override
  String get productosAgregarAlPedido => 'Add';

  @override
  String get productosBotonImportar => 'Import products';

  @override
  String get productosBuscar => 'Search product...';

  @override
  String get productosCant => 'Qty';

  @override
  String get productosCargando => 'Loading products...';

  @override
  String get productosElegir => 'Select a product';

  @override
  String get productosEmpaque => 'Packaging';

  @override
  String get productosErrorImportarWarehouse =>
      'Could not import from warehouse';

  @override
  String get productosGrupo => 'Group / type';

  @override
  String get productosImportandoWarehouse => 'Importing...';

  @override
  String get productosImportar => 'Import';

  @override
  String get productosImportarWarehouse => 'Import from Warehouse';

  @override
  String get productosMasUsados => 'Most used';

  @override
  String get productosNombre => 'Name';

  @override
  String get productosNueva => '+ New Product';

  @override
  String get productosPeso => 'Weight (kg)';

  @override
  String get productosPesoAuto => 'Calculated weight';

  @override
  String get productosPistaImportar =>
      'One line per product: name, weight(kg), packaging, units/package, group';

  @override
  String productosResultadoImportarWarehouse(Object c, Object u) {
    return 'Imported: $c created, $u updated';
  }

  @override
  String get productosSinResultados => 'No results';

  @override
  String get productosSubtitulo =>
      'Product catalog. Use them in orders; weight is auto-calculated.';

  @override
  String get productosTitulo => 'Products';

  @override
  String get productosTituloCrear => 'New Product';

  @override
  String get productosTituloEditar => 'Edit Product';

  @override
  String get productosTituloImportar => 'Import products (CSV)';

  @override
  String get productosTodosResultados => 'Results';

  @override
  String get productosUnidadesPorEmpaque => 'Units per package';

  @override
  String get productosVacio => 'No products. Add or import the first one.';

  @override
  String get registroDeshabilitado =>
      'New user registration is disabled. Accounts are created and managed only by system administrators.';

  @override
  String get registroPolitica => 'Enterprise access policy';

  @override
  String get registroTieneCuenta => 'Already have an account?';

  @override
  String get reportesCargando => 'Loading report...';

  @override
  String get reportesColCliente => 'Client';

  @override
  String get reportesColDestino => 'Destination';

  @override
  String get reportesColIngresos => 'Revenue';

  @override
  String get reportesColOrdenes => 'Orders';

  @override
  String get reportesColPeso => 'Total Weight';

  @override
  String get reportesColPlaca => 'Plate';

  @override
  String get reportesColPromedioOrden => 'Avg/Order';

  @override
  String get reportesColRuta => 'Route';

  @override
  String reportesCuentaOrdenes(Object n) {
    return '$n orders';
  }

  @override
  String get reportesExportar => 'Export to Excel';

  @override
  String get reportesFiltros => 'Filters';

  @override
  String get reportesIngresosTotales => 'Total Revenue';

  @override
  String get reportesPesoTotal => 'Total Weight';

  @override
  String get reportesPestanaOrdenes => 'Order Detail';

  @override
  String get reportesPestanaPorVehiculo => 'By Vehicle';

  @override
  String get reportesPestanaResumen => 'Summary';

  @override
  String get reportesPrecioPromedio => 'Average Price';

  @override
  String get reportesSinDatosVehiculos =>
      'No vehicle data for the selected filters.';

  @override
  String get reportesSinOrdenes => 'No orders for the selected filters.';

  @override
  String get reportesTitulo => 'Reports';

  @override
  String get reportesTodosVehiculos => 'All vehicles';

  @override
  String get reportesTopVehiculos => 'Top vehicles';

  @override
  String get reportesTotalPedidos => 'Total Orders';

  @override
  String get reportesTotales => 'Totals';

  @override
  String get reportesVehiculo => 'Vehicle';

  @override
  String get rutasActivas => 'Active';

  @override
  String get rutasAgregarArticulo => '+ Add item';

  @override
  String get rutasAgregarPedido => '+ Add client order';

  @override
  String get rutasArticulos => 'Items';

  @override
  String rutasAvisoSobreCapacidad(Object w, Object c) {
    return 'Weight ($w kg) exceeds vehicle capacity ($c kg)';
  }

  @override
  String get rutasBuscarPedidos => 'Search order...';

  @override
  String get rutasCantArticulo => 'Qty';

  @override
  String rutasCapacidad(Object c) {
    return 'cap. $c kg';
  }

  @override
  String get rutasCargaTotal => 'Total load';

  @override
  String get rutasCargandoPedidos => 'Loading orders...';

  @override
  String get rutasCompletando => 'Completing...';

  @override
  String get rutasContinuar => 'Continue →';

  @override
  String rutasCuentaElegidos(Object n) {
    return '$n orders selected';
  }

  @override
  String get rutasDescripcionArticulo => 'Description';

  @override
  String get rutasElegirOrigenGuardado => '— Select a saved origin —';

  @override
  String get rutasElegirParaVer => 'Select a route to see details';

  @override
  String get rutasElegirVehiculo => '— Select a vehicle —';

  @override
  String get rutasEliminarGuardado => 'Delete saved';

  @override
  String get rutasEnCurso => 'In progress';

  @override
  String get rutasEstadoCompletada => 'Completed';

  @override
  String get rutasEstadoEnCurso => 'In progress';

  @override
  String get rutasEstadoPlanificada => 'Planned';

  @override
  String get rutasFechaEntrega => 'Delivery date';

  @override
  String get rutasFechaEntregaOpc => 'Delivery date (optional)';

  @override
  String get rutasGenerando => 'Generating route...';

  @override
  String get rutasGenerar => 'Generate Route';

  @override
  String get rutasGuardarOrigen => '+ Save this origin for future use';

  @override
  String get rutasHistorial => 'History';

  @override
  String get rutasIniciando => 'Starting...';

  @override
  String get rutasIniciar => 'Start route';

  @override
  String rutasKmDesdePartida(Object km) {
    return '$km km from start';
  }

  @override
  String rutasKmInclRegreso(Object km) {
    return '$km km (incl. return)';
  }

  @override
  String get rutasLeyendaParadas => 'Stops';

  @override
  String get rutasLeyendaPartida => 'Start point';

  @override
  String get rutasLeyendaRegreso => 'Return to depot';

  @override
  String get rutasMarcadorBuscar => 'Search by code, name, vehicle...';

  @override
  String get rutasMarcadorDeposito =>
      'Depot address, coordinates, or click on the map';

  @override
  String get rutasMarcadorNombre => 'Name (code is generated automatically)';

  @override
  String get rutasMarcadorNombreOrigen => 'Origin name (e.g. Central Depot)';

  @override
  String get rutasMarcarCompletada => 'Mark as completed';

  @override
  String get rutasNotaCompletada => 'Route completed — in history.';

  @override
  String get rutasNotaSoloLectura =>
      'Active route (read-only). On completion, the vehicle is freed and it moves to history.';

  @override
  String get rutasNueva => '+ New Route';

  @override
  String get rutasOIngresaNuevo => '— or enter a new one below —';

  @override
  String rutasParadasKm(Object n, Object km) {
    return '$n stops · $km km';
  }

  @override
  String rutasParadasYPrecio(Object n) {
    return 'Stops and price per client ($n)';
  }

  @override
  String get rutasPaso1 => 'Start point';

  @override
  String get rutasPaso2Nombre => 'and name (optional)';

  @override
  String get rutasPaso2Vehiculo => 'Vehicle *';

  @override
  String rutasPaso3Pedidos(Object n) {
    return 'Client orders ($n)';
  }

  @override
  String get rutasPedidosDisponibles => 'Available orders';

  @override
  String get rutasPlanificador => 'Route Planner';

  @override
  String rutasResumenPedidos(Object n) {
    return '$n orders';
  }

  @override
  String rutasSeccionPedidoManual(Object n) {
    return 'Add manual order ($n)';
  }

  @override
  String get rutasSinActivas => 'No active routes. Create the first one.';

  @override
  String get rutasSinArticulos => 'No itemized contents';

  @override
  String get rutasSinCodigo => 'No code';

  @override
  String get rutasSinCompletadas => 'No completed routes yet.';

  @override
  String get rutasSinDefinir => 'Not set';

  @override
  String get rutasSinEnCurso => 'No routes in progress.';

  @override
  String get rutasSinGps => 'No GPS coordinates for this route';

  @override
  String get rutasSinPedidosDisponibles => 'No orders available to route.';

  @override
  String get rutasSinVehiculosDisponibles =>
      'No vehicles available. Create or free one in Vehicles to create the route.';

  @override
  String get rutasSobrepeso => 'Overweight';

  @override
  String rutasSobrepesoDetalle(Object w, Object c) {
    return 'Total weight ($w kg) exceeds capacity ($c kg)';
  }

  @override
  String get rutasTitulo => 'Routes';

  @override
  String get rutasTituloModal => 'New Route';

  @override
  String rutasVerParadas(Object n) {
    return 'View stops ($n)';
  }

  @override
  String get sucursalesAgregarPuntoPartida => '+ Add start point';

  @override
  String get sucursalesArea => 'Coverage area (km²)';

  @override
  String get sucursalesCargando => 'Loading branches...';

  @override
  String get sucursalesCodigo => 'Code';

  @override
  String sucursalesCuentaPuntosPartida(Object n) {
    return '$n start points';
  }

  @override
  String get sucursalesMarcadorCodigo => 'e.g. CAM, STG';

  @override
  String sucursalesMiembros(Object n) {
    return '$n users';
  }

  @override
  String get sucursalesNombre => 'Branch name';

  @override
  String get sucursalesNombrePuntoPartida =>
      'Point name (e.g. Central Warehouse)';

  @override
  String get sucursalesNotaCodigo =>
      'Identifies the branch and links it with PEDIDO. Use the same code as in PEDIDO.';

  @override
  String get sucursalesNueva => '+ New Branch';

  @override
  String get sucursalesPistaPuntosPartida =>
      'A branch can have several start points (point of sale, warehouses...). Used when creating routes.';

  @override
  String get sucursalesPuntosPartida => 'Start points';

  @override
  String get sucursalesSinCodigo => 'no code';

  @override
  String get sucursalesSinPermiso =>
      'You do not have permission to manage branches.';

  @override
  String get sucursalesSinPuntosPartida =>
      'No start points yet. Add the first one.';

  @override
  String get sucursalesSubtitulo =>
      'Manage branches. The map centers on the user\'s branch.';

  @override
  String get sucursalesTitulo => 'Branches';

  @override
  String get sucursalesTituloCrear => 'Create Branch';

  @override
  String get sucursalesTituloEditar => 'Edit Branch';

  @override
  String get sucursalesUbicacion => 'Branch location';

  @override
  String get sucursalesVacio => 'No branches. Create the first one.';

  @override
  String get ubicacionAyuda =>
      'Type the address (autocompletes), paste lat, lng, or click on the map.';

  @override
  String get ubicacionBuscando => 'Searching location…';

  @override
  String get ubicacionEtiqueta => 'Location';

  @override
  String get ubicacionMarcador =>
      'Type an address, paste \"lat, lng\", or click on the map';

  @override
  String get ubicacionNoEncontrado =>
      'Not found. Be more specific, paste coordinates, or use the map.';

  @override
  String usuariosActividad(Object o, Object r, Object v) {
    return '$o orders, $r routes, $v vehicles';
  }

  @override
  String get usuariosAdmin => 'User Management';

  @override
  String get usuariosCargando => 'Loading users...';

  @override
  String get usuariosColActividad => 'Activity';

  @override
  String get usuariosColCorreo => 'Email';

  @override
  String get usuariosColRol => 'Role';

  @override
  String get usuariosContrasenaNueva => 'New password (optional)';

  @override
  String get usuariosContrasenaTemporal => 'Temporary password';

  @override
  String get usuariosCorreo => 'Email address';

  @override
  String get usuariosNombreCompleto => 'Full name';

  @override
  String get usuariosNotaSucursal =>
      'A user with a branch only sees/manages the data of THAT branch. No branch = global admin (sees all).';

  @override
  String get usuariosNueva => '+ New User';

  @override
  String get usuariosSinPermiso =>
      'You do not have permission to manage users.';

  @override
  String get usuariosSinSucursal => 'No branch (admin — sees everything)';

  @override
  String get usuariosSucursal => 'Branch';

  @override
  String get usuariosSucursalGlobal => 'Global / All';

  @override
  String get usuariosTitulo => 'Users';

  @override
  String get usuariosTituloCrear => 'Create User';

  @override
  String get usuariosTituloEditar => 'Edit User';

  @override
  String get vehiculosAgregar => 'Add Vehicle';

  @override
  String get vehiculosCapacidad => 'Capacity';

  @override
  String get vehiculosCapacidadMax => 'Max Capacity (kg)';

  @override
  String get vehiculosCargando => 'Loading vehicles...';

  @override
  String get vehiculosEstadoDisponible => 'Available';

  @override
  String get vehiculosEstadoEnUso => 'In use';

  @override
  String get vehiculosEstadoMantenimiento => 'Maintenance';

  @override
  String get vehiculosEtiquetaNombre => 'Vehicle Name *';

  @override
  String get vehiculosMarcadorNombre => 'e.g. Truck #1, Blue Van';

  @override
  String get vehiculosMarcadorNotas => 'Relevant vehicle information...';

  @override
  String get vehiculosMarcarDisponible => 'Mark available';

  @override
  String get vehiculosNotas => 'Notes (optional)';

  @override
  String vehiculosOrdenesAsignadas(Object n) {
    return '$n orders assigned';
  }

  @override
  String get vehiculosPistaGestion =>
      'Manage your fleet. Rates are configured globally in Settings.';

  @override
  String get vehiculosPistaTarifas =>
      'Pricing rates are configured globally in Settings.';

  @override
  String get vehiculosPistaVacio =>
      'Add your first vehicle to assign it to routes';

  @override
  String get vehiculosPlaca => 'Plate (optional)';

  @override
  String get vehiculosRutaActiva => 'Active route';

  @override
  String get vehiculosRutas => 'Routes';

  @override
  String get vehiculosTipo => 'Type';

  @override
  String get vehiculosTipoAuto => 'Car';

  @override
  String get vehiculosTipoBicicleta => 'Bicycle';

  @override
  String get vehiculosTipoCamion => 'Truck';

  @override
  String get vehiculosTipoFurgoneta => 'Van';

  @override
  String get vehiculosTipoMoto => 'Motorcycle';

  @override
  String get vehiculosTipoOtro => 'Other';

  @override
  String get vehiculosTitulo => 'Vehicles';

  @override
  String get vehiculosTituloEditar => 'Edit Vehicle';

  @override
  String get vehiculosTituloNuevo => 'New Vehicle';

  @override
  String get vehiculosVacio => 'No vehicles';

  @override
  String get nuevoCerrar => 'Close';

  @override
  String get nuevoCompartir => 'Share';

  @override
  String get nuevoImprimir => 'Print';

  @override
  String get nuevoPdfNoSePudo => 'The sheet could not be built';

  @override
  String get nuevoVistaPreviaTitulo => 'Print preview';
}
