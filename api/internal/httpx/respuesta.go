// El formato de respuesta que esperan los clientes.
//
// UN SOLO SITIO ESCRIBE ERRORES. Los mensajes de esta API son visibles —salen en la
// pantalla del logístico, en español, y están inventariados literalmente en
// `docs/contratos-api.md`—, así que no pueden depender de cómo le dé por escribir a cada
// manejador. Si mañana el envoltorio cambia, cambia aquí y en ningún otro sitio.
package httpx

import (
	"encoding/json"
	"net/http"
)

// CuerpoError es el contrato: {"error": "..."} y nada más. La APK y la web leen ese
// campo y lo enseñan tal cual.
type CuerpoError struct {
	Error string `json:"error"`
}

// Mensajes literales del contrato. Van aquí como constantes y no sueltos por los
// manejadores porque son parte de la API: cambiarlos rompe a quien los compara.
const (
	MsgNoAutorizado   = "Unauthorized"          // todas las rutas con sesión
	MsgAdminRequerido = "Admin access required" // /api/branches POST y [id]
	MsgNoEncontrado   = "No encontrado"         // /api/branches/[id], /api/origins/[id]
	MsgNotFound       = "Not found"             // /api/vehicles/[id] — en inglés, y así se queda
	MsgCuerpoNoValido = "Cuerpo de la petición no válido"
	MsgErrorInterno   = "Error interno"
	MsgMetodoNoValido = "Método no permitido"
)

// JSON escribe una respuesta con código y cuerpo.
func JSON(w http.ResponseWriter, r *http.Request, codigo int, cuerpo any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(codigo)
	if cuerpo == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(cuerpo); err != nil {
		// La cabecera ya salió: no se puede corregir el código. Sólo queda dejar
		// constancia, porque desde fuera esto se ve como una respuesta cortada.
		Registro(r).Error("no se pudo escribir la respuesta", "err", err)
	}
}

// Error escribe {"error": mensaje} con el código dado.
func Error(w http.ResponseWriter, r *http.Request, codigo int, mensaje string) {
	JSON(w, r, codigo, CuerpoError{Error: mensaje})
}

// ErrorInterno es el 500. El detalle va al REGISTRO, nunca al cliente: los errores de
// pgx traen la consulta y a veces el dato que falló, y eso no sale de aquí.
func ErrorInterno(w http.ResponseWriter, r *http.Request, err error) {
	Registro(r).Error("error interno", "err", err, "ruta", r.URL.Path, "metodo", r.Method)
	Error(w, r, http.StatusInternalServerError, MsgErrorInterno)
}

// NoAutorizado, el 401 de siempre.
func NoAutorizado(w http.ResponseWriter, r *http.Request) {
	Error(w, r, http.StatusUnauthorized, MsgNoAutorizado)
}

// LeerJSON decodifica el cuerpo en destino. Devuelve false y ya ha respondido si el
// cuerpo no vale.
//
// `DisallowUnknownFields` NO se usa a propósito: los clientes mandan campos de más
// —`_count`, `createdAt` devueltos en un GET anterior— y rechazar la petición entera por
// eso convierte cada añadido del front en un fallo del back.
func LeerJSON(w http.ResponseWriter, r *http.Request, destino any) bool {
	defer r.Body.Close()
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxCuerpo))
	if err := dec.Decode(destino); err != nil {
		Registro(r).Warn("cuerpo no válido", "err", err)
		Error(w, r, http.StatusBadRequest, MsgCuerpoNoValido)
		return false
	}
	return true
}

// Tope del cuerpo. Un JSON de reparto grande (un lote del espejo) cabe de sobra; lo que
// no cabe es el intento de tumbar el proceso a base de memoria.
const maxCuerpo = 8 << 20 // 8 MiB
