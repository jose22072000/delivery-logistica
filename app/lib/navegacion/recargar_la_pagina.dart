import 'recargar_la_pagina_stub.dart'
    if (dart.library.js_interop) 'recargar_la_pagina_web.dart'
    as destino;

/// RECARGAR LA PESTAÑA, trayendo el HTML nuevo de verdad.
///
/// Es la mitad web de `aviso_de_version_nueva.dart`: alli lo unico que hace
/// falta para tener la version nueva es **recargar**, porque el paquete lo
/// sirve el servidor y no hay nada instalado. En la APK y en el escritorio esto
/// no existe —no hay pagina que recargar— y por eso el `stub` no hace nada en
/// vez de reventar: si alguien lo llama por error, no pasa nada.
///
/// Va por importacion condicional y no por `kIsWeb` porque `package:web` **no
/// compila** fuera del navegador. El orden de las clausulas es el mismo que en
/// `nucleo/red/eventos.dart`.
Future<void> recargarLaPagina() => destino.recargarLaPagina();
