# Autenticación: az login (o las variables ARM_*). La suscripción se indica en var.subscription_id.
provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}

provider "azuread" {}
