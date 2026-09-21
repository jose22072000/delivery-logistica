package store

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"

	"procovar/reparto-sync/db"
)

// VersionDeLaBase devuelve la migración más alta aplicada, leyendo la tabla de goose.
//
// `is_applied` importa: goose apunta también las vueltas atrás, con `is_applied = false`.
// Contar esas filas daría por aplicada una migración que se deshizo.
//
// Si la tabla no existe, la base no se ha migrado NUNCA. Eso es 0, no un error: el mensaje
// que tiene que leer una persona es «faltan estas seis», no «relation does not exist».
func (b *Base) VersionDeLaBase(ctx context.Context) (int64, error) {
	var version int64
	err := b.pool.QueryRow(ctx,
		`SELECT COALESCE(MAX(version_id), 0) FROM goose_db_version WHERE is_applied`,
	).Scan(&version)
	if err != nil {
		if esTablaQueNoExiste(err) {
			return 0, nil
		}
		return 0, fmt.Errorf("no se pudo leer la versión de la base: %w", err)
	}
	return version, nil
}

// esTablaQueNoExiste: 42P01 es `undefined_table` en Postgres. Se compara el código y no el
// texto del mensaje, que cambia con el idioma del servidor.
func esTablaQueNoExiste(err error) bool {
	var pgErr interface{ SQLState() string }
	if errors.As(err, &pgErr) {
		return pgErr.SQLState() == "42P01"
	}
	return errors.Is(err, pgx.ErrNoRows)
}

// ExigirMigraciones para el arranque en seco si la base del sincronizador está atrasada.
//
// Ver `db/migraciones.go`. Aquí el daño es el de siempre pero sin testigos: el
// sincronizador es lo único que tienen los aparatos sin señal para ponerse al día, y una
// tabla que falta se ve como apuntes que no suben, no como un error.
func (b *Base) ExigirMigraciones(ctx context.Context) error {
	esperadas, err := db.Esperadas()
	if err != nil {
		return err
	}
	enLaBase, err := b.VersionDeLaBase(ctx)
	if err != nil {
		return err
	}
	faltan := db.Faltan(esperadas, enLaBase)
	if len(faltan) == 0 {
		return nil
	}
	nombres := make([]string, 0, len(faltan))
	for _, m := range faltan {
		nombres = append(nombres, m.Nombre)
	}
	// El mensaje lo lee quien está desplegando, a las siete de la mañana y con prisa: dice
	// qué falta, qué pasa si arranca así y dónde está escrito el paso.
	return fmt.Errorf(
		"la base está ATRASADA: le faltan %d migración(es) que este código da por aplicadas:\n"+
			"  %s\n"+
			"la base va por la %d.\n\n"+
			"Arrancar así deja el sincronizador contestando errores que nadie mira: los aparatos\n"+
			"no suben lo que hicieron sin señal y no hay ninguna pantalla que lo diga.\n"+
			"Aplica las migraciones ANTES de desplegar el sincronizador — el paso está en docs/despliegue.md.",
		len(faltan), strings.Join(nombres, "\n  "), enLaBase,
	)
}
