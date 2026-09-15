/// COMO SE LLAMA EL FICHERO DE LA BASE. Uno por persona.
///
/// ## Por que una base por persona y no una sola
///
/// Hasta el 15/09/2026 habia **una sola base por aparato** (`reparto.sqlite`) y
/// al cerrar sesion `borrarTodoLoDelDominio()` borraba el dominio pero dejaba la
/// cola, a proposito. Juntar las dos cosas daba esto:
///
///  1. El logistico A entra, baja lo suyo, trabaja sin senal y le quedan 23
///     apuntes sin subir.
///  2. A cierra sesion: sus datos se borran, **sus 23 apuntes se quedan**.
///  3. Entra B y baja lo suyo.
///  4. Al haber senal, **los 23 apuntes de A suben con el token de B**.
///
/// Eso es el trabajo de una sucursal subiendo como si fuera de otra. Y ademas A
/// tenia que rebajarse sus ocho mil clientes cada vez que alternaban, por la
/// conexion de alla.
///
/// Partiendo por fichero, cada persona tiene **su base y su cola**, cerrar
/// sesion no borra nada —cambia de copia— y quien vuelve encuentra lo suyo.
/// La cola de A no puede viajar con el token de B porque, con B delante, la cola
/// de A ni siquiera esta abierta. Y por si eso un dia dejara de ser verdad, la
/// subida lo comprueba otra vez con el dueno anotado dentro de la propia base
/// (`nucleo/sincro/subida.dart`).
///
/// **Por fichero y no por una columna `dueno` en cada tabla**: una columna hay
/// que acordarse de ponerla en el `WHERE` de cada consulta de las siete
/// pantallas, y el dia que a una se le olvide, los pedidos de A salen en la
/// lista de B sin que nada falle. Un fichero no se puede olvidar en un `WHERE`.
///
/// ## Lo que esto NO arregla, dicho aqui
///
/// Los datos de A **siguen en el disco** despues de que A salga: sus clientes
/// con sus direcciones y sus pedidos del dia. Es un cambio real frente al
/// borrado de antes y hay que decirlo:
///
///  * El borrado de antes tampoco protegia gran cosa: dejaba la cola entera —con
///    los cuerpos de los apuntes, que llevan resultados de entrega y notas— y
///    solo borraba del que se iba, nunca del que no habia vuelto.
///  * A cambio, lo de antes garantizaba perder trabajo sin subir cada vez que
///    dos personas se alternaban, y hacia subir lo de A con el token de B, que
///    es peor que un fichero en un disco.
///  * La mitigacion es el **gesto explicito de olvidar a alguien**
///    (`BaseLocal.olvidar`), que borra su copia entera y **avisa antes si esa
///    persona tiene trabajo sin subir**. No pasa sola al cerrar sesion, porque
///    cerrar sesion es lo que hacen diez veces al dia dos personas que comparten
///    la tablet, y borrarlo ahi es tirar el dia de alguien sin decirselo.
///  * Lo que de verdad lo cerraria es cifrar cada copia con una clave que salga
///    de la contrasena de la persona. No se hace hoy porque la regla de la casa
///    es que **sin conexion no se comprueba ninguna contrasena** —validarla
///    contra una copia guardada en el telefono deja sin efecto dar de baja a
///    alguien (`docs/identidad.md`)— y una clave derivada asi habria que poder
///    comprobarla sin senal. Queda escrito para el dia que se decida.
library;

/// El fichero de la persona [dueno], o el neutro cuando no hay nadie dentro.
///
/// [dueno] es el `sub` del token: el identificador de la fila en la base de
/// auth. No cambia cuando a alguien le cambian el nombre, el correo o la
/// sucursal, que es justo lo que hace falta para que quien vuelve encuentre lo
/// suyo.
String nombreDeLaBase(String? dueno) {
  final limpio = dueno?.trim() ?? '';
  // SIN NADIE DENTRO: antes de entrar no hay datos de nadie que mirar, pero la
  // aplicacion tiene que poder abrir la base igual —el arranque la toca para
  // enterarse de si sirve—. Es un fichero aparte y a proposito: si esto abriera
  // `reparto` —el nombre que se usaba cuando habia una sola base por aparato—,
  // la pantalla de acceso estaria leyendo los datos del ultimo que entro.
  if (limpio.isEmpty) return 'reparto-sin-nadie';
  return 'reparto-${_legible(limpio)}-${_huella(limpio)}';
}

/// El nombre de la base de antes, cuando habia una sola por aparato.
///
/// No se usa ya. Vive aqui con nombre para que el arranque pueda MIRAR si
/// existe y decirlo en el registro: en un aparato que venga de la version vieja
/// ese fichero se queda huerfano, y si llevaba cola sin subir, esa cola no la va
/// a mandar nadie. Es poco probable —la aplicacion no esta en manos de nadie
/// todavia— pero callarselo es la clase de silencio que mas dano hace aqui.
const nombreDeLaBaseDeAntes = 'reparto';

/// La parte que se lee con los ojos. Solo lo que vale en un nombre de fichero en
/// los tres destinos, y corto: quien busca el fichero en un aparato para mirar
/// un problema tiene que poder reconocerlo.
String _legible(String dueno) {
  final buffer = StringBuffer();
  for (final unidad in dueno.codeUnits) {
    final esLetra =
        (unidad >= 0x41 && unidad <= 0x5A) ||
        (unidad >= 0x61 && unidad <= 0x7A);
    final esDigito = unidad >= 0x30 && unidad <= 0x39;
    buffer.writeCharCode(esLetra || esDigito ? unidad : 0x5F);
    if (buffer.length >= 32) break;
  }
  return buffer.toString();
}

/// La huella del `sub` ENTERO, en hexadecimal.
///
/// Va detras de la parte legible porque esa parte se recorta y se le quitan
/// caracteres: dos `sub` distintos pueden acabar igual, y dos personas
/// compartiendo fichero es exactamente lo que este fichero existe para impedir.
/// FNV-1a a mano y no `hashCode`: el de Dart no promete el mismo numero entre
/// versiones de la maquina virtual, y un nombre de fichero que cambia solo es
/// una persona que un dia abre la aplicacion y no encuentra su dia.
String _huella(String dueno) {
  var hash = 0x811c9dc5;
  for (final unidad in dueno.codeUnits) {
    hash ^= unidad & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
    if (unidad > 0xff) {
      hash ^= (unidad >> 8) & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
