resource "azurerm_storage_account" "st" {
  name                     = "st${replace(local.name, "-", "")}001"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  public_network_access_enabled = false

  tags = local.tags
}

resource "azurerm_storage_share" "files" {
  name               = "uploads"
  storage_account_id = azurerm_storage_account.st.id
  quota              = 100
}

resource "azurerm_private_endpoint" "pe_file" {
  name                = "pe-file-${local.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.snet_pe.id

  private_service_connection {
    name                           = "psc-file-${local.name}"
    private_connection_resource_id = azurerm_storage_account.st.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-file"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["file"].id]
  }

  tags = local.tags
}
