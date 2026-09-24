// EL ALMACEN DE ORIGEN SE ELIGE DOS VECES, Y TIENE QUE SALIR EL MISMO.
//
// Aqui ([AlmacenDeReferencia.elegir]) y en el servidor (`ElegirAlmacen`,
// `api/internal/cotizar/almacen.go`), porque «Armar la ruta de esta zona» se
// resuelve en local en la APK y en el servidor cuando se pulsa en la WEB. Si los
// dos no eligen EXACTAMENTE el mismo almacen no falla nada: sale un kilometraje
// en la web y otro en el telefono, los dos creibles, y de esos km sale lo que se
// le cobra al cliente.
//
// Paso, y es lo que se arreglo el 24/09/2026: este lado filtraba `activo` y el
// servidor no, asi que en una sucursal con el almacen principal dado de baja
// —con coordenadas buenas— el mismo boton media desde dos sitios distintos.
// Habia dos pruebas verdes afirmando lo contrario la una de la otra, y ninguna
// las comparaba.
//
// POR QUE UN FICHERO COMPARTIDO Y NO UNA TABLA AQUI (CLAUDE.md §3-bis): una
// tabla escrita aqui solo comprueba que este lado hace lo que esta prueba cree;
// se puede cambiar la regla en los dos sitios de ESTE fichero y salir verde con
// el servidor ya separado. El fichero es el MISMO —`docs/almacen-de-origen.
// casos.json`, no una copia— y lo leen las pruebas de los dos lenguajes: cambiar
// la regla en un solo lado pone en rojo la prueba del otro.
//
// Precedente identico: `test/pantallas/rutas/geo_test.dart` con
// `docs/orden-de-paradas.casos.json`.
//
// Y ESTA PRUEBA NO ES UN `testWidgets` NI ABRE LA BASE a proposito: llama a
// `elegir` con las filas en la mano. Lo que ata a los dos lenguajes es la
// FUNCION, no la consulta; lo de la consulta —el `ORDER BY`, el filtro por
// sucursal, el «todavia no ha bajado»— ya esta en
// `test/pantallas/tablero/las_tres_pantallas_contestan_igual_test.dart`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/almacenes/almacen_de_referencia.dart';
import 'package:reparto/nucleo/base/base.dart';

/// El MISMO fichero que lee `api/internal/cotizar/almacen_casos_compartidos_test.go`,
/// no una copia. Una copia se desincroniza y entonces las dos pruebas salen
/// verdes diciendo cosas distintas, que es justo el fallo que esto cierra.
const rutaDeLosCasos = '../docs/almacen-de-origen.casos.json';

/// Los casos que son EL motivo de que esto exista. Si alguien los quita del
/// fichero, el contrato se queda sin la parte que costo dinero, y eso tambien
/// tiene que ponerse rojo.
const imprescindibles = <String>[
  'EL CASO DE JOSE: el principal dado de baja con coordenadas buenas',
  'el único que hay está de baja',
  'el (0,0) no cuenta, aunque sea el principal',
  'sin principal manda el NOMBRE, no el orden de la lista',
];

void main() {
  final fichero = File(rutaDeLosCasos);

  test('el fichero compartido esta donde dice y trae los casos que importan', () {
    expect(
      fichero.existsSync(),
      isTrue,
      reason:
          'sin ${fichero.path} no hay NADA que ate este lado con el servidor: '
          'los dos vuelven a poder elegir almacenes distintos sin que salte '
          'nada, y de ese almacen sale el kilometraje que se cobra. Si esto '
          'salta dentro de una imagen, es que al Dockerfile le falta '
          '`COPY docs/almacen-de-origen.casos.json '
          '/docs/almacen-de-origen.casos.json` (ver deploy/Dockerfile.app, que '
          'ya lo hace con docs/orden-de-paradas.casos.json).',
    );

    final doc = jsonDecode(fichero.readAsStringSync()) as Map<String, dynamic>;
    final casos = doc['casos'] as List;
    expect(
      casos,
      isNotEmpty,
      reason: 'una prueba sin casos no prueba nada',
    );

    final nombres = [for (final c in casos) (c as Map)['nombre'] as String];
    for (final n in imprescindibles) {
      expect(
        nombres,
        contains(n),
        reason:
            'el caso «$n» ya no esta en ${fichero.path}. Es uno de los que '
            'separaban el servidor del aparato el 24/09/2026: quitarlo deja el '
            'contrato verde y sin vigilar justo por donde se rompio.',
      );
    }
  });

  final doc = jsonDecode(fichero.readAsStringSync()) as Map<String, dynamic>;

  for (final crudo in (doc['casos'] as List)) {
    final caso = crudo as Map<String, dynamic>;
    final nombre = caso['nombre'] as String;
    final nota = caso['nota'] as String;
    final esperado = caso['elegido'] as String?;

    // La lista se le da TAL CUAL viene del fichero, sin ordenar: los casos
    // estan desordenados a proposito, porque el desempate tiene que salir de
    // los datos y no de quien sirvio la lista.
    final almacenes = [
      for (final a in (caso['almacenes'] as List))
        Almacen(
          id: (a as Map)['id'] as String,
          sucursalCodigo: 'HAB',
          nombre: a['nombre'] as String,
          lat: (a['lat'] as num?)?.toDouble(),
          lng: (a['lng'] as num?)?.toDouble(),
          principal: (a['principal'] as bool?) ?? false,
          activo: (a['activo'] as bool?) ?? true,
        ),
    ];

    test('«$nombre»', () {
      final salio = AlmacenDeReferencia.elegir(almacenes);

      if (esperado == null) {
        expect(
          salio?.id,
          isNull,
          reason:
              '«$nombre»: se eligio «${salio?.nombre}» y no tendria que servir '
              'ninguno.\n$nota\n'
              'El servidor contesta 409 «no tiene ningun almacen con '
              'coordenadas» para estos mismos datos, asi que alli sale un '
              'cartel y aqui unos kilometros. Si el cambio es a proposito hay '
              'que cambiar ${fichero.path}, ESTE lado Y '
              'api/internal/cotizar/almacen.go a la vez.',
        );
        return;
      }

      expect(
        salio?.id,
        esperado,
        reason:
            '«$nombre»: se midio desde «${salio?.id ?? 'ninguno'}» y el '
            'servidor mide desde «$esperado».\n$nota\n'
            'Dos origenes son DOS KILOMETRAJES para el mismo boton, los dos '
            'creibles, y de esos km sale el cobro. No falla nada y no lo '
            'ensena ninguna pantalla. Si el cambio es a proposito hay que '
            'cambiar ${fichero.path}, ESTE lado Y '
            'api/internal/cotizar/almacen.go a la vez.',
      );
    });
  }
}
