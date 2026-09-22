// El «no» del armado, en su propio fichero para poder probarlo suelto.
//
// Vive aparte del asistente porque lo que hay que sujetar es una propiedad
// visual —que el texto se vea y quepa—, y llegar hasta aquí por el asistente
// entero obliga a pasar por Drift dentro de un `testWidgets`, que es donde las
// pruebas de este proyecto se cuelgan en vez de fallar (`CLAUDE.md` §5).

import 'package:flutter/material.dart';

import '../../../diseno/colores.dart';
import '../../../diseno/tema.dart';

/// El «no» del armado, pegado encima del botón que lo provocó.
///
/// Ámbar y no rojo: no se ha roto nada, hay algo que corregir. Y con su ✕,
/// porque un aviso que no se puede quitar tapa el pie a 390 px y deja a alguien
/// sin ver el botón (`CLAUDE.md`: la ✕ nunca puede desaparecer).
class AvisoDeRechazo extends StatelessWidget {
  const AvisoDeRechazo({
    super.key,
    required this.mensaje,
    required this.alCerrar,
  });

  final String mensaje;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(Aire.md, Aire.sm, Aire.xs, Aire.sm),
        decoration: BoxDecoration(
          color: Colores.ambarFondo,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colores.ambar),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                mensaje,
                style: Tipos.texto(tamano: 13, color: Colores.tinta),
              ),
            ),
            IconButton(
              onPressed: alCerrar,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: 'Quitar el aviso',
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
