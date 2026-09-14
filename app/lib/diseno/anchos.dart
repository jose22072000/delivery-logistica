/// Las anchuras que deciden que se ve. Estan aqui, con nombre, porque son
/// **reglas del pliego** (§11) y no gustos: un numero suelto dentro de un
/// `if (ancho < 1280)` a los tres meses nadie sabe de donde salio.
abstract final class Anchos {
  /// A partir de aqui la barra lateral es fija. Por debajo se sale de la
  /// pantalla y se abre con el boton de menu.
  static const escritorio = 1024.0;

  /// Por debajo de esto se oculta el selector de idioma. Sucursal y moneda NO
  /// se ocultan nunca: son los que cambian los numeros.
  static const idioma = 640.0;

  /// Tabla de Pedidos, por orden de prescindibilidad (§11).
  static const sucursalYVehiculo = 1536.0;
  static const ruta = 1280.0;
  static const articulosYFactura = 1024.0;
  static const entrega = 768.0;

  /// La tabla de Clientes se desplaza ELLA, no la pagina.
  static const minimoTablaClientes = 736.0;

  static const barraLateral = 256.0;
  static const altoBarraSuperior = 64.0;
}

/// Los cuatro anchos de cajon del pliego (§9.2). En movil siempre es la pantalla
/// entera, pase lo que pase.
enum AnchoCajon {
  md(448),
  lg(672),
  xl(896),
  completo(double.infinity);

  const AnchoCajon(this.px);

  final double px;
}
