import 'dart:convert';

/// El par de tokens y lo que el token de acceso lleva dentro.
///
/// `sub`, `sucursalId` y `roles` se copian del token porque es lo que la API ya
/// lee, y porque sin red hay que poder saber quien es y que sucursal le toca sin
/// preguntarle a nadie.
class Sesion {
  const Sesion({
    required this.token,
    required this.refresh,
    required this.sub,
    this.sucursalId,
    this.roles = const <String>[],
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

  bool get esSuperAdmin => roles.contains('SUPER ADMIN');

  Map<String, Object?> aJson() => <String, Object?>{
    'token': token,
    'refresh': refresh,
    'sub': sub,
    'sucursalId': sucursalId,
    'roles': roles,
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

  static List<String> _roles(Object? crudo) => switch (crudo) {
    final List<Object?> lista => lista.whereType<String>().toList(),
    final String uno => <String>[uno],
    _ => const <String>[],
  };
}
