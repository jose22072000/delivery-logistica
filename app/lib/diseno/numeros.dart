import 'package:intl/intl.dart';

/// Como se pinta UN IMPORTE en la moneda que se esta mirando.
///
/// Sale de `TasaDeLaMirada.importe` con la moneda de `monedaEfectivaProvider`,
/// los dos en `navegacion/estado_navegacion.dart`. Va como parametro y no como
/// `ref.watch` dentro de cada widget para que las tablas y las tarjetas sigan
/// siendo `StatelessWidget` y se puedan probar con una funcion a mano.
///
/// **Ningun importe se pinta con [Numeros.importe] a pelo.** Esa da el numero
/// suelto, sin moneda: un `1.234,56` que lo mismo puede ser dolares que pesos,
/// y con la tasa a 700 la diferencia entre los dos es de tres ceros.
typedef PintarImporte = String Function(double? usd);

/// Formato de numeros para pintar, **provisional**.
///
/// Lo definitivo es `nucleo/formato/` (Dinero, Peso, Distancia), que es de otra
/// ola y trae la conversion USD/CUP con la tasa por sucursal. Mientras no este,
/// estas cuatro funciones evitan que cada pantalla invente su propio
/// `toStringAsFixed`, que es como acaban dos tablas dando dos numeros distintos
/// para la misma suma.
abstract final class Numeros {
  static final _entero = NumberFormat.decimalPattern('es');
  static final _dos = NumberFormat('#,##0.00', 'es');
  static final _uno = NumberFormat('#,##0.0', 'es');

  static String entero(num v) => _entero.format(v);

  /// Importes: **2 decimales siempre**, como el Excel del pliego.
  ///
  /// Da el numero PELADO, sin moneda. Para pintar dinero en una pantalla hay
  /// que pasar por [PintarImporte], que sabe si toca USD o CUP y con que tasa;
  /// esta se queda para quien la necesite dentro de esa conversion.
  static String importe(num v) => _dos.format(v);

  /// LO QUE SE ESCRIBE DONDE UN IMPORTE NO SE SABE.
  ///
  /// Son las mismas dos palabras que pinta `Pedidos` (`usd()` en
  /// `pantallas/pedidos/datos/formato.dart`) y las mismas que la hoja de
  /// paradas de una ruta, para que la misma cifra no se llame de dos maneras
  /// segun la pantalla. **Nunca un `0,00`**: un cero es un precio y se lee como
  /// «este domicilio es gratis» (`CLAUDE.md` §2).
  static const sinCotizar = 'sin cotizar';

  /// UN TOTAL AL QUE LE FALTA ALGUN SUMANDO. Ni el total a medias ni un `—`
  /// mudo: el `—` dice que no se sabe y el parentesis dice **cuantas** faltan,
  /// que es lo unico con lo que alguien puede ir a arreglarlo.
  ///
  /// Es lo mismo que hace el pre-despacho con su `sinPeso` / `sinUnidades`.
  static String totalIncompleto(int cuantas) =>
      '— ($cuantas sin cotizar)';

  /// Pesos: **1 decimal**, como el pliego (`<n.n> kg`).
  static String kg(num v) => '${_uno.format(v)} kg';

  /// Los kg del panel van REDONDEADOS, sin decimales: es el subtexto de una
  /// tarjeta, no una factura.
  static String kgRedondeado(num v) => '${_entero.format(v.round())} kg';

  static String km(num v) => '${_uno.format(v)} km';
}
