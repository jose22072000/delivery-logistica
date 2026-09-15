import 'dart:convert';

/// El par de tokens y lo que el token de acceso lleva dentro.
///
/// `sub`, `sucursalId` y `roles` se copian del token porque es lo que la API ya
/// lee, y porque sin red hay que poder saber quien es y que sucursal le toca sin
/// preguntarle a nadie.
///
/// `nombre`, `correo` y `rol` se copian por lo mismo, pero para ENSENARLOS: el
/// menu de la cuenta dice quien eres, y preguntarselo a `/api/me` cada vez que
/// alguien pulsa el avatar es una peticion para pintar dos renglones que el
/// token ya trae firmados. Auth los manda como `name`, `email` y `role`.
class Sesion {
  const Sesion({
    required this.token,
    required this.refresh,
    required this.sub,
    this.sucursalId,
    this.roles = const <String>[],
    this.nombre = '',
    this.correo = '',
    this.rol = '',
  });

  factory Sesion.deJson(Map<String, Object?> json) {
    final token = json['token'] as String?;
    // Auth contesta `refresh_token` en las tres puertas (`/api/auth/token`,
    // `/refresh` y `/logout`). `refresh` se sigue admitiendo porque es como se
    // guarda el par en el aparato, y lo guardado tiene que poder volver a
    // leerse.
    final refresh = (json['refresh_token'] ?? json['refresh']) as String?;
    if (token == null || refresh == null) {
      throw const FormatException('la respuesta no trae el par de tokens');
    }
    final carga = _cargaDelToken(token);
    return Sesion(
      token: token,
      refresh: refresh,
      sub: (json['sub'] ?? carga['sub'] ?? '') as String,
      // El token trae el CODIGO de la sucursal (CAM, HAB, STG...) con dos
      // nombres, `sucursal` y `branch_id`, que es lo que firma auth
      // (`apk-tokens.ts`) y lo que lee la API del reparto. Vacio significa
      // «ninguna», que en un Super Admin son las ocho.
      sucursalId: _sucursal(
        json['sucursalId'] ??
            carga['sucursalId'] ??
            carga['sucursal'] ??
            carga['branch_id'],
      ),
      roles: _roles(json['roles'] ?? carga['roles']),
      // Los tres de ensenar. Vacio es una respuesta valida, no un fallo: una
      // sesion GUARDADA ANTES de que esto existiera no los tiene, y un token de
      // otra puerta podria no traerlos. Quien los pinta decide que poner en su
      // lugar; lo que no puede pasar es que falten y la aplicacion no arranque.
      nombre: _texto(json['nombre'] ?? carga['name']),
      correo: _texto(json['correo'] ?? carga['email']),
      rol: _texto(json['rol'] ?? carga['role']),
    );
  }

  final String token;

  /// El refresh, **de un solo uso**. Se sustituye ENTERO en cada renovacion y el
  /// viejo no se guarda nunca: el servidor lee un refresh repetido como robo y
  /// revoca todas las sesiones de la cuenta.
  final String refresh;

  final String sub;
  final String? sucursalId;

  /// Escritos exactamente asi: `SUPER ADMIN`, `ADMINISTRADOR`, `SUPERVISOR`,
  /// `GESTOR`, `OPERADOR`. PEDIDO los compara como texto.
  final List<String> roles;

  /// El nombre de la persona (`name` del token). Puede venir vacio.
  final String nombre;

  /// El correo (`email` del token). Puede venir vacio.
  final String correo;

  /// El rol en singular que manda auth (`role`), que NO es lo mismo que [roles]:
  /// aquel es la lista con la que se decide que se puede hacer, este es la
  /// palabra que se pinta debajo del nombre.
  final String rol;

  bool get esSuperAdmin => roles.contains('SUPER ADMIN');

  /// El nombre para PINTAR. Nunca vacio y nunca el `sub`.
  ///
  /// El `sub` es el identificador de la fila en la base de auth
  /// (`uaoOUHqTXNYUv672kjdLoZLpFrseCz9e`). A quien lo lee no le dice nada, y
  /// ensenarselo al logistico es sacar la base a la cara. Sin nombre se pone
  /// «Tu cuenta», que al menos es verdad.
  String get nombreParaVer => nombre.isNotEmpty ? nombre : 'Tu cuenta';

  /// La letra del cuadro del avatar. La del nombre, o `?` si no hay nombre —
  /// **nunca** la del `sub`, que seria una letra de un identificador.
  String get inicial =>
      nombre.isEmpty ? '?' : nombre.substring(0, 1).toUpperCase();

  /// El rotulo de debajo del nombre: el `role` de auth, o el primero de [roles]
  /// si aquel no vino. Vacio si no hay ninguno, y entonces no se pinta.
  String get rolParaVer =>
      rol.isNotEmpty ? rol : (roles.isNotEmpty ? roles.first : '');

  Map<String, Object?> aJson() => <String, Object?>{
    'token': token,
    'refresh': refresh,
    'sub': sub,
    'sucursalId': sucursalId,
    'roles': roles,
    'nombre': nombre,
    'correo': correo,
    'rol': rol,
  };

  @override
  String toString() => 'Sesion(sub: $sub, sucursal: $sucursalId)';

  /// Lee la carga del JWT SIN comprobar la firma.
  ///
  /// Y esta bien que no la compruebe: quien valida el token es el servidor en
  /// cada peticion. Aqui sólo se lee para saber que sucursal pintar en la barra.
  /// Confiar en esto para decidir permisos seria darle a cualquiera con un
  /// editor de texto el rol que quiera.
  static Map<String, Object?> _cargaDelToken(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return const <String, Object?>{};
      final normalizado = base64Url.normalize(partes[1]);
      final json = jsonDecode(utf8.decode(base64Url.decode(normalizado)));
      return json is Map<String, Object?> ? json : const <String, Object?>{};
    } on Object {
      // Un token ilegible no puede tumbar el arranque: se entra sin los extras
      // y el servidor dira lo que tenga que decir en la primera peticion.
      return const <String, Object?>{};
    }
  }

  /// La sucursal, o `null` si viene vacia. La cadena vacia que firma auth
  /// cuando alguien no tiene ninguna NO puede quedarse como sucursal: seria una
  /// cabecera `x-sucursal-id: ` en cada peticion.
  static String? _sucursal(Object? crudo) {
    final texto = crudo is String ? crudo.trim() : null;
    return (texto == null || texto.isEmpty) ? null : texto;
  }

  /// Un texto del token, o vacio. Lo que no sea texto se trata como ausente: un
  /// `name` que viniera como numero no puede reventar el arranque.
  static String _texto(Object? crudo) => crudo is String ? crudo.trim() : '';

  static List<String> _roles(Object? crudo) => switch (crudo) {
    final List<Object?> lista => lista.whereType<String>().toList(),
    final String uno => <String>[uno],
    _ => const <String>[],
  };
}
