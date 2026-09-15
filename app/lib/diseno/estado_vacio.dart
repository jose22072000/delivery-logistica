import 'package:flutter/material.dart';

import '../nucleo/frescura/reloj_de_datos.dart';
import 'colores.dart';
import 'tema.dart';

/// «Aqui no hay nada». Es un DATO: se consulto y salio vacio.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio(this.texto, {this.icono, super.key});

  final String texto;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: Aire.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icono != null) ...[
          // El icono en su circulo de papel, como los estados vacios de
          // delivery: un icono suelto sobre blanco se lee como un fallo.
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Colores.grisFondo,
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: 24, color: Colores.tintaSuave),
          ),
          const SizedBox(height: Aire.md),
        ],
        Text(
          texto,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Colores.tintaSuave),
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
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: Aire.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Colores.ambarFondo,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.cloud_download_outlined,
            size: 24,
            color: Colores.ambar,
          ),
        ),
        const SizedBox(height: Aire.md),
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
    padding: const EdgeInsets.symmetric(horizontal: Aire.md, vertical: 10),
    decoration: BoxDecoration(
      color: Colores.ambarFondo,
      border: Border.all(color: Colores.ambar.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(Radios.lg),
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
