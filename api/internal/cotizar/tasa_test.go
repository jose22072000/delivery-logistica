package cotizar

import (
	"context"
	"errors"
	"testing"
	"time"
)

func tasaDe(codigo string, cup float64) *Tasa {
	return &Tasa{Codigo: codigo, CupPorUsd: cup, Fresca: true, TraidoAt: "2026-09-14T10:00:00Z"}
}

// El TTL de la caché, en tabla. Los dos tiempos son 5 min y 20 s y NO son intercambiables:
// el corto es para el «no hay tasa», que es un estado que alguien está arreglando ahora
// mismo. *Pasó de verdad: la tasa estaba puesta y la pantalla seguía en USD.*
func TestRecuerdoDeTasasTTL(t *testing.T) {
	casos := []struct {
		nombre    string
		primera   *Tasa // lo que Accesos contesta la primera vez
		espera    time.Duration
		segunda   *Tasa // lo que contestaría la segunda vez
		esperaCUP float64
		esperaNil bool
		llamadas  int // cuántas veces se preguntó a Accesos
	}{
		{
			nombre:  "recién traída: no se vuelve a preguntar",
			primera: tasaDe("STG", 400), espera: 1 * time.Minute, segunda: tasaDe("STG", 999),
			esperaCUP: 400, llamadas: 1,
		},
		{
			nombre:  "a los 4 min 59 s sigue valiendo la guardada",
			primera: tasaDe("STG", 400), espera: RecuerdoDeTasa - time.Second, segunda: tasaDe("STG", 999),
			esperaCUP: 400, llamadas: 1,
		},
		{
			nombre:  "pasados los 5 min se vuelve a preguntar",
			primera: tasaDe("STG", 400), espera: RecuerdoDeTasa, segunda: tasaDe("STG", 425),
			esperaCUP: 425, llamadas: 2,
		},
		{
			// El «no hay» TAMBIÉN se recuerda: 200 pedidos del lote no pueden preguntar
			// 200 veces lo mismo.
			nombre:  "el «no hay tasa» se recuerda, pero sólo 19 s",
			primera: nil, espera: RecuerdoSinTasa - time.Second, segunda: tasaDe("GR", 400),
			esperaNil: true, llamadas: 1,
		},
		{
			// A los 20 s se vuelve a preguntar, que es todo el motivo de que haya dos TTL.
			nombre:  "pasados los 20 s el «no hay» se repregunta",
			primera: nil, espera: RecuerdoSinTasa, segunda: tasaDe("GR", 400),
			esperaCUP: 400, llamadas: 2,
		},
		{
			// Y NO al revés: un «no hay» no dura cinco minutos.
			nombre:  "el «no hay» no dura los 5 min de una tasa buena",
			primera: nil, espera: 30 * time.Second, segunda: tasaDe("GR", 387.25),
			esperaCUP: 387.25, llamadas: 2,
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			reloj := time.Date(2026, 9, 14, 10, 0, 0, 0, time.UTC)
			vez := 0
			cache := NuevoRecuerdoDeTasas(func(ctx context.Context, codigo string) (*Tasa, error) {
				vez++
				if vez == 1 {
					return c.primera, nil
				}
				return c.segunda, nil
			}, func() time.Time { return reloj })

			cache.DeSucursal(context.Background(), "STG")
			reloj = reloj.Add(c.espera)
			got := cache.DeSucursal(context.Background(), "STG")

			if c.esperaNil {
				if got != nil {
					t.Fatalf("se esperaba nil, salió %+v", got)
				}
			} else {
				if got == nil {
					t.Fatalf("se esperaba una tasa de %v, salió nil", c.esperaCUP)
				}
				if got.CupPorUsd != c.esperaCUP {
					t.Fatalf("cupPorUsd = %v, se esperaba %v", got.CupPorUsd, c.esperaCUP)
				}
			}
			if vez != c.llamadas {
				t.Fatalf("se preguntó %d veces a Accesos, se esperaban %d", vez, c.llamadas)
			}
		})
	}
}

// Si Accesos LANZA, se devuelve lo último que se supo, aunque esté pasado, y SIN refrescar
// la marca de tiempo. *Una tasa de ayer convierte con un error pequeño; sin ninguna no se
// puede cotizar ni un pedido.*
func TestRecuerdoDeTasasCuandoAccesosFalla(t *testing.T) {
	reloj := time.Date(2026, 9, 14, 10, 0, 0, 0, time.UTC)
	vez := 0
	cache := NuevoRecuerdoDeTasas(func(ctx context.Context, codigo string) (*Tasa, error) {
		vez++
		if vez == 1 {
			return tasaDe("STG", 400), nil
		}
		return nil, errors.New("Accesos no contesta")
	}, func() time.Time { return reloj })

	cache.DeSucursal(context.Background(), "STG")

	// Caducada y con Accesos caído: sale la vieja.
	reloj = reloj.Add(RecuerdoDeTasa + time.Minute)
	got := cache.DeSucursal(context.Background(), "STG")
	if got == nil || got.CupPorUsd != 400 {
		t.Fatalf("se esperaba la tasa vieja (400), salió %+v", got)
	}

	// Y NO se guardó como fresca: el siguiente intento vuelve a salir a Accesos. Si se
	// hubiera refrescado la marca, la de ayer se quedaría cinco minutos disfrazada de hoy.
	got = cache.DeSucursal(context.Background(), "STG")
	if vez != 3 {
		t.Fatalf("se preguntó %d veces; se esperaban 3 (el fallo no refresca la marca)", vez)
	}
	if got == nil || got.CupPorUsd != 400 {
		t.Fatalf("se esperaba seguir con la vieja, salió %+v", got)
	}
}

// NUNCA LA DE OTRA SUCURSAL. Es el error que más daño hace aquí: *convertir un importe de
// Granma con la tasa de La Habana da un número creíble que nadie cuestiona.*
func TestRecuerdoDeTasasNoMezclaSucursales(t *testing.T) {
	porCodigo := map[string]*Tasa{"STG": tasaDe("STG", 400), "GR": nil}
	pedidos := []string{}
	cache := NuevoRecuerdoDeTasas(func(ctx context.Context, codigo string) (*Tasa, error) {
		pedidos = append(pedidos, codigo)
		return porCodigo[codigo], nil
	}, nil)

	if got := cache.DeSucursal(context.Background(), "STG"); got == nil || got.CupPorUsd != 400 {
		t.Fatalf("STG: %+v", got)
	}
	// Granma no tiene: se queda SIN tasa. No hereda la de Santiago.
	if got := cache.DeSucursal(context.Background(), "GR"); got != nil {
		t.Fatalf("GR tendría que quedarse sin tasa, salió %+v", got)
	}
	if len(pedidos) != 2 || pedidos[0] != "STG" || pedidos[1] != "GR" {
		t.Fatalf("se preguntó por %v, se esperaba [STG GR]", pedidos)
	}
}

// La clave es `codigo.trim().toUpperCase()`: " stg " y "STG" son la misma sucursal, y una
// sola entrada de caché. Sin esto, cada forma de escribirlo sería una llamada más.
func TestRecuerdoDeTasasNormalizaElCodigo(t *testing.T) {
	casos := []string{"STG", "stg", " Stg ", "\tSTG\n"}
	vez := 0
	cache := NuevoRecuerdoDeTasas(func(ctx context.Context, codigo string) (*Tasa, error) {
		vez++
		if codigo != "STG" {
			t.Errorf("a Accesos se le pidió %q; tiene que ir normalizado a STG", codigo)
		}
		return tasaDe("STG", 400), nil
	}, nil)

	for _, c := range casos {
		if got := cache.DeSucursal(context.Background(), c); got == nil || got.CupPorUsd != 400 {
			t.Fatalf("%q: %+v", c, got)
		}
	}
	if vez != 1 {
		t.Fatalf("se preguntó %d veces; las cuatro formas son la misma sucursal", vez)
	}
}

func TestRecuerdoDeTasasSinCodigoYSinCliente(t *testing.T) {
	cache := NuevoRecuerdoDeTasas(func(ctx context.Context, codigo string) (*Tasa, error) {
		t.Fatal("no se puede preguntar por una sucursal sin código")
		return nil, nil
	}, nil)
	for _, c := range []string{"", "   ", "\t"} {
		if got := cache.DeSucursal(context.Background(), c); got != nil {
			t.Fatalf("sin código se esperaba nil, salió %+v", got)
		}
	}
	// Sin cliente de Accesos montado tampoco se inventa una tasa.
	if got := NuevoRecuerdoDeTasas(nil, nil).DeSucursal(context.Background(), "STG"); got != nil {
		t.Fatalf("sin cliente se esperaba nil, salió %+v", got)
	}
}
