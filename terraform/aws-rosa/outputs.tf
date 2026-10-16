output "region" {
  value = var.region
}

output "cluster_api_url" {
  value = module.rosa_hcp.cluster_api_url
}

output "cluster_console_url" {
  value = module.rosa_hcp.cluster_console_url
}

output "cluster_admin_username" {
  value = module.rosa_hcp.cluster_admin_username
}

output "cluster_admin_password" {
  value     = random_password.cluster_admin.result
  sensitive = true
}

output "oc_login" {
  description = "Comando de acceso (la contraseña: terraform output -raw cluster_admin_password)."
  value       = "oc login ${module.rosa_hcp.cluster_api_url} -u ${module.rosa_hcp.cluster_admin_username} -p \"$(terraform output -raw cluster_admin_password)\""
}

output "ecr_registry" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
}

output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.service : k => r.repository_url }
}

output "rds_endpoint" {
  value = aws_db_instance.orders.address
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

output "msk_bootstrap_brokers_scram" {
  value = aws_msk_cluster.this.bootstrap_brokers_sasl_scram
}

output "kafka_username" {
  value = var.kafka_username
}

output "kafka_password" {
  value     = random_password.msk.result
  sensitive = true
}

# Valores para overlays/rosa-aws (config-values.yaml y kustomization.yaml).
output "overlay_values" {
  description = "Valores para sustituir los <...> de overlays/rosa-aws."
  value = {
    ACCOUNT_ID          = data.aws_caller_identity.current.account_id
    REGION              = var.region
    RDS_ENDPOINT        = aws_db_instance.orders.address
    DB_NAME             = var.db_name
    MSK_BOOTSTRAP_SCRAM = aws_msk_cluster.this.bootstrap_brokers_sasl_scram
  }
}
