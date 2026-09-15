import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/portero.dart';
import '../datos/servicio_acceso.dart';
import '../estado/estado_acceso.dart';

/// LA PANTALLA DE ACCESO.
///
/// Sin ella la aplicación entra directa al Panel sin sesión, no descarga nada y
/// todas las pantallas dicen «no se ha descargado todavía» — que es exactamente
/// lo que se vio en `reparto.procovar.cloud`.
///
/// **No lleva `Scaffold` ni armazón**: la pone el enrutador
/// (`conArmazon: false`), porque aquí no hay barra lateral que enseñar — no hay
/// a dónde ir todavía — ni selector de sucursal que rellenar, que sale de la
/// sesión que aún no existe.
class PantallaAcceso extends ConsumerStatefulWidget {
  const PantallaAcceso({super.key});

  @override
  ConsumerState<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends ConsumerState<PantallaAcceso> {
  final _usuario = TextEditingController();
  final _contrasena = TextEditingController();
  final _formulario = GlobalKey<FormState>();
  bool _verContrasena = false;

  @override
  void dispose() {
    _usuario.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    final sesion = await ref
        .read(formularioProvider.notifier)
        .entrar(usuario: _usuario.text, contrasena: _contrasena.text);
    if (sesion == null) return;
    // Quien mueve la aplicación de sitio es el portero, no esta pantalla.
    ref.read(porteroProvider).entro(sesion);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(formularioProvider);
    final entrando = estado is Entrando;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: Aire.lg,
          vertical: Aire.xxl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(Aire.xl),
            decoration: BoxDecoration(
              color: Colores.blanco,
              border: Border.all(color: Colores.linea),
              borderRadius: BorderRadius.circular(Radios.xl),
              boxShadow: Sombras.md,
            ),
            child: Form(
              key: _formulario,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 34,
                    color: Colores.primario,
                  ),
                  const SizedBox(height: Aire.md),
                  Text(
                    'Reparto',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: Aire.xs),
                  Text(
                    'Entra con tu usuario de Procovar.',
                    textAlign: TextAlign.center,
                    style: Tipos.texto(tamano: 13, color: Colores.tintaSuave),
                  ),
                  const SizedBox(height: Aire.xl),
                  TextFormField(
                    controller: _usuario,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    enabled: !entrando,
                    decoration: const InputDecoration(
                      labelText: 'Usuario o correo',
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Escribe tu usuario.'
                        : null,
                  ),
                  const SizedBox(height: Aire.md),
                  TextFormField(
                    controller: _contrasena,
                    autofillHints: const [AutofillHints.password],
                    obscureText: !_verContrasena,
                    enabled: !entrando,
                    // Entrar con la tecla de intro: con guantes en el patio de
                    // un almacén, buscar el botón es un paso de más.
                    onFieldSubmitted: (_) => entrando ? null : _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        tooltip: _verContrasena ? 'Ocultar' : 'Ver',
                        icon: Icon(
                          _verContrasena
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _verContrasena = !_verContrasena),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Escribe tu contraseña.'
                        : null,
                  ),
                  if (estado is NoEntro) ...[
                    const SizedBox(height: Aire.lg),
                    _Aviso(fallo: estado.fallo),
                  ],
                  const SizedBox(height: Aire.xl),
                  FilledButton(
                    onPressed: entrando ? null : _entrar,
                    child: entrando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colores.blanco,
                            ),
                          )
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: Aire.md),
                  Text(
                    // La regla de la casa, dicha antes de que haga falta: quien
                    // se queda sin señal en la calle no tiene a quién preguntar.
                    'Para entrar hace falta conexión. Una vez dentro, no: '
                    'puedes seguir trabajando el día entero sin señal.',
                    textAlign: TextAlign.center,
                    style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El fallo, en cristiano y con lo que hay que hacer.
///
/// El 403 `sin_sucursal` se pinta en ámbar y no en rojo **a propósito**: no es
/// un fallo de quien escribe, la contraseña era buena. Es una cuenta sin
/// sucursal, y lo que la arregla es una llamada a la oficina, no volver a
/// probar.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.fallo});

  final FalloDeAcceso fallo;

  @override
  Widget build(BuildContext context) {
    final esAviso =
        fallo.motivo == MotivoDeAcceso.sinSucursal ||
        fallo.motivo == MotivoDeAcceso.cuentaDeBaja ||
        fallo.motivo == MotivoDeAcceso.sinConexion;

    final color = esAviso ? Colores.ambar : Colores.rojo;
    final fondo = esAviso ? Colores.ambarFondo : Colores.rojoFondo;

    return Container(
      padding: const EdgeInsets.all(Aire.md),
      decoration: BoxDecoration(
        color: fondo,
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(Radios.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (fallo.motivo) {
              MotivoDeAcceso.sinConexion => Icons.wifi_off_outlined,
              MotivoDeAcceso.sinSucursal => Icons.store_outlined,
              MotivoDeAcceso.cuentaDeBaja => Icons.no_accounts_outlined,
              _ => Icons.error_outline,
            },
            size: 18,
            color: color,
          ),
          const SizedBox(width: Aire.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fallo.mensaje,
                  style: Tipos.texto(
                    tamano: 13,
                    peso: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (_queHacer(fallo.motivo) != null) ...[
                  const SizedBox(height: Aire.xs),
                  Text(
                    _queHacer(fallo.motivo)!,
                    style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _queHacer(MotivoDeAcceso motivo) => switch (motivo) {
    MotivoDeAcceso.sinSucursal =>
      'No es un fallo de la aplicación: tu cuenta entró bien. Pide en la '
          'oficina que te den de alta en tu sucursal y vuelve a entrar.',
    MotivoDeAcceso.cuentaDeBaja =>
      'Pregunta en la oficina: la cuenta está dada de baja.',
    MotivoDeAcceso.demasiadosIntentos =>
      'El servidor corta los intentos seguidos para proteger la cuenta.',
    MotivoDeAcceso.sinConexion =>
      'Comprueba la señal. Lo que ya estaba descargado sigue en el aparato.',
    _ => null,
  };
}
