package api

import (
	"net/http"

	"procovar/reparto-api/internal/httpx"
)

// GET /health
//
// Lo sondea el desplegador. Pregunta POR LA BASE, no sólo por el proceso: un servicio
// vivo que no llega a Postgres está caído a todos los efectos, y si contestara 200 el
// desplegador lo daría por bueno y dejaría de reiniciarlo.
func (s *Servidor) salud_(w http.ResponseWriter, r *http.Request) {
	if err := s.salud(r.Context()); err != nil {
		httpx.Registro(r).Error("la base no contesta", "err", err)
		httpx.JSON(w, r, http.StatusServiceUnavailable, map[string]any{
			"ok":   false,
			"base": "no contesta",
		})
		return
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"ok": true, "base": "ok"})
}

// GET /version  (y /api/version, que es la ruta del contrato)
//
// SIN SESIÓN: la APK la consulta antes de entrar, para saber si tiene que actualizarse.
// Con token no serviría para eso.
//
// Sale de la configuración, que a su vez la recibe incrustada al compilar (-ldflags). No
// se lee un fichero ni se pregunta a nadie: esto lo llama cada aparato al arrancar.
func (s *Servidor) version(w http.ResponseWriter, r *http.Request) {
	var v *string
	if s.cfg.Version != "" {
		val := s.cfg.Version
		v = &val
	}
	httpx.JSON(w, r, http.StatusOK, map[string]any{"version": v})
}
