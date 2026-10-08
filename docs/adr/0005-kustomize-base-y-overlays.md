# ADR-0005: Kustomize con una base, overlays mínimos y plataforma reutilizable

- Estado: Aceptado
- Fecha: 2026-10-03

## Contexto

"En mi máquina funciona" aparece cuando cada entorno tiene su propio YAML. Queremos un solo YAML y
diferencias pequeñas, explícitas y revisables.

## Decisión

- `base/`: `Deployment`, `Service` y `ConfigMap` de los dos servicios.
- `platform/`: PostgreSQL por servicio y Kafka de un nodo (KRaft), para destinos sin servicios
  administrados (laptop y Developer Sandbox). Un destino con base de datos y Kafka administrados
  simplemente no lo incluye.
- `overlays/<destino>/` solo puede cambiar: imagen y tag, réplicas, recursos y valores de
  `ConfigMap`. Nada más se parchea.
- Lo que es propio de la plataforma se **agrega** como recurso de borde, sin tocar la base:
  `components/openshift-route` (dos `Route`) y `components/openshift-imagestream` (dos `ImageStream`
  con `lookupPolicy.local`, para resolver `<svc>:<tag>` contra el registro interno) en `openshift` y
  `rosa`; `components/openshift-build-s2i` (dos `BuildConfig` sin triggers que compilan desde GitHub
  en modo JVM hacia el mismo `ImageStreamTag`) solo en `openshift`, para el Sandbox donde no se
  sube la imagen nativa desde la laptop.
- `sandbox/` contiene la salida de `overlays/openshift` dividida por paso (`sandbox/render.py`),
  para pegar en la consola web; se regenera, no se edita. En Podman el borde es
  `--publish` del propio `podman kube play`.
- En Podman el overlay quita `resources`: el Podman rootless (por ejemplo sobre WSL) puede no tener
  delegados los controladores de cgroups y falla al aplicar límites. Es un cambio de recursos, que
  es una de las cuatro cosas permitidas.

## Alternativas

- Helm: más potente, pero las plantillas ocultan qué cambia entre entornos.
- `podman-compose`: no se reutiliza en OpenShift. `podman kube play` consume el mismo YAML.

## Consecuencias

- `git diff overlays/` muestra exactamente en qué difieren los entornos.
- En Podman los nombres DNS son `<deployment>-pod`; por eso las URLs del `ConfigMap` cambian en ese
  overlay. Es un valor, no estructura.
