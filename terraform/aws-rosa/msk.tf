# Kafka administrado (Amazon MSK) con autenticación SASL/SCRAM sobre TLS (puerto 9096).
# La autenticación IAM de MSK requiere la librería aws-msk-iam-auth en los servicios, que no está incluida.

resource "aws_kms_key" "msk_secret" {
  description         = "CMK del secreto SCRAM de MSK (el secreto debe usar una clave propia, no la de AWS)"
  enable_key_rotation = true
}

resource "random_password" "msk" {
  length  = 24
  special = false
}

# El nombre DEBE empezar con "AmazonMSK_" para que MSK pueda asociarlo.
resource "aws_secretsmanager_secret" "msk" {
  name                    = "AmazonMSK_${var.cluster_name}_scram"
  kms_key_id              = aws_kms_key.msk_secret.arn
  recovery_window_in_days = var.protect_data ? 7 : 0
}

resource "aws_secretsmanager_secret_version" "msk" {
  secret_id = aws_secretsmanager_secret.msk.id
  secret_string = jsonencode({
    username = var.kafka_username
    password = random_password.msk.result
  })
}

resource "aws_secretsmanager_secret_policy" "msk" {
  secret_arn = aws_secretsmanager_secret.msk.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AWSKafkaResourcePolicy"
      Effect    = "Allow"
      Principal = { Service = "kafka.amazonaws.com" }
      Action    = "secretsmanager:getSecretValue"
      Resource  = aws_secretsmanager_secret.msk.arn
    }]
  })
}

resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-msk"
  description = "Kafka SASL/SCRAM desde la VPC (workers de ROSA)"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "msk_scram_from_vpc" {
  security_group_id = aws_security_group.msk.id
  description       = "Kafka SASL/SCRAM (TLS) desde la VPC"
  cidr_ipv4         = module.vpc.cidr_block
  ip_protocol       = "tcp"
  from_port         = 9096
  to_port           = 9096
}

resource "aws_msk_configuration" "this" {
  name           = "${var.cluster_name}-config"
  kafka_versions = [var.kafka_version]

  # MSK trae auto.create.topics.enable=false. Con true, orders.placed / inventory.reserved / inventory.rejected
  # se crean al primer uso; con false hay que crearlos a mano (kafka-topics.sh).
  server_properties = <<-EOT
    auto.create.topics.enable = ${var.kafka_auto_create_topics}
    default.replication.factor = 3
    min.insync.replicas = 2
    num.partitions = 3
  EOT
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.kafka_broker_count

  broker_node_group_info {
    instance_type   = var.kafka_instance_type
    client_subnets  = module.vpc.private_subnets
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
  }

  client_authentication {
    sasl {
      scram = true
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }
}

resource "aws_msk_scram_secret_association" "this" {
  cluster_arn     = aws_msk_cluster.this.arn
  secret_arn_list = [aws_secretsmanager_secret.msk.arn]

  depends_on = [
    aws_secretsmanager_secret_version.msk,
    aws_secretsmanager_secret_policy.msk,
  ]
}
