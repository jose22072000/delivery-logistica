import 'package:dio/dio.dart';
import 'package:reparto/nucleo/identidad/entrada_por_accesos.dart';
import 'package:reparto/nucleo/identidad/navegador.dart';

import 'servidor_falso.dart';

/// La base de la API en las pruebas. **Nunca un dominio de Procovar**: este
/// codigo corre en el ordenador de Jose y una peticion de verdad sale de su
/// casa (`CLAUDE.md` de Procovar).
const baseApiDePrueba = 'https://ejemplo.test/api';

/// Un navegador que apunta a donde se le manda en vez de ir.
///
/// Es lo que convierte «se fue al login unico» en algo que una prueba puede
/// mirar. Con `window.location` escrito dentro del widget haria falta un
/// navegador de verdad para saberlo, o sea que no se sabria.
class NavegadorFalso implements Navegador {
  NavegadorFalso({String direccion = 'https://ejemplo.test/'})
    : direccionAlCargar = Uri.parse(direccion);

  /// Con que direccion se cargo la pagina. De aqui salen el motivo del login
  /// unico (`?sso=`) y a donde iba quien abrio el enlace.
  @override
  final Uri direccionAlCargar;

  final List<String> visitados = <String>[];

  /// A donde se fue la ultima vez, o `null` si no se fue a ninguna parte.
  String? get ultimo => visitados.isEmpty ? null : visitados.last;

  @override
  void irA(String destino) => visitados.add(destino);
}

/// La entrada por Accesos contra un servidor falso, con su navegador falso
/// dentro para poder mirar a donde mando a la persona.
EntradaPorAccesos entradaFalsa(
  NavegadorFalso navegador,
  Future<RespuestaFalsa?> Function(PeticionVista) responder,
) => EntradaPorAccesos(
  api: Dio(BaseOptions(baseUrl: baseApiDePrueba))
    ..httpClientAdapter = ServidorFalso(responder),
  navegador: navegador,
  baseApi: baseApiDePrueba,
);

/// Lo que contesta `GET /api/me` cuando la cookie vale.
Map<String, Object?> respuestaDeApiMe({
  required String token,
  String id = 'u-1',
  String nombre = 'Yasmani',
  String correo = 'yasmani@procovar.cu',
  String rol = 'SUPERVISOR',
  String? sucursal = 'HAB',
}) => <String, Object?>{
  'user': <String, Object?>{
    'id': id,
    'email': correo,
    'name': nombre,
    'role': rol,
    'branchId': sucursal,
  },
  'token': token,
};
