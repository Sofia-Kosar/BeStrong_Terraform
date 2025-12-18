resource "azurerm_service_plan" "plan" {
  count               = var.enable_app_service ? 1 : 0
  name                = "asp-${local.name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  os_type  = "Linux"
  sku_name = "B1"

  tags = local.tags
}

resource "azurerm_linux_web_app" "app" {
  count               = var.enable_app_service ? 1 : 0
  name                = "app-${local.name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.plan[0].id

  identity { type = "SystemAssigned" }

  site_config {
    always_on = true

    application_stack {
      docker_image_name   = var.app_image
      docker_registry_url = "https://${azurerm_container_registry.acr.login_server}"
    }
  }

  app_settings = {
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.appi.connection_string
    "SQLSERVER_FQDN"                        = "${azurerm_mssql_server.sql.name}.database.windows.net"
    "SQLDB_NAME"                            = azurerm_mssql_database.db.name
  }

  storage_account {
    name         = "uploads"
    type         = "AzureFiles"
    account_name = azurerm_storage_account.st.name
    share_name   = azurerm_storage_share.files.name
    access_key   = azurerm_storage_account.st.primary_access_key
    mount_path   = "/mounts/uploads"
  }

  tags = local.tags
}

# Outbound into VNet
resource "azurerm_app_service_virtual_network_swift_connection" "vnet_integration" {
  count          = var.enable_app_service ? 1 : 0
  app_service_id = azurerm_linux_web_app.app[0].id
  subnet_id      = azurerm_subnet.snet_app.id
}

# Inbound private access to web app
resource "azurerm_private_endpoint" "pe_web" {
  count               = var.enable_app_service ? 1 : 0
  name                = "pe-web-${local.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.snet_pe.id

  private_service_connection {
    name                           = "psc-web-${local.name}"
    private_connection_resource_id = azurerm_linux_web_app.app[0].id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-web"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["web"].id]
  }

  tags = local.tags
}