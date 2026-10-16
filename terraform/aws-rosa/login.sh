#!/usr/bin/env bash
# Paso 3: abre sesión de oc en el clúster ROSA con las credenciales que generó Terraform y deja listo el proyecto.
# Requisitos: oc, jq.  Proyecto destino: NAMESPACE (por defecto "orders").
# Prueba sin Terraform:  OUTPUTS_JSON=salidas.json ./login.sh
set -euo pipefail
cd "$(dirname "$0")"

NS=${NAMESPACE:-orders}
if [ -n "${OUTPUTS_JSON:-}" ]; then OUT=$(cat "$OUTPUTS_JSON"); else OUT=$(terraform output -json); fi
out() { echo "$OUT" | jq -er ".$1.value"; }

oc login "$(out cluster_api_url)" -u "$(out cluster_admin_username)" -p "$(out cluster_admin_password)"
oc get project "$NS" >/dev/null 2>&1 || oc new-project "$NS"
oc project "$NS"
