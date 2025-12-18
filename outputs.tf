output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "web_app_name" {
  value = var.enable_app_service ? azurerm_linux_web_app.app[0].name : null
}

output "sql_server_fqdn" {
  value = "${azurerm_mssql_server.sql.name}.database.windows.net"
}

output "files_mount_path" {
  value = "/mounts/uploads"
}
