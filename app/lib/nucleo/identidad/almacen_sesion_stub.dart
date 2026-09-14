import 'almacen_sesion.dart';

/// Sin sitio donde guardar: se comporta como la web, que tampoco guarda.
AlmacenDeSesion abrirAlmacenDeSesion() => AlmacenEnMemoria();
