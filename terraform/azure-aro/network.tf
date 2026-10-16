locals {
  rg_name = coalesce(var.resource_group_name, "${var.cluster_name}-rg")
  tags = merge({
    app        = "orders-app"
    managed-by = "terraform"
    cluster    = var.cluster_name
  }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = local.rg_name
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = local.tags
}

# Subredes: nodos de control y workers de ARO (no admiten delegación) y la de PostgreSQL (delegada).
resource "azurerm_subnet" "master" {
  name                 = "master-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 3, 0)]
  service_endpoints    = ["Microsoft.ContainerRegistry"]

  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet" "worker" {
  name                 = "worker-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 3, 1)]
  service_endpoints    = ["Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "db" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 4)]

  delegation {
    name = "postgres"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
