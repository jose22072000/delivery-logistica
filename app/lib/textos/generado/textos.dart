import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'textos_en.dart';
import 'textos_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of Textos
/// returned by `Textos.of(context)`.
///
/// Applications need to include `Textos.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generado/textos.dart';
///
/// return MaterialApp(
///   localizationsDelegates: Textos.localizationsDelegates,
///   supportedLocales: Textos.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the Textos.supportedLocales
/// property.
abstract class Textos {
  Textos(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static Textos of(BuildContext context) {
    return Localizations.of<Textos>(context, Textos)!;
  }

  static const LocalizationsDelegate<Textos> delegate = _TextosDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// De `set.addCurrency` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Agregar moneda'**
  String get ajustesAgregarMoneda;

  /// De `set.configSaved` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Configuración guardada'**
  String get ajustesAjustesGuardados;

  /// De `set.homeHelp` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'La ÚNICA fórmula de precio del sistema. Lo que se le cobra al cliente lo pone el repartidor desde la APK; esto es lo que delivery usa para repartir la carga del camión entre los pedidos.'**
  String get ajustesAyudaDomicilio;

  /// De `set.currenciesHelp` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'USD es la moneda base (=1). Agrega otras monedas con su tasa: cuántas unidades equivalen a 1 USD. En la barra superior eliges en qué moneda ver todos los precios.'**
  String get ajustesAyudaMonedas;

  /// De `set.code` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Código'**
  String get ajustesCodigo;

  /// De `set.homeSaved` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Precios de domicilio guardados'**
  String get ajustesDomicilioGuardado;

  /// De `set.example` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ejemplo con {km} km y {kg} kg:'**
  String ajustesEjemplo(Object km, Object kg);

  /// De `set.saving` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Guardando...'**
  String get ajustesGuardando;

  /// De `set.saveConfig` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Guardar configuración'**
  String get ajustesGuardarAjustes;

  /// De `set.saveHome` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Guardar precios de domicilio'**
  String get ajustesGuardarDomicilio;

  /// De `set.saveCurrencies` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Guardar monedas'**
  String get ajustesGuardarMonedas;

  /// De `set.currenciesSaved` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Monedas actualizadas'**
  String get ajustesMonedasGuardadas;

  /// De `set.formulaNote` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'El ×2 cubre ida y vuelta. Cada cliente paga según su distancia al punto de partida, no a la parada anterior.'**
  String get ajustesNotaFormula;

  /// De `set.costPerKmHint` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'(se aplica ×2 por ida y vuelta)'**
  String get ajustesPistaCostoPorKm;

  /// De `set.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Configuración'**
  String get ajustesTitulo;

  /// De `set.homeTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Costo del domicilio'**
  String get ajustesTituloDomicilio;

  /// De `set.formulaTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Fórmula de cálculo por cliente'**
  String get ajustesTituloFormula;

  /// De `set.currenciesTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Monedas y tasas de cambio'**
  String get ajustesTituloMonedas;

  /// De `set.pricingTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Configuración de Precios (USD)'**
  String get ajustesTituloPrecios;

  /// De `set.unitsPerUsd` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Unidades por 1 USD'**
  String get ajustesUnidadesPorUsd;

  /// De `navbar.language` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get barraIdioma;

  /// De `navbar.currency` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Moneda de visualización'**
  String get barraMoneda;

  /// De `common.actions` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Acciones'**
  String get comunAcciones;

  /// De `common.update` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Actualizar'**
  String get comunActualizar;

  /// De `common.search` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get comunBuscar;

  /// De `common.cancel` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get comunCancelar;

  /// De `common.loading` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cargando...'**
  String get comunCargando;

  /// De `common.create` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get comunCrear;

  /// De `common.from` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Desde'**
  String get comunDesde;

  /// De `common.edit` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Editar'**
  String get comunEditar;

  /// De `common.delete` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get comunEliminar;

  /// De `common.status` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Estado'**
  String get comunEstado;

  /// De `common.date` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Fecha'**
  String get comunFecha;

  /// De `common.save` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get comunGuardar;

  /// De `common.to` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Hasta'**
  String get comunHasta;

  /// De `common.kg` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'kg'**
  String get comunKg;

  /// De `common.km` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'km'**
  String get comunKm;

  /// De `common.clear` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Limpiar'**
  String get comunLimpiar;

  /// De `common.name` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get comunNombre;

  /// De `common.optional` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'(opcional)'**
  String get comunOpcional;

  /// De `common.weight` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso'**
  String get comunPeso;

  /// De `common.price` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Precio'**
  String get comunPrecio;

  /// De `common.remove` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Quitar'**
  String get comunQuitar;

  /// De `common.all` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Todos'**
  String get comunTodos;

  /// De `xls.dateFilter` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Filtro fecha'**
  String get excelFiltroFecha;

  /// De `xls.generated` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Generado'**
  String get excelGenerado;

  /// De `xls.kmFromStart` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Km desde partida'**
  String get excelKmDesdePartida;

  /// De `xls.currency` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Moneda'**
  String get excelMoneda;

  /// De `xls.reportTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Reporte de transportación — ProCovar'**
  String get excelTituloReporte;

  /// De `login.password` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get loginContrasena;

  /// De `login.email` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Correo'**
  String get loginCorreo;

  /// De `login.signingIn` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Iniciando sesión...'**
  String get loginEntrando;

  /// De `login.signIn` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Iniciar Sesión'**
  String get loginEntrar;

  /// De `login.failed` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Error de inicio de sesión'**
  String get loginFallo;

  /// De `login.adminNote` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Las cuentas son gestionadas por un administrador.'**
  String get loginNotaAdmin;

  /// De `login.subtitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Optimización de Rutas de Delivery'**
  String get loginSubtitulo;

  /// De `nav.warehouses` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Almacenes'**
  String get navAlmacenes;

  /// De `nav.logout` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión'**
  String get navCerrarSesion;

  /// De `nav.customers` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Clientes'**
  String get navClientes;

  /// De `nav.settings` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Configuración'**
  String get navConfiguracion;

  /// De `nav.dashboard` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Panel'**
  String get navPanel;

  /// De `nav.orders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Pedidos'**
  String get navPedidos;

  /// De `nav.platform` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Plataforma de Delivery'**
  String get navPlataforma;

  /// De `nav.products` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Productos'**
  String get navProductos;

  /// De `nav.reports` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Reportes'**
  String get navReportes;

  /// De `nav.routes` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Rutas'**
  String get navRutas;

  /// De `nav.branches` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sucursales'**
  String get navSucursales;

  /// De `nav.users` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Usuarios'**
  String get navUsuarios;

  /// De `nav.vehicles` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Vehículos'**
  String get navVehiculos;

  /// De `dash.quickActions` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Acciones Rápidas'**
  String get panelAccionesRapidas;

  /// De `dash.rowRevenue` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ingresos totales'**
  String get panelFilaIngresos;

  /// De `dash.rowOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Total órdenes'**
  String get panelFilaOrdenes;

  /// De `dash.rowWeight` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso total entregado'**
  String get panelFilaPeso;

  /// De `dash.rowAvg` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Precio promedio por orden'**
  String get panelFilaPromedio;

  /// De `dash.manageFleet` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Gestionar Flota'**
  String get panelGestionarFlota;

  /// De `dash.totalRevenue` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ingresos Totales'**
  String get panelIngresosTotales;

  /// De `dash.totalWeightDelivered` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{v} kg peso total entregado'**
  String panelPesoTotalEntregado(Object v);

  /// De `dash.planRoutes` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Planificar Rutas'**
  String get panelPlanificarRutas;

  /// De `dash.avgPerOrder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Promedio {v} por orden'**
  String panelPromedioPorOrden(Object v);

  /// De `dash.summary` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Resumen'**
  String get panelResumen;

  /// De `dash.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Panel'**
  String get panelTitulo;

  /// De `dash.totalOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Total de Órdenes'**
  String get panelTotalPedidos;

  /// De `dash.vehiclesRegistered` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Vehículos Registrados'**
  String get panelVehiculosRegistrados;

  /// De `dash.viewReports` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ver Reportes'**
  String get panelVerReportes;

  /// De `pedido.addThis` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Agregar este pedido'**
  String get pedidoManualAgregarEste;

  /// De `pedido.customer` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre del cliente *'**
  String get pedidoManualCliente;

  /// De `pedido.address` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Dirección de entrega *'**
  String get pedidoManualDireccion;

  /// De `pedido.customerPh` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ej: Juan Pérez'**
  String get pedidoManualMarcadorCliente;

  /// De `pedido.weight` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso (kg) *'**
  String get pedidoManualPeso;

  /// De `ord.colItems` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Artículos'**
  String get pedidosColArticulos;

  /// De `ord.colClient` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cliente'**
  String get pedidosColCliente;

  /// De `ord.colAddress` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Dirección'**
  String get pedidosColDireccion;

  /// De `ord.colDelivery` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Entrega'**
  String get pedidosColEntrega;

  /// De `ord.colRoute` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ruta'**
  String get pedidosColRuta;

  /// De `ord.colVehicle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Vehículo'**
  String get pedidosColVehiculo;

  /// De `ord.subtitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Todos los pedidos acumulados de todas las rutas'**
  String get pedidosSubtitulo;

  /// De `ord.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Pedidos'**
  String get pedidosTitulo;

  /// De `ord.totalOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Total de pedidos: {n}'**
  String pedidosTotalPedidos(Object n);

  /// De `ord.empty` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay pedidos. Crea una ruta con pedidos.'**
  String get pedidosVacio;

  /// De `prod.addToOrder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Agregar'**
  String get productosAgregarAlPedido;

  /// De `prod.importBtn` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Importar productos'**
  String get productosBotonImportar;

  /// De `prod.search` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Buscar producto...'**
  String get productosBuscar;

  /// De `prod.qty` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cant.'**
  String get productosCant;

  /// De `prod.loading` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cargando productos...'**
  String get productosCargando;

  /// De `prod.pick` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Selecciona un producto'**
  String get productosElegir;

  /// De `prod.packaging` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Empaque'**
  String get productosEmpaque;

  /// De `prod.importWarehouseError` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'No se pudo importar del warehouse'**
  String get productosErrorImportarWarehouse;

  /// De `prod.category` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Grupo / tipo'**
  String get productosGrupo;

  /// De `prod.importingWarehouse` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Importando...'**
  String get productosImportandoWarehouse;

  /// De `prod.import` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Importar'**
  String get productosImportar;

  /// De `prod.importWarehouse` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Importar del Warehouse'**
  String get productosImportarWarehouse;

  /// De `prod.topUsed` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Más usados'**
  String get productosMasUsados;

  /// De `prod.name` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get productosNombre;

  /// De `prod.new` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Nuevo Producto'**
  String get productosNueva;

  /// De `prod.weight` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso (kg)'**
  String get productosPeso;

  /// De `prod.autoWeight` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso calculado'**
  String get productosPesoAuto;

  /// De `prod.importHint` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Una línea por producto: nombre, peso(kg), empaque, unid/empaque, grupo'**
  String get productosPistaImportar;

  /// De `prod.importWarehouseResult` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Importados: {c} creados, {u} actualizados'**
  String productosResultadoImportarWarehouse(Object c, Object u);

  /// De `prod.none` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin resultados'**
  String get productosSinResultados;

  /// De `prod.subtitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Catálogo de productos. Úsalos en los pedidos; el peso se calcula solo.'**
  String get productosSubtitulo;

  /// De `prod.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Productos'**
  String get productosTitulo;

  /// De `prod.createTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nuevo Producto'**
  String get productosTituloCrear;

  /// De `prod.editTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Editar Producto'**
  String get productosTituloEditar;

  /// De `prod.importTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Importar productos (CSV)'**
  String get productosTituloImportar;

  /// De `prod.allResults` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Resultados'**
  String get productosTodosResultados;

  /// De `prod.unitsPerPackage` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Unid. por empaque'**
  String get productosUnidadesPorEmpaque;

  /// De `prod.empty` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin productos. Agrega o importa el primero.'**
  String get productosVacio;

  /// De `register.disabled` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'El registro de nuevos usuarios está deshabilitado. Las cuentas las crean y gestionan solo los administradores.'**
  String get registroDeshabilitado;

  /// De `register.policy` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Política de acceso empresarial'**
  String get registroPolitica;

  /// De `register.haveAccount` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'¿Ya tienes una cuenta?'**
  String get registroTieneCuenta;

  /// De `rep.loading` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cargando reporte...'**
  String get reportesCargando;

  /// De `rep.colClient` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cliente'**
  String get reportesColCliente;

  /// De `rep.colDest` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Destino'**
  String get reportesColDestino;

  /// De `rep.colRevenue` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ingresos'**
  String get reportesColIngresos;

  /// De `rep.colOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Órdenes'**
  String get reportesColOrdenes;

  /// De `rep.colWeight` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso Total'**
  String get reportesColPeso;

  /// De `rep.colPlate` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Placa'**
  String get reportesColPlaca;

  /// De `rep.colAvgOrder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Promedio/Orden'**
  String get reportesColPromedioOrden;

  /// De `rep.colRoute` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ruta'**
  String get reportesColRuta;

  /// De `rep.ordersCount` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{n} órdenes'**
  String reportesCuentaOrdenes(Object n);

  /// De `rep.export` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Exportar a Excel'**
  String get reportesExportar;

  /// De `rep.filters` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Filtros'**
  String get reportesFiltros;

  /// De `rep.totalRevenue` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ingresos Totales'**
  String get reportesIngresosTotales;

  /// De `rep.totalWeight` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso Total'**
  String get reportesPesoTotal;

  /// De `rep.tabOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Detalle de Órdenes'**
  String get reportesPestanaOrdenes;

  /// De `rep.tabByVehicle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Por Vehículo'**
  String get reportesPestanaPorVehiculo;

  /// De `rep.tabSummary` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Resumen'**
  String get reportesPestanaResumen;

  /// De `rep.avgPrice` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Precio Promedio'**
  String get reportesPrecioPromedio;

  /// De `rep.noVehicleData` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'No hay datos de vehículos para los filtros seleccionados.'**
  String get reportesSinDatosVehiculos;

  /// De `rep.noOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'No hay órdenes para los filtros seleccionados.'**
  String get reportesSinOrdenes;

  /// De `rep.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Reportes'**
  String get reportesTitulo;

  /// De `rep.allVehicles` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Todos los vehículos'**
  String get reportesTodosVehiculos;

  /// De `rep.topVehicles` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Top vehículos'**
  String get reportesTopVehiculos;

  /// De `rep.totalOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Total Órdenes'**
  String get reportesTotalPedidos;

  /// De `rep.totals` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Totales'**
  String get reportesTotales;

  /// De `rep.vehicle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Vehículo'**
  String get reportesVehiculo;

  /// De `routes.active` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Planificadas'**
  String get rutasActivas;

  /// De `routes.addItem` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Agregar artículo'**
  String get rutasAgregarArticulo;

  /// De `routes.addOrder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Agregar pedido de cliente'**
  String get rutasAgregarPedido;

  /// De `routes.items` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Artículos'**
  String get rutasArticulos;

  /// De `routes.overCapWarn` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso ({w} kg) supera capacidad del vehículo ({c} kg)'**
  String rutasAvisoSobreCapacidad(Object w, Object c);

  /// De `routes.searchOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Buscar pedido...'**
  String get rutasBuscarPedidos;

  /// De `routes.itemQty` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cant.'**
  String get rutasCantArticulo;

  /// De `routes.capacity` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'cap. {c} kg'**
  String rutasCapacidad(Object c);

  /// De `routes.totalLoad` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Carga total'**
  String get rutasCargaTotal;

  /// De `routes.loadingOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cargando pedidos...'**
  String get rutasCargandoPedidos;

  /// De `routes.completing` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Completando...'**
  String get rutasCompletando;

  /// De `routes.continue` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Continuar →'**
  String get rutasContinuar;

  /// De `routes.selectedCount` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{n} pedidos seleccionados'**
  String rutasCuentaElegidos(Object n);

  /// De `routes.itemDesc` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Descripción'**
  String get rutasDescripcionArticulo;

  /// De `routes.selectSavedOrigin` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'— Seleccionar origen guardado —'**
  String get rutasElegirOrigenGuardado;

  /// De `routes.selectToView` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Selecciona una ruta para ver el detalle'**
  String get rutasElegirParaVer;

  /// De `routes.selectVehicle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'— Selecciona un vehículo —'**
  String get rutasElegirVehiculo;

  /// De `routes.deleteSaved` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Eliminar guardado'**
  String get rutasEliminarGuardado;

  /// De `routes.inProgress` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'En curso'**
  String get rutasEnCurso;

  /// De `routes.status.completed` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Completada'**
  String get rutasEstadoCompletada;

  /// De `routes.status.in_progress` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'En curso'**
  String get rutasEstadoEnCurso;

  /// De `routes.status.planned` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Planificada'**
  String get rutasEstadoPlanificada;

  /// De `routes.deliveryDate` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Fecha de entrega'**
  String get rutasFechaEntrega;

  /// De `routes.deliveryDateOpt` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Fecha de entrega (opcional)'**
  String get rutasFechaEntregaOpc;

  /// De `routes.generating` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Generando ruta...'**
  String get rutasGenerando;

  /// De `routes.generate` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Generar Ruta'**
  String get rutasGenerar;

  /// De `routes.saveOrigin` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Guardar este origen para uso futuro'**
  String get rutasGuardarOrigen;

  /// De `routes.history` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Historial'**
  String get rutasHistorial;

  /// De `routes.starting` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Iniciando...'**
  String get rutasIniciando;

  /// De `routes.start` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Iniciar ruta'**
  String get rutasIniciar;

  /// De `routes.kmFromStart` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{km} km desde partida'**
  String rutasKmDesdePartida(Object km);

  /// De `routes.kmInclReturn` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{km} km (incl. regreso)'**
  String rutasKmInclRegreso(Object km);

  /// De `routes.legendStops` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Paradas'**
  String get rutasLeyendaParadas;

  /// De `routes.legendStart` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Punto de partida'**
  String get rutasLeyendaPartida;

  /// De `routes.legendReturn` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Regreso al depósito'**
  String get rutasLeyendaRegreso;

  /// De `routes.searchPlaceholder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Buscar por código, nombre, vehículo...'**
  String get rutasMarcadorBuscar;

  /// De `routes.depotPlaceholder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Dirección del depósito, coordenadas, o click en el mapa'**
  String get rutasMarcadorDeposito;

  /// De `routes.namePlaceholder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre (el código se genera solo)'**
  String get rutasMarcadorNombre;

  /// De `routes.originNamePh` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre del origen (ej: Bodega Central)'**
  String get rutasMarcadorNombreOrigen;

  /// De `routes.markComplete` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Marcar como completada'**
  String get rutasMarcarCompletada;

  /// De `routes.completedNote` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ruta completada — en historial.'**
  String get rutasNotaCompletada;

  /// De `routes.readonlyNote` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ruta activa (solo lectura). Al completarla, el vehículo queda disponible y pasa al historial.'**
  String get rutasNotaSoloLectura;

  /// De `routes.new` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Nueva Ruta'**
  String get rutasNueva;

  /// De `routes.orEnterNew` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'— o ingresa uno nuevo abajo —'**
  String get rutasOIngresaNuevo;

  /// De `routes.stopsKm` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{n} paradas · {km} km'**
  String rutasParadasKm(Object n, Object km);

  /// De `routes.stopsAndPrice` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Paradas y precio por cliente ({n})'**
  String rutasParadasYPrecio(Object n);

  /// De `routes.step1` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Punto de partida'**
  String get rutasPaso1;

  /// De `routes.step2Name` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'y nombre (opcional)'**
  String get rutasPaso2Nombre;

  /// De `routes.step2Vehicle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Vehículo *'**
  String get rutasPaso2Vehiculo;

  /// De `routes.step3Orders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Pedidos de cliente ({n})'**
  String rutasPaso3Pedidos(Object n);

  /// De `routes.availableOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Pedidos disponibles'**
  String get rutasPedidosDisponibles;

  /// De `routes.planner` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Planificador de Rutas'**
  String get rutasPlanificador;

  /// De `routes.ordersSummary` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{n} pedidos'**
  String rutasResumenPedidos(Object n);

  /// De `routes.manualOrderSection` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Agregar pedido manual ({n})'**
  String rutasSeccionPedidoManual(Object n);

  /// De `routes.noActive` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin rutas activas. Crea la primera.'**
  String get rutasSinActivas;

  /// De `routes.noItems` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin artículos detallados'**
  String get rutasSinArticulos;

  /// De `routes.noCode` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin código'**
  String get rutasSinCodigo;

  /// De `routes.noCompleted` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin rutas completadas aún.'**
  String get rutasSinCompletadas;

  /// De `routes.notSet` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin definir'**
  String get rutasSinDefinir;

  /// De `routes.noInProgress` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin rutas en curso.'**
  String get rutasSinEnCurso;

  /// De `routes.noGps` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin coordenadas GPS para esta ruta'**
  String get rutasSinGps;

  /// De `routes.noAvailOrders` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'No hay pedidos disponibles para rutear.'**
  String get rutasSinPedidosDisponibles;

  /// De `routes.noVehiclesAvail` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'No hay vehículos disponibles. Crea o libera uno en Vehículos para poder crear la ruta.'**
  String get rutasSinVehiculosDisponibles;

  /// De `routes.overweight` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sobrepeso'**
  String get rutasSobrepeso;

  /// De `routes.overweightFull` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Peso total ({w} kg) supera capacidad ({c} kg)'**
  String rutasSobrepesoDetalle(Object w, Object c);

  /// De `routes.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Rutas'**
  String get rutasTitulo;

  /// De `routes.modalTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nueva Ruta'**
  String get rutasTituloModal;

  /// De `routes.viewStops` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ver paradas ({n})'**
  String rutasVerParadas(Object n);

  /// De `br.addStartPoint` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Agregar punto de partida'**
  String get sucursalesAgregarPuntoPartida;

  /// De `br.area` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Área de cobertura (km²)'**
  String get sucursalesArea;

  /// De `br.loading` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cargando sucursales...'**
  String get sucursalesCargando;

  /// De `br.code` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Código'**
  String get sucursalesCodigo;

  /// De `br.startPointsCount` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{n} puntos de partida'**
  String sucursalesCuentaPuntosPartida(Object n);

  /// De `br.codePlaceholder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ej: CAM, STG'**
  String get sucursalesMarcadorCodigo;

  /// De `br.members` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{n} usuarios'**
  String sucursalesMiembros(Object n);

  /// De `br.name` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre de la sucursal'**
  String get sucursalesNombre;

  /// De `br.startPointName` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre del punto (ej: Almacén Central)'**
  String get sucursalesNombrePuntoPartida;

  /// De `br.codeNote` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Identifica la sucursal y la enlaza con PEDIDO. Usa el mismo código que en PEDIDO.'**
  String get sucursalesNotaCodigo;

  /// De `br.new` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Nueva Sucursal'**
  String get sucursalesNueva;

  /// De `br.startPointsHint` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Una sucursal puede tener varios puntos de partida (punto de venta, almacenes...). Se usan al crear rutas.'**
  String get sucursalesPistaPuntosPartida;

  /// De `br.startPoints` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Puntos de partida'**
  String get sucursalesPuntosPartida;

  /// De `br.noCode` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'sin código'**
  String get sucursalesSinCodigo;

  /// De `br.noPermission` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'No tienes permisos para gestionar sucursales.'**
  String get sucursalesSinPermiso;

  /// De `br.noStartPoints` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin puntos de partida. Agrega el primero.'**
  String get sucursalesSinPuntosPartida;

  /// De `br.subtitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Gestiona las sucursales. El mapa se centra en la sucursal del usuario.'**
  String get sucursalesSubtitulo;

  /// De `br.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sucursales'**
  String get sucursalesTitulo;

  /// De `br.createTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Crear Sucursal'**
  String get sucursalesTituloCrear;

  /// De `br.editTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Editar Sucursal'**
  String get sucursalesTituloEditar;

  /// De `br.location` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ubicación de la sucursal'**
  String get sucursalesUbicacion;

  /// De `br.empty` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin sucursales. Crea la primera.'**
  String get sucursalesVacio;

  /// De `loc.help` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Escribe la dirección (autocompleta), pega lat, lng, o haz click en el mapa.'**
  String get ubicacionAyuda;

  /// De `loc.searching` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Buscando ubicación…'**
  String get ubicacionBuscando;

  /// De `loc.label` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ubicación'**
  String get ubicacionEtiqueta;

  /// De `loc.placeholder` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Escribe una dirección, pega \"lat, lng\", o haz click en el mapa'**
  String get ubicacionMarcador;

  /// De `loc.notfound` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'No se encontró. Sé más específico, pega coordenadas, o usa el mapa.'**
  String get ubicacionNoEncontrado;

  /// De `usr.activity` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{o} órdenes, {r} rutas, {v} vehículos'**
  String usuariosActividad(Object o, Object r, Object v);

  /// De `usr.admin` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Administración de Usuarios'**
  String get usuariosAdmin;

  /// De `usr.loading` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cargando usuarios...'**
  String get usuariosCargando;

  /// De `usr.colActivity` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Actividad'**
  String get usuariosColActividad;

  /// De `usr.colEmail` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Correo'**
  String get usuariosColCorreo;

  /// De `usr.colRole` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Rol'**
  String get usuariosColRol;

  /// De `usr.newPassword` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nueva contraseña (opcional)'**
  String get usuariosContrasenaNueva;

  /// De `usr.tempPassword` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Contraseña temporal'**
  String get usuariosContrasenaTemporal;

  /// De `usr.email` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Correo electrónico'**
  String get usuariosCorreo;

  /// De `usr.fullName` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre completo'**
  String get usuariosNombreCompleto;

  /// De `usr.branchNote` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Un usuario con sucursal solo ve/gestiona los datos de ESA sucursal. Sin sucursal = admin global (ve todas).'**
  String get usuariosNotaSucursal;

  /// De `usr.new` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'+ Nuevo Usuario'**
  String get usuariosNueva;

  /// De `usr.noPermission` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'No tienes permisos para gestionar usuarios.'**
  String get usuariosSinPermiso;

  /// De `usr.noBranch` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin sucursal (admin — ve todo)'**
  String get usuariosSinSucursal;

  /// De `usr.branch` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sucursal'**
  String get usuariosSucursal;

  /// De `usr.branchGlobal` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Global / Todas'**
  String get usuariosSucursalGlobal;

  /// De `usr.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Usuarios'**
  String get usuariosTitulo;

  /// De `usr.createTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Crear Usuario'**
  String get usuariosTituloCrear;

  /// De `usr.editTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Editar Usuario'**
  String get usuariosTituloEditar;

  /// De `veh.add` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Agregar Vehículo'**
  String get vehiculosAgregar;

  /// De `veh.capacity` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Capacidad'**
  String get vehiculosCapacidad;

  /// De `veh.capacityMax` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Capacidad Máx. (kg)'**
  String get vehiculosCapacidadMax;

  /// De `veh.loading` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Cargando vehículos...'**
  String get vehiculosCargando;

  /// De `veh.status.available` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Disponible'**
  String get vehiculosEstadoDisponible;

  /// De `veh.status.in_use` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'En uso'**
  String get vehiculosEstadoEnUso;

  /// De `veh.status.maintenance` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Mantenimiento'**
  String get vehiculosEstadoMantenimiento;

  /// De `veh.nameLabel` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nombre del Vehículo *'**
  String get vehiculosEtiquetaNombre;

  /// De `veh.namePh` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ej: Camión #1, Furgoneta Azul'**
  String get vehiculosMarcadorNombre;

  /// De `veh.notesPh` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Información relevante del vehículo...'**
  String get vehiculosMarcadorNotas;

  /// De `veh.markAvailable` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Marcar disponible'**
  String get vehiculosMarcarDisponible;

  /// De `veh.notes` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Notas (opcional)'**
  String get vehiculosNotas;

  /// De `veh.ordersAssigned` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'{n} órdenes asignadas'**
  String vehiculosOrdenesAsignadas(Object n);

  /// De `veh.manageHint` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Gestiona tu flota. Las tarifas se configuran globalmente en Configuración.'**
  String get vehiculosPistaGestion;

  /// De `veh.feesHint` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Las tarifas de precios se configuran globalmente en Configuración.'**
  String get vehiculosPistaTarifas;

  /// De `veh.emptyHint` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Agrega tu primer vehículo para asignarlo a rutas'**
  String get vehiculosPistaVacio;

  /// De `veh.plate` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Placa (opcional)'**
  String get vehiculosPlaca;

  /// De `veh.activeRoute` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Ruta activa'**
  String get vehiculosRutaActiva;

  /// De `veh.routes` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Rutas'**
  String get vehiculosRutas;

  /// De `veh.type` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Tipo'**
  String get vehiculosTipo;

  /// De `veh.type.car` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Auto'**
  String get vehiculosTipoAuto;

  /// De `veh.type.bicycle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Bicicleta'**
  String get vehiculosTipoBicicleta;

  /// De `veh.type.truck` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Camión'**
  String get vehiculosTipoCamion;

  /// De `veh.type.van` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Furgoneta'**
  String get vehiculosTipoFurgoneta;

  /// De `veh.type.motorcycle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Moto'**
  String get vehiculosTipoMoto;

  /// De `veh.type.other` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Otro'**
  String get vehiculosTipoOtro;

  /// De `veh.title` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Vehículos'**
  String get vehiculosTitulo;

  /// De `veh.editTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Editar Vehículo'**
  String get vehiculosTituloEditar;

  /// De `veh.newTitle` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Nuevo Vehículo'**
  String get vehiculosTituloNuevo;

  /// De `veh.empty` en delivery/src/lib/i18n.ts.
  ///
  /// In es, this message translates to:
  /// **'Sin vehículos'**
  String get vehiculosVacio;

  /// NUEVO: el `window.close()` del HTML de Next pasa a ser una accion del cajon.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get nuevoCerrar;

  /// NUEVO: no existe en Next. En el patio de un almacen la hoja se manda por WhatsApp.
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get nuevoCompartir;

  /// NUEVO: el boton flotante del HTML de Next pasa a ser una accion del cajon.
  ///
  /// In es, this message translates to:
  /// **'Imprimir'**
  String get nuevoImprimir;

  /// NUEVO: en Next no puede fallar porque es HTML; aqui el PDF se arma y puede reventar.
  ///
  /// In es, this message translates to:
  /// **'No se pudo armar la hoja'**
  String get nuevoPdfNoSePudo;

  /// NUEVO: en Next la hoja se abre en una ventana del navegador; aqui es un cajon con el PDF dentro.
  ///
  /// In es, this message translates to:
  /// **'Vista previa'**
  String get nuevoVistaPreviaTitulo;
}

class _TextosDelegate extends LocalizationsDelegate<Textos> {
  const _TextosDelegate();

  @override
  Future<Textos> load(Locale locale) {
    return SynchronousFuture<Textos>(lookupTextos(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_TextosDelegate old) => false;
}

Textos lookupTextos(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return TextosEn();
    case 'es':
      return TextosEs();
  }

  throw FlutterError(
    'Textos.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
