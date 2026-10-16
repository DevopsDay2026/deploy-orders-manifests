data "aws_caller_identity" "current" {}

# VPC con subredes públicas (NLB, NAT) y privadas (workers, RDS, MSK), Internet Gateway y NAT.
module "vpc" {
  source  = "terraform-redhat/rosa-hcp/rhcs//modules/vpc"
  version = "~> 1.7"

  name_prefix              = var.cluster_name
  vpc_cidr                 = var.vpc_cidr
  availability_zones_count = var.availability_zones_count
}

# Contraseña del usuario cluster-admin de OpenShift (política de ROSA: 14+ caracteres, mayúsculas, minúsculas, números).
resource "random_password" "cluster_admin" {
  length      = 20
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

# Clúster ROSA con plano de control hospedado (HCP) y los roles de IAM/OIDC que necesita.
module "rosa_hcp" {
  source  = "terraform-redhat/rosa-hcp/rhcs"
  version = "~> 1.7"

  cluster_name      = var.cluster_name
  openshift_version = var.openshift_version

  machine_cidr           = module.vpc.cidr_block
  aws_subnet_ids         = concat(module.vpc.private_subnets, module.vpc.public_subnets)
  aws_availability_zones = module.vpc.availability_zones

  replicas             = var.replicas
  compute_machine_type = var.compute_machine_type

  create_account_roles  = true
  account_role_prefix   = var.cluster_name
  create_operator_roles = true
  operator_role_prefix  = var.cluster_name
  create_oidc           = true

  create_admin_user          = true
  admin_credentials_username = "cluster-admin"
  admin_credentials_password = random_password.cluster_admin.result

  wait_for_create_complete = true
}
