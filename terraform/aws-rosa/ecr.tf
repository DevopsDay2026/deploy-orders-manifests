# Un repositorio por servicio. La imagen nativa se publica con: podman push <registro>/<servicio>:1.0.0
resource "aws_ecr_repository" "service" {
  for_each = toset(["orders-service", "inventory-service"])

  name                 = each.key
  image_tag_mutability = "MUTABLE"
  force_delete         = !var.protect_data

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}
