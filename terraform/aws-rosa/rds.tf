# PostgreSQL 16 administrado (Amazon RDS) en las subredes privadas. Una sola base; Flyway crea el esquema
# de cada servicio (orders, inventory) al arrancar.

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "db" {
  name       = "${var.cluster_name}-db"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "db" {
  name        = "${var.cluster_name}-db"
  description = "PostgreSQL desde la VPC (workers de ROSA)"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_vpc" {
  security_group_id = aws_security_group.db.id
  description       = "PostgreSQL desde la VPC"
  cidr_ipv4         = module.vpc.cidr_block
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
}

resource "aws_db_instance" "orders" {
  identifier     = "${var.cluster_name}-pg"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  multi_az          = var.db_multi_az

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period   = 7
  deletion_protection       = var.protect_data
  skip_final_snapshot       = !var.protect_data
  final_snapshot_identifier = var.protect_data ? "${var.cluster_name}-pg-final" : null
}

# Las credenciales también quedan en Secrets Manager (para External Secrets u otros consumidores).
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.cluster_name}/orders-app/db"
  recovery_window_in_days = var.protect_data ? 7 : 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.orders.address
    dbname   = var.db_name
  })
}
