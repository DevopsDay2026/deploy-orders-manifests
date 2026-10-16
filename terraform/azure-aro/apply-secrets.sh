#!/usr/bin/env bash
# Crea en el clúster los Secret de los dos servicios con las credenciales que generó Terraform
# (PostgreSQL y Event Hubs), sin escribirlas en ningún archivo. Requiere `oc` con sesión en el proyecto destino.
# Prueba sin Terraform:  OUTPUTS_JSON=salidas.json ./apply-secrets.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${OUTPUTS_JSON:-}" ]; then OUT=$(cat "$OUTPUTS_JSON"); else OUT=$(terraform output -json); fi
out() { echo "$OUT" | jq -er ".$1.value"; }

DB_USERNAME=$(out db_username)
DB_PASSWORD=$(out db_password)
# Event Hubs: SASL PLAIN con el usuario literal $ConnectionString y la cadena de conexión como contraseña.
KAFKA_JAAS="org.apache.kafka.common.security.plain.PlainLoginModule required username=\"\$ConnectionString\" password=\"$(out eventhubs_connection_string)\";"

for svc in orders-service inventory-service; do
  oc create secret generic "$svc-secrets" \
    --from-literal=DB_USERNAME="$DB_USERNAME" \
    --from-literal=DB_PASSWORD="$DB_PASSWORD" \
    --from-literal=KAFKA_SASL_JAAS_CONFIG="$KAFKA_JAAS" \
    --dry-run=client -o yaml | oc apply -f -
done

# El clúster necesita credenciales para tirar de ACR (usuario admin: solo para la demo).
ACR_SERVER=$(out acr_login_server)
oc create secret docker-registry acr-pull \
  --docker-server="$ACR_SERVER" \
  --docker-username="$(out acr_admin_username)" \
  --docker-password="$(out acr_admin_password)" \
  --dry-run=client -o yaml | oc apply -f -
oc secrets link default acr-pull --for=pull
