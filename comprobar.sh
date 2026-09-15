#!/usr/bin/env bash
# Las comprobaciones de siempre, antes de subir nada.
#
# # Por que un script y no GitHub Actions
#
# Esto vivia en `.github/workflows/go.yml` y se quito el 15/09/2026 por dos razones:
#
#   1. El token de GitHub de Jose no tiene permiso `workflow`, asi que el push se
#      rechazaba entero por ese fichero — y arreglarlo era darle a un token mas permisos
#      de los que necesita para todo lo demas.
#   2. En Procovar despliega Dokploy, que clona y construye el. Un workflow que
#      construyera lo mismo seria duplicar lo que ya hay.
#
# Lo que si valia de aquel fichero era `sqlc diff`, y por algo concreto: cazo que el
# codigo generado llevaba SIETE COLUMNAS de retraso respecto a la migracion, o sea que la
# API no estaba leyendo los campos nuevos. Compilaba igual porque el cambio era aditivo, y
# por eso nadie lo habia visto. Eso se queda.
#
# Uso:   ./comprobar.sh
set -euo pipefail
export PATH="$PATH:$HOME/go/bin:/opt/flutter/bin"

fallos=0
paso() { printf "  %-34s " "$1"; }
bien() { echo "ok"; }
mal()  { echo "FALLA"; fallos=$((fallos+1)); }

for m in api sync; do
  echo "== $m =="
  cd "$m"
  paso "gofmt";     [ -z "$(gofmt -l . 2>/dev/null)" ] && bien || mal
  paso "go vet";    go vet ./... >/dev/null 2>&1 && bien || mal
  paso "go test";   go test ./... >/dev/null 2>&1 && bien || mal
  paso "go build";  go build ./... >/dev/null 2>&1 && bien || mal
  # El que caza que el codigo generado se quedo atras respecto al esquema.
  paso "sqlc diff"; sqlc diff >/dev/null 2>&1 && bien || mal
  cd ..
done

echo "== app (Flutter) =="
cd app
paso "analyze"; flutter analyze >/dev/null 2>&1 && bien || mal
# Con tope: una prueba colgada se come la sesion entera en vez de fallar. Ya paso.
paso "test";    timeout 300 flutter test >/dev/null 2>&1 && bien || mal
cd ..

echo
[ "$fallos" -eq 0 ] && echo "Todo en verde." || { echo "$fallos comprobaciones fallan."; exit 1; }
