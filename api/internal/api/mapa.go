package api

import (
	"net/http"

	"procovar/reparto-api/internal/config"
	"procovar/reparto-api/internal/httpx"
)

// EL ANUNCIO DEL PAQUETE DE MAPA — el hermano de `/api/version`, y a propósito
// se parece hasta en las comas.
//
// Lo que hay colgado para que la APK y el escritorio dibujen el mapa de Cuba SIN
// CONEXIÓN. Jose, 17/09/2026:
//
//	«que se descargue el mapa en la aplicación de Cuba para que tenga el mapa ya
//	siempre funcional; cuando cargue sólo una vez, para que pueda trabajar»
//	«decir servidor del mapa descargado, algo así como datos de la APK para
//	saber si sacaron cosas nuevas, para mantener eso hecho»
//
// Esas dos frases son las dos mitades: **una sola descarga** y **una forma de
// saber si lo que tengo se quedó viejo**. Esta ruta es la segunda mitad.
//
// TRES COSAS QUE NO HACE, y las tres a propósito:
//
//   - **no sirve el fichero.** El `.pmtiles` lo sirve el servidor de estáticos
//     del VPS; aquí sólo se dice dónde está. Servir 26 MB desde el proceso que
//     atiende el tablero es quedarse sin tablero mientras alguien baja el mapa.
//   - **no habla con OpenStreetMap ni con Geofabrik.** El fichero se genera a
//     mano (`herramientas/mapa-cuba`) y se cuelga a mano. Bajar teselas en
//     bloque de `tile.openstreetmap.org` va contra su política de uso y el
//     castigo es un bloqueo por IP; ya nos pasó con Hostinger el 04/08/2026.
//   - **no toca Postgres.** Los diez aparatos llaman aquí a la vez, la mañana
//     que vuelve la señal, y todo sale de la configuración leída al arrancar.
//
// Y una que sí hace, que es la que separa esto de un enlace en un correo: manda
// el **tamaño** y el **sha256**. El tamaño para que nadie empiece una descarga
// de 26 MB sin saber que son 26 MB; el sha256 porque es lo único que distingue
// «bajado» de «bajado entero» (`CLAUDE.md` §3).

// mapaSalida es el contrato. Tipo declarado y no un `map`, como los demás
// manejadores: un mapa se cambia sin querer al tocar cualquier línea y el
// cliente se entera en el patio de un almacén.
type mapaSalida struct {
	// Niveles es `null` mientras no haya nada colgado, igual que `ultima` en
	// `/api/version`. Entonces el aparato no ofrece descargar nada, que es el
	// estado seguro: inventarse un nivel manda a diez personas a un enlace que
	// no existe.
	Niveles []nivelDeMapaSalida `json:"niveles"`
}

type nivelDeMapaSalida struct {
	Nivel string `json:"nivel"`
	// Version es la del ORIGEN de los datos (el sello del `.osm.pbf`), no la de
	// la api ni la de la aplicación. Es contra ésta contra la que el aparato
	// compara lo que tiene guardado.
	Version string `json:"version"`
	Fecha   string `json:"fecha,omitempty"`
	Bytes   int64  `json:"bytes"`
	SHA256  string `json:"sha256"`
	URL     string `json:"url"`
}

// GET /mapa  (y /api/mapa, que es la ruta del contrato)
//
// SIN SESIÓN, como `/api/version`: el aparato lo consulta al arrancar y no
// siempre hay alguien dentro todavía.
func (s *Servidor) mapa(w http.ResponseWriter, r *http.Request) {
	httpx.JSON(w, r, http.StatusOK, mapaSalida{Niveles: nivelesDe(s.cfg.Mapa)})
}

// nivelesDe traduce la configuración al contrato. Aparte del manejador para
// poder probarla sin levantar un router.
func nivelesDe(m *config.Mapa) []nivelDeMapaSalida {
	if !m.HayAlguno() {
		return nil
	}
	salida := make([]nivelDeMapaSalida, 0, len(m.Paquetes))
	for _, p := range m.Paquetes {
		salida = append(salida, nivelDeMapaSalida{
			Nivel: p.Nivel, Version: p.Version, Fecha: p.Fecha,
			Bytes: p.Bytes, SHA256: p.SHA256, URL: p.URL,
		})
	}
	return salida
}
