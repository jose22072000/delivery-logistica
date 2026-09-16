import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../proveedores.dart';
import '../registro/registro.dart';
import 'base.dart';
import 'conexion/conexion.dart';

/// QUIEN TIENE DATOS EN ESTE APARATO, y cuánto trabajo sin subir le queda.
class PersonaEnElAparato {
  const PersonaEnElAparato({
    required this.sub,
    required this.nombre,
    required this.pendientes,
  });

  /// El `sub` de su token. Es lo que nombra su copia.
  final String sub;

  /// El nombre para PINTAR. Nunca el `sub`: ese es el identificador de la fila
  /// en la base de auth y enseñárselo al logístico es sacar la base a la cara
  /// (ver `identidad/sesion.dart`). Vacío cuando la copia es de antes de que
  /// esto se guardara.
  final String nombre;

  /// Apuntes suyos **sin subir**. Es lo que hay que decir ANTES de olvidarla.
  final int pendientes;

  String get nombreParaVer =>
      nombre.isNotEmpty ? nombre : 'Una cuenta anterior';

  bool get tieneTrabajoSinSubir => pendientes > 0;

  @override
  String toString() =>
      'PersonaEnElAparato($nombreParaVer, pendientes: $pendientes)';
}

/// LAS COPIAS DEL APARATO: listarlas y **olvidar** una.
///
/// ## Por qué olvidar es un gesto aparte
///
/// Cerrar sesión **cambia de copia** y no borra nada, que es lo que hace posible
/// que dos personas se alternen en una tablet sin perder el día y sin que la
/// cola de una suba con el token de la otra
/// (`conexion/nombre.dart`). El precio es que los datos de quien salió siguen en
/// el disco, y eso hay que poder deshacerlo a mano.
///
/// Se hace a mano y no al salir porque **salir es lo que hacen diez veces al
/// día** dos personas que comparten el aparato: borrar ahí es tirar el día de
/// alguien sin decírselo, que es exactamente lo que el proyecto no puede
/// permitirse. Olvidar, en cambio, se pide una vez, se avisa antes si esa
/// persona tiene trabajo sin subir, y entonces sí se borra entero.
class Personas {
  const Personas();

  /// Las copias que hay, con su nombre y su cuenta de pendientes.
  ///
  /// **Sin la de quien está dentro ahora mismo**: esa copia está abierta, y
  /// ofrecerse a borrarla mientras se usa es un gesto que no puede acabar bien.
  /// Para irse está «Cerrar sesión».
  Future<List<PersonaEnElAparato>> listar({String? excepto}) async {
    final salida = <PersonaEnElAparato>[];
    for (final fichero in await copiasEnElAparato()) {
      final persona = await _mirar(fichero);
      if (persona == null) continue;
      if (persona.sub == excepto) continue;
      salida.add(persona);
    }
    salida.sort((a, b) => a.nombreParaVer.compareTo(b.nombreParaVer));
    return salida;
  }

  /// Borra la copia de [sub]: su dominio, **su cola** y su fichero.
  ///
  /// No pregunta nada: quien llama ya preguntó, con [listar] en la mano y con
  /// `tieneTrabajoSinSubir` delante. Esto es el gesto, no la decisión.
  Future<void> olvidar(String sub) async {
    final base = BaseLocal(dueno: sub);
    try {
      final quedaban = await base.cuantosPendientes();
      await base.olvidar();
      if (quedaban > 0) {
        // Queda dicho aunque la persona lo haya aceptado: si mañana alguien
        // pregunta por qué no llegó el cierre de una ruta, esto es lo único que
        // lo explica.
        Registro.aviso(
          'olvidada la copia de $sub con $quedaban apuntes sin subir',
        );
      }
    } finally {
      await base.close();
    }
    await borrarLaCopia(sub);
    Registro.info('copia olvidada: $sub');
  }

  /// Abre una copia sólo para preguntarle quién es y qué le queda.
  Future<PersonaEnElAparato?> _mirar(String fichero) async {
    // El nombre del fichero no dice el `sub` —lleva la parte legible recortada y
    // una huella—, así que se le pregunta a la base, que lo tiene anotado.
    final base = BaseLocal.con(abrirConexionDeFichero(fichero));
    try {
      final sub = await base.duenoGuardado();
      if (sub == null) return null;
      return PersonaEnElAparato(
        sub: sub,
        nombre: await base.nombreDelDueno() ?? '',
        pendientes: await base.cuantosPendientes(),
      );
    } on Object catch (e) {
      Registro.aviso('no se pudo mirar la copia $fichero: $e');
      return null;
    } finally {
      await base.close();
    }
  }
}

final personasProvider = Provider<Personas>((ref) => const Personas());

/// Quién más tiene datos en este aparato. Lo mira quien ofrezca el gesto de
/// olvidar; se recalcula al invalidarlo.
final personasEnElAparatoProvider = FutureProvider<List<PersonaEnElAparato>>(
  // `excepto`: la copia de quien está dentro está abierta, y ofrecerse a
  // borrarla mientras se usa es un gesto que no puede acabar bien. Para irse
  // está «Cerrar sesión».
  (ref) => ref
      .watch(personasProvider)
      .listar(excepto: ref.watch(duenoDeLaBaseProvider)),
);
