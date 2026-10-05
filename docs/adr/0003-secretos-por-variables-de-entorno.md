# ADR-0003: Secretos por variables de entorno

- Estado: Aceptado
- Fecha: 2026-10-03

## Contexto

La misma imagen y el mismo YAML deben correr en la laptop, en OpenShift y en ROSA. Lo único que
cambia son valores, y algunos son secretos.

## Decisión

- Cada servicio lee un `ConfigMap` (`<servicio>-config`) y un `Secret` (`<servicio>-secrets`) con
  `envFrom`. La base de datos de cada servicio lee su usuario y contraseña del mismo `Secret`.
- Los `Secret` **no forman parte de Kustomize ni del repositorio**. Se commitea
  `secrets.example.yaml` con placeholders; `secrets.yaml` está en `.gitignore` y se aplica aparte
  (`podman kube play secrets.yaml` / `oc apply -f secrets.yaml`).
- Ningún manifiesto lleva `value:` con credenciales.

## Consecuencias

- Si falta el `Secret`, el pod no arranca: el error es visible y temprano.
- En un clúster con operador de secretos (External Secrets, Vault) basta con que este cree un
  `Secret` con el mismo nombre; los `Deployment` no cambian.
