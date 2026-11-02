output "fqdn" {
  description = "Public FQDN of the VM."
  value       = azurerm_public_ip.this.fqdn
}

output "public_ip" {
  description = "Public IP address."
  value       = azurerm_public_ip.this.ip_address
}

output "resource_group" {
  description = "Value for AZURE_RESOURCE_GROUP."
  value       = azurerm_resource_group.this.name
}

output "vm_name" {
  description = "Value for AZURE_VM_NAME."
  value       = azurerm_linux_virtual_machine.this.name
}

output "ssh_command" {
  description = "SSH into the VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.this.fqdn}"
}

output "smoke_url" {
  description = "Gateway health URL once deployed."
  value       = "http://${azurerm_public_ip.this.fqdn}:${var.gateway_port}/health"
}
