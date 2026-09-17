// LA PANTALLA DEL MAPA SIN CONEXIÓN.
//
// Lo que tiene que quedar claro aquí, y es todo lo que hay que entender de este
// fichero:
//
//  * **EL TAMAÑO SE DICE ANTES.** Nadie baja 26 MB sin saber que son 26 MB, y
//    menos con los datos de Cuba. El número va en el botón, no en la letra
//    pequeña.
//  * **No se baja nada solo.** Se ofrece, decide la persona. Igual que el aviso
//    de versión de la aplicación (`docs/actualizaciones.md` §1.2).
//  * **Si falla, se dice qué faltó y si se conserva lo bajado.** «No se pudo
//    descargar» no le dice a nadie qué hacer.
//  * **Sin paquete NO pasa nada malo.** El mapa de la ruta se dibuja igual con
//    el croquis. Esta pantalla lo dice con esas palabras, porque Jose creía lo
//    contrario y en esta aplicación no es verdad.
//
// En la web esta pantalla **no existe**: se sale en la primera línea. Regla 1.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diseno/colores.dart';
import '../../mapa/anuncio_de_mapa.dart';
import '../../mapa/descarga_de_mapa.dart';
import '../../mapa/proveedores_de_mapa.dart';

/// LAS FRASES, con nombre y públicas.
///
/// Con nombre porque la prueba tiene que poder decir «sale ÉSTA y no la otra»
/// sin copiar la cadena: una prueba que repite el texto del código no comprueba
/// el texto, comprueba que sabe copiar (`CLAUDE.md` §5).
abstract final class TextosDelMapaGuardado {
  static const titulo = 'Mapa de Cuba sin conexión';

  /// LO PRIMERO QUE SE LEE, y es la frase que desmonta la creencia de que sin
  /// mapa no se puede trabajar.
  static const noHaceFalta =
      'El mapa de las rutas funciona sin esto: las paradas, su orden y el '
      'recorrido se dibujan con lo que ya está en el aparato. Descargar el mapa '
      'de Cuba añade las calles de fondo, también sin señal.';

  static const enLaWeb =
      'Esta pantalla es de la aplicación de Android y del escritorio. En el '
      'navegador el mapa sale del servidor y no hay nada que descargar.';

  static const nadaColgado =
      'Todavía no hay ningún mapa colgado para descargar. Cuando lo haya, '
      'aparecerá aquí con su tamaño.';

  static const noSeSupo =
      'No se pudo preguntar si hay un mapa nuevo. Se mira otro día; lo que ya '
      'esté descargado sigue funcionando.';

  /// LA ATRIBUCIÓN. La licencia de OpenStreetMap la exige donde se enseñe el
  /// mapa, también sin conexión. El croquis ya la pinta encima de las teselas;
  /// aquí se repite porque aquí es donde se explica de dónde salen los datos.
  static const atribucion =
      'Los mapas son de © OpenStreetMap y sus colaboradores, con licencia ODbL.';

  static String ilegibles(int cuantos) =>
      'El servidor anunció $cuantos ${cuantos == 1 ? 'nivel' : 'niveles'} más '
      'que esta versión de la aplicación no sabe leer. No se puede descargar '
      '${cuantos == 1 ? 'ése' : 'ésos'} hasta actualizarla.';

  static String tengo(PaqueteGuardado g) =>
      'Tienes «${g.titulo}»: ${enMegas(g.bytes)}, versión ${g.version}.';

  static String bajando(int bajados, int total) =>
      'Bajando ${enMegas(bajados)} de ${enMegas(total)} '
      '(${(bajados * 100 / total).clamp(0, 100).round()} %).';

  /// El botón, **con el tamaño dentro**.
  static String bajar(NivelDeMapa n) => '${n.titulo} — ${enMegas(n.bytes)}';
}

const claveDeAtribucionDelMapa = ValueKey('mapa-guardado-atribucion');
const claveDeAvisoDeDescarga = ValueKey('mapa-guardado-aviso');
ValueKey<String> claveDeBajar(String nivel) => ValueKey<String>('mapa-guardado-bajar-$nivel');

class PantallaMapaSinConexion extends ConsumerStatefulWidget {
  const PantallaMapaSinConexion({super.key});

  @override
  ConsumerState<PantallaMapaSinConexion> createState() =>
      _PantallaMapaSinConexionState();
}

class _PantallaMapaSinConexionState
    extends ConsumerState<PantallaMapaSinConexion> {
  ({int bajados, int total})? _comoVa;
  String? _aviso;
  CancelToken? _cancelar;

  @override
  Widget build(BuildContext context) {
    // REGLA 1 —en la web, nada— se pregunta UNA vez, y es en
    // `estadoDelMapaProvider`, que contesta `MapaNoAplica`. Aquí había otra
    // pregunta igual y se quitó al romperla a propósito y ver que la prueba
    // seguía verde: **la guarda era redundante**. Dos sitios donde se pregunta
    // lo mismo es el §3-bis de `CLAUDE.md` en pequeño — el día que uno cambie,
    // el otro se queda mintiendo y nadie lo nota.
    final estado = ref.watch(estadoDelMapaProvider);
    return _Hoja(
      children: [
        const Text(
          TextosDelMapaGuardado.noHaceFalta,
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        ...switch (estado) {
          AsyncError(:final error) => [
            _Aviso(texto: 'No se pudo abrir la carpeta del mapa: $error'),
          ],
          AsyncData(value: final v) => _segunElEstado(v),
          // Mientras se pregunta NO se promete nada. Empezar diciendo «al día»
          // es la misma familia de fallo que un «Todo en verde» antes de
          // comprobar nada.
          _ => const [LinearProgressIndicator()],
        },
        if (_comoVa case final v?) ...[
          const SizedBox(height: 12),
          // EL NÚMERO, no una rueda. Una rueda en una descarga de 26 MB por la
          // conexión de allá no distingue «va lenta» de «está parada».
          Text(
            TextosDelMapaGuardado.bajando(v.bajados, v.total),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: v.total == 0 ? null : v.bajados / v.total,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _cancelar?.cancel(),
            child: const Text('Detener'),
          ),
        ],
        if (_aviso case final a?) ...[
          const SizedBox(height: 12),
          _Aviso(key: claveDeAvisoDeDescarga, texto: a),
        ],
        const SizedBox(height: 20),
        const Text(
          TextosDelMapaGuardado.atribucion,
          key: claveDeAtribucionDelMapa,
          style: TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  List<Widget> _segunElEstado(EstadoDelMapa estado) => switch (estado) {
    MapaNoAplica() => const [Text(TextosDelMapaGuardado.enLaWeb)],
    NoSeSupoDelMapa(:final tengo) => [
      if (tengo != null) Text(TextosDelMapaGuardado.tengo(tengo)),
      const SizedBox(height: 8),
      const Text(TextosDelMapaGuardado.noSeSupo, style: TextStyle(fontSize: 12)),
    ],
    SinPaqueteDeMapa(:final ofertas, :final ilegibles) => [
      if (ofertas.isEmpty)
        const Text(TextosDelMapaGuardado.nadaColgado)
      else
        ..._ofertas(ofertas),
      if (ilegibles > 0) ...[
        const SizedBox(height: 8),
        _Aviso(texto: TextosDelMapaGuardado.ilegibles(ilegibles)),
      ],
    ],
    MapaAlDia(:final tengo, :final ofertas) => [
      Text(TextosDelMapaGuardado.tengo(tengo)),
      const SizedBox(height: 4),
      const Text(
        'Está al día.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 12),
      ..._ofertas(ofertas.where((o) => o.nivel != tengo.nivel).toList()),
    ],
    HayMapaNuevo(:final tengo, :final nuevo, :final motivo, :final ofertas) => [
      Text(TextosDelMapaGuardado.tengo(tengo)),
      const SizedBox(height: 8),
      _Aviso(texto: motivo),
      const SizedBox(height: 8),
      ..._ofertas([nuevo, ...ofertas.where((o) => o.nivel != nuevo.nivel)]),
    ],
  };

  List<Widget> _ofertas(List<NivelDeMapa> niveles) => [
    for (final n in niveles) ...[
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton(
              key: claveDeBajar(n.nivel),
              // Se apaga mientras hay otra descarga en marcha: dos a la vez por
              // esta conexión es no terminar ninguna.
              onPressed: _comoVa != null ? null : () => _bajar(n),
              // EL TAMAÑO VA EN EL BOTÓN.
              child: Text(TextosDelMapaGuardado.bajar(n)),
            ),
            const SizedBox(height: 4),
            Text(n.explicacion, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    ],
  ];

  Future<void> _bajar(NivelDeMapa nivel) async {
    final descarga = ref.read(descargaDeMapaProvider);
    if (descarga == null) return;
    final cancelar = CancelToken();
    setState(() {
      _aviso = null;
      _cancelar = cancelar;
      _comoVa = (bajados: 0, total: nivel.bytes);
    });

    final resultado = await descarga.bajar(
      nivel,
      cancelar: cancelar,
      comoVa: ({required bajados, required total}) {
        if (mounted) setState(() => _comoVa = (bajados: bajados, total: total));
      },
    );
    if (!mounted) return;

    setState(() {
      _comoVa = null;
      _cancelar = null;
      _aviso = switch (resultado) {
        DescargaLista(:final guardado) =>
          'Listo. ${TextosDelMapaGuardado.tengo(guardado)} Ya se puede trabajar '
              'sin señal.',
        // EL MOTIVO LITERAL. Ya dice él mismo qué faltó y si lo bajado se
        // conserva, que es lo accionable; «no se pudo» no lo es.
        DescargaFallida(:final motivo) => motivo,
      };
    });
    if (resultado is DescargaLista) {
      // Lo guardado cambió: que se enteren la pantalla y el mapa de la ruta.
      ref.invalidate(paqueteGuardadoProvider);
      ref.invalidate(estadoDelMapaProvider);
    }
  }
}

/// LA HOJA. **Sin `Scaffold` ni `AppBar`**: los pone el armazón
/// (`navegacion/pantalla_registrada.dart`). Devolver otro deja dos barras
/// superiores y rompe el selector de sucursal.
class _Hoja extends StatelessWidget {
  const _Hoja({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(texto, style: TextStyle(fontSize: 12, color: Colores.tinta)),
    ),
  );
}
