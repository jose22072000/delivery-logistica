/// Las tres URL, por `--dart-define`. Nunca en el codigo y nunca en el APK
/// como constante editable.
///
/// Van separadas porque son tres servicios distintos y uno puede mudarse sin
/// los otros: `auth` es de toda Procovar, `api` y `sync` son del reparto.
abstract final class Entorno {
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://reparto.procovar.cloud/api',
  );

  static const syncUrl = String.fromEnvironment(
    'SYNC_URL',
    defaultValue: 'https://reparto.procovar.cloud/sync',
  );

  static const authUrl = String.fromEnvironment(
    'AUTH_URL',
    defaultValue: 'https://auth.procovar.cloud',
  );

  /// `true` cuando las tres estan puestas a mano. Sirve para que el arranque
  /// avise en vez de intentar hablar con un dominio que no es.
  static bool get configurado =>
      apiUrl.isNotEmpty && syncUrl.isNotEmpty && authUrl.isNotEmpty;
}
