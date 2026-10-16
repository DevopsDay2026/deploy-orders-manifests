#!/usr/bin/env bash
# Genera overlays/local-aro-azure (ignorado por git) con los valores de `terraform output`.
# Así los archivos versionados de overlays/aro-azure conservan sus <placeholders>.
#
# Requisitos: terraform (con el estado de este directorio), jq.
# Prueba sin Terraform:  OUTPUTS_JSON=salidas.json ./render-overlay.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${OUTPUTS_JSON:-}" ]; then OUT=$(cat "$OUTPUTS_JSON"); else OUT=$(terraform output -json); fi
val() { echo "$OUT" | jq -er ".overlay_values.value.$1"; }

ACR_NAME=$(val ACR_NAME)
PG_SERVER=$(val PG_SERVER)
DB_NAME=$(val DB_NAME)
EVENTHUBS_NAMESPACE=$(val EVENTHUBS_NAMESPACE)

SRC=../../overlays/aro-azure
DEST=../../overlays/local-aro-azure
rm -rf "$DEST"
cp -r "$SRC" "$DEST"

sed -i.bak "s|<ACR_NAME>|$ACR_NAME|g" "$DEST/kustomization.yaml"
sed -i.bak "s|<PG_SERVER>|$PG_SERVER|g; s|/ordersapp?|/$DB_NAME?|g; s|<EVENTHUBS_NAMESPACE>|$EVENTHUBS_NAMESPACE|g" \
  "$DEST/config-values.yaml"
rm -f "$DEST"/*.bak

if grep -rn '<[A-Z_]*>' "$DEST" >/dev/null 2>&1; then
  echo "Quedaron placeholders sin sustituir:" >&2
  grep -rn '<[A-Z_]*>' "$DEST" >&2
  exit 1
fi
echo "OK -> overlays/local-aro-azure   (aplicar con: oc apply -k overlays/local-aro-azure)"
