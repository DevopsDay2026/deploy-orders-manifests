# Architecture Decision Records

| ADR | Decisión | Estado |
|---|---|---|
| [0001](0001-arquitectura-hexagonal.md) | Los manifiestos tratan a los servicios hexagonales como cajas configuradas por entorno | Aceptado |
| [0002](0002-outbox-y-consumidores-idempotentes.md) | Kafka *at-least-once*: qué exige el outbox al despliegue | Aceptado |
| [0003](0003-secretos-por-variables-de-entorno.md) | ConfigMap + Secret por `envFrom`; ningún secreto en el repositorio | Aceptado |
| [0004](0004-nativo-en-podman-con-mandrel.md) | Una sola imagen nativa para todos los destinos | Aceptado |
| [0005](0005-kustomize-base-y-overlays.md) | Kustomize: una base, overlays mínimos y plataforma reutilizable | Aceptado |
