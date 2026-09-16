// EL MENU DE LA CUENTA — el avatar de la barra superior.
//
// Es el patron de `delivery/src/components/UserMenu.tsx`, traido entero. Aqui
// dentro va lo de TU CUENTA y nada mas: quien eres, a que otras aplicaciones
// puedes ir, y salir. Cerrar sesion no es una pantalla a la que ir, y por eso no
// esta en la barra lateral entre las pantallas (§8.1).
//
// Lo que habia antes y por que se fue: un circulo azul con un icono de persona
// generico, y un desplegable cuyo primer renglon ensenaba
// `uaoOUHqTXNYUv672kjdLoZLpFrseCz9e` —el identificador de la fila de esa persona
// en la base de auth— con la lista de roles debajo. Ese numero no significa nada
// para quien lo lee: es la base en la cara del logistico. **Aqui no se pinta el
// `sub` en ningun sitio**, y hay una prueba que falla si vuelve.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../diseno/anchos.dart';
import '../diseno/cajon.dart';
import '../diseno/colores.dart';
import '../diseno/tema.dart';
import '../nucleo/identidad/sesion.dart';
import '../nucleo/proveedores.dart';
import '../nucleo/registro/registro.dart';
import 'portero.dart';

/// Una baldosa del menu, tal como la manda `GET /api/apps` (`api/internal/api/
/// yo.go`). **La lista la decide el servidor**, no esta pantalla: filtrarla aqui
/// por el rol que lleva el aparato seria ensenarle el mapa completo a quien
/// edite ese valor.
class Aplicacion {
  const Aplicacion({
    required this.href,
    required this.icono,
    required this.titulo,
    required this.descripcion,
  });

  factory Aplicacion.deJson(Map<String, Object?> json) => Aplicacion(
    href: (json['href'] ?? '') as String,
    icono: (json['icon'] ?? '') as String,
    titulo: (json['title'] ?? '') as String,
    descripcion: (json['description'] ?? '') as String,
  );

  final String href;

  /// El nombre del icono en el catalogo de Iconify (`mdi:routes`), que es lo que
  /// usa la de Next. Aqui se traduce con [_icono].
  final String icono;

  final String titulo;
  final String descripcion;
}

/// La sesion que se esta pintando, para el boton y la cabecera del menu.
///
/// Sale de lo GUARDADO, no de una peticion: el nombre y el correo vienen dentro
/// del token que firmo auth, asi que se saben sin red. Se prefiere la del
/// portero —que es la que acaba de entrar— y si no hay, se lee el almacen.
///
/// `autoDispose` a proposito: al salir, la barra se desmonta y esto se tira, asi
/// que quien entre despues no se encuentra con el nombre del anterior.
final sesionParaElMenuProvider = FutureProvider.autoDispose<Sesion?>((
  ref,
) async {
  final delPortero = ref.read(porteroProvider).sesion;
  if (delPortero != null) return delPortero;
  return ref.read(almacenSesionProvider).leer();
});

/// Las aplicaciones a las que se puede ir.
///
/// Se piden **una sola vez y sólo cuando se abre el menu**: no hace falta
/// consultarlas en cada pantalla para pintar un avatar. Es lo mismo que hace la
/// de Next con `enabled: !!token && abierto` y media hora de `staleTime`; aqui
/// lo da el propio provider, que al no ser `autoDispose` guarda la respuesta
/// mientras la aplicacion viva.
///
/// **Si falla, devuelve la lista vacia y no lanza.** El menu es «quien eres y
/// salir»; las aplicaciones son un extra. Un menu que no abre porque no hay red
/// es peor que un menu sin baldosas.
final aplicacionesProvider = FutureProvider<List<Aplicacion>>((ref) async {
  try {
    final datos = await ref
        .read(clienteApiProvider)
        .pedir<Map<String, Object?>>('/apps');
    final lista = (datos['apps'] as List<Object?>?) ?? const <Object?>[];
    return [
      for (final a in lista.whereType<Map<String, Object?>>())
        Aplicacion.deJson(a),
    ];
  } on Object catch (e) {
    Registro.aviso('no se pudieron leer las aplicaciones: $e');
    return const <Aplicacion>[];
  }
});

/// El boton del avatar y su menu.
class MenuDeCuenta extends ConsumerStatefulWidget {
  const MenuDeCuenta({super.key});

  @override
  ConsumerState<MenuDeCuenta> createState() => _MenuDeCuentaState();
}

class _MenuDeCuentaState extends ConsumerState<MenuDeCuenta> {
  /// Sólo para girar el chevron. Lo de abrir y cerrar lo lleva el `Navigator`.
  bool _abierto = false;

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionParaElMenuProvider).value;
    final estrecho = MediaQuery.sizeOf(context).width < Anchos.idioma;

    return Semantics(
      button: true,
      label: 'Tu cuenta',
      child: Material(
        color: _abierto
            ? Colores.tinta.withValues(alpha: 0.04)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radios.lg),
        child: InkWell(
          onTap: _abrir,
          borderRadius: BorderRadius.circular(Radios.lg),
          hoverColor: Colores.tinta.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Aire.sm, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // El nombre y el rol se esconden en el telefono (`hidden
                // sm:block`): ahi el ancho es para el titulo de la pantalla.
                if (!estrecho) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          sesion?.nombreParaVer ?? 'Tu cuenta',
                          overflow: TextOverflow.ellipsis,
                          style: Tipos.texto(
                            tamano: 14,
                            peso: FontWeight.w600,
                            color: Colores.tinta,
                          ),
                        ),
                      ),
                      if ((sesion?.rolParaVer ?? '').isNotEmpty)
                        Text(
                          sesion!.rolParaVer,
                          style: Tipos.texto(
                            tamano: 10,
                            peso: FontWeight.w600,
                            color: Colores.tintaSuave.withValues(alpha: 0.75),
                            interletra: 0.5,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                ],
                _Inicial(sesion: sesion),
                // Gira 180° al abrir, como el de la de Next.
                AnimatedRotation(
                  turns: _abierto ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colores.tintaSuave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _abrir() async {
    // Pedir las aplicaciones AQUI, al abrir, y no en `build`: es lo que hace que
    // no se consulten en cada pantalla sólo para pintar un avatar.
    ref.read(aplicacionesProvider);

    setState(() => _abierto = true);
    final anchoPantalla = MediaQuery.sizeOf(context).width;

    if (anchoPantalla < Anchos.escritorio) {
      // En movil, CAJON: la regla de la casa. Trae de serie la ✕ que no
      // desaparece, el velo que cierra al pulsar fuera y Escape.
      final sesion = await ref.read(sesionParaElMenuProvider.future);
      if (!mounted) return;
      await abrirCajon<void>(
        context,
        titulo: sesion?.nombreParaVer ?? 'Tu cuenta',
        subtitulo: (sesion?.correo.isNotEmpty ?? false) ? sesion!.correo : null,
        ancho: AnchoCajon.md,
        cuerpo: (contexto) => const _Cuerpo(conCabecera: false),
      );
    } else {
      // En escritorio, un desplegable ANCLADO al avatar. No un modal centrado:
      // esto es del rincon de tu cuenta y tiene que salir de ahi.
      //
      // `showMenu` se pinta en el `Overlay`, que es lo que en la de Next hace el
      // portal: asi no se recorta contra el borde de la barra superior. Y trae
      // las dos salidas que alli estan escritas a mano — pulsar fuera cierra, y
      // Escape tambien, porque el `ModalBarrier` atiende el `DismissIntent`.
      await showMenu<void>(
        context: context,
        position: _debajoDelBoton(),
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
        color: Colores.blanco,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radios.xl),
          side: BorderSide(color: Colores.linea),
        ),
        items: const [
          PopupMenuItem<void>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _Cuerpo(conCabecera: true),
          ),
        ],
      );
    }

    if (mounted) setState(() => _abierto = false);
  }

  /// Pegado al borde DERECHO del avatar y justo debajo, como el
  /// `right: window.innerWidth - r.right` de la de Next.
  RelativeRect _debajoDelBoton() {
    final caja = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final abajoIzquierda = caja.localToGlobal(
      caja.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    );
    final abajoDerecha = caja.localToGlobal(
      caja.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    return RelativeRect.fromLTRB(
      abajoIzquierda.dx,
      abajoIzquierda.dy + 6,
      overlay.size.width - abajoDerecha.dx,
      0,
    );
  }
}

/// El cuadro del avatar: degradado de `--primary` a `--secondary` y **la inicial
/// del nombre**, no un icono de persona. Un icono generico es el mismo para
/// todos; la letra dice de quien es la sesion abierta.
class _Inicial extends StatelessWidget {
  const _Inicial({required this.sesion});

  final Sesion? sesion;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colores.primario, Colores.secundario],
      ),
      borderRadius: BorderRadius.circular(Radios.lg),
      boxShadow: Sombras.md,
    ),
    child: Text(
      sesion?.inicial ?? '?',
      style: Tipos.texto(
        tamano: 14,
        peso: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}

/// Lo de dentro del menu, igual en el desplegable y en el cajon.
class _Cuerpo extends ConsumerWidget {
  const _Cuerpo({required this.conCabecera});

  /// El cajon ya pone el nombre y el correo en SU cabecera, con la ✕ al lado;
  /// repetirlos dentro seria decirlo dos veces.
  final bool conCabecera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionParaElMenuProvider).value;
    final aplicaciones =
        ref.watch(aplicacionesProvider).value ?? const <Aplicacion>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (conCabecera) ...[
          Container(
            width: double.infinity,
            color: Colores.tinta.withValues(alpha: 0.02),
            padding: const EdgeInsets.symmetric(
              horizontal: Aire.lg,
              vertical: Aire.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sesion?.nombreParaVer ?? 'Tu cuenta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tipos.texto(
                    tamano: 14,
                    peso: FontWeight.w600,
                    color: Colores.tinta,
                  ),
                ),
                // Sin correo no se pinta el renglon vacio: una linea en blanco
                // debajo del nombre se lee como que falta algo.
                if (sesion?.correo.isNotEmpty ?? false)
                  Text(
                    sesion!.correo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tipos.texto(
                      tamano: 12,
                      color: Colores.tintaSuave.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colores.linea),
        ],
        // Las aplicaciones son un EXTRA. Sin ellas —sin red, o con `/api/apps`
        // caido— el menu sigue siendo el menu, y no sale ningun aviso rojo: no
        // ha fallado nada que la persona pidiera.
        if (aplicaciones.isNotEmpty) ...[
          ConstrainedBox(
            // Alto de sobra para que la ultima no quede cortada por la mitad:
            // una lista que parece terminar donde no termina es una lista
            // incompleta.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Aire.lg,
                      Aire.md,
                      Aire.lg,
                      Aire.xs,
                    ),
                    child: Text(
                      'Ir a',
                      style: Tipos.texto(
                        tamano: 10,
                        peso: FontWeight.w600,
                        color: Colores.tintaSuave.withValues(alpha: 0.6),
                        interletra: 0.6,
                      ),
                    ),
                  ),
                  for (final a in aplicaciones) _Baldosa(aplicacion: a),
                  const SizedBox(height: Aire.sm),
                ],
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colores.linea),
        ],
        Padding(
          padding: const EdgeInsets.all(6),
          child: _Salir(conCabecera: conCabecera),
        ),
      ],
    );
  }
}

/// Una aplicacion. Se abre FUERA —pestana nueva en web, navegador en la APK— y
/// se dice con la flechita, porque salir de la aplicacion sin avisar en medio de
/// un reparto es perder lo que estabas mirando.
class _Baldosa extends StatelessWidget {
  const _Baldosa({required this.aplicacion});

  final Aplicacion aplicacion;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _ir(aplicacion.href),
    hoverColor: Colores.tinta.withValues(alpha: 0.035),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Aire.lg,
        vertical: Aire.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              _icono(aplicacion.icono),
              size: 20,
              color: Colores.tintaSuave.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(width: Aire.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  aplicacion.titulo,
                  style: Tipos.texto(
                    tamano: 14,
                    peso: FontWeight.w500,
                    color: Colores.tinta,
                  ),
                ),
                Text(
                  aplicacion.descripcion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tipos.texto(
                    tamano: 11,
                    color: Colores.tintaSuave.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Aire.sm),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              Icons.open_in_new,
              size: 13,
              color: Colores.tintaSuave.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    ),
  );

  static Future<void> _ir(String href) async {
    final destino = Uri.tryParse(href);
    if (destino == null) return;
    try {
      await launchUrl(destino, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      // Que no se pueda abrir no puede tumbar el menu: se anota y ya. La persona
      // sigue teniendo su nombre, su correo y su Salir.
      Registro.aviso('no se pudo abrir $href: $e');
    }
  }
}

/// SALIR, en rojo. Es el unico renglon del menu que destruye algo, y por eso es
/// el unico que no va en tinta.
class _Salir extends ConsumerWidget {
  const _Salir({required this.conCabecera});

  /// En el cajon hay que cerrarlo antes de irse; en el desplegable lo cierra el
  /// propio `showMenu` al salir del `Navigator`.
  final bool conCabecera;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(Radios.lg),
    child: InkWell(
      onTap: () => _salir(context, ref),
      borderRadius: BorderRadius.circular(Radios.lg),
      hoverColor: Colores.rojoFondo,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.logout, size: 18, color: Colores.rojo),
            const SizedBox(width: Aire.md),
            Text(
              'Cerrar sesión',
              style: Tipos.texto(
                tamano: 14,
                peso: FontWeight.w600,
                color: Colores.rojo,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _salir(BuildContext context, WidgetRef ref) async {
    final pendientes = await ref.read(baseProvider).cuantosPendientes();
    if (!context.mounted) return;

    if (pendientes > 0) {
      // Trabajo sin subir: se dice CUANTO y se pregunta. Salir lo borraria del
      // aparato sin que nadie lo hubiera visto nunca en el servidor.
      final sigue = await showDialog<bool>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: const Text('Queda trabajo sin subir'),
          content: Text(
            'Hay $pendientes ${pendientes == 1 ? "apunte" : "apuntes"} sin '
            'subir al servidor. Si sales ahora se borra lo de este aparato y '
            'ese trabajo se pierde.\n\nConecta y espera a que suba antes de '
            'salir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(false),
              child: const Text('Me quedo'),
            ),
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(true),
              child: const Text('Salir y perderlo'),
            ),
          ],
        ),
      );
      if (sigue != true) return;
    }

    // El cajon se cierra a mano: si no, queda el panel abierto encima de la
    // pantalla de acceso.
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await ref.read(porteroProvider).salir();
  }
}

/// Del nombre de Iconify que manda el servidor al icono de Material.
///
/// Es un mapa escrito y no una tabla porque el catalogo de `/api/apps` son los
/// dominios de la casa: nueve, y cambian una vez al ano. Lo que no este se pinta
/// con el icono de «una aplicacion», que es mejor que un hueco: una baldosa sin
/// icono parece rota.
IconData _icono(String deIconify) => switch (deIconify) {
  'mdi:clipboard-list-outline' => Icons.receipt_long_outlined,
  'mdi:package-variant-closed-check' => Icons.inventory_2_outlined,
  'mdi:routes' => Icons.route_outlined,
  'mdi:chart-bar' => Icons.bar_chart_outlined,
  'mdi:cash-register' => Icons.point_of_sale_outlined,
  'mdi:swap-horizontal' => Icons.swap_horiz_outlined,
  'mdi:view-dashboard-outline' => Icons.dashboard_outlined,
  'mdi:home-outline' => Icons.home_outlined,
  'mdi:shield-account-outline' => Icons.admin_panel_settings_outlined,
  _ => Icons.apps_outlined,
};
