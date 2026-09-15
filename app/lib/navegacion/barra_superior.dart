import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/anchos.dart';
import '../diseno/colores.dart';
import '../diseno/selector.dart';
import '../diseno/tema.dart';
import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';
import 'estado_navegacion.dart';
import 'portero.dart';

/// La barra superior: 64 px, pegajosa arriba (pliego §8.2).
///
/// Izquierda: boton de menu **solo en movil**, titulo de la pantalla y
/// `actualizando…` con el giro mientras haya cualquier consulta en vuelo.
/// Derecha: sucursal, moneda y avatar.
class BarraSuperior extends ConsumerWidget implements PreferredSizeWidget {
  const BarraSuperior({required this.titulo, this.alAbrirMenu, super.key});

  final String titulo;

  /// `null` en escritorio: alli la barra lateral esta siempre a la vista y un
  /// boton de menu que no abre nada es un boton que ensena a desconfiar.
  final VoidCallback? alAbrirMenu;

  @override
  Size get preferredSize => const Size.fromHeight(Anchos.altoBarraSuperior);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final actualizando = ref.watch(actualizandoProvider);

    // Sobre PAPEL, no sobre blanco: en delivery la barra es `bg-paper/80` y lo
    // blanco son las tarjetas y la barra lateral. Una barra superior blanca
    // sobre un fondo casi blanco hace que la pantalla no tenga arriba.
    return Container(
      height: Anchos.altoBarraSuperior,
      decoration: const BoxDecoration(
        color: Colores.papel,
        border: Border(bottom: BorderSide(color: Colores.linea)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Aire.md),
      child: Row(
        children: [
          if (alAbrirMenu != null)
            IconButton(
              tooltip: 'Menú',
              icon: const Icon(Icons.menu, size: 22),
              color: Colores.tintaSuave,
              onPressed: alAbrirMenu,
            ),
          const SizedBox(width: Aire.xs),
          Flexible(
            child: Text(
              titulo,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.titleLarge,
            ),
          ),
          if (actualizando) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colores.tintaSuave,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'actualizando…',
              style: Tipos.texto(
                tamano: 11,
                peso: FontWeight.w500,
                color: Colores.tintaSuave.withValues(alpha: 0.7),
              ),
            ),
          ],
          const Spacer(),
          const _Sucursal(),
          // `Idioma` (ES/EN) va JUSTO AQUI, entre sucursal y moneda, y se oculta
          // por debajo de 640 px (§11). No esta todavia porque no hay ARB ni
          // `flutter_localizations` en el pubspec — es la ola 1-C —, y un
          // desplegable de idioma que no cambia ni una palabra ensena a
          // desconfiar de la barra entera. Cuando entre gen_l10n se anade aqui,
          // envuelto en `if (ancho >= Anchos.idioma)`.
          const SizedBox(width: 8),
          const _Moneda(),
          const SizedBox(width: 8),
          const _Avatar(),
        ],
      ),
    );
  }
}

/// El selector de sucursal del Super Admin.
///
/// Cambiarlo **no recarga la pagina**: los providers de pantalla miran
/// `sucursalMiradaProvider`, asi que se reconstruyen solos y los numeros cambian
/// en el sitio. Eso es lo que pide el pliego §0 y es la razon de que la sucursal
/// viva en un provider y no en la URL.
class _Sucursal extends ConsumerWidget {
  const _Sucursal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sucursales =
        ref.watch(sucursalesProvider).value ?? const <Sucursal>[];
    final mirada = ref.watch(sucursalMiradaProvider);

    // Con ninguna no se pinta nada; con una sola, etiqueta fija (§8.2).
    if (sucursales.isEmpty) return const SizedBox.shrink();
    if (sucursales.length == 1) {
      final unica = sucursales.first;
      final codigo = unica.externalId;
      // Una sola sucursal: se dice cual es en una pastilla blanca con su borde
      // fino — la misma caja que el selector, para que la barra no tenga una
      // pieza sin forma al lado de otra que si la tiene.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 8),
        decoration: BoxDecoration(
          color: Colores.blanco,
          border: Border.all(color: Colores.linea),
          borderRadius: BorderRadius.circular(Radios.lg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.store_outlined,
              size: 16,
              color: Colores.tintaSuave,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                codigo == null ? unica.name : '${unica.name} ($codigo)',
                overflow: TextOverflow.ellipsis,
                style: Tipos.texto(tamano: 14, color: Colores.tinta),
              ),
            ),
          ],
        ),
      );
    }

    // Si la sucursal guardada ya no esta entre las visibles, se olvida (§8.2):
    // dejarla puesta filtraria por una sucursal que la persona ya no ve y la
    // pantalla saldria vacia sin motivo a la vista.
    final valida = mirada != null && sucursales.any((s) => s.id == mirada);
    final valor = valida ? mirada : '';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Selector<String>(
        icono: Icons.store_outlined,
        tooltip: 'Sucursal que se está mirando',
        etiquetaVacia: 'Todas las sucursales (${sucursales.length})',
        valor: valor,
        opciones: [
          OpcionSelector<String>(
            valor: '',
            etiqueta: 'Todas las sucursales (${sucursales.length})',
          ),
          for (final s in sucursales)
            OpcionSelector<String>(
              valor: s.id,
              etiqueta: s.name,
              nota: s.externalId,
            ),
        ],
        alElegir: (v) => ref
            .read(sucursalMiradaProvider.notifier)
            .mirar(v.isEmpty ? null : v),
      ),
    );
  }
}

/// La moneda en la que se PINTAN los importes.
///
/// Sin tasa se queda en USD fijo, con borde ambar y el motivo en el tooltip
/// (§8.2). No se ofrece elegir CUP sin tasa: convertir sin tasa es inventarse un
/// numero, y un numero inventado en una hoja de reparto acaba cobrado.
class _Moneda extends ConsumerWidget {
  const _Moneda();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monedas = ref.watch(monedasProvider).value ?? const <Moneda>[];
    final mirada = ref.watch(monedaMiradaProvider);
    final conTasa = monedas
        .where((m) => m.code != 'USD' && m.rate > 0)
        .toList();

    if (conTasa.isEmpty) {
      return Tooltip(
        message:
            'Esta sucursal no tiene tasa de cambio todavía: '
            'los importes sólo se pueden ver en USD.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 8),
          decoration: BoxDecoration(
            color: Colores.blanco,
            border: Border.all(color: Colores.ambar.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(Radios.lg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.money_off_csred_outlined,
                size: 16,
                color: Colores.ambar,
              ),
              const SizedBox(width: 6),
              // En mono: es una cifra, aunque sea el codigo de la moneda.
              Text(
                'USD',
                style: Tipos.mono(
                  tamano: 12,
                  peso: FontWeight.w600,
                  color: Colores.ambar,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Selector<String>(
      tooltip: 'Moneda de visualización',
      etiquetaVacia: 'USD',
      valor: mirada,
      opciones: [
        const OpcionSelector<String>(valor: 'USD', etiqueta: 'USD'),
        for (final m in conTasa)
          OpcionSelector<String>(
            valor: m.code,
            etiqueta: m.code,
            nota: '1 USD = ${m.rate}',
          ),
      ],
      alElegir: (v) => ref.read(monedaMiradaProvider.notifier).mirar(v),
    );
  }
}

/// El avatar. Dice **quien eres y que sucursal te toca** —que es lo que se puede
/// saber sin red, porque sale del token guardado— y deja salir.
///
/// `Salir` **pregunta antes si queda trabajo sin subir** (caso I7). Cerrar
/// sesion borra lo local (regla 8): en el aparato quedan los clientes con sus
/// direcciones y los pedidos del dia, y si el telefono cambia de manos eso no
/// puede seguir ahi. Lo que NO se borra sin avisar es la cola: el dia de alguien
/// no se tira en silencio.
class _Avatar extends ConsumerWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Cuenta',
      icon: const CircleAvatar(
        radius: 16,
        backgroundColor: Colores.primario,
        child: Icon(Icons.person_outline, size: 18, color: Colors.white),
      ),
      onSelected: (que) {
        if (que == 'salir') _salir(context, ref);
      },
      itemBuilder: (contexto) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: FutureBuilder<String>(
            future: _quienSoy(ref),
            builder: (contexto, resultado) => Text(
              resultado.data ?? 'Cargando...',
              style: Theme.of(contexto).textTheme.bodySmall,
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'salir',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: Colores.tintaSuave),
              SizedBox(width: 8),
              Text('Salir'),
            ],
          ),
        ),
      ],
    );
  }

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

    await ref.read(porteroProvider).salir();
  }

  Future<String> _quienSoy(WidgetRef ref) async {
    final sesion = await ref.read(almacenSesionProvider).leer();
    if (sesion == null) return 'Sin sesión guardada en este aparato';
    final roles = sesion.roles.isEmpty ? '—' : sesion.roles.join(', ');
    return '${sesion.sub}\n$roles';
  }
}
