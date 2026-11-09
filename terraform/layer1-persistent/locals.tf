locals {
  tags = {
    environment = var.environment
    layer       = "persistent"
    managed_by  = "terraform"
    project     = "${var.prefix}-experimental"
    cost_center = var.cost_center
  }
}
