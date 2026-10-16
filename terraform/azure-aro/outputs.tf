output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = azurerm_redhat_openshift_cluster.this.name
}

output "cluster_console_url" {
  value = azurerm_redhat_openshift_cluster.this.console_url
}

output "cluster_api_url" {
  value = azurerm_redhat_openshift_cluster.this.api_server_profile[0].url
}

output "oc_login_hint" {
  description = "Las credenciales de kubeadmin no las expone Terraform: se piden a Azure."
  value       = "az aro list-credentials -g ${azurerm_resource_group.this.name} -n ${var.cluster_name}"
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "acr_admin_username" {
  value = azurerm_container_registry.this.admin_username
}

output "acr_admin_password" {
  value     = azurerm_container_registry.this.admin_password
  sensitive = true
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "db_name" {
  value = var.db_name
}

output "db_username" {
  value = var.db_username
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}

output "eventhubs_namespace" {
  value = azurerm_eventhub_namespace.this.name
}

output "eventhubs_bootstrap" {
  value = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net:9093"
}

output "eventhubs_connection_string" {
  description = "Va como contraseña del usuario literal $ConnectionString (SASL PLAIN)."
  value       = azurerm_eventhub_namespace_authorization_rule.app.primary_connection_string
  sensitive   = true
}

# Valores para overlays/aro-azure (config-values.yaml y kustomization.yaml).
output "overlay_values" {
  description = "Valores para sustituir los <...> de overlays/aro-azure."
  value = {
    ACR_NAME            = azurerm_container_registry.this.name
    PG_SERVER           = azurerm_postgresql_flexible_server.this.name
    DB_NAME             = var.db_name
    EVENTHUBS_NAMESPACE = azurerm_eventhub_namespace.this.name
  }
}
