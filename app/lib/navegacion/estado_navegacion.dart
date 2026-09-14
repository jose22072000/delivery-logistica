import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';

/// Lo que necesita el armazon y no tiene por que saber ninguna pantalla.

/// Las sucursales que esta persona puede mirar. Salen de la base local, no de la
/// red: la barra tiene que pintarse igual sin conexion.
final sucursalesProvider = StreamProvider<List<Sucursal>>(
  (ref) =>
      (ref.watch(baseProvider).select(ref.watch(baseProvider).branches)
            ..orderBy([(b) => OrderingTerm(expression: b.name)]))
          .watch(),
);

/// Las monedas con tasa. USD siempre esta; las demas solo si tienen tasa, porque
/// sin tasa no hay conversion y ofrecerla seria ensenar un numero inventado.
final monedasProvider = StreamProvider<List<Moneda>>(
  (ref) =>
      (ref.watch(baseProvider).select(ref.watch(baseProvider).currencies)
            ..where((m) => m.activa.equals(true))
            ..orderBy([(m) => OrderingTerm(expression: m.code)]))
          .watch(),
);

/// La unica fila de ajustes. Trae la tasa CUP y de cuando es.
final ajustesProvider = StreamProvider<Ajustes?>(
  (ref) => ref.watch(baseProvider).select(ref.watch(baseProvider).settings).watchSingleOrNull(),
);

/// La moneda en la que se PINTAN los importes. Los datos se guardan en USD
/// siempre; esto es solo como se muestran.
class MonedaMirada extends Notifier<String> {
  @override
  String build() => 'USD';

  void mirar(String codigo) => state = codigo;
}

final monedaMiradaProvider = NotifierProvider<MonedaMirada, String>(
  MonedaMirada.new,
);

/// Cuantas consultas hay en vuelo. Es un CONTADOR y no un booleano por lo mismo
/// que el bloqueo de scroll del cajon se lleva por contador: con dos ciclos
/// solapados, el primero en terminar apagaria el giro mientras el segundo sigue
/// trabajando, y la barra diria «al dia» con la bajada a medias.
class EnVuelo extends Notifier<int> {
  @override
  int build() => 0;

  void empieza() => state = state + 1;

  void termina() => state = state > 0 ? state - 1 : 0;
}

final enVueloProvider = NotifierProvider<EnVuelo, int>(EnVuelo.new);

/// El giro y `actualizando…` de la barra superior (pliego §8.2).
final actualizandoProvider = Provider<bool>(
  (ref) => ref.watch(enVueloProvider) > 0,
);

/// De que hora son los datos, para TODA la aplicacion: la bajada **mas vieja**
/// de todas las colecciones. Una pantalla no esta al dia si una de las
/// colecciones que usa no lo esta, asi que manda la peor.
final frescuraGlobalProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(frescuraProvider).laMasVieja(),
);
