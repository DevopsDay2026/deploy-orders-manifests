#!/usr/bin/env bash
# Crea en el clúster los Secret de los dos servicios con las credenciales que generó Terraform
# (RDS y MSK/SCRAM), sin escribirlas en ningún archivo. Requiere `oc` con sesión en el proyecto destino.
# Prueba sin Terraform:  OUTPUTS_JSON=salidas.json ./apply-secrets.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${OUTPUTS_JSON:-}" ]; then OUT=$(cat "$OUTPUTS_JSON"); else OUT=$(terraform output -json); fi
out() { echo "$OUT" | jq -er ".$1.value"; }

DB_USERNAME=$(out db_username)
DB_PASSWORD=$(out db_password)
KAFKA_JAAS="org.apache.kafka.common.security.scram.ScramLoginModule required username=\"$(out kafka_username)\" password=\"$(out kafka_password)\";"

for svc in orders-service inventory-service; do
  oc create secret generic "$svc-secrets" \
    --from-literal=DB_USERNAME="$DB_USERNAME" \
    --from-literal=DB_PASSWORD="$DB_PASSWORD" \
    --from-literal=KAFKA_SASL_JAAS_CONFIG="$KAFKA_JAAS" \
    --dry-run=client -o yaml | oc apply -f -
done
