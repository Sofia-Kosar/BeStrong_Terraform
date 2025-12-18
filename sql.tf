resource "azurerm_mssql_server" "sql" {
  name                         = "sql-${local.name}-001"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password

  public_network_access_enabled = false
  tags                          = local.tags
}

resource "azurerm_mssql_database" "db" {
  name      = "bestrongdb"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "S0"
  tags      = local.tags
}

resource "azurerm_private_endpoint" "pe_sql" {
  name                = "pe-sql-${local.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.snet_pe.id

  private_service_connection {
    name                           = "psc-sql-${local.name}"
    private_connection_resource_id = azurerm_mssql_server.sql.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-sql"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["sql"].id]
  }

  tags = local.tags
}
