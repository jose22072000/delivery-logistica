import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:reparto/nucleo/base/base.dart';

/// Una `BaseLocal` en memoria, recien creada. El mismo Dart y el mismo SQL que
/// en el aparato: lo unico que cambia es donde vive el fichero.
BaseLocal baseDePrueba() => BaseLocal.con(NativeDatabase.memory());

/// Deja este aparato **ya dado de alta**, sin pasar por `POST /sync/aparato`.
///
/// Sirve para las pruebas que no van de eso: el alta tiene su propio fichero, y
/// arrastrarla a cada prueba de subida taparia lo que esa prueba mira. El
/// identificador lo pone el servidor de verdad; aqui se pone a mano, que es
/// justo lo que el alta habria dejado en la base.
Future<void> aparatoYaDeAlta(
  BaseLocal base, {
  String id = '9f3a0d2e-0000-4000-8000-000000000001',
}) => base
    .into(base.preferencias)
    .insertOnConflictUpdate(
      PreferenciasCompanion.insert(
        clave: ClaveDePreferencia.aparato,
        valor: id,
      ),
    );

/// Deja el aparato **ya configurado**: con la marca de bajada de los pedidos.
///
/// Es exactamente lo que mira el portero para decidir si hay que ensenar
/// «Configurando Reparto» o entrar directo al Panel, y lo que mira
/// `RecuentoDeLoQueHay.vaATraerTodo`: la marca de `orders` y no otra, porque es
/// la que `Bajada.ciclo` usa de cursor.
Future<void> aparatoYaConfigurado(BaseLocal base, {DateTime? cuando}) => base
    .into(base.frescura)
    .insertOnConflictUpdate(
      FrescuraCompanion.insert(
        coleccion: Colecciones.pedidos,
        hasta: const Value('2026-09-15T08:00:00.000Z'),
        bajadaAt: Value(cuando ?? DateTime(2026, 9, 15, 8, 30)),
        completa: const Value(true),
      ),
    );
