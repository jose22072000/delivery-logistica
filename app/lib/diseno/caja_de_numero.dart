// La caja de un TOPE: «km máx.», «costo mín.», «hasta cuántos km del almacén».
//
// Es la hermana de `caja_de_busqueda.dart` y nace del mismo día y de la misma
// queja de Jose, 22/09/2026:
//
//     «tengo q dar enter para q el filtro funcione»
//
// La caja de buscar ya no lo pide. Estas dos sí, y quedarse a medias es peor
// que no arreglar nada: en la misma fila de filtros, escribir en una aplica
// solo y escribir en la de al lado no hace nada, y no hay manera de adivinar
// cuál es cuál.
//
// **Pero un número no se puede filtrar al vuelo como una palabra.** Tecleando
// `12` el respiro de la caja de buscar aplicaría primero `1` —que es un número
// perfectamente válido y deja la lista casi vacía— y luego `12`. Una lista que
// parpadea a un resultado equivocado mientras se escribe no es un filtro que
// ayude.
//
// Lo que hace esta caja, entonces:
//
// 1. **Aplica al salir del campo**, que es cuando el número está entero. Se
//    pasa al filtro de al lado, o se toca la lista, y ya está puesto.
// 2. **Intro sigue aplicando**, para quien tiene el hábito.
// 3. **No aplica dos veces lo mismo**: si el número no cambió, no se consulta.
// 4. **Lo que no es un número no borra el tope y no se queda mintiendo.** Con
//    `onSubmitted` puro, escribir `veinte` dejaba el campo diciendo `veinte` y
//    el filtro puesto en 20: la pantalla enseñaba un tope y aplicaba otro. Aquí
//    el campo vuelve a lo que de verdad está aplicado.
//
// Vacío sí es una respuesta: **quita el tope**.

import 'package:flutter/material.dart';

import 'tema.dart';

class CajaDeNumero extends StatefulWidget {
  const CajaDeNumero({
    required this.valor,
    required this.alAplicar,
    required this.pista,
    this.ancho = 220,
    super.key,
  });

  /// El tope que está puesto AHORA. `null` = ninguno.
  final double? valor;

  /// `null` quita el tope.
  final ValueChanged<double?> alAplicar;

  final String pista;

  /// `null` = tan ancha como la deje su padre.
  final double? ancho;

  /// Cómo se escribe un tope en el campo. `null` es el campo vacío, y un
  /// entero se escribe sin el `.0` que le cuelga `toString()`.
  static String comoTexto(double? valor) {
    if (valor == null) return '';
    return valor == valor.roundToDouble()
        ? valor.round().toString()
        : valor.toString();
  }

  /// El número que hay escrito, o `null` si no hay ninguno.
  ///
  /// La coma vale como separador decimal: en el teclado de allá es la que cae
  /// debajo del pulgar, y `3,5` km es lo que escribe cualquiera.
  static double? numeroDe(String texto) =>
      double.tryParse(texto.trim().replaceAll(',', '.'));

  @override
  State<CajaDeNumero> createState() => _CajaDeNumeroState();
}

class _CajaDeNumeroState extends State<CajaDeNumero> {
  late final TextEditingController _control = TextEditingController(
    text: CajaDeNumero.comoTexto(widget.valor),
  );
  late final FocusNode _foco = FocusNode()..addListener(_alCambiarElFoco);

  /// EL ÚLTIMO TOPE QUE SALIÓ DE AQUÍ, y por qué no vale mirar [valor].
  ///
  /// `valor` es lo que el filtro sabe, y tarda en volver: entre que se aplica y
  /// que el eco llega hay repintados. Intro aplica y **además** suelta el
  /// campo, así que los dos caminos —Intro y salir— llegaban seguidos con
  /// `valor` todavía en lo de antes y se aplicaba dos veces: dos consultas
  /// iguales sobre la lista entera, y la segunda no puede cambiar nada.
  late double? _ultimoAplicado = widget.valor;

  void _alCambiarElFoco() {
    if (!_foco.hasFocus) _aplicar();
  }

  void _aplicar() {
    final texto = _control.text.trim();
    final numero = CajaDeNumero.numeroDe(texto);

    // Ni un número ni el campo vacío: no es «sin tope», es un error de tecleo.
    // Se devuelve el campo a lo que está aplicado en vez de dejar la pantalla
    // diciendo una cosa y el filtro haciendo otra.
    if (numero == null && texto.isNotEmpty) {
      _escribir(widget.valor);
      return;
    }

    if (numero == _ultimoAplicado) return;
    _ultimoAplicado = numero;
    widget.alAplicar(numero);
  }

  void _escribir(double? valor) {
    _ultimoAplicado = valor;
    final texto = CajaDeNumero.comoTexto(valor);
    // El cursor al FINAL, no en -1, que es donde lo deja `_control.text = …`.
    _control.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }

  /// Lo que venga de fuera —`Limpiar`, un enlace con otro tope— gana, **salvo
  /// mientras el campo está en las manos de alguien**. Pisar lo que se está
  /// escribiendo es el fallo que costó la caja de buscar; aquí es más difícil
  /// que pase, porque el eco sólo llega después de soltar el campo, pero la
  /// regla es la misma y no cuesta nada.
  @override
  void didUpdateWidget(CajaDeNumero anterior) {
    super.didUpdateWidget(anterior);
    if (widget.valor == anterior.valor) return;
    if (_foco.hasFocus) return;
    _escribir(widget.valor);
  }

  @override
  void dispose() {
    _foco.removeListener(_alCambiarElFoco);
    _foco.dispose();
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final campo = TextField(
      controller: _control,
      focusNode: _foco,
      style: Tipos.texto(tamano: 14),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: widget.pista,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (_) => _aplicar(),
    );
    final ancho = widget.ancho;
    return ancho == null ? campo : SizedBox(width: ancho, child: campo);
  }
}
