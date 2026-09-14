import 'package:flutter/material.dart';

import '../nucleo/frescura/reloj_de_datos.dart';
import 'colores.dart';

/// «Aqui no hay nada». Es un DATO: se consulto y salio vacio.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio(this.texto, {this.icono, super.key});

  final String texto;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icono != null) ...[
          Icon(icono, size: 32, color: Colores.gris),
          const SizedBox(height: 8),
        ],
        Text(
          texto,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colores.gris),
        ),
      ],
    ),
  );
}

/// «Esto no se ha descargado». **No es lo mismo que vacio**, y por eso es otro
/// widget y no un parametro: una lista vacia en una coleccion que nunca se bajo
/// es un FALLO que se lee como un dato (caso S7). En ambar, con el texto que
/// dice que se arregla solo.
class PantallaSinDescargar extends StatelessWidget {
  const PantallaSinDescargar({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_download_outlined,
          size: 32,
          color: Colores.ambar,
        ),
        const SizedBox(height: 8),
        Text(
          SinDescargar.textoDeLaPantallaVacia,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colores.ambar),
        ),
      ],
    ),
  );
}

/// El aviso ambar de una franja: se usa arriba de los Informes cuando los
/// numeros salen del aparato y no del servidor.
class AvisoAmbar extends StatelessWidget {
  const AvisoAmbar(
    this.texto, {
    this.icono = Icons.warning_amber_outlined,
    super.key,
  });

  final String texto;
  final IconData icono;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      border: Border.all(color: Colores.ambar.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: Colores.ambar),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colores.ambar),
          ),
        ),
      ],
    ),
  );
}
