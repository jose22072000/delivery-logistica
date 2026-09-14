package httpx

import "encoding/json"

// Opcional distingue las TRES cosas que puede decir un campo de un PATCH:
//
//	no vino          -> Presente=false            -> no se toca
//	vino como null   -> Presente=true, Valor=nil  -> se BORRA
//	vino con valor   -> Presente=true, Valor=&v   -> se pone
//
// POR QUÉ HACE FALTA: con un `*string` pelado no se puede separar «no me mandes esto» de
// «déjalo vacío», y las dos cosas llegan como nil. Ahí es donde un PATCH que sólo quería
// cambiar el nombre borra la matrícula del camión. Por eso las consultas generadas llevan
// pares `tocar_plate` / `plate`: este tipo es lo que los rellena.
type Opcional[T any] struct {
	Presente bool
	Valor    *T
}

func (o *Opcional[T]) UnmarshalJSON(b []byte) error {
	o.Presente = true
	if string(b) == "null" {
		o.Valor = nil
		return nil
	}
	var v T
	if err := json.Unmarshal(b, &v); err != nil {
		return err
	}
	o.Valor = &v
	return nil
}

// Puntero es el valor para un `coalesce(...)`: nil cuando el campo no vino.
func (o Opcional[T]) Puntero() *T {
	if !o.Presente {
		return nil
	}
	return o.Valor
}

// Con devuelve el valor, o el de por defecto si no vino o vino null. Para los POST, donde
// no hay tri-estado: o lo mandan o se usa el de la casa.
func (o Opcional[T]) Con(porDefecto T) T {
	if o.Valor == nil {
		return porDefecto
	}
	return *o.Valor
}
