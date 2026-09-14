/// El ayudante `¿No sabes el costo por km?` del pliego (§5).
///
/// Es aritmetica pura y va aparte de la pantalla para poder comprobarla con el
/// caso del pliego sin montar un widget: `180000 CUP / 72 km / 320` tiene que
/// dar el mismo `$/km` que la de Next, y ese numero acaba en el precio de cada
/// domicilio.
abstract final class CostoPorKm {
  /// La tasa de la casa cuando Accesos no ha dado otra.
  static const tasaPorDefecto = 320.0;

  /// `costo_km(USD) = cobroCUP / (2 × km × tasa)`.
  ///
  /// El 2 es ida y vuelta: el camionero cobra el viaje entero y el `hasta ___
  /// km` que se escribe es sólo la ida.
  static double? calcular({
    required double? cobroCup,
    required double? km,
    double tasa = tasaPorDefecto,
  }) {
    if (cobroCup == null || km == null) return null;
    if (cobroCup <= 0 || km <= 0 || tasa <= 0) return null;
    final valor = cobroCup / (2 * km * tasa);
    if (!valor.isFinite) return null;
    return valor;
  }
}
