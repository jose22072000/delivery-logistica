// LA CUARTA CAPA: el recorrido por calles que sale del paquete guardado.
//
// ═══════════════════════════════════════════════════════════════════════════
// EL INCIDENTE: «la ruta no es lógica, son rectas»
// ═══════════════════════════════════════════════════════════════════════════
//
// Jose, 21/09/2026, probando la APK con el avión puesto y el mapa de Cuba ya
// bajado:
//
// > «y ademas recontra la ruta no es logica es son rectas eso no lo queremos te
// > dije»
//
// Tenía razón y el motivo era de una pieza: el único enrutador que había era
// `CallesDeOsrm`, que es una petición HTTP a `router.project-osrm.org`. Sin
// señal devuelve `null` y el mapa cae a la línea recta de parada a parada. O
// sea: el aparato tenía **Cuba entera en el disco** —geometría de calles de
// sobra, la misma con la que se dibuja el fondo— y aun así el recorrido se
// pintaba cruzando manzanas y bahías en diagonal.
//
// Esto enruta con esa misma geometría, sin una sola petición.
//
// ## Cómo se enruta con un mapa que está cortado en teselas
//
// Una tesela vectorial no es un grafo: es un dibujo. Trae tiras de líneas
// recortadas al cuadro de la tesela, simplificadas, y **sin ninguna idea de qué
// se junta con qué**. Reconstruir el grafo son tres costuras, y las tres
// hicieron falta de verdad — medido sobre el fichero real de La Habana, un
// grafo hecho sólo uniendo vértices iguales quedaba en **396 trozos, y el mayor
// era el 21% de los nodos**. Con eso no se llega de ningún sitio a ningún otro:
//
//  1. **La costura entre teselas.** El generador recorta cada vía al cuadro de
//     su tesela con un margen alrededor (`herramientas/mapa-cuba/teselar.go`),
//     así que la misma calle sale dos veces, una por cada lado, y con los
//     vértices en sitios distintos porque cada tesela se simplifica por su
//     cuenta. Aquí se tira el sobrante, se corta **justo en el borde** —que es
//     una coordenada exacta y la misma para las dos teselas— y luego se cosen
//     los dos extremos.
//  2. **Los cruces sin vértice compartido.** Douglas-Peucker borra los vértices
//     que están casi en línea recta, y el cruce de dos calles rectas es
//     exactamente eso: en el mismo trozo de La Habana había **776 cruces de
//     verdad en los que ninguna de las dos calles tenía un vértice**. Se
//     calculan los cortes y se parte cada vía por ahí.
//  3. **Las calles que mueren contra otra.** Una calle que termina contra una
//     avenida deja su último vértice pegado a la avenida pero **no encima**: la
//     simplificación movió la avenida medio metro. Cada extremo de vía se
//     engancha al segmento más cercano que tenga a menos de unos metros.
//
// Las tres se hacen en la misma pasada y con la misma tolerancia, y las tres
// tienen prueba propia.
//
// ## Lo que se midió al romperlas a propósito, y hay que saberlo
//
// La 2 y la 3 **se tapan la una a la otra sobre el fichero de verdad**: quitando
// la 3, las rutas de La Habana salían idénticas; quitando la 2, también (sólo se
// caía el tramo Habana–Camagüey, que va a z9). O sea que hoy sobra una de las
// dos para esos tramos — y se dejan las dos igualmente, porque cuál sobra
// depende de cómo venga cortado el mapa, y la que sobra no cuesta nada. Lo que
// **no** sobra es la prueba de cada una por separado: con teselas de mentira
// cada costura se cae sola, que es lo que permite enterarse el día que el
// generador cambie y deje de haber red de seguridad.
//
// ## LO QUE ESTE MAPA NO SABE: puentes y túneles
//
// El paquete guarda de cada vía sólo `clase` y `nombre`
// (`herramientas/mapa-cuba/teselar.go`). **No guarda si va por encima o por
// debajo**, así que un paso elevado sobre una calle se lee aquí como un cruce y
// se parte como si se pudiera girar. El efecto medido en La Habana es de un 2%
// de camino de menos (9,49 km contra 9,69 km sin partir los cruces), y de vez en
// cuando una línea que gira donde no se puede girar. Se acepta a sabiendas: esto
// dibuja el recorrido en un mapa, no le canta las maniobras al chofer, y la
// alternativa —no partir ningún cruce— es el grafo en 396 trozos. El día que
// haga falta afinarlo, lo que hay que cambiar es el generador para que escriba
// el nivel, no esto.
//
// ## Lo que NUNCA hace
//
//  * **No lanza.** El contrato de `RecorridoPorCalles` lo dice y aquí importa
//    más que en ningún sitio: esto corre dentro del repintado del mapa de la
//    ruta. Una excepción aquí no es un error en un log, es la pantalla del
//    logístico en negro a las siete de la mañana.
//  * **No tira el recorrido entero por un tramo malo.** Si entre dos paradas no
//    hay camino —una está en un cayo, la otra al otro lado de una bahía sin
//    puente en el mapa— ese tramo sale recto y **los demás siguen por calles**.
//    Devolver `null` por un tramo dejaría toda la ruta en rectas, que es
//    volver al fallo del 21/09.
//  * **No se come la interfaz.** Hay tope de teselas por tramo, se baja de
//    nivel de zoom en vez de cargar cientos, y hay un presupuesto de tiempo
//    para la llamada entera: pasado, lo que quede sale recto.
//
// ## Por qué NO va en un isolate
//
// Se midió antes de decidirlo (`sonda_enrutado_test.dart`). Un tramo típico de
// La Habana —cinco teselas de z14, unas 3.400 tiras de calle, 9.900 nodos—
// tarda **39 ms** en este equipo; los 290 ms del primero de la sonda son el
// calentamiento de la máquina virtual y no vuelven a aparecer. Una ruta entera
// de ocho paradas son 310-370 ms **repartidos en ocho tramos**, con un `await`
// de por medio (la lectura del fichero) que deja respirar al hilo de la
// interfaz entre uno y otro. Meter
// `compute` costaría copiar las teselas crudas al isolate y volver con la línea
// —y, peor, obligaría a que todo esto fuera código de nivel superior sin estado,
// perdiendo la caché. Si algún día un tramo se dispara, el sitio donde meterlo
// es `_tramoPorCalles`, que ya está aislado para eso.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../nucleo/registro/registro.dart';
import '../pantallas/rutas/datos/geo.dart';
import '../pantallas/rutas/datos/mapa_en_vivo.dart';
import 'mvt.dart';
import 'pmtiles.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LA REJILLA: coordenadas globales en unidades de tesela
// ─────────────────────────────────────────────────────────────────────────────
//
// Todo lo de aquí dentro trabaja en **unidades de tesela de un nivel de zoom
// concreto**, no en grados. O sea: `x = (teselaX + px / extension) * 4096`.
//
// Se hace así por dos cosas, y las dos se notan:
//
//  * **Mercator es conforme**: en un trozo de ciudad, un paso en x mide lo mismo
//    que un paso en y, así que la distancia euclídea en estas unidades por un
//    solo factor da metros. Con grados haría falta un coseno por arista, y las
//    aristas son decenas de miles.
//  * **El borde de una tesela cae en un número exacto** (múltiplo de 4096), que
//    es lo que permite coser las dos mitades de una calle partida sin depender
//    de que dos `double` salgan iguales por casualidad.
const unidadesPorTesela = 4096.0;

const _radioTierraM = 6378137.0;

double _gxDeLng(double lng, int z) =>
    (lng + 180) / 360 * (1 << z) * unidadesPorTesela;

double _gyDeLat(double lat, int z) {
  final r = lat * math.pi / 180;
  final y = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
  return y * (1 << z) * unidadesPorTesela;
}

double _lngDeGx(double gx, int z) =>
    gx / ((1 << z) * unidadesPorTesela) * 360 - 180;

double _latDeGy(double gy, int z) {
  final y = gy / ((1 << z) * unidadesPorTesela);
  final n = math.pi * (1 - 2 * y);
  return 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
}

/// Cuántos metros mide una unidad de rejilla a esa latitud y ese zoom.
///
/// Se calcula **una vez por tramo**, con la latitud del medio. Cuba entera va de
/// 19,8° a 23,3°: el coseno cambia un 3% de punta a punta, y dentro de un
/// corredor de reparto es inapreciable. Lo que se usa esto es para las
/// tolerancias de costura y para el radio de enganche de una parada, no para
/// facturar kilómetros — los km de la ruta los sigue poniendo `geo.dart` con
/// haversine.
@visibleForTesting
double metrosPorUnidad(double lat, int z) =>
    2 * math.pi * _radioTierraM * math.cos(lat * math.pi / 180) /
    ((1 << z) * unidadesPorTesela);

// ─────────────────────────────────────────────────────────────────────────────
// QUÉ VÍAS VALEN Y CUÁNTO CUESTA CADA UNA
// ─────────────────────────────────────────────────────────────────────────────

/// El recargo de cada clase de vía sobre sus metros.
///
/// **Ninguno baja de 1.0, y eso no es estética: es lo que hace admisible la
/// heurística del A\*.** Si una clase costara menos que su distancia en línea
/// recta, la estimación se pasaría de optimista y A\* dejaría de garantizar el
/// camino más corto — devolvería uno cualquiera, a veces con un rodeo absurdo,
/// y sin dar ningún aviso.
///
/// Los números dicen una cosa concreta: **un camión de reparto no se mete por
/// una calle de servicio ni por un camino de tierra si tiene una avenida a
/// mano**. Un servicio a 2,0 significa «entra si ahorra más de la mitad del
/// camino», que es lo que hace una persona.
const _recargoPorClase = <String, double>{
  'autopista': 1.0,
  'carretera': 1.0,
  'principal': 1.05,
  'secundaria': 1.1,
  'terciaria': 1.2,
  'calle': 1.35,
  'servicio': 2.0,
  'camino': 2.5,
};

// ─────────────────────────────────────────────────────────────────────────────
// LAS CADENAS: una tira de vía ya recortada a su tesela
// ─────────────────────────────────────────────────────────────────────────────

/// Un trozo de vía, en unidades de rejilla y ya recortado al cuadro de su
/// tesela.
///
/// Las coordenadas van seguidas —`x0, y0, x1, y1, …`— en vez de en una lista de
/// puntos. Son decenas de miles por tramo y cada objeto `Offset` es un objeto
/// más que reservar y recorrer.
@visibleForTesting
class CadenaDeVia {
  const CadenaDeVia(this.puntos, this.recargo);

  final List<double> puntos;
  final double recargo;

  int get cuantos => puntos.length ~/ 2;
}

// ─────────────────────────────────────────────────────────────────────────────
// EL GRAFO
// ─────────────────────────────────────────────────────────────────────────────

/// EL GRAFO DE CALLES DE UN TRAMO.
///
/// Se arma una vez por tramo y se tira. No se guarda entero entre tramos porque
/// dos tramos de una ruta casi nunca comparten corredor; lo que sí se guarda es
/// **la línea ya calculada**, que es lo que de verdad se vuelve a pedir cuando
/// alguien cambia de pestaña y vuelve.
@visibleForTesting
class GrafoDeCalles {
  GrafoDeCalles._(this._xs, this._ys, this._vecinos, this._pesos, this._rejilla,
      this._ladoDeCelda, this._origenX, this._origenY);

  final List<double> _xs;
  final List<double> _ys;
  final List<List<int>> _vecinos;
  final List<List<double>> _pesos;

  /// Nodos por celda, para encontrar el más cercano a una parada sin recorrer
  /// los cuarenta mil.
  final Map<int, List<int>> _rejilla;
  final double _ladoDeCelda;
  final double _origenX;
  final double _origenY;

  int get cuantosNodos => _xs.length;

  double x(int nodo) => _xs[nodo];
  double y(int nodo) => _ys[nodo];

  /// ARMAR EL GRAFO. Las tres costuras del comentario de arriba pasan aquí.
  ///
  /// [toleranciaUnidades] es lo lejos que puede estar un extremo de vía de otra
  /// vía para darlos por unidos. Va en unidades de rejilla: quien llama lo saca
  /// de metros con [metrosPorUnidad].
  factory GrafoDeCalles.deCadenas(
    List<CadenaDeVia> cadenas, {
    required double toleranciaUnidades,
  }) {
    // ── Los segmentos, planos ──────────────────────────────────────────────
    final segAx = <double>[];
    final segAy = <double>[];
    final segBx = <double>[];
    final segBy = <double>[];
    final segRecargo = <double>[];
    // Los cortes que le caen a cada segmento: la posición `t` dentro de él, más
    // el punto exacto. El punto se guarda y no se recalcula a propósito: los dos
    // segmentos que se cruzan tienen que quedarse con **el mismo** `double`, o
    // el cruce se parte en dos nodos separados por una milésima y el grafo
    // vuelve a quedar en trozos.
    final cortes = <int, List<({double t, double x, double y})>>{};

    // Dónde empieza cada cadena dentro de la lista de segmentos, para saber
    // cuáles son extremos.
    final primerSegmento = <int>[];
    for (final cadena in cadenas) {
      primerSegmento.add(segAx.length);
      final p = cadena.puntos;
      for (var i = 0; i + 3 < p.length; i += 2) {
        segAx.add(p[i]);
        segAy.add(p[i + 1]);
        segBx.add(p[i + 2]);
        segBy.add(p[i + 3]);
        segRecargo.add(cadena.recargo);
      }
    }
    final cuantosSeg = segAx.length;
    if (cuantosSeg == 0) {
      return GrafoDeCalles._(
          const [], const [], const [], const [], const {}, 1, 0, 0);
    }

    // ── La rejilla de segmentos ────────────────────────────────────────────
    //
    // El lado se saca de la tolerancia y no de un número redondo: la rejilla
    // sólo sirve para no comparar todos con todos, y tiene que ser lo bastante
    // grande para que dos cosas a `tolerancia` de distancia caigan en celdas
    // vecinas y no a tres de distancia.
    final lado = math.max(toleranciaUnidades * 8, 64.0);
    final celdas = <int, List<int>>{};
    int clave(int cx, int cy) => cx * 1048576 + cy;

    void sembrar(int i) {
      final ax = segAx[i], ay = segAy[i], bx = segBx[i], by = segBy[i];
      final largo = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
      // Se siembra ANDANDO por el segmento, no por su recuadro: una carretera
      // de veinte kilómetros en diagonal tiene un recuadro de cuatrocientas
      // celdas y toca doce.
      final pasos = (largo / (lado / 2)).ceil().clamp(1, 4096);
      var anterior = -1;
      for (var s = 0; s <= pasos; s++) {
        final t = s / pasos;
        final cx = ((ax + (bx - ax) * t) / lado).floor();
        final cy = ((ay + (by - ay) * t) / lado).floor();
        final k = clave(cx, cy);
        if (k == anterior) continue;
        anterior = k;
        (celdas[k] ??= <int>[]).add(i);
      }
    }

    for (var i = 0; i < cuantosSeg; i++) {
      sembrar(i);
    }

    void anotarCorte(int seg, double t, double px, double py) {
      if (t <= 1e-9 || t >= 1 - 1e-9) return; // ya es un vértice
      (cortes[seg] ??= []).add((t: t, x: px, y: py));
    }

    // ── Costura 2: los cruces de verdad ────────────────────────────────────
    final yaMirados = <int>{};
    for (final lista in celdas.values) {
      for (var a = 0; a < lista.length; a++) {
        for (var b = a + 1; b < lista.length; b++) {
          final i = lista[a];
          final j = lista[b];
          final par = i < j ? i * cuantosSeg + j : j * cuantosSeg + i;
          if (!yaMirados.add(par)) continue;
          final ax = segAx[i], ay = segAy[i], bx = segBx[i], by = segBy[i];
          final cx = segAx[j], cy = segAy[j], dx = segBx[j], dy = segBy[j];
          final rx = bx - ax, ry = by - ay;
          final sx = dx - cx, sy = dy - cy;
          final den = rx * sy - ry * sx;
          if (den == 0) continue; // paralelos: no hay un punto de cruce
          final t = ((cx - ax) * sy - (cy - ay) * sx) / den;
          final u = ((cx - ax) * ry - (cy - ay) * rx) / den;
          if (t < 0 || t > 1 || u < 0 || u > 1) continue;
          final px = ax + rx * t;
          final py = ay + ry * t;
          anotarCorte(i, t, px, py);
          anotarCorte(j, u, px, py);
        }
      }
    }

    // ── Costura 1 y 3: los extremos ────────────────────────────────────────
    //
    // Un extremo de cadena es o el final de una calle (que muere contra otra) o
    // el corte del borde de la tesela (que tiene su gemelo en la de al lado).
    // Los dos se arreglan igual: se busca el segmento más cercano que no sea de
    // la misma cadena y se los une.
    //
    // **Sólo los extremos**, y eso es deliberado: enganchar cualquier vértice a
    // cualquier vía cercana uniría dos calles paralelas separadas por una acera
    // y el camión atravesaría manzanas.
    final pegados = <({double x, double y, double px, double py})>[];
    for (var c = 0; c < cadenas.length; c++) {
      final desde = primerSegmento[c];
      final hasta = (c + 1 < cadenas.length ? primerSegmento[c + 1] : cuantosSeg);
      if (desde >= hasta) continue;
      final extremos = <({double x, double y})>[
        (x: segAx[desde], y: segAy[desde]),
        (x: segBx[hasta - 1], y: segBy[hasta - 1]),
      ];
      for (final e in extremos) {
        var mejorD2 = toleranciaUnidades * toleranciaUnidades;
        var mejorSeg = -1;
        var mejorT = 0.0;
        var mejorX = 0.0;
        var mejorY = 0.0;
        final cx0 = (e.x / lado).floor();
        final cy0 = (e.y / lado).floor();
        for (var dcx = -1; dcx <= 1; dcx++) {
          for (var dcy = -1; dcy <= 1; dcy++) {
            final lista = celdas[clave(cx0 + dcx, cy0 + dcy)];
            if (lista == null) continue;
            for (final s in lista) {
              if (s >= desde && s < hasta) continue; // su propia cadena
              final ax = segAx[s], ay = segAy[s];
              final vx = segBx[s] - ax, vy = segBy[s] - ay;
              final largo2 = vx * vx + vy * vy;
              var t = largo2 == 0
                  ? 0.0
                  : ((e.x - ax) * vx + (e.y - ay) * vy) / largo2;
              if (t < 0) t = 0;
              if (t > 1) t = 1;
              final px = ax + vx * t;
              final py = ay + vy * t;
              final d2 = (px - e.x) * (px - e.x) + (py - e.y) * (py - e.y);
              if (d2 < mejorD2) {
                mejorD2 = d2;
                mejorSeg = s;
                mejorT = t;
                mejorX = px;
                mejorY = py;
              }
            }
          }
        }
        if (mejorSeg < 0) continue;
        anotarCorte(mejorSeg, mejorT, mejorX, mejorY);
        pegados.add((x: e.x, y: e.y, px: mejorX, py: mejorY));
      }
    }

    // ── Los nodos ──────────────────────────────────────────────────────────
    //
    // Se cuantiza a cuartos de unidad —a z14, catorce centímetros— para que dos
    // vías que comparten un vértice de OSM caigan en el mismo nodo. La clave se
    // arma con coordenadas RELATIVAS al primer segmento y no absolutas: en la
    // web los enteros son `double` de 53 bits, y empaquetar dos coordenadas
    // globales de z15 se sale. Aquí no hay paquete en la web, pero esto tiene
    // que **compilar y portarse igual** en los cuatro destinos.
    var origenX = double.infinity;
    var origenY = double.infinity;
    for (var i = 0; i < cuantosSeg; i++) {
      origenX = math.min(origenX, math.min(segAx[i], segBx[i]));
      origenY = math.min(origenY, math.min(segAy[i], segBy[i]));
    }
    origenX = origenX.floorToDouble();
    origenY = origenY.floorToDouble();

    final xs = <double>[];
    final ys = <double>[];
    final vecinos = <List<int>>[];
    final pesos = <List<double>>[];
    final indice = <int, int>{};

    int nodo(double px, double py) {
      final qx = ((px - origenX) * 4).round();
      final qy = ((py - origenY) * 4).round();
      final k = qy * 16777216 + qx;
      final ya = indice[k];
      if (ya != null) return ya;
      final nuevo = xs.length;
      indice[k] = nuevo;
      xs.add(px);
      ys.add(py);
      vecinos.add(<int>[]);
      pesos.add(<double>[]);
      return nuevo;
    }

    void unir(int a, int b, double peso) {
      if (a == b) return;
      final ya = vecinos[a].indexOf(b);
      if (ya >= 0) {
        if (peso < pesos[a][ya]) {
          pesos[a][ya] = peso;
          pesos[b][vecinos[b].indexOf(a)] = peso;
        }
        return;
      }
      vecinos[a].add(b);
      pesos[a].add(peso);
      vecinos[b].add(a);
      pesos[b].add(peso);
    }

    for (var i = 0; i < cuantosSeg; i++) {
      final ax = segAx[i], ay = segAy[i], bx = segBx[i], by = segBy[i];
      final recargo = segRecargo[i];
      final trozos = cortes[i];
      var anterior = nodo(ax, ay);
      var anteriorX = ax;
      var anteriorY = ay;
      if (trozos != null) {
        trozos.sort((p, q) => p.t.compareTo(q.t));
        for (final corte in trozos) {
          final n = nodo(corte.x, corte.y);
          final d = math.sqrt((corte.x - anteriorX) * (corte.x - anteriorX) +
              (corte.y - anteriorY) * (corte.y - anteriorY));
          unir(anterior, n, d * recargo);
          anterior = n;
          anteriorX = corte.x;
          anteriorY = corte.y;
        }
      }
      final fin = nodo(bx, by);
      final d = math.sqrt(
          (bx - anteriorX) * (bx - anteriorX) + (by - anteriorY) * (by - anteriorY));
      unir(anterior, fin, d * recargo);
    }

    // Y el salto del extremo a la vía contra la que muere. Va sin recargo: son
    // unos centímetros, y cobrárselos caros haría que A* prefiriera dar la
    // vuelta a la manzana antes que cruzar una costura.
    for (final p in pegados) {
      final a = nodo(p.x, p.y);
      final b = nodo(p.px, p.py);
      final d = math.sqrt((p.px - p.x) * (p.px - p.x) + (p.py - p.y) * (p.py - p.y));
      unir(a, b, d);
    }

    // ── La rejilla de nodos, para enganchar las paradas ────────────────────
    final rejilla = <int, List<int>>{};
    final ladoNodos = math.max(toleranciaUnidades * 8, 64.0);
    for (var n = 0; n < xs.length; n++) {
      final cx = ((xs[n] - origenX) / ladoNodos).floor();
      final cy = ((ys[n] - origenY) / ladoNodos).floor();
      (rejilla[cx * 1048576 + cy] ??= <int>[]).add(n);
    }

    return GrafoDeCalles._(
        xs, ys, vecinos, pesos, rejilla, ladoNodos, origenX, origenY);
  }

  /// El nodo de vía más cercano a un punto, o `null` si no hay ninguno a menos
  /// de [radioUnidades].
  ///
  /// El radio importa: **una parada a medio kilómetro de la calle más cercana no
  /// es una parada mal enganchada, es una parada que el mapa no conoce**, y
  /// engancharla igual dibujaría una raya de medio kilómetro campo a través
  /// hasta la carretera. Mejor que ese tramo salga recto y se vea que es
  /// aproximado.
  int? nodoMasCerca(double px, double py, double radioUnidades) {
    if (_xs.isEmpty) return null;
    final cx0 = ((px - _origenX) / _ladoDeCelda).floor();
    final cy0 = ((py - _origenY) / _ladoDeCelda).floor();
    final anillos = math.max(1, (radioUnidades / _ladoDeCelda).ceil());
    var mejor = -1;
    var mejorD2 = radioUnidades * radioUnidades;
    for (var r = 0; r <= anillos; r++) {
      for (var dcx = -r; dcx <= r; dcx++) {
        for (var dcy = -r; dcy <= r; dcy++) {
          // Sólo el borde del anillo: lo de dentro ya se miró en la vuelta
          // anterior.
          if (r > 0 && dcx.abs() != r && dcy.abs() != r) continue;
          final lista = _rejilla[(cx0 + dcx) * 1048576 + (cy0 + dcy)];
          if (lista == null) continue;
          for (final n in lista) {
            final d2 = (_xs[n] - px) * (_xs[n] - px) + (_ys[n] - py) * (_ys[n] - py);
            if (d2 < mejorD2) {
              mejorD2 = d2;
              mejor = n;
            }
          }
        }
      }
      // Si ya hay uno dentro del anillo cerrado, no hace falta abrir más.
      if (mejor >= 0 && math.sqrt(mejorD2) <= r * _ladoDeCelda) break;
    }
    return mejor < 0 ? null : mejor;
  }

  /// A\* de [desde] a [hasta]. Devuelve los nodos del camino, o `null`.
  ///
  /// La heurística es la distancia en línea recta, que es admisible porque
  /// ningún recargo baja de 1.0 (ver [_recargoPorClase]). [topeDeNodos] es el
  /// freno de mano: un corredor grande puede tener cien mil nodos y explorarlos
  /// todos para descubrir que no hay camino es medio segundo de interfaz
  /// congelada.
  List<int>? camino(int desde, int hasta, {int topeDeNodos = 120000}) {
    if (_xs.isEmpty) return null;
    if (desde == hasta) return [desde];
    final costo = List<double>.filled(_xs.length, double.infinity);
    final deDonde = List<int>.filled(_xs.length, -1);
    final cerrado = List<bool>.filled(_xs.length, false);
    final destinoX = _xs[hasta];
    final destinoY = _ys[hasta];
    double falta(int n) {
      final dx = _xs[n] - destinoX;
      final dy = _ys[n] - destinoY;
      return math.sqrt(dx * dx + dy * dy);
    }

    final cola = _MonticuloMinimo();
    costo[desde] = 0;
    cola.meter(falta(desde), desde);
    var sacados = 0;

    while (!cola.vacio) {
      final n = cola.sacar();
      if (cerrado[n]) continue;
      cerrado[n] = true;
      if (n == hasta) {
        final camino = <int>[];
        var c = hasta;
        while (c != -1) {
          camino.add(c);
          c = deDonde[c];
        }
        return camino.reversed.toList();
      }
      if (++sacados > topeDeNodos) return null;
      final vs = _vecinos[n];
      final ps = _pesos[n];
      for (var i = 0; i < vs.length; i++) {
        final v = vs[i];
        if (cerrado[v]) continue;
        final nuevo = costo[n] + ps[i];
        if (nuevo < costo[v]) {
          costo[v] = nuevo;
          deDonde[v] = n;
          cola.meter(nuevo + falta(v), v);
        }
      }
    }
    return null;
  }
}

/// Un montículo binario del tamaño justo.
///
/// No hay `PriorityQueue` en la biblioteca estándar de Dart y meter `collection`
/// por esto sería traer un paquete para veinte líneas. Admite claves repetidas
/// —un nodo puede entrar varias veces con costes distintos— porque quien lo usa
/// descarta los ya cerrados al sacarlos, que es más barato que buscar y
/// reordenar.
class _MonticuloMinimo {
  final _prioridad = <double>[];
  final _valor = <int>[];

  bool get vacio => _valor.isEmpty;

  void meter(double p, int v) {
    _prioridad.add(p);
    _valor.add(v);
    var i = _valor.length - 1;
    while (i > 0) {
      final padre = (i - 1) >> 1;
      if (_prioridad[padre] <= _prioridad[i]) break;
      _intercambiar(i, padre);
      i = padre;
    }
  }

  int sacar() {
    final cima = _valor.first;
    final ultimo = _valor.length - 1;
    _intercambiar(0, ultimo);
    _prioridad.removeLast();
    _valor.removeLast();
    var i = 0;
    while (true) {
      final izq = 2 * i + 1;
      final der = izq + 1;
      var menor = i;
      if (izq < _valor.length && _prioridad[izq] < _prioridad[menor]) menor = izq;
      if (der < _valor.length && _prioridad[der] < _prioridad[menor]) menor = der;
      if (menor == i) break;
      _intercambiar(i, menor);
      i = menor;
    }
    return cima;
  }

  void _intercambiar(int a, int b) {
    final p = _prioridad[a];
    _prioridad[a] = _prioridad[b];
    _prioridad[b] = p;
    final v = _valor[a];
    _valor[a] = _valor[b];
    _valor[b] = v;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EL ENRUTADOR
// ─────────────────────────────────────────────────────────────────────────────

/// EL RECORRIDO POR CALLES QUE SALE DEL PAQUETE GUARDADO.
///
/// Mismo puerto que `CallesDeOsrm` y mismo patrón que `FondoDelPaquete`: el
/// paquete primero —instantáneo, sin datos, y lo único que hay en el patio de
/// un almacén— y la red detrás, para lo que el paquete no cubra.
class CallesDelPaquete implements RecorridoPorCalles {
  CallesDelPaquete(
    this.paquete, {
    this.respaldo,
    this.presupuesto = const Duration(seconds: 3),
  });

  final PaqueteDeTeselas paquete;

  /// A quién preguntarle cuando el paquete no sabe nada de esta zona. `null`
  /// deja el recorrido **exactamente** como se ve sin señal.
  final RecorridoPorCalles? respaldo;

  /// Lo que puede durar como mucho una llamada entera. Pasado, los tramos que
  /// falten salen rectos.
  ///
  /// Esto existe por una ruta de veinticinco paradas repartidas por media
  /// provincia: cada tramo por separado es rápido, pero veinticinco seguidos en
  /// el hilo de la interfaz son varios segundos de mapa congelado, y el mapa
  /// congelado se lee como «la aplicación se colgó».
  final Duration presupuesto;

  /// Lo ya calculado, por tramo. Se guarda la LÍNEA y no el grafo: dos tramos
  /// de una ruta casi nunca comparten corredor, así que el grafo no se
  /// reaprovecha, pero la línea sí — `croquis_de_ruta.dart` vuelve a pedir el
  /// recorrido cada vez que se abre la ruta.
  final _tramosHechos = <String, List<Punto>?>{};


  /// El tope de teselas por tramo. Es lo que impide que un tramo de dos
  /// provincias intente abrir cuatrocientas: cuando se pasa, **se baja de nivel
  /// de zoom**, que trae menos calles pero las mismas carreteras — que es
  /// justo lo que hace falta para cruzar la isla.
  static const topeDeTeselas = 28;

  /// A cuántos metros de una vía puede estar una parada para engancharla.
  ///
  /// Seiscientos, y el número tiene un porqué medido: un punto de prueba al sur
  /// de La Habana quedaba a **468 m** de la calle más cercana del paquete —está
  /// en medio de un campo— y con el tope en 400 el tramo entero salía recto. Un
  /// domicilio mal geolocalizado por medio kilómetro sigue siendo un domicilio;
  /// lo que hay a más de medio kilómetro de cualquier vía no es una parada que
  /// el mapa conozca, y engancharla dibujaría una raya campo a través.
  static const radioDeEngancheM = 600.0;

  /// La tolerancia de las tres costuras. Ocho metros: más que el error de la
  /// simplificación (menos de un metro a z14) y menos que la distancia entre
  /// dos calles paralelas de La Habana, que es la que no se puede cruzar.
  static const toleranciaDeCosturaM = 8.0;

  @override
  Future<List<Punto>?> entre(List<Punto> puntos) async {
    // NUNCA LANZA: el contrato lo dice y esto corre dentro del repintado del
    // mapa. Un `try` alrededor de todo y ya; lo que salga mal se anota.
    try {
      return await _entre(puntos);
    } on Object catch (e, pila) {
      Registro.fallo('el enrutador del paquete falló; se deja la recta', e, pila);
      return null;
    }
  }

  Future<List<Punto>?> _entre(List<Punto> puntos) async {
    if (puntos.length < 2) return null;
    final reloj = Stopwatch()..start();
    final hecho = await coserLosTramos(
      puntos,
      _tramoPorCalles,
      quedaTiempo: () => reloj.elapsed < presupuesto,
    );
    if (!hecho.algunoPorCalles) {
      // El paquete no sabe nada de esta zona (o no hay camino por ninguna
      // parte). Se le pregunta a la red, que es la que puede saber de un sitio
      // que no está en el mapa bajado. Sin respaldo, `null`: el mapa dibuja la
      // recta y **lo dice**.
      return respaldo?.entre(puntos);
    }
    return hecho.linea;
  }

  /// UN TRAMO. Devuelve `null` si no hay camino por calles — y ese `null` es
  /// una respuesta buena, no un error.
  Future<List<Punto>?> _tramoPorCalles(Punto a, Punto b) async {
    final clave = '${a.lat.toStringAsFixed(6)},${a.lng.toStringAsFixed(6)};'
        '${b.lat.toStringAsFixed(6)},${b.lng.toStringAsFixed(6)}';
    if (_tramosHechos.containsKey(clave)) return _tramosHechos[clave];
    final linea = await _calcular(a, b);
    // Se guarda también el `null`: que no haya camino entre dos paradas no
    // cambia hasta que cambie el mapa, y volver a intentarlo en cada repintado
    // es pagar el corredor entero para nada.
    if (_tramosHechos.length > 200) _tramosHechos.clear();
    return _tramosHechos[clave] = linea;
  }

  Future<List<Punto>?> _calcular(Punto a, Punto b) async {
    final latMedia = (a.lat + b.lat) / 2;
    final z = _zoomDelTramo(a, b);
    if (z == null) return null;

    final teselas = _teselasDelCorredor(a, b, z);
    if (teselas.isEmpty) return null;

    final cadenas = <CadenaDeVia>[];
    for (final t in teselas) {
      // Cada `await` es un respiro para el hilo de la interfaz. No es un
      // adorno: leer veintiocho teselas del fichero y decodificarlas de un
      // tirón es el rato en el que el mapa no responde al dedo.
      //
      // AQUÍ HUBO UNA CACHÉ DE TESELAS DECODIFICADAS Y SE QUITÓ. La idea era
      // buena sobre el papel —ocho paradas de La Habana son ocho corredores que
      // se solapan casi enteros— pero al medirla no movía nada: la ruta de ocho
      // paradas tardaba 310 ms sin ella y 343 ms con ella. Lo que cuesta no es
      // leer y decodificar la tesela, es armar el grafo, y eso hay que hacerlo
      // igual para cada tramo. Se quita: guardar dos megas de calles en el
      // teléfono de un repartidor a cambio de nada no es una optimización.
      final crudo = await _teselaSegura(z, t.x, t.y);
      if (crudo == null) continue;
      _cadenasDeLaTesela(crudo, t.x, t.y, cadenas);
    }
    if (cadenas.isEmpty) return null;

    final porUnidad = metrosPorUnidad(latMedia, z);
    // LAS TOLERANCIAS NO SON UN NÚMERO DE METROS, SON UN MÚLTIPLO DE LO QUE
    // BORRÓ EL GENERADOR. Ocho metros están bien a z14, donde la simplificación
    // mueve medio metro; a z9 la simplificación mueve **doscientos ochenta**
    // (ocho unidades de tesela), así que ocho metros no cosen nada y el tramo
    // Habana–Camagüey salía `null` con el grafo entero cargado. Medido: con la
    // tolerancia fija, z9 daba 9.629 nodos y ningún camino.
    final delGenerador = _toleranciaDelGenerador(z);
    final grafo = GrafoDeCalles.deCadenas(
      cadenas,
      toleranciaUnidades:
          math.max(toleranciaDeCosturaM / porUnidad, 3 * delGenerador),
    );
    final radio =
        math.max(radioDeEngancheM / porUnidad, 20 * delGenerador);
    final na = grafo.nodoMasCerca(_gxDeLng(a.lng, z), _gyDeLat(a.lat, z), radio);
    final nb = grafo.nodoMasCerca(_gxDeLng(b.lng, z), _gyDeLat(b.lat, z), radio);
    if (na == null || nb == null) return null;

    final camino = grafo.camino(na, nb);
    if (camino == null || camino.length < 2) return null;

    // La línea empieza y acaba **en las paradas**, no en el nodo de vía al que
    // se engancharon: el pin está donde está el cliente, y una línea que muere
    // treinta metros antes se ve como un fallo de dibujo.
    final linea = <Punto>[a];
    for (final n in camino) {
      linea.add(Punto(_latDeGy(grafo.y(n), z), _lngDeGx(grafo.x(n), z)));
    }
    linea.add(b);
    return linea;
  }

  Future<Uint8List?> _teselaSegura(int z, int x, int y) async {
    try {
      return await paquete.tesela(z, x, y);
    } on Object {
      // Una tesela ilegible es UNA tesela, no el paquete. Mismo criterio que
      // `fondo_del_paquete.dart`.
      return null;
    }
  }

  /// A QUÉ ZOOM SE ENRUTA.
  ///
  /// Se empieza por el más detallado que quepa en el paquete —z14 es el primero
  /// que trae calles de servicio y caminos— y **se baja mientras no quepan las
  /// teselas en el tope**. Bajar un nivel cuadruplica el terreno de cada tesela
  /// y quita las clases menores: para cruzar de Matanzas a Villa Clara eso no es
  /// una pérdida, es lo correcto.
  ///
  /// `null` si el paquete no llega ni al zoom más bajo que serviría.
  int? _zoomDelTramo(Punto a, Punto b) {
    var z = math.min(14, paquete.cabecera.zMax);
    while (z >= paquete.cabecera.zMin) {
      if (_cuantasTeselasMasOMenos(a, b, z) <= topeDeTeselas) return z;
      z--;
    }
    return null;
  }

  /// CUÁNTAS TESELAS SERÍAN, **sin enumerarlas**.
  ///
  /// Hace falta separado de [_teselasDelCorredor] por una razón de coste muy
  /// concreta: elegir el zoom es probar seis o siete niveles, y enumerar el
  /// corredor de La Habana a Camagüey a z14 es recorrer **millones** de teselas
  /// para descubrir que son demasiadas. La cuenta de aquí es la banda: lo largo
  /// del tramo en teselas, por lo ancho del margen.
  double _cuantasTeselasMasOMenos(Punto a, Punto b, int z) {
    final ax = _gxDeLng(a.lng, z);
    final ay = _gyDeLat(a.lat, z);
    final bx = _gxDeLng(b.lng, z);
    final by = _gyDeLat(b.lat, z);
    final largoU = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    final margenU = _margenDelCorredor(a, b, z);
    final alto = largoU / unidadesPorTesela + 2 * margenU / unidadesPorTesela + 1;
    final ancho = 2 * margenU / unidadesPorTesela + 1;
    return alto * ancho;
  }

  /// El margen del corredor, en unidades de rejilla.
  ///
  /// Nunca menos de 800 m —una calle de sentido único obliga a dar una vuelta de
  /// manzana— y un quinto del tramo para los rodeos de verdad, los de bordear
  /// una bahía. El tope de arriba es el que impide que esto se vaya de las
  /// manos.
  double _margenDelCorredor(Punto a, Punto b, int z) {
    final porUnidad = metrosPorUnidad((a.lat + b.lat) / 2, z);
    final ax = _gxDeLng(a.lng, z);
    final ay = _gyDeLat(a.lat, z);
    final bx = _gxDeLng(b.lng, z);
    final by = _gyDeLat(b.lat, z);
    final largoM =
        math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) * porUnidad;
    return math.min(math.max(800.0, largoM * 0.2), 12000.0) / porUnidad;
  }

  /// LAS TESELAS DEL CORREDOR: las que toca la banda entre las dos paradas.
  ///
  /// No es el recuadro de las dos paradas. Un tramo de veinte kilómetros en
  /// diagonal tiene un recuadro con cientos de teselas de las que la ruta no
  /// pisa ni la mitad; la banda se queda con las que están a tiro del camino.
  List<({int x, int y})> _teselasDelCorredor(Punto a, Punto b, int z) {
    final ax = _gxDeLng(a.lng, z);
    final ay = _gyDeLat(a.lat, z);
    final bx = _gxDeLng(b.lng, z);
    final by = _gyDeLat(b.lat, z);
    final margen = _margenDelCorredor(a, b, z);

    final n = 1 << z;
    final x0 = ((math.min(ax, bx) - margen) / unidadesPorTesela).floor().clamp(0, n - 1);
    final x1 = ((math.max(ax, bx) + margen) / unidadesPorTesela).floor().clamp(0, n - 1);
    final y0 = ((math.min(ay, by) - margen) / unidadesPorTesela).floor().clamp(0, n - 1);
    final y1 = ((math.max(ay, by) + margen) / unidadesPorTesela).floor().clamp(0, n - 1);

    final salida = <({int x, int y})>[];
    final alcance = margen + unidadesPorTesela * 0.71; // media diagonal
    for (var tx = x0; tx <= x1; tx++) {
      for (var ty = y0; ty <= y1; ty++) {
        final cx = (tx + 0.5) * unidadesPorTesela;
        final cy = (ty + 0.5) * unidadesPorTesela;
        if (_distanciaAlSegmento(cx, cy, ax, ay, bx, by) <= alcance) {
          salida.add((x: tx, y: ty));
        }
        // Un corredor desbocado se corta aquí mismo: quien llama cuenta las
        // teselas para decidir si baja de zoom, y contar cuatro mil para
        // descubrir que son demasiadas cuesta más que la cuenta.
        if (salida.length > topeDeTeselas * 40) return salida;
      }
    }
    return salida;
  }

  /// CUÁNTO MUEVE LA SIMPLIFICACIÓN A ESTE ZOOM, en unidades de tesela.
  ///
  /// Es una copia de `tolerancia(z)` de `herramientas/mapa-cuba/niveles.go`, y
  /// que sea una copia es un riesgo conocido: si allí se afloja y aquí no, las
  /// costuras dejan de cerrar y el enrutado vuelve a las rectas **sin un solo
  /// error**. No se puede leer del fichero —el paquete no lo guarda—, así que lo
  /// que hay es este comentario y la prueba del fichero de verdad, que es la que
  /// se pondría roja.
  static double _toleranciaDelGenerador(int z) {
    if (z <= 8) return 8;
    if (z <= 11) return 4;
    return 1.5;
  }

  static double _distanciaAlSegmento(
      double px, double py, double ax, double ay, double bx, double by) {
    final vx = bx - ax, vy = by - ay;
    final largo2 = vx * vx + vy * vy;
    var t = largo2 == 0 ? 0.0 : ((px - ax) * vx + (py - ay) * vy) / largo2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final dx = ax + vx * t - px;
    final dy = ay + vy * t - py;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _cadenasDeLaTesela(
    Uint8List crudo,
    int tx,
    int ty,
    List<CadenaDeVia> fuera,
  ) {
    for (final capa in leerTeselaVectorial(crudo)) {
      if (capa.nombre != 'carretera') continue;
      final ext = capa.extension.toDouble();
      if (ext <= 0) continue;
      for (final r in capa.rasgos) {
        if (r.forma != FormaVectorial.linea) continue;
        final recargo = _recargoPorClase[r.clase];
        // Una clase que no conocemos no se enruta. Es el mismo criterio que
        // `_comoSePinta`: adivinar mete al camión por donde no pasa.
        if (recargo == null) continue;
        for (final parte in r.partes) {
          recortarALaTesela(parte, ext, tx, ty, recargo, fuera);
        }
      }
    }
  }
}

/// PEGAR LOS TRAMOS EN UNA SOLA LÍNEA, cada uno como se pueda.
///
/// Está fuera de la clase y a la vista de las pruebas **a propósito**: es la
/// regla que dice que un tramo malo no se lleva por delante a los demás, y esa
/// regla tiene que poder comprobarse sin un paquete de mapa de 60 MB al lado.
/// Con ella dentro de la clase, la única forma de probarla era el fichero de
/// verdad, y una prueba que sólo corre en esta máquina no protege nada.
///
/// [porCalles] devuelve la línea de un tramo o `null` si no hay camino.
/// [quedaTiempo] es el presupuesto: cuando dice que no, lo que falta sale recto
/// sin ni siquiera intentarlo.
@visibleForTesting
Future<({List<Punto> linea, bool algunoPorCalles})> coserLosTramos(
  List<Punto> puntos,
  Future<List<Punto>?> Function(Punto a, Punto b) porCalles, {
  required bool Function() quedaTiempo,
}) async {
  final salida = <Punto>[puntos.first];
  var algunoPorCalles = false;
  for (var i = 0; i + 1 < puntos.length; i++) {
    final a = puntos[i];
    final b = puntos[i + 1];
    final tramo = quedaTiempo() ? await porCalles(a, b) : null;
    if (tramo != null && tramo.length > 2) {
      algunoPorCalles = true;
      salida.addAll(tramo.skip(1));
    } else {
      // LA RECTA, **sólo para este tramo**. Devolver `null` aquí dejaría toda
      // la ruta en rectas por un solo tramo malo, que es exactamente el fallo
      // del 21/09 del que sale este fichero: con una parada en un cayo, las
      // otras nueve perdían sus calles.
      salida.add(b);
    }
  }
  return (linea: salida, algunoPorCalles: algunoPorCalles);
}

/// EL RECORTE AL CUADRO DE LA TESELA, que es la costura número uno.
///
/// El generador recorta con un margen alrededor (`teselar.go`: «una carretera
/// cortada exactamente en el borde deja una costura blanca entre dos teselas»),
/// y para dibujar eso está bien. Para enrutar es veneno: la misma calle aparece
/// en las dos teselas, con vértices distintos porque cada una se simplifica por
/// su cuenta, y el grafo se llena de parejas de calles paralelas que no se
/// tocan.
///
/// Aquí se tira el sobrante y **se corta en el borde exacto**. Eso es lo que
/// hace que las dos mitades se puedan coser: el borde de la tesela `x` y el de
/// la `x+1` son el mismo número —un múltiplo de 4096 en la rejilla global— y el
/// punto de cruce sale en el mismo sitio desde los dos lados, con la única
/// diferencia de lo que movió la simplificación, que a z14 es menos de un metro.
@visibleForTesting
void recortarALaTesela(
  List<Offset> parte,
  double ext,
  int tx,
  int ty,
  double recargo,
  List<CadenaDeVia> fuera,
) {
  final puntos = parte;
  if (puntos.length < 2) return;
  // De unidades locales de la tesela a la rejilla global.
  double gx(double px) => (tx + px / ext) * unidadesPorTesela;
  double gy(double py) => (ty + py / ext) * unidadesPorTesela;

  var actual = <double>[];
  void cerrar() {
    if (actual.length >= 4) fuera.add(CadenaDeVia(actual, recargo));
    actual = <double>[];
  }

  for (var i = 0; i + 1 < puntos.length; i++) {
    final p = puntos[i];
    final q = puntos[i + 1];
    final ax = p.dx, ay = p.dy;
    final bx = q.dx, by = q.dy;

    // Liang-Barsky contra el cuadro [0, ext]².
    var t0 = 0.0;
    var t1 = 1.0;
    final dx = bx - ax;
    final dy = by - ay;
    var vale = true;
    for (var lado = 0; lado < 4 && vale; lado++) {
      final (double p_, double q_) = switch (lado) {
        0 => (-dx, ax - 0),
        1 => (dx, ext - ax),
        2 => (-dy, ay - 0),
        _ => (dy, ext - ay),
      };
      if (p_ == 0) {
        if (q_ < 0) vale = false;
      } else {
        final r = q_ / p_;
        if (p_ < 0) {
          if (r > t1) {
            vale = false;
          } else if (r > t0) {
            t0 = r;
          }
        } else {
          if (r < t0) {
            vale = false;
          } else if (r < t1) {
            t1 = r;
          }
        }
      }
    }
    if (!vale || t1 <= t0) {
      cerrar();
      continue;
    }
    // Si el trozo visible no empieza en el vértice, es que veníamos de fuera:
    // se abre cadena nueva en el punto del borde.
    if (t0 > 0 || actual.isEmpty) {
      cerrar();
      actual.add(gx(ax + dx * t0));
      actual.add(gy(ay + dy * t0));
    }
    actual.add(gx(ax + dx * t1));
    actual.add(gy(ay + dy * t1));
    if (t1 < 1) cerrar();
  }
  cerrar();
}
