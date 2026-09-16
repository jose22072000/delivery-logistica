import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/base/base.dart';
import 'package:reparto/nucleo/base/tablas/aparato.dart';
import 'package:reparto/nucleo/cola/apunte.dart';
import 'package:reparto/nucleo/cola/cola_salida.dart';

import '../../apoyo/base_de_prueba.dart';

/// LAS DOS DECISIONES SOBRE UN RECHAZO: descartarlo o reintentarlo.
///
/// El pliego dice que un apunte rechazado «se queda a la vista con su motivo
/// **hasta que una persona decida**», y hasta hoy faltaba justo eso: la
/// decisión. No había forma de quitarlos ni de volver a intentarlos, así que se
/// quedaban en la pantalla para siempre. Jose, 16/09/2026: «no puedo borrar esas
/// notificaciones».
///
/// Con diez repartidores y varios turnos por aparato, una bandeja que sólo crece
/// deja de leerse a la tercera semana — y entonces el rechazo que SÍ importaba
/// se pierde entre los viejos.
void main() {
  late BaseLocal base;
  late ColaDeSalida cola;

  setUp(() {
    base = baseDePrueba();
    cola = ColaDeSalida(base);
  });

  tearDown(() => base.close());

  Future<String> unRechazado() async {
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns',
      cuerpo: const <String, Object?>{'nombre': 'Vista'},
    );
    await cola.resolver(
      clave,
      const ResultadoApunte(
        estado: EstadoResultado.rechazado,
        motivo: 'El servidor dijo que no',
      ),
    );
    return clave;
  }

  test('descartar lo quita de en medio', () async {
    final clave = await unRechazado();
    expect((await cola.porClave(clave))?.estado, EstadoApunte.rechazado);

    await cola.descartar(clave);

    expect(
      await cola.porClave(clave),
      isNull,
      reason: 'descartar es la decisión de «esto ya no aplica»',
    );
  });

  test('reintentar lo devuelve a la cola, limpio', () async {
    final clave = await unRechazado();

    await cola.reintentar(clave);

    final vuelto = await cola.porClave(clave);
    expect(vuelto?.estado, EstadoApunte.pendiente);
    expect(
      vuelto?.motivo,
      isNull,
      reason: 'el motivo viejo no puede quedarse pegado: ya no es cierto',
    );
    expect(
      vuelto?.intentos,
      0,
      reason: 'vuelve a empezar: si no, se rendiría antes de tiempo',
    );
    // Y sale en el próximo envío, que es de lo que se trata.
    expect((await cola.lote()).map((a) => a.clave), contains(clave));
  });

  test('ninguna de las dos toca lo que NO está rechazado', () async {
    // Un apunte pendiente no se descarta ni se «reintenta» por error: sería
    // tirar trabajo que todavía iba a subir solo.
    final clave = await cola.encolar(
      metodo: 'POST',
      ruta: '/board/columns',
      cuerpo: const <String, Object?>{'nombre': 'Otra'},
    );

    await cola.descartar(clave);
    expect(
      await cola.porClave(clave),
      isNotNull,
      reason: 'descartar sólo vale sobre un rechazado',
    );

    await cola.reintentar(clave);
    expect((await cola.porClave(clave))?.estado, EstadoApunte.pendiente);
  });
}
