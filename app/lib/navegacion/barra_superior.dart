import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diseno/anchos.dart';
import '../diseno/colores.dart';
import '../diseno/selector.dart';
import '../nucleo/base/base.dart';
import '../nucleo/proveedores.dart';
import 'estado_navegacion.dart';

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

    return Container(
      height: Anchos.altoBarraSuperior,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colores.borde)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (alAbrirMenu != null)
            IconButton(
              tooltip: 'Menú',
              icon: const Icon(Icons.menu),
              onPressed: alAbrirMenu,
            ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              titulo,
              overflow: TextOverflow.ellipsis,
              style: tema.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (actualizando) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text(
              'actualizando…',
              style: tema.textTheme.bodySmall?.copyWith(color: Colores.gris),
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
    final sucursales = ref.watch(sucursalesProvider).value ?? const <Sucursal>[];
    final mirada = ref.watch(sucursalMiradaProvider);

    // Con ninguna no se pinta nada; con una sola, etiqueta fija (§8.2).
    if (sucursales.isEmpty) return const SizedBox.shrink();
    if (sucursales.length == 1) {
      final unica = sucursales.first;
      final codigo = unica.externalId;
      return Text(
        codigo == null ? unica.name : '${unica.name} ($codigo)',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colores.gris),
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
        alElegir: (v) =>
            ref.read(sucursalMiradaProvider.notifier).mirar(v.isEmpty ? null : v),
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
    final conTasa = monedas.where((m) => m.code != 'USD' && m.rate > 0).toList();

    if (conTasa.isEmpty) {
      return Tooltip(
        message: 'Esta sucursal no tiene tasa de cambio todavía: '
            'los importes sólo se pueden ver en USD.',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colores.ambar),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('USD', style: TextStyle(color: Colores.ambar)),
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

/// El avatar. Hoy dice **quien eres y que sucursal te toca**, que es lo que se
/// puede saber sin red (sale del token guardado).
///
/// `Salir` e `Ir a otra aplicación` NO estan todavia: cerrar sesion borra lo
/// local (regla 8) y tiene que preguntar antes si queda trabajo sin subir (caso
/// I7), y despues aterrizar en una pantalla de acceso que aun no existe. Un
/// boton que borra el dia de alguien y lo deja en una pantalla en blanco es peor
/// que no tener boton. Entra con la pantalla de acceso.
class _Avatar extends ConsumerWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<void>(
      tooltip: 'Cuenta',
      icon: const CircleAvatar(
        radius: 14,
        backgroundColor: Colores.indigo,
        child: Icon(Icons.person, size: 16, color: Colors.white),
      ),
      itemBuilder: (contexto) => <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          enabled: false,
          child: FutureBuilder<String>(
            future: _quienSoy(ref),
            builder: (contexto, resultado) => Text(
              resultado.data ?? 'Cargando...',
              style: Theme.of(contexto).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }

  Future<String> _quienSoy(WidgetRef ref) async {
    final sesion = await ref.read(almacenSesionProvider).leer();
    if (sesion == null) return 'Sesión en la cookie del navegador';
    final roles = sesion.roles.isEmpty ? '—' : sesion.roles.join(', ');
    return '${sesion.sub}\n$roles';
  }
}
