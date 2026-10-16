variable "subscription_id" {
  description = "Id de la suscripción de Azure (az account show --query id -o tsv)."
  type        = string
}

variable "location" {
  description = "Región de Azure."
  type        = string
  default     = "eastus"
}

variable "cluster_name" {
  description = "Nombre del clúster ARO; también prefija el resto de los recursos."
  type        = string
  default     = "orders-demo"

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{1,18}[a-z0-9]$", var.cluster_name))
    error_message = "Usa minúsculas, números y guiones; empieza con letra; entre 3 y 20 caracteres."
  }
}

variable "resource_group_name" {
  description = "Grupo de recursos. Si es null se usa <cluster_name>-rg."
  type        = string
  default     = null
}

variable "vnet_cidr" {
  type    = string
  default = "10.0.0.0/20"
}

variable "master_vm_size" {
  description = "ARO exige un tamaño mínimo para los nodos de control."
  type        = string
  default     = "Standard_D8s_v5"
}

variable "worker_vm_size" {
  description = "Tamaño de los workers (x86_64: la imagen nativa se construye para x86_64)."
  type        = string
  default     = "Standard_D4s_v5"
}

variable "worker_count" {
  description = "ARO exige un mínimo de 3 workers."
  type        = number
  default     = 3

  validation {
    condition     = var.worker_count >= 3
    error_message = "ARO requiere al menos 3 workers."
  }
}

variable "aro_version" {
  description = "Versión de OpenShift. null = la predeterminada. Consulta: az aro get-versions -l <región>"
  type        = string
  default     = null
}

variable "pull_secret" {
  description = "Pull secret de Red Hat (https://console.redhat.com/openshift/install/pull-secret). Opcional: habilita los operadores de Red Hat."
  type        = string
  default     = null
  sensitive   = true
}

variable "api_visibility" {
  description = "Public o Private (API de OpenShift)."
  type        = string
  default     = "Public"
}

variable "ingress_visibility" {
  description = "Public o Private (router de OpenShift, es decir, las Route)."
  type        = string
  default     = "Public"
}

# --- datos -------------------------------------------------------------------------
variable "db_name" {
  description = "Base de datos única; cada servicio usa su propio esquema (orders, inventory), ver ADR-0005."
  type        = string
  default     = "ordersapp"
}

variable "db_username" {
  description = "Administrador de PostgreSQL. Para producción, un usuario por servicio con privilegios mínimos."
  type        = string
  default     = "orders_admin"
}

variable "db_sku_name" {
  type    = string
  default = "B_Standard_B2s"
}

variable "eventhub_topics" {
  description = "Cada tópico de Kafka es un event hub con el mismo nombre."
  type        = list(string)
  default     = ["orders.placed", "inventory.reserved", "inventory.rejected"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
