// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'textos.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class TextosEs extends Textos {
  TextosEs([String locale = 'es']) : super(locale);

  @override
  String get ajustesAgregarMoneda => '+ Agregar moneda';

  @override
  String get ajustesAjustesGuardados => 'Configuración guardada';

  @override
  String get ajustesAyudaDomicilio =>
      'La ÚNICA fórmula de precio del sistema. Lo que se le cobra al cliente lo pone el repartidor desde la APK; esto es lo que delivery usa para repartir la carga del camión entre los pedidos.';

  @override
  String get ajustesAyudaMonedas =>
      'USD es la moneda base (=1). Agrega otras monedas con su tasa: cuántas unidades equivalen a 1 USD. En la barra superior eliges en qué moneda ver todos los precios.';

  @override
  String get ajustesCodigo => 'Código';

  @override
  String get ajustesDomicilioGuardado => 'Precios de domicilio guardados';

  @override
  String ajustesEjemplo(Object km, Object kg) {
    return 'Ejemplo con $km km y $kg kg:';
  }

  @override
  String get ajustesGuardando => 'Guardando...';

  @override
  String get ajustesGuardarAjustes => 'Guardar configuración';

  @override
  String get ajustesGuardarDomicilio => 'Guardar precios de domicilio';

  @override
  String get ajustesGuardarMonedas => 'Guardar monedas';

  @override
  String get ajustesMonedasGuardadas => 'Monedas actualizadas';

  @override
  String get ajustesNotaFormula =>
      'El ×2 cubre ida y vuelta. Cada cliente paga según su distancia al punto de partida, no a la parada anterior.';

  @override
  String get ajustesPistaCostoPorKm => '(se aplica ×2 por ida y vuelta)';

  @override
  String get ajustesTitulo => 'Configuración';

  @override
  String get ajustesTituloDomicilio => 'Costo del domicilio';

  @override
  String get ajustesTituloFormula => 'Fórmula de cálculo por cliente';

  @override
  String get ajustesTituloMonedas => 'Monedas y tasas de cambio';

  @override
  String get ajustesTituloPrecios => 'Configuración de Precios (USD)';

  @override
  String get ajustesUnidadesPorUsd => 'Unidades por 1 USD';

  @override
  String get barraIdioma => 'Idioma';

  @override
  String get barraMoneda => 'Moneda de visualización';

  @override
  String get comunAcciones => 'Acciones';

  @override
  String get comunActualizar => 'Actualizar';

  @override
  String get comunBuscar => 'Buscar';

  @override
  String get comunCancelar => 'Cancelar';

  @override
  String get comunCargando => 'Cargando...';

  @override
  String get comunCrear => 'Crear';

  @override
  String get comunDesde => 'Desde';

  @override
  String get comunEditar => 'Editar';

  @override
  String get comunEliminar => 'Eliminar';

  @override
  String get comunEstado => 'Estado';

  @override
  String get comunFecha => 'Fecha';

  @override
  String get comunGuardar => 'Guardar';

  @override
  String get comunHasta => 'Hasta';

  @override
  String get comunKg => 'kg';

  @override
  String get comunKm => 'km';

  @override
  String get comunLimpiar => 'Limpiar';

  @override
  String get comunNombre => 'Nombre';

  @override
  String get comunOpcional => '(opcional)';

  @override
  String get comunPeso => 'Peso';

  @override
  String get comunPrecio => 'Precio';

  @override
  String get comunQuitar => 'Quitar';

  @override
  String get comunTodos => 'Todos';

  @override
  String get excelFiltroFecha => 'Filtro fecha';

  @override
  String get excelGenerado => 'Generado';

  @override
  String get excelKmDesdePartida => 'Km desde partida';

  @override
  String get excelMoneda => 'Moneda';

  @override
  String get excelTituloReporte => 'Reporte de transportación — ProCovar';

  @override
  String get loginContrasena => 'Contraseña';

  @override
  String get loginCorreo => 'Correo';

  @override
  String get loginEntrando => 'Iniciando sesión...';

  @override
  String get loginEntrar => 'Iniciar Sesión';

  @override
  String get loginFallo => 'Error de inicio de sesión';

  @override
  String get loginNotaAdmin =>
      'Las cuentas son gestionadas por un administrador.';

  @override
  String get loginSubtitulo => 'Optimización de Rutas de Delivery';

  @override
  String get navAlmacenes => 'Almacenes';

  @override
  String get navCerrarSesion => 'Cerrar sesión';

  @override
  String get navClientes => 'Clientes';

  @override
  String get navConfiguracion => 'Configuración';

  @override
  String get navPanel => 'Panel';

  @override
  String get navPedidos => 'Pedidos';

  @override
  String get navPlataforma => 'Plataforma de Delivery';

  @override
  String get navProductos => 'Productos';

  @override
  String get navReportes => 'Reportes';

  @override
  String get navRutas => 'Rutas';

  @override
  String get navSucursales => 'Sucursales';

  @override
  String get navUsuarios => 'Usuarios';

  @override
  String get navVehiculos => 'Vehículos';

  @override
  String get panelAccionesRapidas => 'Acciones Rápidas';

  @override
  String get panelFilaIngresos => 'Ingresos totales';

  @override
  String get panelFilaOrdenes => 'Total órdenes';

  @override
  String get panelFilaPeso => 'Peso total entregado';

  @override
  String get panelFilaPromedio => 'Precio promedio por orden';

  @override
  String get panelGestionarFlota => 'Gestionar Flota';

  @override
  String get panelIngresosTotales => 'Ingresos Totales';

  @override
  String panelPesoTotalEntregado(Object v) {
    return '$v kg peso total entregado';
  }

  @override
  String get panelPlanificarRutas => 'Planificar Rutas';

  @override
  String panelPromedioPorOrden(Object v) {
    return 'Promedio $v por orden';
  }

  @override
  String get panelResumen => 'Resumen';

  @override
  String get panelTitulo => 'Panel';

  @override
  String get panelTotalPedidos => 'Total de Órdenes';

  @override
  String get panelVehiculosRegistrados => 'Vehículos Registrados';

  @override
  String get panelVerReportes => 'Ver Reportes';

  @override
  String get pedidoManualAgregarEste => '+ Agregar este pedido';

  @override
  String get pedidoManualCliente => 'Nombre del cliente *';

  @override
  String get pedidoManualDireccion => 'Dirección de entrega *';

  @override
  String get pedidoManualMarcadorCliente => 'Ej: Juan Pérez';

  @override
  String get pedidoManualPeso => 'Peso (kg) *';

  @override
  String get pedidosColArticulos => 'Artículos';

  @override
  String get pedidosColCliente => 'Cliente';

  @override
  String get pedidosColDireccion => 'Dirección';

  @override
  String get pedidosColEntrega => 'Entrega';

  @override
  String get pedidosColRuta => 'Ruta';

  @override
  String get pedidosColVehiculo => 'Vehículo';

  @override
  String get pedidosSubtitulo =>
      'Todos los pedidos acumulados de todas las rutas';

  @override
  String get pedidosTitulo => 'Pedidos';

  @override
  String pedidosTotalPedidos(Object n) {
    return 'Total de pedidos: $n';
  }

  @override
  String get pedidosVacio => 'Aún no hay pedidos. Crea una ruta con pedidos.';

  @override
  String get productosAgregarAlPedido => 'Agregar';

  @override
  String get productosBotonImportar => 'Importar productos';

  @override
  String get productosBuscar => 'Buscar producto...';

  @override
  String get productosCant => 'Cant.';

  @override
  String get productosCargando => 'Cargando productos...';

  @override
  String get productosElegir => 'Selecciona un producto';

  @override
  String get productosEmpaque => 'Empaque';

  @override
  String get productosErrorImportarWarehouse =>
      'No se pudo importar del warehouse';

  @override
  String get productosGrupo => 'Grupo / tipo';

  @override
  String get productosImportandoWarehouse => 'Importando...';

  @override
  String get productosImportar => 'Importar';

  @override
  String get productosImportarWarehouse => 'Importar del Warehouse';

  @override
  String get productosMasUsados => 'Más usados';

  @override
  String get productosNombre => 'Nombre';

  @override
  String get productosNueva => '+ Nuevo Producto';

  @override
  String get productosPeso => 'Peso (kg)';

  @override
  String get productosPesoAuto => 'Peso calculado';

  @override
  String get productosPistaImportar =>
      'Una línea por producto: nombre, peso(kg), empaque, unid/empaque, grupo';

  @override
  String productosResultadoImportarWarehouse(Object c, Object u) {
    return 'Importados: $c creados, $u actualizados';
  }

  @override
  String get productosSinResultados => 'Sin resultados';

  @override
  String get productosSubtitulo =>
      'Catálogo de productos. Úsalos en los pedidos; el peso se calcula solo.';

  @override
  String get productosTitulo => 'Productos';

  @override
  String get productosTituloCrear => 'Nuevo Producto';

  @override
  String get productosTituloEditar => 'Editar Producto';

  @override
  String get productosTituloImportar => 'Importar productos (CSV)';

  @override
  String get productosTodosResultados => 'Resultados';

  @override
  String get productosUnidadesPorEmpaque => 'Unid. por empaque';

  @override
  String get productosVacio => 'Sin productos. Agrega o importa el primero.';

  @override
  String get registroDeshabilitado =>
      'El registro de nuevos usuarios está deshabilitado. Las cuentas las crean y gestionan solo los administradores.';

  @override
  String get registroPolitica => 'Política de acceso empresarial';

  @override
  String get registroTieneCuenta => '¿Ya tienes una cuenta?';

  @override
  String get reportesCargando => 'Cargando reporte...';

  @override
  String get reportesColCliente => 'Cliente';

  @override
  String get reportesColDestino => 'Destino';

  @override
  String get reportesColIngresos => 'Ingresos';

  @override
  String get reportesColOrdenes => 'Órdenes';

  @override
  String get reportesColPeso => 'Peso Total';

  @override
  String get reportesColPlaca => 'Placa';

  @override
  String get reportesColPromedioOrden => 'Promedio/Orden';

  @override
  String get reportesColRuta => 'Ruta';

  @override
  String reportesCuentaOrdenes(Object n) {
    return '$n órdenes';
  }

  @override
  String get reportesExportar => 'Exportar a Excel';

  @override
  String get reportesFiltros => 'Filtros';

  @override
  String get reportesIngresosTotales => 'Ingresos Totales';

  @override
  String get reportesPesoTotal => 'Peso Total';

  @override
  String get reportesPestanaOrdenes => 'Detalle de Órdenes';

  @override
  String get reportesPestanaPorVehiculo => 'Por Vehículo';

  @override
  String get reportesPestanaResumen => 'Resumen';

  @override
  String get reportesPrecioPromedio => 'Precio Promedio';

  @override
  String get reportesSinDatosVehiculos =>
      'No hay datos de vehículos para los filtros seleccionados.';

  @override
  String get reportesSinOrdenes =>
      'No hay órdenes para los filtros seleccionados.';

  @override
  String get reportesTitulo => 'Reportes';

  @override
  String get reportesTodosVehiculos => 'Todos los vehículos';

  @override
  String get reportesTopVehiculos => 'Top vehículos';

  @override
  String get reportesTotalPedidos => 'Total Órdenes';

  @override
  String get reportesTotales => 'Totales';

  @override
  String get reportesVehiculo => 'Vehículo';

  @override
  String get rutasActivas => 'Activas';

  @override
  String get rutasAgregarArticulo => '+ Agregar artículo';

  @override
  String get rutasAgregarPedido => '+ Agregar pedido de cliente';

  @override
  String get rutasArticulos => 'Artículos';

  @override
  String rutasAvisoSobreCapacidad(Object w, Object c) {
    return 'Peso ($w kg) supera capacidad del vehículo ($c kg)';
  }

  @override
  String get rutasBuscarPedidos => 'Buscar pedido...';

  @override
  String get rutasCantArticulo => 'Cant.';

  @override
  String rutasCapacidad(Object c) {
    return 'cap. $c kg';
  }

  @override
  String get rutasCargaTotal => 'Carga total';

  @override
  String get rutasCargandoPedidos => 'Cargando pedidos...';

  @override
  String get rutasCompletando => 'Completando...';

  @override
  String get rutasContinuar => 'Continuar →';

  @override
  String rutasCuentaElegidos(Object n) {
    return '$n pedidos seleccionados';
  }

  @override
  String get rutasDescripcionArticulo => 'Descripción';

  @override
  String get rutasElegirOrigenGuardado => '— Seleccionar origen guardado —';

  @override
  String get rutasElegirParaVer => 'Selecciona una ruta para ver el detalle';

  @override
  String get rutasElegirVehiculo => '— Selecciona un vehículo —';

  @override
  String get rutasEliminarGuardado => 'Eliminar guardado';

  @override
  String get rutasEnCurso => 'En curso';

  @override
  String get rutasEstadoCompletada => 'Completada';

  @override
  String get rutasEstadoEnCurso => 'En curso';

  @override
  String get rutasEstadoPlanificada => 'Planificada';

  @override
  String get rutasFechaEntrega => 'Fecha de entrega';

  @override
  String get rutasFechaEntregaOpc => 'Fecha de entrega (opcional)';

  @override
  String get rutasGenerando => 'Generando ruta...';

  @override
  String get rutasGenerar => 'Generar Ruta';

  @override
  String get rutasGuardarOrigen => '+ Guardar este origen para uso futuro';

  @override
  String get rutasHistorial => 'Historial';

  @override
  String get rutasIniciando => 'Iniciando...';

  @override
  String get rutasIniciar => 'Iniciar ruta';

  @override
  String rutasKmDesdePartida(Object km) {
    return '$km km desde partida';
  }

  @override
  String rutasKmInclRegreso(Object km) {
    return '$km km (incl. regreso)';
  }

  @override
  String get rutasLeyendaParadas => 'Paradas';

  @override
  String get rutasLeyendaPartida => 'Punto de partida';

  @override
  String get rutasLeyendaRegreso => 'Regreso al depósito';

  @override
  String get rutasMarcadorBuscar => 'Buscar por código, nombre, vehículo...';

  @override
  String get rutasMarcadorDeposito =>
      'Dirección del depósito, coordenadas, o click en el mapa';

  @override
  String get rutasMarcadorNombre => 'Nombre (el código se genera solo)';

  @override
  String get rutasMarcadorNombreOrigen =>
      'Nombre del origen (ej: Bodega Central)';

  @override
  String get rutasMarcarCompletada => 'Marcar como completada';

  @override
  String get rutasNotaCompletada => 'Ruta completada — en historial.';

  @override
  String get rutasNotaSoloLectura =>
      'Ruta activa (solo lectura). Al completarla, el vehículo queda disponible y pasa al historial.';

  @override
  String get rutasNueva => '+ Nueva Ruta';

  @override
  String get rutasOIngresaNuevo => '— o ingresa uno nuevo abajo —';

  @override
  String rutasParadasKm(Object n, Object km) {
    return '$n paradas · $km km';
  }

  @override
  String rutasParadasYPrecio(Object n) {
    return 'Paradas y precio por cliente ($n)';
  }

  @override
  String get rutasPaso1 => 'Punto de partida';

  @override
  String get rutasPaso2Nombre => 'y nombre (opcional)';

  @override
  String get rutasPaso2Vehiculo => 'Vehículo *';

  @override
  String rutasPaso3Pedidos(Object n) {
    return 'Pedidos de cliente ($n)';
  }

  @override
  String get rutasPedidosDisponibles => 'Pedidos disponibles';

  @override
  String get rutasPlanificador => 'Planificador de Rutas';

  @override
  String rutasResumenPedidos(Object n) {
    return '$n pedidos';
  }

  @override
  String rutasSeccionPedidoManual(Object n) {
    return 'Agregar pedido manual ($n)';
  }

  @override
  String get rutasSinActivas => 'Sin rutas activas. Crea la primera.';

  @override
  String get rutasSinArticulos => 'Sin artículos detallados';

  @override
  String get rutasSinCodigo => 'Sin código';

  @override
  String get rutasSinCompletadas => 'Sin rutas completadas aún.';

  @override
  String get rutasSinDefinir => 'Sin definir';

  @override
  String get rutasSinEnCurso => 'Sin rutas en curso.';

  @override
  String get rutasSinGps => 'Sin coordenadas GPS para esta ruta';

  @override
  String get rutasSinPedidosDisponibles =>
      'No hay pedidos disponibles para rutear.';

  @override
  String get rutasSinVehiculosDisponibles =>
      'No hay vehículos disponibles. Crea o libera uno en Vehículos para poder crear la ruta.';

  @override
  String get rutasSobrepeso => 'Sobrepeso';

  @override
  String rutasSobrepesoDetalle(Object w, Object c) {
    return 'Peso total ($w kg) supera capacidad ($c kg)';
  }

  @override
  String get rutasTitulo => 'Rutas';

  @override
  String get rutasTituloModal => 'Nueva Ruta';

  @override
  String rutasVerParadas(Object n) {
    return 'Ver paradas ($n)';
  }

  @override
  String get sucursalesAgregarPuntoPartida => '+ Agregar punto de partida';

  @override
  String get sucursalesArea => 'Área de cobertura (km²)';

  @override
  String get sucursalesCargando => 'Cargando sucursales...';

  @override
  String get sucursalesCodigo => 'Código';

  @override
  String sucursalesCuentaPuntosPartida(Object n) {
    return '$n puntos de partida';
  }

  @override
  String get sucursalesMarcadorCodigo => 'Ej: CAM, STG';

  @override
  String sucursalesMiembros(Object n) {
    return '$n usuarios';
  }

  @override
  String get sucursalesNombre => 'Nombre de la sucursal';

  @override
  String get sucursalesNombrePuntoPartida =>
      'Nombre del punto (ej: Almacén Central)';

  @override
  String get sucursalesNotaCodigo =>
      'Identifica la sucursal y la enlaza con PEDIDO. Usa el mismo código que en PEDIDO.';

  @override
  String get sucursalesNueva => '+ Nueva Sucursal';

  @override
  String get sucursalesPistaPuntosPartida =>
      'Una sucursal puede tener varios puntos de partida (punto de venta, almacenes...). Se usan al crear rutas.';

  @override
  String get sucursalesPuntosPartida => 'Puntos de partida';

  @override
  String get sucursalesSinCodigo => 'sin código';

  @override
  String get sucursalesSinPermiso =>
      'No tienes permisos para gestionar sucursales.';

  @override
  String get sucursalesSinPuntosPartida =>
      'Sin puntos de partida. Agrega el primero.';

  @override
  String get sucursalesSubtitulo =>
      'Gestiona las sucursales. El mapa se centra en la sucursal del usuario.';

  @override
  String get sucursalesTitulo => 'Sucursales';

  @override
  String get sucursalesTituloCrear => 'Crear Sucursal';

  @override
  String get sucursalesTituloEditar => 'Editar Sucursal';

  @override
  String get sucursalesUbicacion => 'Ubicación de la sucursal';

  @override
  String get sucursalesVacio => 'Sin sucursales. Crea la primera.';

  @override
  String get ubicacionAyuda =>
      'Escribe la dirección (autocompleta), pega lat, lng, o haz click en el mapa.';

  @override
  String get ubicacionBuscando => 'Buscando ubicación…';

  @override
  String get ubicacionEtiqueta => 'Ubicación';

  @override
  String get ubicacionMarcador =>
      'Escribe una dirección, pega \"lat, lng\", o haz click en el mapa';

  @override
  String get ubicacionNoEncontrado =>
      'No se encontró. Sé más específico, pega coordenadas, o usa el mapa.';

  @override
  String usuariosActividad(Object o, Object r, Object v) {
    return '$o órdenes, $r rutas, $v vehículos';
  }

  @override
  String get usuariosAdmin => 'Administración de Usuarios';

  @override
  String get usuariosCargando => 'Cargando usuarios...';

  @override
  String get usuariosColActividad => 'Actividad';

  @override
  String get usuariosColCorreo => 'Correo';

  @override
  String get usuariosColRol => 'Rol';

  @override
  String get usuariosContrasenaNueva => 'Nueva contraseña (opcional)';

  @override
  String get usuariosContrasenaTemporal => 'Contraseña temporal';

  @override
  String get usuariosCorreo => 'Correo electrónico';

  @override
  String get usuariosNombreCompleto => 'Nombre completo';

  @override
  String get usuariosNotaSucursal =>
      'Un usuario con sucursal solo ve/gestiona los datos de ESA sucursal. Sin sucursal = admin global (ve todas).';

  @override
  String get usuariosNueva => '+ Nuevo Usuario';

  @override
  String get usuariosSinPermiso =>
      'No tienes permisos para gestionar usuarios.';

  @override
  String get usuariosSinSucursal => 'Sin sucursal (admin — ve todo)';

  @override
  String get usuariosSucursal => 'Sucursal';

  @override
  String get usuariosSucursalGlobal => 'Global / Todas';

  @override
  String get usuariosTitulo => 'Usuarios';

  @override
  String get usuariosTituloCrear => 'Crear Usuario';

  @override
  String get usuariosTituloEditar => 'Editar Usuario';

  @override
  String get vehiculosAgregar => 'Agregar Vehículo';

  @override
  String get vehiculosCapacidad => 'Capacidad';

  @override
  String get vehiculosCapacidadMax => 'Capacidad Máx. (kg)';

  @override
  String get vehiculosCargando => 'Cargando vehículos...';

  @override
  String get vehiculosEstadoDisponible => 'Disponible';

  @override
  String get vehiculosEstadoEnUso => 'En uso';

  @override
  String get vehiculosEstadoMantenimiento => 'Mantenimiento';

  @override
  String get vehiculosEtiquetaNombre => 'Nombre del Vehículo *';

  @override
  String get vehiculosMarcadorNombre => 'Ej: Camión #1, Furgoneta Azul';

  @override
  String get vehiculosMarcadorNotas => 'Información relevante del vehículo...';

  @override
  String get vehiculosMarcarDisponible => 'Marcar disponible';

  @override
  String get vehiculosNotas => 'Notas (opcional)';

  @override
  String vehiculosOrdenesAsignadas(Object n) {
    return '$n órdenes asignadas';
  }

  @override
  String get vehiculosPistaGestion =>
      'Gestiona tu flota. Las tarifas se configuran globalmente en Configuración.';

  @override
  String get vehiculosPistaTarifas =>
      'Las tarifas de precios se configuran globalmente en Configuración.';

  @override
  String get vehiculosPistaVacio =>
      'Agrega tu primer vehículo para asignarlo a rutas';

  @override
  String get vehiculosPlaca => 'Placa (opcional)';

  @override
  String get vehiculosRutaActiva => 'Ruta activa';

  @override
  String get vehiculosRutas => 'Rutas';

  @override
  String get vehiculosTipo => 'Tipo';

  @override
  String get vehiculosTipoAuto => 'Auto';

  @override
  String get vehiculosTipoBicicleta => 'Bicicleta';

  @override
  String get vehiculosTipoCamion => 'Camión';

  @override
  String get vehiculosTipoFurgoneta => 'Furgoneta';

  @override
  String get vehiculosTipoMoto => 'Moto';

  @override
  String get vehiculosTipoOtro => 'Otro';

  @override
  String get vehiculosTitulo => 'Vehículos';

  @override
  String get vehiculosTituloEditar => 'Editar Vehículo';

  @override
  String get vehiculosTituloNuevo => 'Nuevo Vehículo';

  @override
  String get vehiculosVacio => 'Sin vehículos';

  @override
  String get nuevoCerrar => 'Cerrar';

  @override
  String get nuevoCompartir => 'Compartir';

  @override
  String get nuevoImprimir => 'Imprimir';

  @override
  String get nuevoPdfNoSePudo => 'No se pudo armar la hoja';

  @override
  String get nuevoVistaPreviaTitulo => 'Vista previa';
}
