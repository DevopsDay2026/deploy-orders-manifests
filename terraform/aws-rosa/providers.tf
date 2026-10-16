provider "aws" {
  region = var.region

  default_tags {
    tags = merge({
      app        = "orders-app"
      managed-by = "terraform"
      cluster    = var.cluster_name
    }, var.tags)
  }
}

# Sin token explícito, el proveedor lee la variable de entorno RHCS_TOKEN.
# Token: https://console.redhat.com/openshift/token/rosa
provider "rhcs" {
  token = var.rhcs_token
}
