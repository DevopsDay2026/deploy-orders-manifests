# Registro de imágenes. El usuario admin es solo para la demo: en producción usa un token de ámbito limitado
# o una identidad administrada.
resource "azurerm_container_registry" "this" {
  name                = "ordersdemo${random_string.suffix.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  sku           = "Basic"
  admin_enabled = true
}
