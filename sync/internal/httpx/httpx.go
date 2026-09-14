// Package httpx es la forma de contestar, y sobre todo la forma de contestar MAL.
//
// El formato del error es el de `delivery` y el de `reparto-api`: `{"error": "..."}` con el
// texto en español y entero. No es un código que traducir en el cliente — es la frase que
// va a leer la persona que tiene el teléfono en la mano, y por eso se conserva literal
// (ver `docs/contratos-api.md`).
package httpx

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"
)

// Tope del cuerpo de una petición. La subida manda la cola entera de un día, así que no
// puede ser pequeño; pero sin tope, un cuerpo inventado se come la memoria del servicio.
const TopeCuerpo = 32 << 20 // 32 MiB

type sobreError struct {
	Error string `json:"error"`
}

// Fallo contesta con el formato de la casa.
func Fallo(w http.ResponseWriter, estado int, motivo string) {
	JSON(w, estado, sobreError{Error: motivo})
}

// JSON escribe la respuesta. Si el codificado falla a media escritura ya no se puede
// cambiar el código de estado —la cabecera salió—, así que sólo queda dejar constancia.
func JSON(w http.ResponseWriter, estado int, cuerpo any) {
	datos, err := json.Marshal(cuerpo)
	if err != nil {
		slog.Error("no se pudo codificar la respuesta", "err", err)
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"No se pudo componer la respuesta"}`))
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(estado)
	_, _ = w.Write(datos)
}

// Leer descodifica el cuerpo y, si no se puede, YA contesta el 400. Devuelve false para
// que quien llama sólo tenga que volverse.
//
// Sin `DisallowUnknownFields` a propósito: la APK de un logístico que no actualizó puede
// mandar un campo de más, y tirarle la subida entera del día por eso sería perder trabajo
// por una diferencia de versión.
func Leer(w http.ResponseWriter, r *http.Request, destino any) bool {
	defer r.Body.Close()
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, TopeCuerpo))
	if err := dec.Decode(destino); err != nil {
		var grande *http.MaxBytesError
		if errors.As(err, &grande) {
			Fallo(w, http.StatusRequestEntityTooLarge, "El envío es demasiado grande. Sube la cola por tandas.")
			return false
		}
		Fallo(w, http.StatusBadRequest, "El cuerpo de la petición no es JSON válido")
		return false
	}
	return true
}

// Recuperar evita que un fallo en un apunte tire el servicio entero. Un pánico aquí deja
// sin sincronizar a las diez sucursales, no sólo a la que lo provocó.
func Recuperar(log *slog.Logger, siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if p := recover(); p != nil {
				log.Error("pánico atendiendo la petición", "ruta", r.URL.Path, "panico", p)
				Fallo(w, http.StatusInternalServerError, "Error interno")
			}
		}()
		siguiente.ServeHTTP(w, r)
	})
}

// Registro deja una línea por petición. En este servicio el registro no es un adorno: es
// de donde sale «Palma subió a las 19:40 y se cortó a mitad».
func Registro(log *slog.Logger, siguiente http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		inicio := time.Now()
		espia := &espiaEstado{ResponseWriter: w, estado: http.StatusOK}
		siguiente.ServeHTTP(espia, r)
		log.Info("petición",
			"metodo", r.Method,
			"ruta", r.URL.Path,
			"estado", espia.estado,
			"ms", time.Since(inicio).Milliseconds())
	})
}

type espiaEstado struct {
	http.ResponseWriter
	estado int
}

func (e *espiaEstado) WriteHeader(estado int) {
	e.estado = estado
	e.ResponseWriter.WriteHeader(estado)
}
