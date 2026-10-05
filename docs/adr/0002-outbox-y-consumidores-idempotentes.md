# ADR-0002: Outbox y consumidores idempotentes (vista desde el despliegue)

- Estado: Aceptado
- Fecha: 2026-10-03

## Contexto

Los servicios publican con outbox y consumen de forma idempotente (ADR-0002 de cada backend).

## Decisión

- Se pueden escalar las réplicas de ambos servicios: el relay del outbox usa
  `FOR UPDATE SKIP LOCKED` y los consumidores comparten grupo, así que `replicas` es un valor libre
  del overlay.
- Los tópicos (`orders.placed`, `inventory.reserved`, `inventory.rejected` y sus `.dlq`) se crean
  solos en el Kafka de `platform/` (`auto.create.topics.enable`). Un Kafka administrado que no lo
  permita debe crearlos antes del despliegue.
- Los nombres de tópico viajan en el `ConfigMap`; deben coincidir en los dos servicios.

## Consecuencias

Reiniciar o duplicar pods no pierde ni duplica efectos de negocio.
