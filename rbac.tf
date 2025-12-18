resource "azurerm_role_assignment" "acr_pull" {
  count                = var.enable_app_service ? 1 : 0
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.app[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  count                = var.enable_app_service ? 1 : 0
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.app[0].identity[0].principal_id
}
