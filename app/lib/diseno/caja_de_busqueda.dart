// La caja de buscar de las listas.
//
// Dos cosas que parecen de adorno y no lo son:
//
// 1. **Busca sola a los 400 ms de dejar de teclear**, como la de Next. Antes
//    habia que pulsar Intro, y quien escribe «arroz» y mira la lista se queda
//    esperando a que cambie sin saber que le falta una tecla.
// 2. **Se vacia cuando se vacian los filtros.** Esto es lo que de verdad hacia
//    dano: `Quitar filtros` ponia `q` a vacio en el estado pero la caja seguia
//    con el texto puesto, asi que la pantalla ensenaba una lista SIN filtrar
//    debajo de una caja que decia estar filtrando. Cualquiera lee eso como
//    «esto es todo lo que hay de arroz».
//
// Por eso el texto no es estado de este widget: manda [valor], y cuando cambia
// desde fuera la caja se pone al dia.

import 'dart:async';

import 'package:flutter/material.dart';

import 'tema.dart';

class CajaDeBusqueda extends StatefulWidget {
  const CajaDeBusqueda({
    required this.valor,
    required this.alBuscar,
    this.pista = 'Buscar',
    this.ancho = 220,
    this.espera = esperaPorDefecto,
    super.key,
  });

  /// Los 400 ms de la de Next (`pantallas.md` §2 y §4). Ni se teclea contra la
  /// base en cada letra ni hay que pulsar nada.
  static const esperaPorDefecto = Duration(milliseconds: 400);

  /// Lo que dice el filtro AHORA. Si cambia desde fuera —`Quitar filtros`,
  /// `Limpiar`— la caja se pone al dia.
  final String valor;

  final ValueChanged<String> alBuscar;
  final String pista;
  final double ancho;
  final Duration espera;

  @override
  State<CajaDeBusqueda> createState() => _CajaDeBusquedaState();
}

class _CajaDeBusquedaState extends State<CajaDeBusqueda> {
  late final TextEditingController _control = TextEditingController(
    text: widget.valor,
  );
  Timer? _cuentaAtras;

  @override
  void didUpdateWidget(CajaDeBusqueda anterior) {
    super.didUpdateWidget(anterior);
    // Sólo cuando el de fuera y el de dentro NO coinciden: si no, cada vez que
    // la busqueda terminara de aplicarse el cursor saltaria al principio a
    // mitad de palabra.
    if (widget.valor != _control.text) {
      // Y se cancela lo que hubiera pendiente: una limpieza tiene que ganarle a
      // una letra que todavia no ha llegado a buscarse.
      _cuentaAtras?.cancel();
      _control.text = widget.valor;
    }
  }

  @override
  void dispose() {
    _cuentaAtras?.cancel();
    _control.dispose();
    super.dispose();
  }

  void _teclearon(String texto) {
    _cuentaAtras?.cancel();
    _cuentaAtras = Timer(widget.espera, () {
      if (mounted) widget.alBuscar(texto);
    });
  }

  /// Intro busca YA. La espera es para quien escribe seguido, no un castigo
  /// para quien ya sabe lo que quiere.
  void _ahora(String texto) {
    _cuentaAtras?.cancel();
    widget.alBuscar(texto);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.ancho,
    child: TextField(
      controller: _control,
      style: Tipos.texto(tamano: 14),
      decoration: InputDecoration(
        hintText: widget.pista,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
      ),
      onChanged: _teclearon,
      onSubmitted: _ahora,
    ),
  );
}
