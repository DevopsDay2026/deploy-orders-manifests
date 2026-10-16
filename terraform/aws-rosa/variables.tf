variable "region" {
  description = "Región de AWS donde se crea todo."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Nombre del clúster ROSA; también prefija VPC, roles, RDS y MSK. Máximo 15 caracteres."
  type        = string
  default     = "orders-demo"

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,13}[a-z0-9]$", var.cluster_name))
    error_message = "Usa minúsculas, números y guiones; empieza con letra; entre 2 y 15 caracteres."
  }
}

variable "openshift_version" {
  description = "Versión de OpenShift para ROSA HCP. Consulta las disponibles con: rosa list versions --hosted-cp"
  type        = string
}

variable "rhcs_token" {
  description = "Token de OpenShift Cluster Manager. Si es null se usa la variable de entorno RHCS_TOKEN."
  type        = string
  default     = null
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones_count" {
  description = "Cantidad de zonas de disponibilidad (una subred pública y una privada por zona)."
  type        = number
  default     = 3
}

variable "replicas" {
  description = "Cantidad de nodos worker. En ROSA HCP debe ser múltiplo del número de zonas."
  type        = number
  default     = 3
}

variable "compute_machine_type" {
  description = "Tipo de instancia de los workers (x86_64: la imagen nativa se construye para x86_64)."
  type        = string
  default     = "m6i.xlarge"
}

# --- datos -------------------------------------------------------------------------
variable "db_name" {
  description = "Base de datos única; cada servicio usa su propio esquema (orders, inventory), ver ADR-0005."
  type        = string
  default     = "ordersapp"
}

variable "db_username" {
  description = "Usuario administrador de RDS. Para producción, un usuario por servicio con privilegios mínimos."
  type        = string
  default     = "orders_admin"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "kafka_version" {
  description = "Versión de Kafka en MSK. Consulta las vigentes con: aws kafka list-kafka-versions"
  type        = string
  default     = "3.8.x"
}

variable "kafka_instance_type" {
  type    = string
  default = "kafka.t3.small"
}

variable "kafka_broker_count" {
  description = "Debe ser múltiplo del número de zonas."
  type        = number
  default     = 3
}

variable "kafka_username" {
  description = "Usuario SASL/SCRAM que usan los servicios."
  type        = string
  default     = "orders"
}

variable "kafka_auto_create_topics" {
  description = "true: MSK crea los tópicos al primer uso (cómodo para la demo). false: créalos tú (recomendado en producción)."
  type        = bool
  default     = true
}

# --- ciclo de vida -----------------------------------------------------------------
variable "protect_data" {
  description = "true: RDS con protección contra borrado y snapshot final, ECR sin borrado forzado. Úsalo fuera de la demo."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Etiquetas adicionales para todos los recursos."
  type        = map(string)
  default     = {}
}
