locals {
  private_dns_zones = {
    vault = "privatelink.vaultcore.azure.net"
    web   = "privatelink.azurewebsites.net"
    sql   = "privatelink.database.windows.net"
    file  = "privatelink.file.core.windows.net"
    acr   = "privatelink.azurecr.io"
  }
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = azurerm_private_dns_zone.zones
  name                  = "link-${each.key}-${local.name}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.tags
}
