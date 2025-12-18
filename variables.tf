variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "location" {
  type    = string
  default = "northeurope"
}

variable "project" {
  type    = string
  default = "bestrong"
}

variable "env" {
  type    = string
  default = "dev"

}

variable "sql_admin_login" {
  type      = string
  sensitive = true
}

variable "sql_admin_password" {
  type      = string
  sensitive = true

}

variable "app_image" {
  type        = string
  description = "Full image name, e.g. acrbestrongdev001.azurecr.io/backend:1.0.0"
}

variable "tags" {
  type    = map(string)
  default = {}

}

variable "enable_app_service" {
  type    = bool
  default = false
}
