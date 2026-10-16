#!/usr/bin/env bash
# Paso 2: sube las imágenes nativas (ya construidas en Podman) al Azure Container Registry que creó Terraform.
# Requisitos: az CLI con sesión, podman, jq, y las imágenes localhost/<servicio>:<tag> (make image TAG=1.0.0).
# Prueba sin Terraform:  OUTPUTS_JSON=salidas.json ./push-images.sh
set -euo pipefail
cd "$(dirname "$0")"

TAG=${TAG:-1.0.0}
if [ -n "${OUTPUTS_JSON:-}" ]; then OUT=$(cat "$OUTPUTS_JSON"); else OUT=$(terraform output -json); fi
out() { echo "$OUT" | jq -er ".$1.value"; }

ACR=$(out acr_login_server)

echo "Login en $ACR"
az acr login --name "${ACR%%.*}" --expose-token --output tsv --query accessToken | \
  podman login "$ACR" --username 00000000-0000-0000-0000-000000000000 --password-stdin

for svc in orders-service inventory-service; do
  podman image exists "localhost/$svc:$TAG" || { echo "Falta la imagen localhost/$svc:$TAG (make image TAG=$TAG)" >&2; exit 1; }
  podman tag "localhost/$svc:$TAG" "$ACR/$svc:$TAG"
  podman push "$ACR/$svc:$TAG"
done
echo "OK: imágenes $TAG publicadas en $ACR"
