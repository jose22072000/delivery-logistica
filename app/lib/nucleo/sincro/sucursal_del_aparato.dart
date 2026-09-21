// DE QUE SUCURSAL ES ESTE APARATO.
//
// Ver `ClaveDePreferencia.sucursalDelAparato` para el incidente completo. En una
// linea: quien ve las ocho sucursales no tiene ninguna propia, y sin una el alta
// del aparato contesta 400 y **no sube nada de lo que se hizo sin señal**.
//
// Es del APARATO y no de la persona: sobrevive a cerrar sesion, igual que el id
// del aparato. Un telefono que esta en Camagüey sigue estando en Camagüey
// aunque lo coja otro chofer.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../base/base.dart';
import '../proveedores.dart';
import '../registro/registro.dart';

class SucursalDelAparato extends Notifier<String?> {
  @override
  String? build() => null;

  /// Se llama al entrar, con la base ya abierta.
  Future<void> restaurar() async {
    try {
      state = await ref
          .read(baseProvider)
          .preferencia(ClaveDePreferencia.sucursalDelAparato);
    } on Object catch (e) {
      Registro.aviso('no se pudo recordar la sucursal del aparato: $e');
    }
  }

  Future<void> poner(String sucursalId) async {
    state = sucursalId;
    try {
      await ref
          .read(baseProvider)
          .anotarPreferencia(ClaveDePreferencia.sucursalDelAparato, sucursalId);
    } on Object catch (e) {
      // Si no se pudo escribir, lo peor que pasa es que se vuelva a preguntar.
      Registro.aviso('no se pudo anotar la sucursal del aparato: $e');
    }
  }
}

final sucursalDelAparatoProvider =
    NotifierProvider<SucursalDelAparato, String?>(SucursalDelAparato.new);
