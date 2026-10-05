# deploy-orders-manifests

Manifiestos de la aplicación de pedidos de la charla *"En mi máquina funciona"*: los mismos YAML de
Kubernetes para la laptop (`podman kube play`), OpenShift (Developer Sandbox) y ROSA. Entre destinos
solo cambian imagen/tag, réplicas, recursos y valores de `ConfigMap`/`Secret`.

```
base/                         Deployment + Service + ConfigMap de orders-service e inventory-service
platform/                     PostgreSQL por servicio + Kafka de un nodo (destinos sin servicios administrados)
components/openshift-route/   Route de cada servicio (solo /api)
overlays/podman/              laptop
overlays/openshift/           Developer Sandbox
overlays/rosa/                ROSA: 2 réplicas y más recursos
secrets.example.yaml          plantilla de los Secret (secrets.yaml está ignorado por git)
```

## Cómo correrlo en 3 comandos (laptop con Podman)

Antes: construir las dos imágenes nativas con `make image TAG=1.0.0` en `backend-orders-service` y
en `backend-inventory-service`.

```bash
cp secrets.example.yaml secrets.yaml                                   # 1. y reemplazar los <...>
podman kube play secrets.yaml                                          # 2. crea los Secret en Podman
kubectl kustomize overlays/podman | podman kube play -                 # 3. PostgreSQL, Kafka y los dos servicios
```

Sin `kubectl` ni `oc` instalados, Kustomize también corre en un contenedor:

```bash
podman run --rm -v "$PWD:/work" registry.k8s.io/kustomize/kustomize:v5.4.3 build /work/overlays/podman \
  | podman kube play -
```

(En Git Bash de Windows: anteponer `MSYS_NO_PATHCONV=1` y usar `"$(pwd -W):/work"`.)

Probar el flujo completo:

```bash
curl -X PUT localhost:8081/api/v1/stock/SKU-1 -H 'Content-Type: application/json' -d '{"available":5}'
curl -i -X POST localhost:8080/api/v1/orders -H 'Content-Type: application/json' \
  -d '{"customerId":"customer-1","lines":[{"sku":"SKU-1","quantity":2}]}'
curl localhost:8080/api/v1/orders/<id>        # CONFIRMED; con cantidad mayor al stock: REJECTED
curl localhost:8081/api/v1/stock/SKU-1        # available: 3
```

Para trabajar solo con los backends (modo dev o binario nativo, sin imágenes) no hace falta este
repositorio: `./run.sh infra` en cualquiera de los dos backends levanta PostgreSQL y Kafka en pods
propios (`local-postgres`, `local-kafka`). El pod `local-postgres` publica el puerto 5433,
igual que este overlay: antes de `podman kube play` hay que bajarlo con `./run.sh infra down`.

Apagar: `kubectl kustomize overlays/podman | podman kube down -` (agregar `--force` para borrar
también los volúmenes) y `podman kube down secrets.yaml`.

## OpenShift (Developer Sandbox) y ROSA

El Developer Sandbox es un clúster OpenShift; `overlays/openshift` y `overlays/rosa` usan el mismo
YAML y solo difieren en réplicas, recursos y valores de `ConfigMap`. Las imágenes se suben al
registro interno del proyecto y se resuelven por ImageStream.

```bash
oc login --token=<token> --server=<api-del-sandbox>

# 1. la misma imagen que corrió en la laptop
REGISTRY=$(oc registry info --public)
oc whoami -t | podman login -u "$(oc whoami)" --password-stdin "$REGISTRY"
for svc in orders-service inventory-service; do
  podman tag  localhost/$svc:1.0.0 "$REGISTRY/$(oc project -q)/$svc:1.0.0"
  podman push "$REGISTRY/$(oc project -q)/$svc:1.0.0"
done
oc set image-lookup orders-service inventory-service   # los Deployment resuelven "orders-service:1.0.0"

# 2. secretos y aplicación
oc apply -f secrets.yaml
oc apply -k overlays/openshift          # o: oc apply -k overlays/rosa
oc rollout status deploy/orders-service deploy/inventory-service

# 3. probar
ORDERS=https://$(oc get route orders-service -o jsonpath='{.spec.host}')
INVENTORY=https://$(oc get route inventory-service -o jsonpath='{.spec.host}')
curl -X PUT "$INVENTORY/api/v1/stock/SKU-1" -H 'Content-Type: application/json' -d '{"available":5}'
curl -i -X POST "$ORDERS/api/v1/orders" -H 'Content-Type: application/json' \
  -d '{"customerId":"customer-1","lines":[{"sku":"SKU-1","quantity":2}]}'
```

Estado de verificación: los tres overlays se validaron con `kustomize build`. El flujo completo en
Podman y el despliegue en el Sandbox todavía no se han ejecutado de punta a punta.

## Qué cambia en cada destino

| | `podman` | `openshift` | `rosa` |
|---|---|---|---|
| Imagen | `localhost/<svc>:1.0.0` | `<svc>:1.0.0` (ImageStream) | `<svc>:1.0.0` (ImageStream) |
| Réplicas | 1 | 1 | 2 |
| Recursos | sin límites (cgroups de Podman rootless) | base | más memoria y CPU |
| `ConfigMap` | hosts `<deployment>-pod`, `LOG_JSON=false` | base | `OUTBOX_BATCH_SIZE=200` |
| Borde | `hostPort` 8080 / 8081 (servicios) y 5432 / 5433 (bases, para DBeaver o `psql`) | `Route` (TLS edge, solo `/api`) | `Route` (TLS edge, solo `/api`) |
| `Secret` | `podman kube play secrets.yaml` | `oc apply -f secrets.yaml` | `oc apply -f secrets.yaml` |

## Variables de entorno

| Variable | Obligatoria | Dónde se define |
|---|---|---|
| `DB_USERNAME`, `DB_PASSWORD` | sí | `Secret` `<svc>-secrets` (`secrets.yaml`, fuera de git) |
| `KAFKA_SASL_JAAS_CONFIG` | no | mismo `Secret`, solo si el Kafka exige SASL |
| `DB_URL`, `KAFKA_BOOTSTRAP_SERVERS` | sí | `ConfigMap` `<svc>-config` (base; el overlay `podman` cambia los hosts) |
| `KAFKA_SECURITY_PROTOCOL`, `*_TOPIC`, `LOG_JSON`, `LOG_LEVEL`, `OUTBOX_*`, `DB_SCHEMA` | no | `ConfigMap` `<svc>-config` |
| `KAFKA_ADVERTISED_LISTENERS` | sí (Kafka de `platform/`) | `ConfigMap` `kafka-config` |

## Documentación

- [ADRs](docs/adr/README.md)
- Contrato de eventos: `docs/events.md` en cada backend
