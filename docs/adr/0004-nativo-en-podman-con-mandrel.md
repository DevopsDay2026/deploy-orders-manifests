# ADR-0004: Una sola imagen nativa para todos los destinos

- Estado: Aceptado
- Fecha: 2026-10-03

## Contexto

Cada backend compila su binario nativo con Mandrel dentro de Podman y lo empaqueta sobre
`ubi9-quarkus-micro-image` con usuario no root (ADR-0004 de cada backend).

## Decisión

- La imagen se construye una vez (`make image`) y se etiqueta para cada registro. Los overlays solo
  cambian nombre y tag con `images:`.
- Los `Deployment` exigen `runAsNonRoot`, sin escalada de privilegios y sin capabilities, compatible
  con el SCC `restricted` de OpenShift (UID arbitrario, grupo 0).
- Las imágenes de `platform/` (PostgreSQL de sclorg y Kafka de Strimzi) también funcionan con UID
  arbitrario.

## Consecuencias

Lo que se prueba en la laptop es, byte a byte, lo que corre en el clúster.
