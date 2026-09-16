import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';
import '../../../navegacion/portero.dart';
import '../../../nucleo/plataforma.dart';
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

  /// SE ENTRÓ Y LA SESIÓN NO SE QUEDÓ. No es lo mismo que la comprobación de
  /// antes de escribir la contraseña: esto ya pasó, con esta cuenta, ahora.
  ///
  /// Existe aparte porque en web la comprobación previa no se hace —allí no hay
  /// promesa de día sin señal que cumplir— pero **el fallo de verdad sí se
  /// dice**: si el navegador no guarda, el botón de entrar no haría nada y la
  /// persona se quedaría delante de un formulario mudo probando una contraseña
  /// que era buena.
  bool _noSeGuardo = false;

  @override
  void dispose() {
    _usuario.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!(_formulario.currentState?.validate() ?? false)) return;
    final acceso = await ref
        .read(formularioProvider.notifier)
        .entrar(usuario: _usuario.text, contrasena: _contrasena.text);
    if (acceso == null) return;
    if (!acceso.seGuardo) {
      // ENTRÓ, pero la sesión no se quedó guardada. Se dice AHORA, que es el
      // único momento en el que todavía hay conexión y hay a quién preguntar:
      // descubrirlo mañana es descubrirlo en el patio de un almacén.
      //
      // Y en web se dice igual, aunque allí no haya promesa que romper: sin
      // sesión guardada el interceptor no tiene token que poner y todo
      // respondería 401. Eso es un fallo de verdad, y lo que se quitó de la web
      // es el aparato de PREPARARSE para no tener conexión, no el aviso de que
      // algo acaba de salir mal.
      ref.invalidate(saludDelAlmacenProvider);
      setState(() => _noSeGuardo = true);
      return;
    }
    // Quien mueve la aplicación de sitio es el portero, no esta pantalla.
    await ref.read(porteroProvider).entro(acceso.sesion);
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(formularioProvider);
    final entrando = estado is Entrando;
    // ¿HAY PROMESA QUE HACER? En web, NO — 15/09/2026.
    //
    // «Una vez dentro, no: puedes seguir trabajando el día entero sin señal» es
    // la regla de la casa y es verdad en la APK y en el escritorio, donde quien
    // entra se va al patio de un almacén. En un navegador es mentira en las dos
    // direcciones: ni hace falta —la web se abre desde internet, siempre— ni se
    // cumple, porque lo que sostiene la sesión ahí es lo que haya en el
    // navegador y nadie le prometió a esa persona un día entero de nada.
    //
    // Y por lo mismo se cae el aviso de «este aparato no guarda la sesión»: sólo
    // existe para decir que la promesa NO se va a poder cumplir. Sin promesa no
    // hay nada que desdecir, y lo que quedaría es un recuadro ámbar diciéndole a
    // alguien que va a tener que volver a entrar en un sitio donde eso es lo
    // normal. **Ni se pinta ni se pregunta**: la comprobación del almacén es una
    // ida y vuelta de verdad, y aquí no la paga nadie.
    final hayPromesaDeDiaSinSenal = ref.watch(trabajaSinConexionProvider);
    // LA PROMESA, comprobada. Ver `nucleo/identidad/almacen_sesion.dart`.
    //
    // En web se le pregunta al almacén **sólo si ya falló de verdad**: nada de
    // sondearlo antes por si acaso, que es justo el aparato de prepararse que
    // aquí sobra.
    final salud = (hayPromesaDeDiaSinSenal || _noSeGuardo)
        ? ref.watch(saludDelAlmacenProvider).asData?.value
        : null;
    final guarda = salud?.guarda ?? true;
    // ¿Había datos en el aparato y aun así no hay sesión? Entonces esto no es
    // «entra»: es que la sesión se perdió, y hay que decirlo.
    final sesionPerdida = ref.read(porteroProvider).sesionPerdida;

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
                  // LA MARCA, y a tamano legible.
                  //
                  // Aqui es donde el logo de PROCOVAR se puede ver de verdad: el
                  // monograma va calado en la caja del camion y a 36 px —lo que
                  // mide el isotipo de la barra lateral— seria una mancha. Esta
                  // pantalla tiene sitio de sobra, y es ademas la primera que ve
                  // cualquiera, asi que es la que tiene que decir de quien es
                  // esto antes de pedir una contrasena.
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radios.xl),
                      child: Image.asset(
                        'assets/marca/logo.png',
                        width: 72,
                        height: 72,
                        // Sin esto el navegador la interpola al encoger y los
                        // trazos del monograma —que son finos— salen sucios.
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
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
                  if (sesionPerdida) ...[
                    const SizedBox(height: Aire.lg),
                    const _SesionPerdida(),
                  ],
                  if (!guarda) ...[
                    const SizedBox(height: Aire.lg),
                    _NoGuarda(
                      motivo: salud!.motivo!,
                      hayPromesaDeDiaSinSenal: hayPromesaDeDiaSinSenal,
                    ),
                  ],
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
                  // LA PROMESA DEL DÍA SIN SEÑAL — sólo donde hay día sin señal.
                  // En web no se escribe ninguna frase en su lugar: no hay nada
                  // que avisar, y una línea puesta para llenar el hueco es una
                  // línea que nadie lee.
                  if (hayPromesaDeDiaSinSenal) ...[
                    const SizedBox(height: Aire.md),
                    Text(
                      // La regla de la casa, dicha antes de que haga falta:
                      // quien se queda sin señal en la calle no tiene a quién
                      // preguntar.
                      //
                      // **O se cumple, o no se promete.** Si este aparato no
                      // puede guardar la sesión, la frase de siempre es mentira
                      // y no se escribe: lo que se escribe es lo que de verdad
                      // va a pasar. El aviso de arriba dice el resto.
                      guarda
                          ? 'Para entrar hace falta conexión. Una vez dentro, '
                                'no: puedes seguir trabajando el día entero sin '
                                'señal.'
                          : 'Para entrar hace falta conexión, y en este aparato '
                                'hará falta cada vez que abras la aplicación.',
                      textAlign: TextAlign.center,
                      style: Tipos.texto(tamano: 11, color: Colores.tintaSuave),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// LA SESIÓN SE PERDIÓ, y el aparato tiene datos dentro.
///
/// El caso del 15/09/2026: se entró, se bajó el día, se cerró la aplicación y al
/// abrirla pedía la contraseña otra vez con los datos ahí mismo, en el disco. Un
/// formulario mudo deja a esa persona probando su contraseña buena una y otra
/// vez en el patio de un almacén, convencida de que se le olvidó.
class _SesionPerdida extends StatelessWidget {
  const _SesionPerdida();

  @override
  Widget build(BuildContext context) => const _Recuadro(
    icono: Icons.history_toggle_off,
    titulo: 'Tu sesión se perdió.',
    detalle:
        'Los datos que bajaste siguen en el aparato. Para volver a entrar hace '
        'falta señal; no es tu contraseña.',
  );
}

/// ESTE APARATO NO GUARDA LA SESIÓN.
///
/// En la APK y en el escritorio se dice **antes** de escribir la contraseña,
/// porque lo que está en juego es la promesa del día entero sin señal y hay que
/// desdecirla a tiempo. En web no se dice nunca por adelantado —allí no hay tal
/// promesa— y sólo aparece cuando el navegador ya se ha negado a guardar de
/// verdad, que ahí es otra cosa: sin sesión guardada no hay token que poner en
/// las peticiones y la página no sirve para nada.
class _NoGuarda extends StatelessWidget {
  const _NoGuarda({
    required this.motivo,
    required this.hayPromesaDeDiaSinSenal,
  });

  final String motivo;

  /// `true` en la APK y el escritorio. En web cambia qué se explica, porque lo
  /// que se rompe no es lo mismo.
  final bool hayPromesaDeDiaSinSenal;

  @override
  Widget build(BuildContext context) => _Recuadro(
    icono: Icons.lock_open_outlined,
    titulo: motivo,
    detalle: hayPromesaDeDiaSinSenal
        ? 'Vas a poder trabajar todo el día sin señal, pero al cerrar la '
              'aplicación tendrás que entrar otra vez, y para eso hace falta '
              'conexión. Avisa a la oficina antes de irte al almacén.'
        : 'Puede ser una ventana privada o el navegador con los datos del sitio '
              'bloqueados. Ábrelo en una ventana normal y vuelve a entrar: sin '
              'guardar la sesión, la página no se puede quedar dentro.',
  );
}

/// El recuadro ámbar de los dos avisos de arriba. Ámbar y no rojo a propósito:
/// no es un fallo de quien escribe, y volver a probar la contraseña no lo
/// arregla.
class _Recuadro extends StatelessWidget {
  const _Recuadro({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Aire.md),
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(Radios.md),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: Colores.ambar),
        const SizedBox(width: Aire.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: Tipos.texto(
                  tamano: 13,
                  peso: FontWeight.w600,
                  color: Colores.ambar,
                ),
              ),
              const SizedBox(height: Aire.xs),
              Text(
                detalle,
                style: Tipos.texto(tamano: 12, color: Colores.tintaSuave),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// El fallo, en cristiano y con lo que hay que hacer.
///
/// El 403 `sin_sucursal` se pinta en ámbar y no en rojo **a propósito**: no es
/// un fallo de quien escribe, la contraseña era buena. Es una cuenta sin
/// sucursal, y lo que la arregla es una llamada a la oficina, no volver a
/// probar.
class _Aviso extends ConsumerWidget {
  const _Aviso({required this.fallo});

  final FalloDeAcceso fallo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lee el destino por provider y no llamando a `Destino` para que la prueba
    // de la pareja —«en web no sale / en aparato si sale»— pueda ponerse en el
    // otro lado sin compilar para web.
    final sinConexion = ref.watch(trabajaSinConexionProvider);
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
              // El icono tambien cambia: en la web no se dibuja una antena
              // tachada para decir que el servidor no contesta.
              MotivoDeAcceso.sinConexion when !sinConexion =>
                Icons.cloud_off_outlined,
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
                if (_queHacer(fallo.motivo, sinConexion) != null) ...[
                  const SizedBox(height: Aire.xs),
                  Text(
                    _queHacer(fallo.motivo, sinConexion)!,
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

  static String? _queHacer(
    MotivoDeAcceso motivo,
    bool sinConexion,
  ) => switch (motivo) {
    MotivoDeAcceso.sinSucursal =>
      'No es un fallo de la aplicación: tu cuenta entró bien. Pide en la '
          'oficina que te den de alta en tu sucursal y vuelve a entrar.',
    MotivoDeAcceso.cuentaDeBaja =>
      'Pregunta en la oficina: la cuenta está dada de baja.',
    MotivoDeAcceso.demasiadosIntentos =>
      'El servidor corta los intentos seguidos para proteger la cuenta.',
    // En la WEB no se habla de señal ni de lo que hay guardado en el aparato.
    // La web se abre desde un navegador con internet: si la pagina cargo, la
    // conexion hay. Lo que falla es el servidor, y decirle «comprueba la señal»
    // a quien esta en la oficina lo manda a mirar donde no es.
    //
    // Paso el 16/09: el acceso de la web fallaba por CORS —auth no autorizaba el
    // origen del reparto— y la pantalla lo contaba como falta de señal. Un fallo
    // de configuracion disfrazado de problema de cobertura.
    MotivoDeAcceso.sinConexion => TextosDeCaida.queHacer(
      sinConexion: sinConexion,
    ),
    _ => null,
  };
}
