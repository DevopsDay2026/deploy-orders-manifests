# ADR-0001: Arquitectura hexagonal (vista desde el despliegue)

- Estado: Aceptado
- Fecha: 2026-10-03

## Contexto

Los dos backends son hexagonales: toda la infraestructura (PostgreSQL, Kafka, HTTP) entra por
adaptadores configurados con variables de entorno. El detalle está en el ADR-0001 de cada backend.

## Decisión

Los manifiestos no conocen el interior de los servicios. Cada servicio es un `Deployment` con un
puerto HTTP, tres probes (`/q/health/started`, `/live`, `/ready`) y dos fuentes de configuración
(`ConfigMap` y `Secret`). Cambiar de broker o de base de datos es cambiar valores, no YAML.

## Consecuencias

El mismo `Deployment` sirve en Podman, OpenShift y ROSA; los adaptadores de salida reciben el
destino real por variables.
