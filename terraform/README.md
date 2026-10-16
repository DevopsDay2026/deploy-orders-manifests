# Terraform: la infraestructura bajo el mismo YAML

La aplicación (Deployment, Service, ConfigMap, Route) se describe con **Kustomize** y no cambia entre
destinos. Lo que sí cambia es el terreno donde aterriza: red, clúster OpenShift, base de datos, Kafka y
registro de imágenes. Esa capa se declara aquí con **Terraform**:

| Capa | Qué contiene | Herramienta |
|---|---|---|
| Infraestructura | VPC/VNet, clúster ROSA/ARO, PostgreSQL, Kafka, registro, secretos | **Terraform** (este directorio) |
| Aplicación | Deployment, Service, ConfigMap, Route | **Kustomize** (`base/` + `overlays/`) |

```
terraform/
├── aws-rosa/    VPC · ROSA HCP · RDS PostgreSQL · MSK · ECR · Secrets Manager   → overlays/rosa-aws
└── azure-aro/   VNet · ARO · PostgreSQL flexible · Event Hubs · ACR             → overlays/aro-azure
```

> **Estado:** ambas configuraciones pasan `terraform validate` (esquemas reales de los proveedores) y
> `terraform fmt`, y los scripts auxiliares se probaron con salidas simuladas. **No se ha ejecutado
> `terraform apply` en AWS ni en Azure**: no hubo acceso a esas nubes. Espera encontrar ajustes en el primer
> despliegue real (versiones de OpenShift, cuotas, permisos).

## Qué crea cada módulo

### `aws-rosa/`
| Archivo | Recursos |
|---|---|
| `main.tf` | VPC con subredes públicas y privadas, Internet Gateway y NAT (submódulo oficial de Red Hat); clúster **ROSA con plano de control hospedado (HCP)**, con sus roles de IAM y OIDC |
| `rds.tf` | RDS PostgreSQL 16 (Multi-AZ, cifrado) en subredes privadas; credenciales en Secrets Manager |
| `msk.tf` | MSK con SASL/SCRAM sobre TLS (puerto 9096); secreto cifrado con una CMK; configuración con `auto.create.topics.enable` |
| `ecr.tf` | Repositorios `orders-service` e `inventory-service`, con escaneo al subir |

### `azure-aro/`
| Archivo | Recursos |
|---|---|
| `network.tf` | Grupo de recursos, red virtual y subredes (master, worker y base de datos delegada) |
| `aro.tf` | Service principal, permisos de red y clúster **ARO** |
| `postgres.tf` | PostgreSQL servidor flexible 16, acceso privado, base `ordersapp` |
| `eventhubs.tf` | Event Hubs (endpoint Kafka :9093), un event hub por tópico, credencial de solo envío y escucha |
| `acr.tf` | Azure Container Registry |

## Requisitos

| | AWS | Azure |
|---|---|---|
| CLI | `terraform` ≥ 1.6, `aws`, `oc`, `podman`, `jq` | `terraform` ≥ 1.6, `az`, `oc`, `podman`, `jq` |
| Credenciales | `aws configure` (o SSO) | `az login` |
| Otros | Token de <https://console.redhat.com/openshift/token/rosa> en `RHCS_TOKEN`; ROSA habilitado en la cuenta | Permiso para crear aplicaciones en Entra ID; proveedores `Microsoft.RedHatOpenShift` y afines registrados |
| Cuota | 3 × `m6i.xlarge` | 3 × `Standard_D4s_v5` y 3 × `Standard_D8s_v5` |

## Flujo completo (AWS)

```bash
export RHCS_TOKEN="<token>"
cd terraform/aws-rosa
cp terraform.tfvars.example terraform.tfvars      # ajusta openshift_version (rosa list versions --hosted-cp)
terraform init
terraform plan -out tfplan
terraform apply tfplan                            # ~30-40 min: ROSA, RDS y MSK son lentos

# 1. imagen nativa -> ECR
ECR=$(terraform output -raw ecr_registry)
aws ecr get-login-password --region us-east-1 | podman login --username AWS --password-stdin "$ECR"
for svc in orders-service inventory-service; do
  podman tag  localhost/$svc:1.0.0 "$ECR/$svc:1.0.0"
  podman push "$ECR/$svc:1.0.0"
done

# 2. acceso al clúster, secretos y overlay con los valores de Terraform
eval "$(terraform output -raw oc_login)"
oc new-project orders
./apply-secrets.sh          # Secret de ambos servicios (RDS + MSK), sin escribirlos en disco
./render-overlay.sh         # genera overlays/local-rosa-aws (ignorado por git)

# 3. aplicación
cd ../..
oc apply -k overlays/local-rosa-aws
oc rollout status deploy/orders-service deploy/inventory-service
```

## Flujo completo (Azure)

```bash
cd terraform/azure-aro
cp terraform.tfvars.example terraform.tfvars      # subscription_id, location...
terraform init
terraform plan -out tfplan
terraform apply tfplan                            # ~40 min: ARO es lo más lento

# 1. imagen nativa -> ACR
ACR=$(terraform output -raw acr_login_server)
az acr login --name "${ACR%%.*}" --expose-token --output tsv --query accessToken | \
  podman login "$ACR" --username 00000000-0000-0000-0000-000000000000 --password-stdin
for svc in orders-service inventory-service; do
  podman tag  localhost/$svc:1.0.0 "$ACR/$svc:1.0.0"
  podman push "$ACR/$svc:1.0.0"
done

# 2. acceso al clúster, secretos y overlay
az aro list-credentials -g "$(terraform output -raw resource_group)" -n orders-demo   # kubeadmin
oc login "$(terraform output -raw cluster_api_url)" -u kubeadmin -p <contraseña>
oc new-project orders
./apply-secrets.sh          # Secret de ambos servicios (PostgreSQL + Event Hubs) y pull secret de ACR
./render-overlay.sh         # genera overlays/local-aro-azure (ignorado por git)

# 3. aplicación
cd ../..
oc apply -k overlays/local-aro-azure
oc rollout status deploy/orders-service deploy/inventory-service
```

## Probar

```bash
ORDERS=https://$(oc get route orders-service -o jsonpath='{.spec.host}')
INVENTORY=https://$(oc get route inventory-service -o jsonpath='{.spec.host}')
curl -X PUT "$INVENTORY/api/v1/stock/SKU-1" -H 'Content-Type: application/json' -d '{"available":5}'
curl -i -X POST "$ORDERS/api/v1/orders" -H 'Content-Type: application/json' \
  -d '{"customerId":"customer-1","lines":[{"sku":"SKU-1","quantity":2}]}'
```

## Decisiones y límites

- **Una sola base (`ordersapp`) con un esquema por servicio** (ADR-0005): Flyway crea `orders` e `inventory`.
  Es lo mismo que en la laptop; no hay que crear bases a mano.
- **Kafka en AWS:** MSK trae `auto.create.topics.enable=false`. Aquí se activa con
  `kafka_auto_create_topics = true` para que `orders.placed`, `inventory.reserved` e `inventory.rejected` existan al
  primer uso. En producción ponlo en `false` y créalos explícitamente (`kafka-topics.sh`).
- **Kafka en Azure:** cada tópico es un *event hub*; Terraform los crea. Event Hubs implementa el protocolo
  Kafka con diferencias: verifica productores y consumidores en el primer despliegue.
- **MSK con SCRAM, no IAM:** la autenticación IAM requiere la librería `aws-msk-iam-auth` en los servicios,
  que no está incluida.
- **Estado de Terraform:** se guarda en local (`terraform.tfstate`, ignorado por git) y **contiene los
  secretos**. Para trabajo en equipo usa un backend remoto cifrado (S3 + DynamoDB, o Azure Storage) antes
  de crear nada real.
- **Credenciales generadas por Terraform** (`random_password`): salen como salidas *sensibles*
  (`terraform output -raw db_password`). Los scripts `apply-secrets.sh` las pasan directo a `oc`.
- **Pull de imágenes en ROSA:** los workers deberían poder leer ECR con su rol de instancia; verifícalo. Si
  ves `ImagePullBackOff` por autorización, crea un *pull secret* (`aws ecr get-login-password`).
- **`terraform.lock.hcl`** se versiona; se generó en Windows y `terraform init` lo completa para tu plataforma.

## Qué no cubre

GitOps (Argo CD), WAF, escaneo y firma de imágenes en CI, `NetworkPolicy`, rotación de secretos,
observabilidad, VPC endpoints privados para los servicios de AWS y recuperación ante desastres.

## Costo y limpieza

Esto **cuesta dinero mientras exista** (ROSA HCP, RDS Multi-AZ y MSK son los mayores). Estimación en
`charla/costo.md` del material de la charla.

```bash
oc delete project orders                 # primero la aplicación
terraform -chdir=terraform/aws-rosa destroy      # o azure-aro
```
