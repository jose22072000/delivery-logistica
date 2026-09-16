import 'package:flutter_test/flutter_test.dart';
import 'package:reparto/nucleo/sincro/ciclo.dart';
import 'package:reparto/pantallas/panel/datos/textos_del_dia.dart';

/// EL ORDEN DE LAS CUATRO CONDICIONES, QUE ES DONDE ESTUVO EL FALLO.
///
/// El 16/09/2026, en un Galaxy A16 con el wifi puesto y sin salida a internet,
/// la tarjeta del Panel se quedó más de un minuto diciendo «Enviando datos...
/// Subiendo lo que hiciste...» sin subir absolutamente nada, y sin nombrar la
/// conexión ni una vez. Los seis apuntes seguían en la cola.
///
/// La causa era una línea: `enVuelo` se miraba ANTES que la red, así que estando
/// en vuelo nunca se llegaba a comprobar si las peticiones llegaban. Y dura
/// mucho, porque el cliente reintenta con esperas crecientes antes de rendirse:
/// el minuto de mentira era el caso NORMAL, no el raro.
///
/// Palabras de Jose: «tienes q notificar q estas sin conexion ok la aplicacion
/// tiene q informar eso».
void main() {
  group('sin red', () {
    test('MIENTRAS SE INTENTA SUBIR se dice que no hay conexión', () {
      expect(
        queTocaAhora(
          enVuelo: true,
          paso: PasoDelCiclo.subir,
          vaMal: true,
          pendientes: 6,
        ),
        QueToca.sinConexion,
        reason:
            'es el caso del A16: decir «Enviando datos» mientras no sale un '
            'paquete es mentir en el único sitio donde alguien mira para saber '
            'si su trabajo salió del teléfono',
      );
    });

    test('y también mientras se intenta bajar', () {
      expect(
        queTocaAhora(
          enVuelo: true,
          paso: PasoDelCiclo.bajar,
          vaMal: true,
          pendientes: 0,
        ),
        QueToca.sinConexion,
      );
    });

    test('el texto NOMBRA la falta de conexión y lo que pasa con lo hecho', () {
      final titulo = TextosDelDia.titulo(QueToca.sinConexion);
      final explicacion = TextosDelDia.explicacion(QueToca.sinConexion);

      expect(titulo, contains('sin conexión'));
      expect(explicacion.toLowerCase(), contains('no hay conexión'));
      expect(
        explicacion,
        contains('sube solo'),
        reason:
            'quien ve «6 sin subir» lo que quiere saber es si eso se va a '
            'perder',
      );
    });
  });

  group('con red', () {
    test('subiendo de verdad SÍ se dice «enviando»', () {
      expect(
        queTocaAhora(
          enVuelo: true,
          paso: PasoDelCiclo.subir,
          vaMal: false,
          pendientes: 6,
        ),
        QueToca.enviando,
        reason:
            'al empezar todavía no ha fallado nada y entonces «Enviando '
            'datos» SÍ es verdad: lo que no puede es quedarse ahí',
      );
    });

    test('bajando se dice «trayendo»', () {
      expect(
        queTocaAhora(
          enVuelo: true,
          paso: PasoDelCiclo.bajar,
          vaMal: false,
          pendientes: 0,
        ),
        QueToca.trayendo,
      );
    });

    test('parado y con trabajo dentro: hay que enviar', () {
      expect(
        queTocaAhora(enVuelo: false, paso: null, vaMal: false, pendientes: 6),
        QueToca.hayQueEnviar,
      );
    });

    test('parado y sin nada pendiente: lo que toca es traer el día', () {
      expect(
        queTocaAhora(enVuelo: false, paso: null, vaMal: false, pendientes: 0),
        QueToca.alDia,
      );
    });
  });

  group('un intento que se eterniza', () {
    test('pasados 30 s deja de decir «enviando», aunque vaMal sea false', () {
      expect(
        queTocaAhora(
          enVuelo: true,
          paso: PasoDelCiclo.subir,
          // `vaMal` tarda TRES ciclos: al abrir la aplicación sin red el
          // contador empieza en cero, así que durante todo el primer ciclo
          // —unos 55 s de reintentos— no ayuda nada. Ése es el hueco.
          vaMal: false,
          pendientes: 6,
          llevaEnVuelo: pacienciaDelIntento,
        ),
        QueToca.sinConexion,
        reason:
            'es el caso del A16 recién abierto: medio minuto diciendo '
            '«Enviando datos...» sin que salga un paquete',
      );
    });

    test('antes de los 30 s se sigue diciendo «enviando», que es verdad', () {
      expect(
        queTocaAhora(
          enVuelo: true,
          paso: PasoDelCiclo.subir,
          vaMal: false,
          pendientes: 6,
          llevaEnVuelo: const Duration(seconds: 5),
        ),
        QueToca.enviando,
        reason:
            'un envío que acaba de empezar SÍ está enviando: adelantar el '
            'aviso lo convertiría en ruido',
      );
    });
  });
}
