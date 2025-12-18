locals {
  name = "${var.project}-${var.env}"
  tags = merge({
    project = var.project
    env     = var.env
  }, var.tags)
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

data "azurerm_client_config" "current" {}