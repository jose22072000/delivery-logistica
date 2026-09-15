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

// El manejador de `/version` y `/api/version` vive en `version.go`: dejó de ser una línea
// cuando tuvo que decir además cuál es la última versión publicada de la aplicación y de
// dónde se baja.
