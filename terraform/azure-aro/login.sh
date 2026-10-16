#!/usr/bin/env bash
# Paso 3: abre sesión de oc en el clúster ARO (credenciales kubeadmin que da Azure) y deja listo el proyecto.
# Requisitos: az CLI con sesión, oc, jq.  Proyecto destino: NAMESPACE (por defecto "orders").
# Si el certificado de la API no es de confianza en tu equipo: OC_INSECURE=true ./login.sh
# Prueba sin Terraform:  OUTPUTS_JSON=salidas.json ./login.sh
set -euo pipefail
cd "$(dirname "$0")"

NS=${NAMESPACE:-orders}
if [ -n "${OUTPUTS_JSON:-}" ]; then OUT=$(cat "$OUTPUTS_JSON"); else OUT=$(terraform output -json); fi
out() { echo "$OUT" | jq -er ".$1.value"; }

CREDS=$(az aro list-credentials -g "$(out resource_group)" -n "$(out cluster_name)" -o json)
EXTRA=()
[ "${OC_INSECURE:-false}" = "true" ] && EXTRA+=(--insecure-skip-tls-verify=true)

oc login "$(out cluster_api_url)" -u "$(echo "$CREDS" | jq -er .kubeadminUsername)" \
  -p "$(echo "$CREDS" | jq -er .kubeadminPassword)" ${EXTRA[@]+"${EXTRA[@]}"}
oc get project "$NS" >/dev/null 2>&1 || oc new-project "$NS"
oc project "$NS"
