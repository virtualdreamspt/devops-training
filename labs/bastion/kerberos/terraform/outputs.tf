output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.demo.name
}

output "ne_vnet_id" {
  description = "North Europe VNET ID"
  value       = azurerm_virtual_network.ne.id
}

output "us_vnet_id" {
  description = "East US VNET ID"
  value       = azurerm_virtual_network.us.id
}

output "ne_vpn_public_ip" {
  description = "Public IP of the North Europe VPN Gateway"
  value       = azurerm_public_ip.ne_vpn.ip_address
}

output "us_vpn_public_ip" {
  description = "Public IP of the East US VPN Gateway"
  value       = azurerm_public_ip.us_vpn.ip_address
}

output "bastion_public_ip" {
  description = "Public IP of the Azure Bastion"
  value       = azurerm_public_ip.bastion.ip_address
}

output "primary_dc_private_ip" {
  description = "Private IP of the Primary DC (North Europe) — KDC target"
  value       = azurerm_network_interface.ne_dc.private_ip_address
}

output "secondary_dc_private_ip" {
  description = "Private IP of the Secondary DC (East US)"
  value       = azurerm_network_interface.us_dc.private_ip_address
}

output "client_vm_private_ip" {
  description = "Private IP of the domain-joined client VM (East US)"
  value       = azurerm_network_interface.us_client.private_ip_address
}

output "domain_name" {
  description = "Active Directory domain name"
  value       = var.domain_name
}

output "kerberos_test_hint" {
  description = "How to verify Kerberos is hitting the North Europe KDC"
  value       = "On DEMO-CLIENT-US, run: klist  — after logging in as demo-user@${var.domain_name}. The KDC entry should show 10.1.1.4 (DEMO-DC-NE)."
}
