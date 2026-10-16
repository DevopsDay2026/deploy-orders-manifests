# Despliegue en AWS: ROSA con Amazon ECR, RDS y MSK

Paso a paso para llevar **la misma imagen nativa** de la laptop a **ROSA** (Red Hat OpenShift Service on
AWS) usando servicios administrados: Amazon ECR (imágenes), Amazon RDS for PostgreSQL y Amazon MSK
(Kafka).

> **Estado:** esta guía **no se ha ejecutado de punta a punta**. El manifiesto compila
> (`kustomize build overlays/rosa-aws`) y los comandos siguen la documentación de AWS y de Red Hat, pero
> no hubo despliegue real en AWS. Cada paso marca qué verificar. Las capturas y cualquier ajuste salen
> del primer despliegue real.

![Arquitectura de referencia](arquitectura-rosa-aro.png)

*Arquitectura de referencia, no es lo que opera una entidad concreta.* El diagrama anterior sobre EKS
sigue en [arquitectura-eks.png](arquitectura-eks.png): sirve igual, cambia solo la plataforma (Route en
lugar de Ingress/ALB).

## Qué viaja intacto y qué cambia

| | Laptop / Sandbox | ROSA en AWS |
|---|---|---|
| Imagen | `localhost/<svc>:1.0.0` o ImageStream | `<cuenta>.dkr.ecr.<región>.amazonaws.com/<svc>:1.0.0` |
| PostgreSQL | contenedor de `platform/` | Amazon RDS |
| Kafka | contenedor de `platform/` | Amazon MSK |
| Secret | `secrets.yaml` | `secrets.yaml` (producción: External Secrets + Secrets Manager) |
| Borde | `Route` | `Route` (mismo componente) |
| `Deployment`, `Service` | `base/` | `base/` (sin cambios) |

El overlay [`overlays/rosa-aws`](../../overlays/rosa-aws) aplica exactamente eso.

## Despliegue recomendado: Terraform + Kustomize

La infraestructura (VPC, ROSA HCP, RDS, MSK, ECR) se declara en [`terraform/aws-rosa`](../../terraform/aws-rosa) y
la aplicación sigue siendo el mismo YAML de Kustomize:

```bash
export RHCS_TOKEN="<token de console.redhat.com>"
cd terraform/aws-rosa
cp terraform.tfvars.example terraform.tfvars && terraform init && terraform apply     # infraestructura
# imagen nativa -> ECR (podman push), luego:
./apply-secrets.sh && ./render-overlay.sh                                              # secretos y overlay
cd ../.. && oc apply -k overlays/local-rosa-aws                                        # aplicación
```

El flujo completo, qué crea cada archivo y sus límites están en [terraform/README.md](../../terraform/README.md).
Las secciones numeradas de abajo son la **alternativa manual con las CLI** (sirven para entender qué hace
Terraform paso a paso).

## Requisitos

- Cuenta de AWS con ROSA habilitado y cuota para 3 nodos `m6i.xlarge`.
- CLI: `aws`, `rosa`, `oc`, `podman`. Cuenta de Red Hat (token de <https://console.redhat.com/openshift/token/rosa>).
- La imagen nativa construida **en una máquina x86_64** (los nodos `m6i` son x86_64). Si la construiste en
  ARM (Apple Silicon), el pod fallará con `exec format error`: construye en x86_64 o en CI
  multi-arquitectura.

Variables que se usan abajo:

```bash
export AWS_REGION=us-east-1
export CLUSTER=orders-demo
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

## Alternativa manual · 1. Clúster ROSA con plano de control hospedado (HCP)

```bash
rosa login --token="<token>"
rosa verify quota && rosa verify permissions
rosa create account-roles --hosted-cp --mode auto --yes

# VPC con subredes públicas y privadas en 2-3 zonas (o usa una existente)
rosa create cluster --cluster-name $CLUSTER --sts --mode auto --hosted-cp \
  --region $AWS_REGION --subnet-ids <subnets-privadas,subnets-publicas> \
  --compute-machine-type m6i.xlarge --replicas 3 --yes

rosa logs install -c $CLUSTER --watch     # ~15-20 min
rosa create admin -c $CLUSTER              # imprime el comando oc login
```

Verificar: `rosa describe cluster -c $CLUSTER` en estado `ready`. Los flags exactos cambian entre
versiones: `rosa create cluster --help`.

## 2. PostgreSQL en Amazon RDS

```bash
aws rds create-db-subnet-group --db-subnet-group-name orders-db \
  --db-subnet-group-description "orders" --subnet-ids <subnets-privadas>

aws rds create-db-instance --db-instance-identifier orders-pg \
  --engine postgres --engine-version 16 --db-instance-class db.t4g.medium \
  --allocated-storage 20 --storage-encrypted --multi-az --no-publicly-accessible \
  --db-name ordersapp --master-username orders_admin --master-user-password '<contraseña>' \
  --db-subnet-group-name orders-db --vpc-security-group-ids <sg-rds>
```

- El grupo de seguridad `<sg-rds>` debe permitir **5432 desde el grupo de seguridad de los nodos worker**
  de ROSA.
- Agrega `--db-name ordersapp` al comando anterior: ambos servicios usan **la misma base** y cada uno su propio
  esquema (`orders`, `inventory`), así que no hay que crear bases a mano.

Flyway crea el esquema `orders` / `inventory` al arrancar cada servicio. Para producción usa un usuario
por servicio con privilegios mínimos, no el maestro.

## 3. Kafka en Amazon MSK

1. Crea un clúster **provisioned** (`kafka.t3.small`, 3 brokers, 3 zonas) con **SASL/SCRAM** habilitado y
   cifrado TLS.
2. Crea un secreto en Secrets Manager llamado `AmazonMSK_<nombre>` con
   `{"username":"orders","password":"<contraseña>"}`, cifrado con una CMK propia, y asócialo:

```bash
aws kafka batch-associate-scram-secret --cluster-arn <arn-msk> --secret-arn-list <arn-secreto>
aws kafka get-bootstrap-brokers --cluster-arn <arn-msk>     # usar BootstrapBrokerStringSaslScram (:9096)
```

3. **Crea los tópicos a mano**: MSK no los crea automáticamente (`auto.create.topics.enable=false` por
   defecto). Son los de los `ConfigMap`. Primero el archivo de propiedades del cliente, `client.properties`:

```properties
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="orders" password="<contraseña>";
```

   Y luego, desde un pod con las herramientas de Kafka (el archivo se copia con `oc cp`):

```bash
oc run kafka-client --image=quay.io/strimzi/kafka:0.45.0-kafka-3.9.0 --restart=Never -- sleep 3600
oc wait --for=condition=Ready pod/kafka-client
oc cp client.properties kafka-client:/tmp/client.properties

for t in orders.placed inventory.reserved inventory.rejected; do
  oc exec kafka-client -- bin/kafka-topics.sh --bootstrap-server <MSK_BOOTSTRAP_SCRAM> \
    --command-config /tmp/client.properties --create --if-not-exists --topic $t \
    --partitions 3 --replication-factor 3
done
oc delete pod kafka-client
```

> **IAM en lugar de SCRAM:** MSK soporta autenticación IAM, pero requiere la librería `aws-msk-iam-auth` en
> el servicio, que **no está incluida**. Esta guía usa SCRAM porque funciona con la configuración actual
> (`KAFKA_SASL_MECHANISM`, `KAFKA_SASL_JAAS_CONFIG`). Si prefieres no administrar Kafka fuera del clúster,
> el overlay `rosa` mantiene Kafka dentro con `platform/kafka.yaml`.

## 4. Imágenes en Amazon ECR

```bash
for svc in orders-service inventory-service; do
  aws ecr create-repository --repository-name $svc --region $AWS_REGION \
    --image-scanning-configuration scanOnPush=true
done

aws ecr get-login-password --region $AWS_REGION | \
  podman login --username AWS --password-stdin $ECR

for svc in orders-service inventory-service; do
  podman tag  localhost/$svc:1.0.0 $ECR/$svc:1.0.0
  podman push $ECR/$svc:1.0.0
done
```

Los nodos worker de ROSA en la misma cuenta pueden leer de ECR con su rol de instancia. **Verificar:** si
los pods quedan en `ImagePullBackOff` con error de autorización, crea un *pull secret*:

```bash
oc create secret docker-registry ecr-pull --docker-server=$ECR --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region $AWS_REGION)"
oc secrets link default ecr-pull --for=pull
```

(El token de ECR caduca a las 12 h: es un parche, no una solución para producción.)

## 5. Configurar y aplicar

Reemplaza los `<...>` en dos archivos del repositorio:

1. [`overlays/rosa-aws/kustomization.yaml`](../../overlays/rosa-aws/kustomization.yaml): `<ACCOUNT_ID>` y
   `<REGION>`.
2. [`overlays/rosa-aws/config-values.yaml`](../../overlays/rosa-aws/config-values.yaml): `<RDS_ENDPOINT>` y
   `<MSK_BOOTSTRAP_SCRAM>`.

Y los secretos (el archivo está ignorado por git):

```bash
cp secrets.example.yaml secrets.yaml
# DB_USERNAME / DB_PASSWORD de RDS en ambos Secret, y en ambos añadir la credencial de Kafka:
#   KAFKA_SASL_JAAS_CONFIG: 'org.apache.kafka.common.security.scram.ScramLoginModule required username="orders" password="<contraseña>";'
oc apply -f secrets.yaml
oc apply -k overlays/rosa-aws
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

Debe devolver el pedido; al consultarlo queda `CONFIRMED` y el stock baja a 3.

## Si algo falla

| Síntoma | Causa probable |
|---|---|
| `exec format error` | La imagen nativa se construyó para otra arquitectura (ARM) |
| `ImagePullBackOff` | Falta permiso para leer de ECR (ver el *pull secret* del paso 4) |
| `CrashLoopBackOff`, `Connection refused` a RDS | Grupo de seguridad de RDS no permite a los nodos |
| El servicio arranca y no consume | Los tópicos no existen (paso 3.3) |
| `SaslAuthenticationException` | SCRAM no asociado al clúster, o `KAFKA_SASL_JAAS_CONFIG` mal formado |

## Limpieza (esto cuesta dinero mientras exista)

```bash
oc delete project orders
rosa delete cluster -c $CLUSTER --yes
aws rds delete-db-instance --db-instance-identifier orders-pg --skip-final-snapshot
aws kafka delete-cluster --cluster-arn <arn-msk>
aws ecr delete-repository --repository-name orders-service --force
aws ecr delete-repository --repository-name inventory-service --force
```

## Qué no cubre

CI/CD, GitOps, WAF, escaneo y firma de imágenes, `NetworkPolicy`, rotación de secretos, observabilidad ni
recuperación ante desastres. El costo estimado del clúster está en `charla/costo.md` del material de la
charla.
