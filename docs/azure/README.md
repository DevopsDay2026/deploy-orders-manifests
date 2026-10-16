# Despliegue en Azure: ARO con Azure Container Registry, PostgreSQL y Event Hubs

Paso a paso para llevar **la misma imagen nativa** de la laptop a **ARO** (Azure Red Hat OpenShift)
usando servicios administrados: Azure Container Registry (imágenes), Azure Database for PostgreSQL
(servidor flexible) y Azure Event Hubs con su endpoint compatible con Kafka.

> **Estado:** esta guía **no se ha ejecutado de punta a punta**. El manifiesto compila
> (`kustomize build overlays/aro-azure`), pero no hubo despliegue real en Azure. La compatibilidad de
> Event Hubs con el cliente Kafka del servicio es lo primero que hay que verificar (ver paso 4).

![Arquitectura de referencia](../aws/arquitectura-rosa-aro.png)

## Qué viaja intacto y qué cambia

| | Laptop / Sandbox | ARO en Azure |
|---|---|---|
| Imagen | `localhost/<svc>:1.0.0` o ImageStream | `<acr>.azurecr.io/<svc>:1.0.0` |
| PostgreSQL | contenedor de `platform/` | Azure Database for PostgreSQL |
| Kafka | contenedor de `platform/` | Event Hubs (API Kafka, puerto 9093) |
| Secret | `secrets.yaml` | `secrets.yaml` (producción: External Secrets + Key Vault) |
| Borde | `Route` | `Route` |
| `Deployment`, `Service` | `base/` | `base/` (sin cambios) |

El overlay [`overlays/aro-azure`](../../overlays/aro-azure) aplica exactamente eso.

## Despliegue recomendado: Terraform + Kustomize

La infraestructura (VNet, ARO, PostgreSQL, Event Hubs, ACR) se declara en [`terraform/azure-aro`](../../terraform/azure-aro)
y la aplicación sigue siendo el mismo YAML de Kustomize:

```bash
az login
cd terraform/azure-aro
cp terraform.tfvars.example terraform.tfvars && terraform init && terraform apply     # infraestructura
# imagen nativa -> ACR (podman push), luego, con sesión de oc:
./apply-secrets.sh && ./render-overlay.sh                                              # secretos y overlay
cd ../.. && oc apply -k overlays/local-aro-azure                                       # aplicación
```

El flujo completo, qué crea cada archivo y sus límites están en [terraform/README.md](../../terraform/README.md).
Las secciones numeradas de abajo son la **alternativa manual con las CLI**.

## Requisitos

- Suscripción de Azure con cuota para 3 workers `Standard_D4s_v5` y 3 masters (ARO exige un mínimo de
  3 workers y 3 masters).
- CLI: `az`, `oc`, `podman`.
- La imagen nativa construida **en x86_64** (las VM `D4s_v5` son x86_64); si se construyó en ARM, el pod
  falla con `exec format error`.

```bash
export RG=orders-demo-rg
export LOCATION=eastus
export CLUSTER=orders-demo
export ACR=ordersdemo$RANDOM        # nombre global único
export PG=orders-pg-$RANDOM
export EH=orders-eh-$RANDOM
```

## Alternativa manual · 1. Clúster ARO

```bash
az login
for p in Microsoft.RedHatOpenShift Microsoft.Compute Microsoft.Storage Microsoft.Authorization; do
  az provider register -n $p --wait
done

az group create -n $RG -l $LOCATION
az network vnet create -g $RG -n aro-vnet --address-prefixes 10.0.0.0/20
az network vnet subnet create -g $RG --vnet-name aro-vnet -n master-subnet --address-prefixes 10.0.0.0/23
az network vnet subnet create -g $RG --vnet-name aro-vnet -n worker-subnet --address-prefixes 10.0.2.0/23
az network vnet subnet create -g $RG --vnet-name aro-vnet -n db-subnet --address-prefixes 10.0.4.0/24 \
  --delegations Microsoft.DBforPostgreSQL/flexibleServers

az aro create -g $RG -n $CLUSTER --vnet aro-vnet \
  --master-subnet master-subnet --worker-subnet worker-subnet \
  --worker-vm-size Standard_D4s_v5 --worker-count 3        # ~35 min
```

Credenciales y acceso:

```bash
az aro list-credentials -g $RG -n $CLUSTER
API=$(az aro show -g $RG -n $CLUSTER --query apiserverProfile.url -o tsv)
oc login $API -u kubeadmin -p <contraseña>
oc new-project orders
```

> Si el clúster debe alcanzar un registro con *pull secret* de Red Hat, pásalo con
> `--pull-secret @pull-secret.txt` en `az aro create`.

## 2. PostgreSQL

```bash
az postgres flexible-server create -g $RG -n $PG -l $LOCATION --version 16 \
  --tier Burstable --sku-name Standard_B2s --storage-size 32 \
  --admin-user orders_admin --admin-password '<contraseña>' \
  --vnet aro-vnet --subnet db-subnet --yes

az postgres flexible-server db create -g $RG --server-name $PG -d ordersapp   # una base; un esquema por servicio
```

El servidor queda con acceso privado dentro de la VNet; los workers de ARO lo alcanzan. Flyway crea los
esquemas al arrancar cada servicio. En producción: un usuario por servicio.

## 3. Imágenes en Azure Container Registry

```bash
az acr create -g $RG -n $ACR --sku Basic
az acr login -n $ACR --expose-token --output tsv --query accessToken | \
  podman login $ACR.azurecr.io --username 00000000-0000-0000-0000-000000000000 --password-stdin

for svc in orders-service inventory-service; do
  podman tag  localhost/$svc:1.0.0 $ACR.azurecr.io/$svc:1.0.0
  podman push $ACR.azurecr.io/$svc:1.0.0
done
```

El clúster necesita credenciales para tirar de ACR:

```bash
az acr update -n $ACR --admin-enabled true       # solo para la demo
oc create secret docker-registry acr-pull --docker-server=$ACR.azurecr.io \
  --docker-username=$ACR --docker-password="$(az acr credential show -n $ACR --query passwords[0].value -o tsv)"
oc secrets link default acr-pull --for=pull
```

En producción usa un *token* de ámbito limitado o una identidad administrada, no el usuario admin.

## 4. Kafka en Event Hubs

```bash
az eventhubs namespace create -g $RG -n $EH -l $LOCATION --sku Standard
for t in orders.placed inventory.reserved inventory.rejected; do
  az eventhubs eventhub create -g $RG --namespace-name $EH -n $t --partition-count 3
done
az eventhubs namespace authorization-rule keys list -g $RG --namespace-name $EH \
  -n RootManageSharedAccessKey --query primaryConnectionString -o tsv
```

Cada tópico de Kafka es un *event hub* con el mismo nombre; **hay que crearlos a mano**. El endpoint Kafka
es `<namespace>.servicebus.windows.net:9093`, con `SASL_SSL` y mecanismo `PLAIN`, usuario literal
`$ConnectionString` y la cadena de conexión como contraseña (va en `secrets.yaml`, abajo).

> **Verificar primero:** Event Hubs implementa el protocolo Kafka con diferencias respecto a Kafka
> (por ejemplo, el comportamiento de los grupos de consumidores y algunas características del productor
> según el nivel). El servicio usa consumidores idempotentes por diseño (ADR-0002), lo que ayuda, pero
> este es el punto más probable de ajuste. Alternativa: mantener Kafka dentro del clúster con
> `platform/kafka.yaml`.

## 5. Configurar y aplicar

1. [`overlays/aro-azure/kustomization.yaml`](../../overlays/aro-azure/kustomization.yaml): `<ACR_NAME>`.
2. [`overlays/aro-azure/config-values.yaml`](../../overlays/aro-azure/config-values.yaml): `<PG_SERVER>` y
   `<EVENTHUBS_NAMESPACE>`.

Secretos (archivo ignorado por git):

```bash
cp secrets.example.yaml secrets.yaml
# DB_USERNAME / DB_PASSWORD del servidor PostgreSQL en ambos Secret, y en ambos añadir:
#   KAFKA_SASL_JAAS_CONFIG: 'org.apache.kafka.common.security.plain.PlainLoginModule required username="$ConnectionString" password="<cadena de conexión>";'
oc apply -f secrets.yaml
oc apply -k overlays/aro-azure
oc rollout status deploy/orders-service deploy/inventory-service
```

## 6. Probar

```bash
ORDERS=https://$(oc get route orders-service -o jsonpath='{.spec.host}')
INVENTORY=https://$(oc get route inventory-service -o jsonpath='{.spec.host}')
curl -X PUT "$INVENTORY/api/v1/stock/SKU-1" -H 'Content-Type: application/json' -d '{"available":5}'
curl -i -X POST "$ORDERS/api/v1/orders" -H 'Content-Type: application/json' \
  -d '{"customerId":"customer-1","lines":[{"sku":"SKU-1","quantity":2}]}'
```

## Si algo falla

| Síntoma | Causa probable |
|---|---|
| `exec format error` | Imagen construida para otra arquitectura |
| `ImagePullBackOff` | Falta el *pull secret* de ACR (paso 3) |
| `Connection refused` a PostgreSQL | El servidor no está en la VNet o la subred no está delegada |
| El servicio arranca y no consume | Los *event hubs* no existen (paso 4) |
| `SaslAuthenticationException` | Cadena de conexión mal copiada, o `$ConnectionString` expandido por el shell |

> Al escribir `$ConnectionString` en un shell, usa comillas simples para que no se expanda.

## Limpieza (esto cuesta dinero mientras exista)

```bash
az group delete -n $RG --yes --no-wait      # borra clúster, base, registro y Event Hubs
```

## Qué no cubre

CI/CD, GitOps, WAF, escaneo y firma de imágenes, `NetworkPolicy`, rotación de secretos, observabilidad ni
recuperación ante desastres.
