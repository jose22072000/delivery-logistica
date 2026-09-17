import 'dart:typed_data';

/// EN LA WEB NO HAY PAQUETE DE MAPA, y no es una carencia: es la regla 1. Quien
/// abre un navegador tiene servidor detras, siempre, asi que guardarse 26 MB de
/// Cuba en el navegador no le ahorra nada a nadie.
///
/// Si algo llama aqui es que se ha colado el aparato de sin-conexion en la web,
/// que es justo lo que Jose ha tenido que pedir que se quite tres veces. Se
/// lanza con ese mensaje para que se lea en la consola y se arregle donde toca,
/// en vez de devolver bytes vacios y dejar un mapa en blanco sin explicacion.
Uint8List descomprimirGzip(Uint8List crudo) => throw UnsupportedError(
  'el paquete de mapa sin conexión es de la APK y del escritorio; en la web no '
  'se abre ninguno',
);
