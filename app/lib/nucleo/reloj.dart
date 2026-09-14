/// El reloj, como parametro y no como llamada suelta a `DateTime.now()`.
///
/// Dos motivos, los dos del pliego:
///
///  * **La hora es la del aparato** (regla 7). Lo que se marca a las cuatro
///    llega como las cuatro aunque suba a las siete, asi que quien pone la hora
///    tiene que ser una pieza identificable y no cincuenta `DateTime.now()`
///    repartidos.
///  * Los tramos del `RelojDeDatos` («hace 5 h», «hace 2 dias») y la poda de la
///    cola sólo se pueden probar si el test puede mover el reloj.
typedef Reloj = DateTime Function();

/// El de verdad.
DateTime relojDelAparato() => DateTime.now();
