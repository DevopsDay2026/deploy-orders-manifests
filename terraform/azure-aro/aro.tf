# Identidad con la que ARO administra los recursos de Azure (requiere permisos para crear aplicaciones en Entra ID).
resource "azuread_application" "aro" {
  display_name = "${var.cluster_name}-aro"
}

resource "azuread_service_principal" "aro" {
  client_id = azuread_application.aro.client_id
}

resource "azuread_service_principal_password" "aro" {
  service_principal_id = azuread_service_principal.aro.id
}

# Proveedor de recursos de ARO (identidad de Microsoft que opera el clúster).
data "azuread_service_principal" "aro_rp" {
  display_name = "Azure Red Hat OpenShift RP"
}

resource "azurerm_role_assignment" "aro_vnet_sp" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.aro.object_id
}

resource "azurerm_role_assignment" "aro_vnet_rp" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = data.azuread_service_principal.aro_rp.object_id
}

resource "azurerm_redhat_openshift_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  cluster_profile {
    domain      = var.cluster_name
    version     = var.aro_version
    pull_secret = var.pull_secret
  }

  network_profile {
    pod_cidr     = "10.128.0.0/14"
    service_cidr = "172.30.0.0/16"
  }

  main_profile {
    vm_size   = var.master_vm_size
    subnet_id = azurerm_subnet.master.id
  }

  worker_profile {
    vm_size      = var.worker_vm_size
    disk_size_gb = 128
    node_count   = var.worker_count
    subnet_id    = azurerm_subnet.worker.id
  }

  api_server_profile {
    visibility = var.api_visibility
  }

  ingress_profile {
    visibility = var.ingress_visibility
  }

  service_principal {
    client_id     = azuread_application.aro.client_id
    client_secret = azuread_service_principal_password.aro.value
  }

  depends_on = [
    azurerm_role_assignment.aro_vnet_sp,
    azurerm_role_assignment.aro_vnet_rp,
  ]
}
