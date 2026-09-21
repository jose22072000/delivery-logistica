import '../base/base.dart';
import '../cola/apunte.dart';
import '../cola/cola_salida.dart';
import '../red/cliente_api.dart';
import '../red/fallos.dart';
import '../registro/registro.dart';
import 'identidad_del_aparato.dart';

/// LA COLA DE OTRO. Se intento subir la cola de una persona con el token de la
/// que esta delante.
///
/// Nunca deberia lanzarse, y por eso existe: cada persona tiene su fichero de
/// base (`nucleo/base/conexion/nombre.dart`), asi que con B delante la cola de A
/// ni siquiera esta abierta. Esta es la segunda cerradura, la que sigue valiendo
/// el dia que alguien cambie como se abren las bases.
///
/// Lo que pasa cuando salta: **no se manda nada y la cola no se toca**. Los
/// apuntes de A siguen enteros y suben el dia que entre A, con SU token. Subir
/// con el token de quien esta delante seria el trabajo de una sucursal
/// apareciendo en otra, y eso no se ve en ningun sitio hasta que no cuadra el
/// inventario.
class ColaDeOtraPersona implements Exception {
  const ColaDeOtraPersona({
    required this.duenoDeLaCola,
    required this.quienEsta,
  });

  /// El `sub` de quien hizo los apuntes.
  final String duenoDeLaCola;

  /// El `sub` de quien tiene la sesion abierta ahora mismo.
  final String? quienEsta;

  @override
  String toString() =>
      'ColaDeOtraPersona(la cola es de $duenoDeLaCola y quien esta es '
      '${quienEsta ?? "nadie"}; no se sube nada)';
}

/// `POST /sync/subida` — la cola del aparato, en el orden en que se hizo.
///
/// Un solo trabajador y un solo lote. Veinte apuntes no son veinte peticiones en
/// paralelo, y no por elegancia: veinte peticiones a la vez al recuperar la
/// senal es lo que dispara veinte 401 a la vez, y eso es lo que el candado de
/// renovacion tiene que aguantar (caso I1). Mejor no darselo.
/// LA MARCA DEL UNICO 404 QUE SIGNIFICA «date de alta otra vez».
///
/// La manda `sync/internal/httpx` (`CodigoAparatoNoRegistrado`). Las dos partes
/// tienen que decir lo mismo: lo ata
/// `test/nucleo/sincro/solo_un_404_tira_el_aparato_test.dart`.
const marcaDeAparatoNoRegistrado = 'aparato_no_registrado';

class Subida {
  Subida({
    required ClienteApi cliente,
    required ColaDeSalida cola,
    required IdentidadDelAparato aparato,
    required BaseLocal base,
    required Future<String?> Function() quienEsta,
  }) : _cliente = cliente,
       _cola = cola,
       _aparato = aparato,
       _base = base,
       _quienEsta = quienEsta;

  final ClienteApi _cliente;
  final ColaDeSalida _cola;

  /// La base de donde sale la cola. Se le pregunta de quien es.
  final BaseLocal _base;

  /// El `sub` de quien tiene la sesion abierta. Es lo que se compara con el
  /// dueno de la cola antes de mandar un solo apunte.
  final Future<String?> Function() _quienEsta;

  /// Quien sabe el identificador de esta instalacion y sabe darla de alta.
  final IdentidadDelAparato _aparato;

  /// Sube un lote y aplica los resultados. Devuelve cuantos apuntes **aceptó el
  /// servidor**.
  ///
  /// Aceptados, no resueltos: un rechazado tambien se resuelve —queda en la
  /// bandeja con su motivo— pero **no subio**, y contarlo aqui hace que la
  /// pantalla diga «Subieron 1 apunte» justo encima de «1 rechazado esperando a
  /// que alguien decida». Visto en el navegador el 15/09/2026, y es la clase de
  /// contradiccion que le quita el valor a todo lo demas que diga la pantalla.
  ///
  /// Lo que lance sale tal cual: si es `FalloDeRed`, la cola se queda entera y
  /// se reintenta luego; si es `SesionMuerta`, quien llama manda a la pantalla
  /// de acceso. En ningun caso se borra un apunte por no haber podido subirlo.
  Future<int> ciclo({int maximo = 200}) async {
    final lote = await _cola.lote(maximo: maximo);
    if (lote.isEmpty) return 0;

    // LA GUARDA: esta cola tiene que ser de quien esta delante.
    //
    // Va ANTES del alta del aparato y antes de tocar la red, porque lo que no
    // puede pasar de ninguna manera es que un apunte de A salga firmado con el
    // token de B. Ver [ColaDeOtraPersona].
    await _laColaEsDeQuienEsta();

    // EL ALTA, ANTES DEL PRIMER ENVIO. Si falla, lo que lance sale de aqui tal
    // cual y la cola no se toca: sin aparato registrado el servidor contesta 404
    // y no se sube nada, asi que dar el lote por bueno seria tirar el dia.
    final respuesta = await _mandarLote(await _aparato.asegurar(), lote);

    final crudos = respuesta['resultados'];
    if (crudos is! List) {
      throw const FormatException('la subida no devolvio `resultados`');
    }

    // Se casa por `clave`, NO por posicion. El protocolo dice que vienen en el
    // mismo orden, pero fiarse de eso significa que un servidor que un dia
    // reordene marcaria el apunte equivocado como rechazado, y eso no da ningun
    // error: sólo trabajo perdido en el sitio que no es.
    var resueltos = 0;
    var aceptados = 0;
    for (final crudo in crudos) {
      if (crudo is! Map<String, Object?>) continue;
      final clave = crudo['clave'] as String?;
      if (clave == null) {
        Registro.fallo('resultado de subida sin clave: $crudo');
        continue;
      }
      final resultado = ResultadoApunte.deJson(crudo);
      await _cola.resolver(clave, resultado);
      resueltos++;
      if (resultado.estado != EstadoResultado.rechazado) aceptados++;
    }

    // Los que no vinieron en la respuesta se quedan pendientes y se reintentan.
    final sinRespuesta = lote.length - resueltos;
    if (sinRespuesta > 0) {
      Registro.aviso('$sinRespuesta apuntes subieron sin respuesta; se quedan');
    }
    return aceptados;
  }

  /// Comprueba que la cola que se va a subir es de quien tiene la sesion.
  ///
  /// Una base **sin dueno anotado** pasa: es la de las pruebas y la de un
  /// aparato que viene de antes de que esto existiera, y ahi no hay nada que
  /// comparar. Lo que no pasa es un dueno anotado que no sea el de la sesion.
  /// ## «No sé quién está» NO es «está otro» — 16/09/2026
  ///
  /// Esta guarda impide que la cola de A suba firmada con el token de B. Bien.
  /// Pero comparaba `null` con un `sub` y trataba la diferencia como una prueba
  /// de que hay otra persona delante, y `null` no prueba nada: **es la ausencia
  /// del dato, no un dato distinto.**
  ///
  /// En la web `_quienEsta()` devuelve `null` SIEMPRE, porque alli la sesion es
  /// la cookie del acceso unico y no se guarda ningun token en el aparato. Y
  /// `duenoGuardado()` si devuelve el `sub`, que se anota al entrar. Asi que la
  /// comparacion no cuadraba nunca y esto **lanzaba en cada ciclo**: la web no ha
  /// podido subir ni un apunte desde que existe.
  ///
  /// Lo que encadenaba detras es lo que se veia: la cola se quedaba llena para
  /// siempre, y el tablero se niega a bajar mientras haya cola —con razon, para
  /// no pisar lo que no ha subido—, asi que **la pantalla se congelaba a la hora
  /// en que alguien hizo el primer gesto** y refrescar no hacia nada. Visto el
  /// 16/09/2026: el tablero de la web llevaba hora y media parado y lo que subia
  /// el telefono no aparecia nunca.
  ///
  /// El comentario de `proveedores.dart` decia que «en web el almacen devuelve
  /// null siempre: ahi no hay con que comparar y la guarda deja pasar, que es lo
  /// correcto». Describia lo que tenia que pasar, no lo que pasaba.
  ///
  /// Se bloquea solo con una CONTRADICCION de verdad: se sabe quien esta, y no es
  /// el dueno de la cola. En el movil eso sigue intacto, que es donde hay dos
  /// personas compartiendo un aparato. En un navegador no las hay.
  Future<void> _laColaEsDeQuienEsta() async {
    final deQuienEs = await _base.duenoGuardado();
    if (deQuienEs == null) return;
    final quienEsta = await _quienEsta();
    if (quienEsta == null || quienEsta == deQuienEs) return;
    final fallo = ColaDeOtraPersona(
      duenoDeLaCola: deQuienEs,
      quienEsta: quienEsta,
    );
    Registro.fallo('$fallo');
    throw fallo;
  }

  /// Manda el lote, y si el servidor dice que este aparato **no esta
  /// registrado**, se da de alta otra vez y lo manda UNA sola vez mas.
  ///
  /// Ese 404 es un caso real y no una rareza: al aparato lo borraron del
  /// registro, o se restauro una copia de la base local con un alta que ya no
  /// existe. El servidor lo contesta con 404 y no con 401 justamente para que el
  /// aparato pueda distinguirlo de una sesion caducada y arreglarlo solo
  /// (`sync/internal/sincro/bajada.go`).
  ///
  /// **UNA sola vez**, y no en bucle: si el alta nueva tampoco sirve, lo que
  /// toca es que el fallo suba y se vea, no gastarle la bateria y los datos al
  /// logistico reintentando contra algo que no va a cambiar.
  Future<Map<String, Object?>> _mandarLote(
    String aparato,
    List<Apunte> lote, {
    bool reintentar = true,
  }) async {
    try {
      return await _cliente.mandar<Map<String, Object?>>(
        'POST',
        '/subida',
        <String, Object?>{
          'aparato': aparato,
          // Cuantos quedan DESPUES de este envio. Lo dice el aparato porque la
          // cola vive en el telefono: lo que no ha subido no existe en el
          // servidor, y sin este numero el panel ensenaria a Palma en verde
          // justo el dia que se le corto la subida a la mitad (`subida.go`).
          'pendientes': await _cola.cuantosQuedanTras(lote.length),
          'apuntes': [for (final a in lote) a.aJson(ColaDeSalida.cuerpoDe(a))],
        },
      );
    } on Rechazo catch (e) {
      // UN 404 NO BASTA: HACE FALTA QUE SEA **ESTE** 404.
      //
      // Tirar el identificador es destructivo —el aparato pierde su sitio en el
      // panel y nace uno nuevo—, asi que se hace **sólo** cuando el servidor lo
      // dice con su marca. Un 404 sin marca es de otro: de Traefik durante un
      // redespliegue, de un camino mal escrito, de un proxy por el medio. Esos
      // ni siquiera son JSON nuestro.
      //
      // Lo que pasaba hasta el 21/09/2026, medido en produccion: **12 aparatos
      // para un solo telefono**, once fantasmas, dos dados de alta de madrugada
      // sin nadie delante. Y cada fantasma se queda en el panel en rojo como
      // «lleva dias sin subir», que es justo lo unico que ese panel sirve para
      // ver. Con diez repartidores, inservible en una semana.
      //
      // Se falla CERRADO: sin marca, se relanza. Lo peor que puede pasar
      // entonces es que un aparato de verdad borrado del registro deje de subir
      // y lo diga —y eso una persona lo arregla—; lo otro llenaba la lista de
      // fantasmas en silencio.
      //
      // Es la misma trampa que el servidor ya tiene resuelta en el otro
      // sentido: `sync/internal/reparto/reparto.go` —«UN 404 QUE NO VIENE DEL
      // REPARTO ES NUESTRO, NO UN RECHAZO»—.
      if (!reintentar ||
          e.codigo != 404 ||
          e.marca != marcaDeAparatoNoRegistrado) {
        rethrow;
      }
      Registro.aviso(
        'el aparato ya no esta registrado: se da de alta otra vez',
      );
      await _aparato.olvidar();
      final nuevo = await _aparato.asegurar();
      return _mandarLote(nuevo, lote, reintentar: false);
    }
  }
}
