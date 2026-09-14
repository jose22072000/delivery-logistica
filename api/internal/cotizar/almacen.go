package cotizar

// EL ALMACÉN DE ORIGEN (§10 de reglas-negocio.md y la regla de selección de
// `/api/quote/home-delivery`).
//
// El almacén VIVE EN ACCESOS y no se copia aquí: un almacén copiado se separa del de
// verdad en cuanto alguien mueve unas coordenadas allá, y *con esas coordenadas se mide lo
// que se le cobra al cliente*.

// Almacen es lo que Accesos devuelve de cada almacén de una sucursal.
type Almacen struct {
	ID        string   `json:"id"`
	Nombre    string   `json:"nombre"`
	Direccion *string  `json:"direccion"`
	Latitud   *float64 `json:"latitud"`
	Longitud  *float64 `json:"longitud"`
	Principal bool     `json:"principal"`
	Activo    bool     `json:"activo"`
}

// TieneCoordenadas: las dos, no una. Media coordenada no es un punto.
func (a Almacen) TieneCoordenadas() bool { return a.Latitud != nil && a.Longitud != nil }

// Punto del almacén. Sólo tiene sentido con TieneCoordenadas() == true.
func (a Almacen) Punto() Punto { return Punto{Lat: *a.Latitud, Lng: *a.Longitud} }

// ElegirAlmacen aplica la regla de selección del origen, en este orden:
//
//  1. El primer almacén con `principal == true` Y con las dos coordenadas.
//  2. Si no hay, el primero con coordenadas, principal o no.
//  3. Si no hay ninguno con coordenadas, nil — y quien llama contesta
//     `409 «<Sucursal> no tiene ningún almacén con coordenadas»`.
//
// POR QUÉ EL 409 Y NO UN APAÑO: *es desde donde sale la mercancía, que es lo que mide la
// APK.* Sin almacén con coordenadas no se contesta un número aproximado —ni se usan las
// coordenadas de la sucursal, que no son el sitio del que sale la carga—: se dice que no
// se puede. Un número aproximado aquí se cobra igual que uno bueno.
//
// OJO: `activo` NO filtra. La regla del pliego mira `principal` y las coordenadas, nada
// más; añadir aquí un filtro por activo cambiaría el almacén elegido en sucursales que
// tienen uno dado de baja con coordenadas buenas, y con él el importe.
func ElegirAlmacen(almacenes []Almacen) *Almacen {
	for i := range almacenes {
		if almacenes[i].Principal && almacenes[i].TieneCoordenadas() {
			return &almacenes[i]
		}
	}
	for i := range almacenes {
		if almacenes[i].TieneCoordenadas() {
			return &almacenes[i]
		}
	}
	return nil
}
