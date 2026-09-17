import 'eventos_stub.dart'
    if (dart.library.js_interop) 'eventos_web.dart'
    as destino;

/// LO QUE CAMBIO EN EL SERVIDOR, en cuanto cambia.
///
/// ## Por que existe
///
/// Hasta hoy, lo que hacia una persona no aparecia en la pantalla de otra hasta
/// que pasaba el temporizador: **dos minutos en la web, cinco en la APK**. Con
/// dos personas trabajando el mismo tablero —una armando zonas en el telefono y
/// otra mirandolas desde el navegador— eso no es trabajar juntos, es trabajar
/// por turnos sin saberlo.
///
/// Jose, 16/09/2026: «hice un tablero en el movil, movi cosas, y en la web no
/// salio en tiempo real, ¿por que razon si eso debe pasar?».
///
/// El canal ya existia en el servidor (`GET /api/eventos`, SSE) desde el
/// principio. Lo que no habia era **nadie escuchandolo**: ni la web ni la APK.
/// Medio protocolo, otra vez.
///
/// ## Que NO hace
///
/// **No trae datos.** El aviso dice «los pedidos cambiaron», no cuales. Quien lo
/// recibe vuelve a pedir su lista, y esa si va acotada a su sucursal — si el
/// aviso llevara las filas dentro, habria que acotarlas aqui y seria un segundo
/// sitio donde equivocarse con el alcance.
///
/// **No sustituye al temporizador.** Es una mejora, no un cimiento: si el canal
/// se cae —un proxy que corta, una red que se va— el reloj sigue ahi y el trabajo
/// llega igual, sólo que mas tarde. Por eso esto nunca lanza: un aviso que no
/// llega no puede dejar a nadie sin sincronizar.
typedef EscuchaDeEventos = Stream<String> Function(String urlBase);

/// Abre el canal y devuelve el TIPO de cada cambio: `pedidos`, `rutas`,
/// `tablero`, `catalogo`, `clientes`.
///
/// El `listo` del principio y los latidos no salen por aqui: son del transporte y
/// no le dicen nada a una pantalla.
///
/// En los destinos donde todavia no hay implementacion devuelve un stream vacio,
/// y entonces manda el temporizador, que es exactamente lo de antes.
Stream<String> escucharEventos(String urlBase) => destino.escucharEventos(urlBase);

/// `true` donde el canal esta implementado. Sirve para poder DECIRLO —y para que
/// una prueba no compruebe algo que en ese destino no existe—.
bool get hayCanalDeEventos => destino.hayCanalDeEventos;
