#!/usr/bin/env bash
# Prueba de humo de punta a punta: crea stock, crea un pedido y espera a que quede CONFIRMED.
# Sirve igual en ROSA, ARO, el Developer Sandbox o una laptop.
#
#   En un clúster (con sesión de oc en el proyecto):   ./smoke-test.sh
#   Contra URLs conocidas (por ejemplo, en la laptop):  ORDERS_URL=http://localhost:8080 \
#                                                       INVENTORY_URL=http://localhost:8081 ./smoke-test.sh
#
# Sale con código 0 solo si el pedido llega a CONFIRMED y el stock baja la cantidad pedida.
set -euo pipefail

SKU=${SKU:-SMOKE-$(date +%s)}
STOCK=${STOCK:-5}
QTY=${QTY:-2}
TIMEOUT=${TIMEOUT:-60}

if [ -z "${ORDERS_URL:-}" ] || [ -z "${INVENTORY_URL:-}" ]; then
  echo "1/4 Esperando el despliegue..."
  oc rollout status deploy/orders-service deploy/inventory-service --timeout=300s
  ORDERS_URL="https://$(oc get route orders-service -o jsonpath='{.spec.host}')"
  INVENTORY_URL="https://$(oc get route inventory-service -o jsonpath='{.spec.host}')"
fi
echo "    orders:    $ORDERS_URL"
echo "    inventory: $INVENTORY_URL"

json() { curl -fsS -H 'Content-Type: application/json' "$@"; }
field() { sed -n "s/.*\"$1\":\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p"; }

echo "2/4 Stock de $SKU = $STOCK"
json -X PUT "$INVENTORY_URL/api/v1/stock/$SKU" -d "{\"available\":$STOCK}" >/dev/null

echo "3/4 Pedido de $QTY unidades"
resp=$(json -X POST "$ORDERS_URL/api/v1/orders" \
  -d "{\"customerId\":\"smoke-test\",\"lines\":[{\"sku\":\"$SKU\",\"quantity\":$QTY}]}")
id=$(echo "$resp" | field id)
[ -n "$id" ] || { echo "No se pudo leer el id del pedido: $resp" >&2; exit 1; }

status=PENDING
for _ in $(seq "$TIMEOUT"); do
  status=$(json "$ORDERS_URL/api/v1/orders/$id" | field status)
  [ "$status" != "PENDING" ] && break
  sleep 1
done
echo "    pedido $id -> $status"
[ "$status" = "CONFIRMED" ] || { echo "FALLA: el pedido quedó en $status (¿Kafka o inventory-service caídos?)" >&2; exit 1; }

echo "4/4 Stock restante"
available=$(json "$INVENTORY_URL/api/v1/stock/$SKU" | field available)
expected=$((STOCK - QTY))
echo "    disponible: $available (esperado $expected)"
[ "$available" = "$expected" ] || { echo "FALLA: el stock no bajó como se esperaba" >&2; exit 1; }
echo "OK: el flujo completo funciona (REST -> PostgreSQL -> Kafka -> inventario -> confirmación)."
