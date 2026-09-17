// LEER LA RESPUESTA DE OSRM.
//
// Aqui no se llama a nadie: **no sale ni una peticion de esta maquina**, que es
// regla de la casa. Lo que se prueba es lo unico que se puede romper de verdad
// en esa pieza —interpretar lo que llega—, y hay un fallo concreto que hay que
// vigilar:
//
// > OSRM da las coordenadas como `[lng, lat]`, **al reves** que todo lo demas de
// > esta casa. Cambiarlas de sitio dibuja la ruta en el oceano Indico: se ve
// > raro, pero no lanza ningun error, no aparece en ningun log y la aplicacion
// > sigue «en verde».
//
// Y la otra mitad: **una respuesta vacia no es una respuesta buena**
// (`CLAUDE.md` §3). Un `routes: []` no significa «esta ruta no tiene camino»;
// significa que no se sabe, y entonces se vuelve a la linea recta en vez de
// pintar una linea de dos puntos inventada.

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/pantallas/rutas/datos/mapa_en_vivo.dart';

Map<String, Object?> respuestaCon(List<List<double>> coordenadas) => {
  'routes': [
    {
      'geometry': {'type': 'LineString', 'coordinates': coordenadas},
    },
  ],
};

void main() {
  test('las coordenadas vienen [lng, lat] y se guardan al derecho', () {
    // Una ruta que va de Camagüey a Holguín. Si se leyeran al reves, el primer
    // punto saldria en (-77.91, 21.38), o sea en el oceano Indico.
    final linea = leerLaGeometria(
      respuestaCon([
        [-77.91, 21.38],
        [-76.26, 20.88],
      ]),
    )!;

    expect(linea.first.lat, 21.38);
    expect(linea.first.lng, -77.91);
    expect(linea.last.lat, 20.88);
    expect(linea.last.lng, -76.26);
  });

  test('se conserva el orden, que es por donde va el camion', () {
    final linea = leerLaGeometria(
      respuestaCon([
        [-77.0, 21.0],
        [-77.1, 21.1],
        [-77.2, 21.2],
      ]),
    )!;

    expect([for (final p in linea) p.lng], [-77.0, -77.1, -77.2]);
  });

  group('lo que NO es una respuesta buena', () {
    test('sin rutas se vuelve a la linea recta', () {
      expect(leerLaGeometria(const {'routes': <Object?>[]}), isNull);
      expect(leerLaGeometria(const {}), isNull);
      expect(leerLaGeometria(null), isNull);
    });

    test('una linea de un solo punto no es una linea', () {
      expect(
        leerLaGeometria(
          respuestaCon([
            [-77.0, 21.0],
          ]),
        ),
        isNull,
      );
    });

    test('un par a medias tira la respuesta entera, no media ruta', () {
      // Media ruta dibujada es peor que ninguna: se ve completa y va por otro
      // sitio. Ante la duda, la linea recta, que al menos dice lo que es.
      expect(
        leerLaGeometria(const {
          'routes': [
            {
              'geometry': {
                'coordinates': [
                  [-77.0, 21.0],
                  [-77.1],
                ],
              },
            },
          ],
        }),
        isNull,
      );
    });

    test('una forma que no se reconoce no revienta: devuelve nulo', () {
      expect(leerLaGeometria(const {'routes': 'ninguna'}), isNull);
      expect(
        leerLaGeometria(const {
          'routes': [
            {'geometry': 'sin coordenadas'},
          ],
        }),
        isNull,
      );
    });
  });

  group('los que no traen nada', () {
    test('SinCalles devuelve nulo y no lanza', () async {
      expect(await const SinCalles().tesela(15, 1, 1), isNull);
    });

    test('SinCallesQueSeguir devuelve nulo y no lanza', () async {
      expect(await const SinCallesQueSeguir().entre(const []), isNull);
    });
  });
}
