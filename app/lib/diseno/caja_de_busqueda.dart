// La caja de buscar de TODAS las listas. Una sola, y por eso está aquí.
//
// Antes cada pantalla se lo montaba por su cuenta y cada una salía distinta:
// el Tablero sólo buscaba al pulsar Intro, Clientes tenía su propio
// temporizador copiado a mano, Vehículos consultaba en cada letra y el
// asistente tenía el suyo. Así es como se llega a «en una pantalla hay que dar
// Intro y en otra no», que es justo lo que Jose contó el 22/09/2026:
//
//     «tengo q dar enter para q el filtro funcione»
//
// Lo que hace esta caja, y las tres cosas cuestan trabajo:
//
// 1. **Busca sola a los 400 ms de dejar de teclear.** Ni hay que pulsar nada ni
//    se consulta en cada pulsación: filtrar 8.348 clientes o 274 pedidos seis
//    veces por palabra se nota en el teléfono de allá. Los 400 ms son los del
//    pliego (`pantallas.md` §2 y §4), los mismos que la de Next.
// 2. **Intro busca YA**, para quien ya tiene el hábito — y **no dispara una
//    segunda búsqueda encima de la que ya salió**: si el texto es el mismo que
//    la última que se mandó, no se manda nada.
// 3. **LO QUE SE ESCRIBE NO SE PIERDE NUNCA.** Esto es lo que de verdad hacía
//    daño y va explicado entero en `didUpdateWidget`.
//
// El texto NO es estado de este widget: manda [valor]. Pero mandar no es
// pisar — ver abajo.

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
  /// `Limpiar`, un enlace con `?q=` — la caja se pone al día.
  final String valor;

  final ValueChanged<String> alBuscar;
  final String pista;

  /// `null` = tan ancha como la deje su padre. Es lo que quiere una caja que
  /// ocupa el ancho de una columna, como la del Tablero.
  final double? ancho;

  final Duration espera;

  @override
  State<CajaDeBusqueda> createState() => _CajaDeBusquedaState();
}

class _CajaDeBusquedaState extends State<CajaDeBusqueda> {
  late final TextEditingController _control = TextEditingController(
    text: widget.valor,
  );
  Timer? _cuentaAtras;

  /// Lo último que esta caja MANDÓ hacia fuera y que todavía no ha visto
  /// volver por [CajaDeBusqueda.valor]. Es la lista de ecos pendientes.
  final _mandados = <String>[];

  /// El texto de la última búsqueda que salió de aquí. Sirve para que Intro no
  /// repita la que ya se hizo.
  late String _ultimaBusqueda = widget.valor;

  /// POR QUÉ SE PIERDEN LETRAS AL ESCRIBIR RÁPIDO, y era esto.
  ///
  /// Se tecleó `CHAPLIN` en el buscador del asistente y el campo se quedó en
  /// `CH`, filtrando por `CH` (23 resultados). No se perdía ninguna pulsación:
  /// lo que pasaba es que **el estado del filtro reescribía el campo por
  /// detrás**.
  ///
  /// La secuencia, con la caja vieja:
  ///
  ///  1. se teclea `CH`, pasan los 400 ms y sale `alBuscar('CH')`;
  ///  2. mientras el filtro se aplica se sigue tecleando `APLIN`, así que el
  ///     campo ya dice `CHAPLIN`;
  ///  3. llega el repintado con `valor == 'CH'` —el eco de la búsqueda del
  ///     paso 1, que es lo último que el filtro sabe—;
  ///  4. la caja vieja veía `valor != _control.text` y **escribía `CH` encima
  ///     de `CHAPLIN`**, cancelando además el temporizador pendiente.
  ///
  /// Cinco letras borradas sin que nadie tocara nada, y el filtro congelado en
  /// un trozo de palabra. Encima `_control.text = …` deja la selección en -1,
  /// así que el cursor también saltaba al principio.
  ///
  /// La regla que lo arregla: **el campo es de la persona; desde fuera sólo se
  /// pisa lo que la persona no está escribiendo.** En orden:
  @override
  void didUpdateWidget(CajaDeBusqueda anterior) {
    super.didUpdateWidget(anterior);

    // 1. ¿Es nuestro propio eco? Entonces el campo ya va por delante y no se
    //    toca. Se consume ese eco y los que quedaran atrás.
    final eco = _mandados.indexOf(widget.valor);
    if (eco >= 0) {
      _mandados.removeRange(0, eco + 1);
      return;
    }

    // 2. Ya dicen lo mismo.
    if (widget.valor == _control.text) return;

    // 3. El de fuera CAMBIÓ: `Limpiar`, `Quitar filtros`, un enlace con otro
    //    `?q=`, cambiar de sucursal. Eso lo ha pedido una persona y gana sobre
    //    lo que hubiera pendiente.
    // 4. Y si NO cambió pero el campo dice otra cosa: si hay una tecla en el
    //    aire es que se está escribiendo por delante del filtro y no se toca
    //    —el temporizador lo va a poner de acuerdo él solo—. Si no la hay, el
    //    campo se quedó descolgado y se pone al día: es el caso que hacía que
    //    `Quitar filtros` dejara la caja con texto encima de una lista sin
    //    filtrar.
    if (anterior.valor == widget.valor && (_cuentaAtras?.isActive ?? false)) {
      return;
    }

    _cuentaAtras?.cancel();
    _mandados.clear();
    _ultimaBusqueda = widget.valor;
    // Y el cursor al FINAL, no en -1, que es donde lo deja `_control.text = …`.
    _control.value = TextEditingValue(
      text: widget.valor,
      selection: TextSelection.collapsed(offset: widget.valor.length),
    );
  }

  @override
  void dispose() {
    _cuentaAtras?.cancel();
    _control.dispose();
    super.dispose();
  }

  /// Cada letra sólo REARMA el respiro. Filtrar aquí serían seis repintados de
  /// la lista entera por palabra.
  void _teclearon(String texto) {
    _cuentaAtras?.cancel();
    _cuentaAtras = Timer(widget.espera, () {
      if (mounted) _mandar(texto);
    });
  }

  /// Intro busca YA. La espera es para quien escribe seguido, no un castigo
  /// para quien ya sabe lo que quiere.
  void _ahora(String texto) => _mandar(texto);

  void _mandar(String texto) {
    _cuentaAtras?.cancel();
    // Intro DESPUÉS de que el respiro ya haya buscado no vuelve a buscar: sería
    // una segunda consulta encima de la que ya está pintada.
    if (texto == _ultimaBusqueda) return;
    _ultimaBusqueda = texto;
    _mandados.add(texto);
    widget.alBuscar(texto);
  }

  @override
  Widget build(BuildContext context) {
    final campo = TextField(
      controller: _control,
      style: Tipos.texto(tamano: 14),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.pista,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
      ),
      onChanged: _teclearon,
      onSubmitted: _ahora,
    );
    final ancho = widget.ancho;
    return ancho == null ? campo : SizedBox(width: ancho, child: campo);
  }
}
