/// SI LAS PETICIONES ESTAN LLEGANDO. No «si el aparato cree que hay wifi».
///
/// El caso de verdad en Cuba **no es «sin conexión», es «conexión mala»**: sin
/// conexión la aplicación lo sabe enseguida; con una conexión que va y viene el
/// aparato **cree que está conectado**, lanza la petición, y el logístico se
/// come una rueda girando sin saber si va a funcionar. Eso es peor que un fallo
/// limpio.
///
/// Por eso el estado que se pinta NO sale de `connectivity_plus`. Ese plugin es
/// una pista —está escrito así en el `pubspec.yaml`— y sirve para **intentarlo
/// antes**, nunca para decidir lo que se enseña. Lo que decide es esto: si los
/// ciclos están llegando.
class SaludDeLaRed {
  const SaludDeLaRed({this.fallosSeguidos = 0, this.ultimaBuena});

  static const bienDeSalida = SaludDeLaRed();

  /// Cuantos ciclos seguidos se han caído por red.
  final int fallosSeguidos;

  /// Cuándo salió bien el último. `null` = todavía ninguno en esta sesión.
  final DateTime? ultimaBuena;

  /// CUANTOS FALLOS SEGUIDOS HACEN FALTA para decir que la conexión va mal.
  ///
  /// Tres, y el número está pensado. El aviso tiene que ser **lento en ponerse y
  /// rápido en quitarse**: con una conexión que va y viene, un indicador que
  /// cambia con cada petición fallida parpadea todo el día, y una señal que
  /// parpadea deja de leerse a los diez minutos — que es justo lo que le pasa al
  /// ámbar de esta casa si se gasta en balde.
  ///
  /// Y tres no es «tres paquetes perdidos»: cada petición del ciclo reintenta
  /// por dentro tres veces (1 s, 4 s y 10 s, `cliente_api.dart`), así que UN
  /// ciclo caído son cuatro intentos y 15 s de esperas — **unos 55 s cuando la
  /// conexión no llega a establecerse, que es como se cae de verdad allá**, y
  /// hasta ~115 s si el servidor coge la conexión y se queda mudo cada vez.
  /// Tres seguidos siguen significando que la conexión lleva **minutos** sin
  /// servir, no que se perdió un paquete.
  ///
  /// El número se dejó en tres al bajar los plazos el 15/09/2026 y no se subió
  /// a compensar: antes eran ~80 s por ciclo y hacían falta tres para llegar a
  /// «minutos»; ahora son ~55 s y tres siguen siendo minutos. Lo que cambió
  /// para bien es que el aviso aparece antes —dos minutos y medio en vez de
  /// cuatro— y quien está en el patio del almacén se entera de que no hay
  /// señal mientras todavía le sirve de algo.
  static const fallosParaDarlaPorMala = 3;

  /// `true` cuando las peticiones llevan un rato sin llegar.
  bool get vaMal => fallosSeguidos >= fallosParaDarlaPorMala;

  /// Un ciclo que llegó. **Se vuelve a normal al momento**: basta UNA buena.
  /// Tardar en recuperarse sería dejar el aviso puesto delante de alguien que ya
  /// tiene señal, y entonces el aviso miente en la otra dirección.
  SaludDeLaRed conUnaBuena(DateTime cuando) =>
      SaludDeLaRed(ultimaBuena: cuando);

  /// Un ciclo que se cayó por red. Los otros fallos —sesión muerta, un rechazo
  /// del servidor— **no cuentan**: esos significan que la petición SÍ llegó.
  SaludDeLaRed conUnaMala() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos + 1,
    ultimaBuena: ultimaBuena,
  );

  @override
  String toString() =>
      'SaludDeLaRed(fallosSeguidos: $fallosSeguidos, '
      'ultimaBuena: $ultimaBuena)';
}
