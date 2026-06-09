terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "azurerm" {
  features {}
}

# ─── Resource Group ─────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "demo" {
  name     = "2605260050001177"
  location = "northeurope"

  tags = {
    environment = "demo"
    project     = "kerberos-lab"
  }
}

# ─── North Europe VNET ──────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "ne" {
  name                = "DEMO-VNET-NorthEurope"
  location            = "northeurope"
  resource_group_name = azurerm_resource_group.demo.name
  address_space       = ["10.1.0.0/16"]
  tags                = { environment = "demo" }
}

resource "azurerm_subnet" "ne_default" {
  name                 = "DEMO-SUBNET-NorthEurope"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.ne.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "ne_gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.ne.name
  address_prefixes     = ["10.1.255.0/27"]
}

# ─── East US VNET ───────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "us" {
  name                = "DEMO-VNET-EastUS"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name
  address_space       = ["10.2.0.0/16"]
  tags                = { environment = "demo" }
}

resource "azurerm_subnet" "us_default" {
  name                 = "DEMO-SUBNET-EastUS"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.us.name
  address_prefixes     = ["10.2.1.0/24"]
}

resource "azurerm_subnet" "us_gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.us.name
  address_prefixes     = ["10.2.255.0/27"]
}

resource "azurerm_subnet" "us_bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.demo.name
  virtual_network_name = azurerm_virtual_network.us.name
  address_prefixes     = ["10.2.254.0/27"]
}

# ─── Network Security Groups ────────────────────────────────────────────────────

resource "azurerm_network_security_group" "ne" {
  name                = "DEMO-NSG-NorthEurope"
  location            = "northeurope"
  resource_group_name = azurerm_resource_group.demo.name

  # Allow AD/DC traffic from US subnet
  security_rule {
    name                       = "AllowADFromUS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.2.0.0/16"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "us" {
  name                = "DEMO-NSG-EastUS"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name

  # Allow AD/DC traffic from NE subnet
  security_rule {
    name                       = "AllowADFromNE"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.1.0.0/16"
    destination_address_prefix = "*"
  }

  # Allow inbound from VirtualNetwork (Bastion RDP)
  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "ne" {
  subnet_id                 = azurerm_subnet.ne_default.id
  network_security_group_id = azurerm_network_security_group.ne.id
}

resource "azurerm_subnet_network_security_group_association" "us" {
  subnet_id                 = azurerm_subnet.us_default.id
  network_security_group_id = azurerm_network_security_group.us.id
}

# ─── VPN Gateways — Public IPs ──────────────────────────────────────────────────

resource "azurerm_public_ip" "ne_vpn" {
  name                = "DEMO-PIP-VNG-NorthEurope"
  location            = "northeurope"
  resource_group_name = azurerm_resource_group.demo.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "us_vpn" {
  name                = "DEMO-PIP-VNG-EastUS"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ─── Virtual Network Gateways ───────────────────────────────────────────────────
# NOTE: VPN Gateway deployment takes ~30-45 minutes each

resource "azurerm_virtual_network_gateway" "ne" {
  name                = "DEMO-VNG-NorthEurope"
  location            = "northeurope"
  resource_group_name = azurerm_resource_group.demo.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
  active_active       = false
  enable_bgp          = false

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.ne_vpn.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.ne_gateway.id
  }
}

resource "azurerm_virtual_network_gateway" "us" {
  name                = "DEMO-VNG-EastUS"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
  active_active       = false
  enable_bgp          = false

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.us_vpn.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.us_gateway.id
  }
}

# ─── Local Network Gateways ─────────────────────────────────────────────────────

resource "azurerm_local_network_gateway" "ne_sees_us" {
  name                = "DEMO-LNG-NE-sees-EastUS"
  location            = "northeurope"
  resource_group_name = azurerm_resource_group.demo.name
  gateway_address     = azurerm_public_ip.us_vpn.ip_address
  address_space       = ["10.2.0.0/16"]
}

resource "azurerm_local_network_gateway" "us_sees_ne" {
  name                = "DEMO-LNG-US-sees-NorthEurope"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name
  gateway_address     = azurerm_public_ip.ne_vpn.ip_address
  address_space       = ["10.1.0.0/16"]
}

# ─── S2S VPN Connections ────────────────────────────────────────────────────────

resource "azurerm_virtual_network_gateway_connection" "ne_to_us" {
  name                       = "DEMO-CONN-NorthEurope-to-EastUS"
  location                   = "northeurope"
  resource_group_name        = azurerm_resource_group.demo.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.ne.id
  local_network_gateway_id   = azurerm_local_network_gateway.ne_sees_us.id
  shared_key                 = var.vpn_shared_key
}

resource "azurerm_virtual_network_gateway_connection" "us_to_ne" {
  name                       = "DEMO-CONN-EastUS-to-NorthEurope"
  location                   = "eastus"
  resource_group_name        = azurerm_resource_group.demo.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.us.id
  local_network_gateway_id   = azurerm_local_network_gateway.us_sees_ne.id
  shared_key                 = var.vpn_shared_key
}

# ─── Azure Bastion (Standard SKU) ───────────────────────────────────────────────

resource "azurerm_public_ip" "bastion" {
  name                = "DEMO-PIP-BASTION-EastUS"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "demo" {
  name                = "DEMO-BASTION-EastUS"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name
  sku                 = "Standard"

  # Kerberos authentication support — required for this lab
  kerberos_enabled = true

  ip_configuration {
    name                 = "DEMO-BASTION-IPConfig"
    subnet_id            = azurerm_subnet.us_bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

# ─── NICs ───────────────────────────────────────────────────────────────────────

resource "azurerm_network_interface" "ne_dc" {
  name                = "DEMO-NIC-DC-NorthEurope"
  location            = "northeurope"
  resource_group_name = azurerm_resource_group.demo.name

  # Static IP so domain members can reliably target this DC
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.ne_default.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.4"
  }
}

resource "azurerm_network_interface" "us_dc" {
  name                = "DEMO-NIC-DC-EastUS"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name

  # Static IP so domain members can reliably target this DC
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.us_default.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.2.1.5"
  }
}

resource "azurerm_network_interface" "us_client" {
  name                = "DEMO-NIC-CLIENT-EastUS"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name

  # Point DNS at the US DC (which forwards to NE DC; SRV for Kerberos points to NE)
  dns_servers = ["10.2.1.5", "10.1.1.4"]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.us_default.id
    private_ip_address_allocation = "Dynamic"
  }
}

# ─── Windows Server 2022 VMs ────────────────────────────────────────────────────

resource "azurerm_windows_virtual_machine" "ne_dc" {
  name                = "DEMO-DC-NE"
  location            = "northeurope"
  resource_group_name = azurerm_resource_group.demo.name
  size                = "Standard_D2s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.ne_dc.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  tags = { role = "primary-dc", region = "northeurope" }
}

resource "azurerm_windows_virtual_machine" "us_dc" {
  name                = "DEMO-DC-US"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name
  size                = "Standard_D2s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.us_dc.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  # Secondary DC depends on VPN being established so it can reach the primary
  depends_on = [
    azurerm_virtual_network_gateway_connection.ne_to_us,
    azurerm_virtual_network_gateway_connection.us_to_ne,
  ]

  tags = { role = "secondary-dc", region = "eastus" }
}

resource "azurerm_windows_virtual_machine" "us_client" {
  name                = "DEMO-CLIENT-US"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.demo.name
  size                = "Standard_B2s"
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.us_client.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  depends_on = [
    azurerm_virtual_network_gateway_connection.ne_to_us,
    azurerm_virtual_network_gateway_connection.us_to_ne,
  ]

  tags = { role = "client", region = "eastus" }
}

# ─── NOTE: AD DS Setup ──────────────────────────────────────────────────────────
# DC promotion requires VM reboots mid-process which causes Custom Script
# Extensions to fail. AD DS setup must be run MANUALLY via Bastion after
# infrastructure is deployed, using the scripts in the scripts/ folder:
#
#   1. Connect to DEMO-DC-NE via Bastion → run scripts\01-setup-primary-dc.ps1
#   2. After reboot, connect to DEMO-DC-US via Bastion → run scripts\02-setup-secondary-dc.ps1
#   3. After reboot, connect to DEMO-CLIENT-US via Bastion → run scripts\03-join-domain.ps1
# ────────────────────────────────────────────────────────────────────────────────
