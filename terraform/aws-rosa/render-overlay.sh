#!/usr/bin/env bash
# Genera overlays/local-rosa-aws (ignorado por git) con los valores de `terraform output`.
# Así los archivos versionados de overlays/rosa-aws conservan sus <placeholders>.
#
# Requisitos: terraform (con el estado de este directorio), jq.
# Prueba sin Terraform:  OUTPUTS_JSON=salidas.json ./render-overlay.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${OUTPUTS_JSON:-}" ]; then OUT=$(cat "$OUTPUTS_JSON"); else OUT=$(terraform output -json); fi
val() { echo "$OUT" | jq -er ".overlay_values.value.$1"; }

ACCOUNT_ID=$(val ACCOUNT_ID)
REGION=$(val REGION)
RDS_ENDPOINT=$(val RDS_ENDPOINT)
DB_NAME=$(val DB_NAME)
MSK_BOOTSTRAP=$(val MSK_BOOTSTRAP_SCRAM)

SRC=../../overlays/rosa-aws
DEST=../../overlays/local-rosa-aws
rm -rf "$DEST"
cp -r "$SRC" "$DEST"

sed -i.bak "s|<ACCOUNT_ID>|$ACCOUNT_ID|g; s|<REGION>|$REGION|g" "$DEST/kustomization.yaml"
sed -i.bak "s|<RDS_ENDPOINT>|$RDS_ENDPOINT|g; s|/ordersapp?|/$DB_NAME?|g; s|<MSK_BOOTSTRAP_SCRAM>|$MSK_BOOTSTRAP|g" \
  "$DEST/config-values.yaml"
rm -f "$DEST"/*.bak

if grep -rn '<[A-Z_]*>' "$DEST" >/dev/null 2>&1; then
  echo "Quedaron placeholders sin sustituir:" >&2
  grep -rn '<[A-Z_]*>' "$DEST" >&2
  exit 1
fi
echo "OK -> overlays/local-rosa-aws   (aplicar con: oc apply -k overlays/local-rosa-aws)"
