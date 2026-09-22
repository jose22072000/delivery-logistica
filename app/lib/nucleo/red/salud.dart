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
  const SaludDeLaRed({
    this.fallosSeguidos = 0,
    this.ultimaBuena,
    this.sinInterfaz = false,
  });

  static const bienDeSalida = SaludDeLaRed();

  /// Cuantos ciclos seguidos se han caído por red.
  final int fallosSeguidos;

  /// Cuándo salió bien el último. `null` = todavía ninguno en esta sesión.
  final DateTime? ultimaBuena;

  /// EL APARATO NO TIENE NI POR DÓNDE SALIR: modo avión, o ninguna red.
  ///
  /// ## La pista del sistema sólo miente en UN sentido — 22/09/2026
  ///
  /// Arriba está escrito que «sin conexión la aplicación lo sabe enseguida», y
  /// no era verdad: con el modo avión puesto a las 12:21:31, la franja siguió
  /// diciendo «Datos de las 12:20» en gris hasta las 12:23. Dos minutos en los
  /// que el Panel afirmaba «Los datos son de ahora mismo». Una pantalla
  /// mintiendo, que es lo que no puede pasar.
  ///
  /// El motivo de no fiarse de `connectivity_plus` sigue siendo bueno, pero sólo
  /// para una de las dos respuestas: **que diga que hay wifi no significa que
  /// salga un paquete** —el caso de allá— y por eso su «sí» no vale. En cambio
  /// su «no» es del sistema operativo: si no hay ni interfaz, no hay red, y eso
  /// no admite discusión ni hace falta esperar a que tres peticiones se caigan.
  ///
  /// Por eso esto es un campo aparte y no un fallo más: al volver la interfaz se
  /// quita solo, sin afirmar que la conexión sirva — eso lo sigue diciendo una
  /// petición que llegue.
  final bool sinInterfaz;

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

  /// `true` cuando las peticiones llevan un rato sin llegar, o cuando no hay ni
  /// por dónde salir.
  bool get vaMal => sinInterfaz || fallosSeguidos >= fallosParaDarlaPorMala;

  /// Un ciclo que llegó. **Se vuelve a normal al momento**: basta UNA buena.
  /// Tardar en recuperarse sería dejar el aviso puesto delante de alguien que ya
  /// tiene señal, y entonces el aviso miente en la otra dirección.
  SaludDeLaRed conUnaBuena(DateTime cuando) =>
      SaludDeLaRed(ultimaBuena: cuando);

  /// El sistema dice que no hay ni interfaz. Se cree **al momento**.
  SaludDeLaRed sinRed() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos,
    ultimaBuena: ultimaBuena,
    sinInterfaz: true,
  );

  /// Volvió la interfaz. Eso NO dice que la conexión sirva: se quita la
  /// certeza de que no hay, y lo demás lo sigue diciendo una petición que
  /// llegue. Si los ciclos seguían cayéndose, el aviso se queda puesto.
  SaludDeLaRed conInterfaz() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos,
    ultimaBuena: ultimaBuena,
  );

  /// Un ciclo que se cayó por red. Los otros fallos —sesión muerta, un rechazo
  /// del servidor— **no cuentan**: esos significan que la petición SÍ llegó.
  SaludDeLaRed conUnaMala() => SaludDeLaRed(
    fallosSeguidos: fallosSeguidos + 1,
    ultimaBuena: ultimaBuena,
  );

  @override
  String toString() =>
      'SaludDeLaRed(fallosSeguidos: $fallosSeguidos, '
      'ultimaBuena: $ultimaBuena, sinInterfaz: $sinInterfaz)';
}
