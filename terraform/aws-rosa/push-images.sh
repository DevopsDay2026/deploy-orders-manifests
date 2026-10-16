#!/usr/bin/env bash
# Paso 2: sube las imágenes nativas (ya construidas en Podman) a los repositorios de ECR que creó Terraform.
# Requisitos: aws CLI con sesión, podman, jq, y las imágenes localhost/<servicio>:<tag> (make image TAG=1.0.0).
# Prueba sin Terraform:  OUTPUTS_JSON=salidas.json ./push-images.sh
set -euo pipefail
cd "$(dirname "$0")"

TAG=${TAG:-1.0.0}
if [ -n "${OUTPUTS_JSON:-}" ]; then OUT=$(cat "$OUTPUTS_JSON"); else OUT=$(terraform output -json); fi
out() { echo "$OUT" | jq -er ".$1.value"; }

ECR=$(out ecr_registry)
REGION=$(out region)

echo "Login en $ECR"
aws ecr get-login-password --region "$REGION" | podman login --username AWS --password-stdin "$ECR"

for svc in orders-service inventory-service; do
  podman image exists "localhost/$svc:$TAG" || { echo "Falta la imagen localhost/$svc:$TAG (make image TAG=$TAG)" >&2; exit 1; }
  podman tag "localhost/$svc:$TAG" "$ECR/$svc:$TAG"
  podman push "$ECR/$svc:$TAG"
done
echo "OK: imágenes $TAG publicadas en $ECR"
