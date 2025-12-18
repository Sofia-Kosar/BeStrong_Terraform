resource "azurerm_container_registry" "acr" {
  name                = "acr${replace(local.name, "-", "")}001"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku           = "Premium" # Private Endpoint needs Premium
  admin_enabled = false
  tags          = local.tags
}

resource "azurerm_private_endpoint" "pe_acr" {
  name                = "pe-acr-${local.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.snet_pe.id

  private_service_connection {
    name                           = "psc-acr-${local.name}"
    private_connection_resource_id = azurerm_container_registry.acr.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-acr"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["acr"].id]
  }

  tags = local.tags
}
