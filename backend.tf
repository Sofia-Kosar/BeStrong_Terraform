terraform {
  backend "azurerm" {
    resource_group_name  = "rg-bestrong-tfstate"
    storage_account_name = "stbestrongtfstate001"
    container_name       = "tfstate"
    key                  = "bestrong-infra.tfstate"

  }
}