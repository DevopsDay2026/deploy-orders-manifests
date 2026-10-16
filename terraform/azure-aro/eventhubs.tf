# Kafka administrado: Event Hubs con su endpoint compatible con Kafka (<namespace>.servicebus.windows.net:9093).
# Es compatible con el protocolo, pero no es Kafka: verifica el comportamiento de productores y consumidores.

resource "azurerm_eventhub_namespace" "this" {
  name                = "${var.cluster_name}-eh-${random_string.suffix.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  sku      = "Standard"
  capacity = 1
}

# Cada tópico de Kafka es un event hub con el mismo nombre.
resource "azurerm_eventhub" "topic" {
  for_each = toset(var.eventhub_topics)

  name              = each.key
  namespace_id      = azurerm_eventhub_namespace.this.id
  partition_count   = 3
  message_retention = 1
}

# Credencial de los servicios: solo enviar y escuchar (sin administrar).
resource "azurerm_eventhub_namespace_authorization_rule" "app" {
  name                = "orders-app"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = azurerm_resource_group.this.name

  listen = true
  send   = true
  manage = false
}
