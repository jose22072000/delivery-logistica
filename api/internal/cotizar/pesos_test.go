package cotizar

import "testing"

// catalogoFalso responde por nombre exacto. El emparejamiento de verdad (§5) es otro
// asunto; aquí sólo hace falta que el respaldo conteste algo para probar la CASCADA.
type catalogoFalso map[string]Acierto

func (c catalogoFalso) Resolver(nombre, codigo string) Acierto {
	if h, ok := c[nombre]; ok {
		return h
	}
	if h, ok := c[codigo]; ok {
		return h
	}
	return Acierto{}
}

func texto(s string) *string { return &s }

// LA CASCADA DE PRIORIDAD, rama por rama (§2.1). El orden no es un detalle: decide de qué
// dato sale el peso con el que se cobra el domicilio y con el que se carga el camión.
func TestPesosDeRenglonesCascada(t *testing.T) {
	cat := catalogoFalso{
		"Malta 355ml": {WeightKg: 0.4, WhName: texto("MALTA BUCANERO 355 ML")},
		"COD-9":       {WeightKg: 1.25, WhName: texto("REFRESCO COLA 1.5 L")},
		"Pesa cero":   {WeightKg: 0},
	}

	casos := []struct {
		nombre       string
		renglon      Renglon
		catalogo     Catalogo
		weightKg     float64
		unitWeightKg float64
		matched      bool
		whName       *string
		fuente       FuentePeso
	}{
		{
			// RAMA 1. `pesoLineaKg` gana a TODO lo demás, aunque vengan los otros tres.
			nombre: "1) pesoLineaKg de PEDIDO manda sobre todo",
			renglon: Renglon{
				Name: "Malta 355ml", PesoLineaKg: De(12.5), PesoKg: De(0.4),
				Packs: De(24), Quantity: De(24), Weight: De(9),
			},
			catalogo: cat,
			weightKg: 12.5, unitWeightKg: 0.4, matched: true, whName: nil, fuente: PesoDePedido,
		},
		{
			// El unitario es informativo: si no viene, 0. NO se deduce dividiendo.
			nombre:   "1) pesoLineaKg sin unitario deja el unitario en 0",
			renglon:  Renglon{Name: "X", PesoLineaKg: De(7.25), PesoKg: NoVino(), Quantity: NoVino(), Packs: NoVino(), Weight: NoVino()},
			weightKg: 7.25, unitWeightKg: 0, matched: true, fuente: PesoDePedido,
		},
		{
			// Un `pesoLineaKg` de 0 no es un peso: sigue la cascada.
			nombre:   "1) pesoLineaKg cero cae a la rama siguiente",
			renglon:  Renglon{Name: "X", PesoLineaKg: De(0), PesoKg: De(0.5), Packs: De(6), Quantity: NoVino(), Weight: NoVino()},
			weightKg: 3, unitWeightKg: 0.5, matched: true, fuente: PesoDePedido,
		},
		{
			// RAMA 2. `packs` manda sobre `quantity` cuando los dos vienen.
			nombre:   "2) pesoKg × packs (packs manda sobre quantity)",
			renglon:  Renglon{Name: "X", PesoLineaKg: NoVino(), PesoKg: De(0.75), Packs: De(4), Quantity: De(100), Weight: NoVino()},
			weightKg: 3, unitWeightKg: 0.75, matched: true, fuente: PesoDePedido,
		},
		{
			nombre:   "2) pesoKg × quantity cuando no hay packs",
			renglon:  Renglon{Name: "X", PesoLineaKg: NoVino(), PesoKg: De(1.5), Packs: NoVino(), Quantity: De(3), Weight: NoVino()},
			weightKg: 4.5, unitWeightKg: 1.5, matched: true, fuente: PesoDePedido,
		},
		{
			// CASO LÍMITE que el pliego marca en mayúsculas: pesoKg SIN packs ni quantity
			// da 0 y NO se devuelve 0 — SE SIGUE CAYENDO. Un 0 aquí se leería como «este
			// producto no pesa», y el camión se cargaría de más.
			nombre:   "2) pesoKg sin packs ni quantity no vale 0: cae al peso manual",
			renglon:  Renglon{Name: "X", PesoLineaKg: NoVino(), PesoKg: De(0.9), Packs: NoVino(), Quantity: NoVino(), Weight: De(2)},
			weightKg: 2, unitWeightKg: 2, matched: true, fuente: PesoManual,
		},
		{
			// …y si no hay peso manual, sigue cayendo hasta el catálogo.
			nombre:   "2) pesoKg sin cantidad cae hasta el catálogo",
			renglon:  Renglon{Name: "Malta 355ml", PesoLineaKg: NoVino(), PesoKg: De(0.9), Packs: NoVino(), Quantity: NoVino(), Weight: NoVino()},
			catalogo: cat,
			// packs es 0, así que la línea vale 0 pero el producto SÍ se emparejó.
			weightKg: 0, unitWeightKg: 0.4, matched: true, whName: texto("MALTA BUCANERO 355 ML"), fuente: PesoDeCatalogo,
		},
		{
			// RAMA 3. OJO: aquí el respaldo de la cantidad es 1, no 0. Un peso tecleado
			// sin cantidad es «una unidad», no «ninguna».
			nombre:   "3) weight manual × quantity",
			renglon:  Renglon{Name: "X", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: NoVino(), Quantity: De(3), Weight: De(2.5)},
			weightKg: 7.5, unitWeightKg: 2.5, matched: true, fuente: PesoManual,
		},
		{
			nombre:   "3) weight manual sin cantidad cuenta como 1 (no como 0)",
			renglon:  Renglon{Name: "X", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: NoVino(), Quantity: NoVino(), Weight: De(2.5)},
			weightKg: 2.5, unitWeightKg: 2.5, matched: true, fuente: PesoManual,
		},
		{
			// RAMA 4. El catálogo local es el RESPALDO, nunca el primero.
			nombre:   "4) catálogo × packs",
			renglon:  Renglon{Name: "Malta 355ml", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: De(24), Quantity: NoVino(), Weight: NoVino()},
			catalogo: cat,
			// 0.4 × 24 da 9.600000000000001 en coma flotante, y ése es el número que da
			// también JavaScript. NO se redondea aquí: el peso de la línea se suma crudo
			// y el redondeo sólo ocurre al final, sobre el importe.
			weightKg: 9.600000000000001, unitWeightKg: 0.4, matched: true, whName: texto("MALTA BUCANERO 355 ML"), fuente: PesoDeCatalogo,
		},
		{
			// Se busca por `sku || code`: sin sku, se prueba el código.
			nombre:   "4) catálogo por código cuando no hay sku",
			renglon:  Renglon{Name: "Nombre que no está", Code: "COD-9", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: De(2), Quantity: NoVino(), Weight: NoVino()},
			catalogo: cat,
			weightKg: 2.5, unitWeightKg: 1.25, matched: true, whName: texto("REFRESCO COLA 1.5 L"), fuente: PesoDeCatalogo,
		},
		{
			// CASO LÍMITE: packs 0 con acierto de catálogo. La línea vale 0 pero SE MARCA
			// EMPAREJADA. Distinguirlo importa: el informe de «productos sin peso» acusaría
			// al catálogo de un fallo que es del pedido.
			nombre:   "4) catálogo con packs 0: línea 0 pero emparejada",
			renglon:  Renglon{Name: "Malta 355ml", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: De(0), Quantity: De(50), Weight: NoVino()},
			catalogo: cat,
			weightKg: 0, unitWeightKg: 0.4, matched: true, whName: texto("MALTA BUCANERO 355 ML"), fuente: PesoDeCatalogo,
		},
		{
			nombre:   "4) el catálogo contesta con peso 0: no cuenta como acierto",
			renglon:  Renglon{Name: "Pesa cero", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: De(5), Quantity: NoVino(), Weight: NoVino()},
			catalogo: cat,
			weightKg: 0, unitWeightKg: 0, matched: false, fuente: PesoDesconocido,
		},
		{
			// RAMA 5.
			nombre:   "5) sin nada: 0 y sin emparejar",
			renglon:  Renglon{Name: "Desconocido", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: NoVino(), Quantity: NoVino(), Weight: NoVino()},
			catalogo: cat,
			weightKg: 0, unitWeightKg: 0, matched: false, fuente: PesoDesconocido,
		},
		{
			nombre:   "5) sin catálogo montado tampoco se inventa nada",
			renglon:  Renglon{Name: "Malta 355ml", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: De(24), Quantity: NoVino(), Weight: NoVino()},
			catalogo: nil,
			weightKg: 0, unitWeightKg: 0, matched: false, fuente: PesoDesconocido,
		},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			r := PesosDeRenglones([]Renglon{c.renglon}, c.catalogo)
			if len(r.Renglones) != 1 {
				t.Fatalf("se esperaba 1 renglón, salieron %d", len(r.Renglones))
			}
			p := r.Renglones[0]
			if p.WeightKg != c.weightKg {
				t.Errorf("weightKg = %v, se esperaba %v", p.WeightKg, c.weightKg)
			}
			if p.UnitWeightKg != c.unitWeightKg {
				t.Errorf("unitWeightKg = %v, se esperaba %v", p.UnitWeightKg, c.unitWeightKg)
			}
			if p.Matched != c.matched {
				t.Errorf("matched = %v, se esperaba %v", p.Matched, c.matched)
			}
			if p.WeightSource != c.fuente {
				t.Errorf("weightSource = %q, se esperaba %q", p.WeightSource, c.fuente)
			}
			switch {
			case c.whName == nil && p.WhName != nil:
				t.Errorf("whName = %q, se esperaba nil", *p.WhName)
			case c.whName != nil && p.WhName == nil:
				t.Errorf("whName = nil, se esperaba %q", *c.whName)
			case c.whName != nil && *p.WhName != *c.whName:
				t.Errorf("whName = %q, se esperaba %q", *p.WhName, *c.whName)
			}
			// El total tiene que ser justo la línea: sólo aportan las ramas 1 a 4.
			if r.Total != c.weightKg {
				t.Errorf("total = %v, se esperaba %v", r.Total, c.weightKg)
			}
		})
	}
}

func TestPesosDeRenglonesTotal(t *testing.T) {
	casos := []struct {
		nombre    string
		renglones []Renglon
		total     float64
		cuantos   int
	}{
		{
			// CASO LÍMITE: sin líneas, total 0 y lista VACÍA (un `[]`, no nil: va a un JSON).
			nombre: "sin líneas", renglones: nil, total: 0, cuantos: 0,
		},
		{
			nombre: "lista vacía", renglones: []Renglon{}, total: 0, cuantos: 0,
		},
		{
			nombre: "las cuatro ramas en un pedido",
			renglones: []Renglon{
				{Name: "a", PesoLineaKg: De(12.5), PesoKg: NoVino(), Packs: NoVino(), Quantity: NoVino(), Weight: NoVino()},
				{Name: "b", PesoLineaKg: NoVino(), PesoKg: De(0.75), Packs: De(4), Quantity: NoVino(), Weight: NoVino()},
				{Name: "c", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: NoVino(), Quantity: De(3), Weight: De(2)},
				{Name: "d", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: NoVino(), Quantity: NoVino(), Weight: NoVino()},
			},
			total: 21.5, cuantos: 4, // 12.5 + 3 + 6 + 0 (la quinta rama aporta 0)
		},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			r := PesosDeRenglones(c.renglones, nil)
			if r.Total != c.total {
				t.Errorf("total = %v, se esperaba %v", r.Total, c.total)
			}
			if len(r.Renglones) != c.cuantos {
				t.Errorf("%d renglones, se esperaban %d", len(r.Renglones), c.cuantos)
			}
			if r.Renglones == nil {
				t.Error("la lista nunca puede ser nil: va a un JSON y tiene que salir []")
			}
		})
	}
}

// `weightFromItems`: UN TOTAL DE 0 SE CONSIDERA «NO RESUELTO» Y CEDE AL RESPALDO. No es lo
// mismo que un pedido que de verdad no pesa: eso no existe, y un cero dice que en el
// camión cabe todo.
func TestPesoDeRenglones(t *testing.T) {
	conPeso := []Renglon{{Name: "a", PesoLineaKg: De(9.25), PesoKg: NoVino(), Packs: NoVino(), Quantity: NoVino(), Weight: NoVino()}}
	sinPeso := []Renglon{{Name: "a", PesoLineaKg: NoVino(), PesoKg: NoVino(), Packs: NoVino(), Quantity: NoVino(), Weight: NoVino()}}

	casos := []struct {
		nombre    string
		renglones []Renglon
		respaldo  Numero
		esperado  float64
	}{
		{"sin líneas manda el respaldo", nil, De(40), 40},
		{"sin líneas y sin respaldo: 0", nil, NoVino(), 0},
		{"con peso resuelto manda el total", conPeso, De(40), 9.25},
		{"total 0 cede al respaldo", sinPeso, De(40), 40},
		{"total 0 y respaldo 0: 0", sinPeso, De(0), 0},
		{"total 0 y respaldo NaN: 0", sinPeso, NoVino(), 0},
		{"el respaldo no pisa un total bueno", conPeso, NoVino(), 9.25},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			if got := PesoDeRenglones(c.renglones, c.respaldo, nil); got != c.esperado {
				t.Fatalf("%v, se esperaba %v", got, c.esperado)
			}
		})
	}
}
