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
//
// ## Lo que se añadió el 24/09/2026, probándola desde el navegador
//
// Los cuatro puntos de arriba tapaban `veinte`, y sólo `veinte`. Lo que se
// colaba entero, medido con una sonda sobre esta misma caja:
//
//     texto=«-5»        aplicado=[-5.0]           campo=«-5»
//     texto=«NaN»       aplicado=[NaN]            campo=«NaN»
//     texto=«Infinity»  aplicado=[Infinity]       campo=«Infinity»
//     texto=«1,500»     aplicado=[1.5]            campo=«1,500»
//
// Las tres primeras son topes que no existen: `km máx. = -5` y
// `costo mín. = NaN` no los cumple ningún pedido, así que la lista del paso 4
// del asistente se queda en blanco y **no hay nada en la pantalla que diga por
// qué**. Es el caso 1 del encargo: un resultado creíble y equivocado que
// ninguna pantalla desmiente.
//
// La cuarta es peor y es exactamente lo que este fichero dice arriba que
// impide: quien escribe `1,500` pensando en mil quinientos se queda con el
// campo diciendo `1,500` **y el filtro puesto en 1.5**. La pantalla enseñaba un
// tope y aplicaba otro, igual que con `onSubmitted` puro.
//
// Por eso ahora:
//
//  5. **Un tope no puede ser negativo, ni `NaN`, ni infinito.** Se rechaza y se
//     DICE por qué, debajo del campo. Un rebote mudo es el mismo agujero con
//     otra forma.
//  6. **Lo que se aplica se reescribe en el campo.** Si lo tecleado y lo
//     aplicado no se escriben igual —`1,500` → `1.5`, `+5` → `5`, `1e9` →
//     `1000000000`—, gana lo aplicado, que es lo único que de verdad está
//     filtrando.

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
  ///
  /// **`NaN` e infinito NO son números aquí**, aunque `double.tryParse` los
  /// acepte: `double.tryParse('NaN')` devuelve `NaN`, y un tope `NaN` no lo
  /// cumple ningún pedido —ni siquiera es igual a sí mismo—, así que la lista
  /// se queda vacía sin que nada lo explique. Se tratan como lo que son para
  /// quien está delante: un error de tecleo.
  static double? numeroDe(String texto) {
    final n = double.tryParse(texto.trim().replaceAll(',', '.'));
    return (n == null || !n.isFinite) ? null : n;
  }

  /// POR QUÉ NO VALE ESTE TEXTO, o `null` si vale. El vacío vale: quita el tope.
  ///
  /// Devuelve la frase que se pinta debajo del campo. Un rechazo mudo —el campo
  /// vuelve a lo de antes y ya— deja a quien escribió pensando que el teclado
  /// no va; y un tope negativo, que es el caso normal de equivocarse con el
  /// signo, se merece que se lo digan.
  static String? porQueNoVale(String texto) {
    final limpio = texto.trim();
    if (limpio.isEmpty) return null;
    final n = numeroDe(limpio);
    if (n == null) return noEsUnNumero;
    if (n < 0) return noPuedeSerNegativo;
    return null;
  }

  /// Literales aquí arriba para que la prueba busque lo que se lee en pantalla.
  static const noEsUnNumero = 'Eso no es un número. Escribe sólo cifras.';
  static const noPuedeSerNegativo = 'Un tope no puede ser negativo.';

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

  /// Lo que se le dice a quien escribió algo que no puede ser un tope. `null`
  /// mientras no haya nada que decir, que es lo normal.
  String? _elFallo;

  void _aplicar() {
    final texto = _control.text.trim();
    final fallo = CajaDeNumero.porQueNoVale(texto);

    // Ni un número, o un número que no puede ser un tope —negativo, `NaN`,
    // infinito—. No es «sin tope», es un error de tecleo. Se devuelve el campo
    // a lo que está aplicado en vez de dejar la pantalla diciendo una cosa y el
    // filtro haciendo otra, **y se dice por qué**: un rebote mudo se lee como
    // que el teclado no funciona.
    if (fallo != null) {
      setState(() => _elFallo = fallo);
      _escribir(widget.valor);
      return;
    }

    final numero = CajaDeNumero.numeroDe(texto);
    if (_elFallo != null) setState(() => _elFallo = null);

    // LO QUE SE APLICA SE ESCRIBE. `1,500` se aplica como `1.5` y `1e9` como
    // `1000000000`: si el campo se quedara con lo tecleado, la pantalla diría
    // un tope y el filtro haría otro, que es el fallo que este fichero viene a
    // impedir. Sólo se toca cuando de verdad cambia, para no mover el cursor de
    // quien escribió el número bien.
    //
    // ANTES de mirar si hay que aplicar, no después: `_escribir` deja puesto
    // `_ultimoAplicado`, y llamarlo primero haría que la comparación de abajo
    // saliera siempre igual y `alAplicar` no se llamara nunca.
    final hayQueAplicar = numero != _ultimoAplicado;
    if (texto != CajaDeNumero.comoTexto(numero)) _escribir(numero);

    if (!hayQueAplicar) return;
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
        // EL MOTIVO, DEBAJO DEL CAMPO. Sale sólo cuando se rechazó algo y se va
        // en cuanto se escribe otra cosa: un aviso que está siempre puesto deja
        // de leerse, y entonces tampoco se lee el día que importa.
        errorText: _elFallo,
        errorStyle: Tipos.texto(tamano: 12),
      ),
      // Escribir borra el aviso: quien ya está corrigiendo no necesita que le
      // sigan diciendo lo que hizo mal.
      onChanged: (_) {
        if (_elFallo != null) setState(() => _elFallo = null);
      },
      onSubmitted: (_) => _aplicar(),
    );
    final ancho = widget.ancho;
    return ancho == null ? campo : SizedBox(width: ancho, child: campo);
  }
}
