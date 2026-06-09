// ============================================================
// demo-kerberos-lab — main.bicep
// Deploys: 2 VNETs, VPN Gateways (S2S), Bastion (Standard),
//          3 Windows Server 2022 VMs (Primary DC / Secondary DC / Client)
// Resource Group must be pre-created: 2605260050001177
// ============================================================

targetScope = 'resourceGroup'

// ─── Parameters ─────────────────────────────────────────────────────────────────

@description('Local admin username for all VMs')
param adminUsername string = 'demoadmin'

@description('Local admin password for all VMs')
@secure()
param adminPassword string

@description('Active Directory fully qualified domain name')
param domainName string = 'demo.local'

@description('Active Directory NetBIOS name')
param domainNetbios string = 'DEMO'

@description('DSRM safe mode password')
@secure()
param safeModePassword string

@description('Pre-shared key for the S2S VPN connection')
@secure()
param vpnSharedKey string

@description('Password for the demo-admin domain user')
@secure()
param domainAdminPassword string

@description('Password for the demo-user domain user')
@secure()
param domainUserPassword string

// ─── Variables ──────────────────────────────────────────────────────────────────

var tags = {
  environment: 'demo'
  project: 'kerberos-lab'
}

// ─── Network Security Groups ─────────────────────────────────────────────────────

resource nsgNE 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'DEMO-NSG-NorthEurope'
  location: 'northeurope'
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowADFromUS'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '10.2.0.0/16'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource nsgUS 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'DEMO-NSG-EastUS'
  location: 'eastus'
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowADFromNE'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '10.1.0.0/16'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowVnetInbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ─── North Europe VNET ──────────────────────────────────────────────────────────

resource vnetNE 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'DEMO-VNET-NorthEurope'
  location: 'northeurope'
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.1.0.0/16']
    }
    subnets: [
      {
        name: 'DEMO-SUBNET-NorthEurope'
        properties: {
          addressPrefix: '10.1.1.0/24'
          networkSecurityGroup: { id: nsgNE.id }
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.1.255.0/27'
        }
      }
    ]
  }
}

// ─── East US VNET ───────────────────────────────────────────────────────────────

resource vnetUS 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'DEMO-VNET-EastUS'
  location: 'eastus'
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.2.0.0/16']
    }
    subnets: [
      {
        name: 'DEMO-SUBNET-EastUS'
        properties: {
          addressPrefix: '10.2.1.0/24'
          networkSecurityGroup: { id: nsgUS.id }
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.2.255.0/27'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.2.254.0/27'
        }
      }
    ]
  }
}

// ─── Public IPs ──────────────────────────────────────────────────────────────────

resource pipVngNE 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'DEMO-PIP-VNG-NorthEurope'
  location: 'northeurope'
  sku: { name: 'Standard' }
  zones: ['1', '2', '3']
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource pipVngUS 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'DEMO-PIP-VNG-EastUS'
  location: 'eastus'
  sku: { name: 'Standard' }
  zones: ['1', '2', '3']
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource pipBastion 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'DEMO-PIP-BASTION-EastUS'
  location: 'eastus'
  sku: { name: 'Standard' }
  tags: tags
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ─── VPN Gateways ───────────────────────────────────────────────────────────────
// NOTE: Each gateway takes ~30-45 minutes to deploy

resource vngNE 'Microsoft.Network/virtualNetworkGateways@2023-05-01' = {
  name: 'DEMO-VNG-NorthEurope'
  location: 'northeurope'
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: { name: 'VpnGw1AZ', tier: 'VpnGw1AZ' }
    enableBgp: false
    activeActive: false
    ipConfigurations: [
      {
        name: 'vnetGatewayConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: pipVngNE.id }
          subnet: { id: '${vnetNE.id}/subnets/GatewaySubnet' }
        }
      }
    ]
  }
}

resource vngUS 'Microsoft.Network/virtualNetworkGateways@2023-05-01' = {
  name: 'DEMO-VNG-EastUS'
  location: 'eastus'
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: { name: 'VpnGw1AZ', tier: 'VpnGw1AZ' }
    enableBgp: false
    activeActive: false
    ipConfigurations: [
      {
        name: 'vnetGatewayConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: { id: pipVngUS.id }
          subnet: { id: '${vnetUS.id}/subnets/GatewaySubnet' }
        }
      }
    ]
  }
}

// ─── Local Network Gateways ──────────────────────────────────────────────────────

resource lngNEseesUS 'Microsoft.Network/localNetworkGateways@2023-05-01' = {
  name: 'DEMO-LNG-NE-sees-EastUS'
  location: 'northeurope'
  tags: tags
  properties: {
    gatewayIpAddress: pipVngUS.properties.ipAddress
    localNetworkAddressSpace: {
      addressPrefixes: ['10.2.0.0/16']
    }
  }
}

resource lngUSseesNE 'Microsoft.Network/localNetworkGateways@2023-05-01' = {
  name: 'DEMO-LNG-US-sees-NorthEurope'
  location: 'eastus'
  tags: tags
  properties: {
    gatewayIpAddress: pipVngNE.properties.ipAddress
    localNetworkAddressSpace: {
      addressPrefixes: ['10.1.0.0/16']
    }
  }
}

// ─── S2S VPN Connections ─────────────────────────────────────────────────────────

resource connNEtoUS 'Microsoft.Network/connections@2023-05-01' = {
  name: 'DEMO-CONN-NorthEurope-to-EastUS'
  location: 'northeurope'
  tags: tags
  properties: {
    connectionType: 'IPsec'
    virtualNetworkGateway1: { id: vngNE.id, properties: {} }
    localNetworkGateway2: { id: lngNEseesUS.id, properties: {} }
    sharedKey: vpnSharedKey
  }
}

resource connUStoNE 'Microsoft.Network/connections@2023-05-01' = {
  name: 'DEMO-CONN-EastUS-to-NorthEurope'
  location: 'eastus'
  tags: tags
  properties: {
    connectionType: 'IPsec'
    virtualNetworkGateway1: { id: vngUS.id, properties: {} }
    localNetworkGateway2: { id: lngUSseesNE.id, properties: {} }
    sharedKey: vpnSharedKey
  }
}

// ─── Azure Bastion (Standard) ────────────────────────────────────────────────────

resource bastion 'Microsoft.Network/bastionHosts@2023-05-01' = {
  name: 'DEMO-BASTION-EastUS'
  location: 'eastus'
  sku: { name: 'Standard' }
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'DEMO-BASTION-IPConfig'
        properties: {
          publicIPAddress: { id: pipBastion.id }
          subnet: { id: '${vnetUS.id}/subnets/AzureBastionSubnet' }
        }
      }
    ]
  }
}

// ─── Network Interfaces ──────────────────────────────────────────────────────────

resource nicDcNE 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'DEMO-NIC-DC-NorthEurope'
  location: 'northeurope'
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.1.1.4'
          subnet: { id: '${vnetNE.id}/subnets/DEMO-SUBNET-NorthEurope' }
        }
      }
    ]
  }
}

resource nicDcUS 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'DEMO-NIC-DC-EastUS'
  location: 'eastus'
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.2.1.5'
          subnet: { id: '${vnetUS.id}/subnets/DEMO-SUBNET-EastUS' }
        }
      }
    ]
    dnsSettings: {
      dnsServers: ['10.1.1.4']
    }
  }
}

resource nicClientUS 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'DEMO-NIC-CLIENT-EastUS'
  location: 'eastus'
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: '${vnetUS.id}/subnets/DEMO-SUBNET-EastUS' }
        }
      }
    ]
    dnsSettings: {
      dnsServers: ['10.2.1.5', '10.1.1.4']
    }
  }
}

// ─── Virtual Machines ────────────────────────────────────────────────────────────

resource vmDcNE 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'DEMO-DC-NE'
  location: 'northeurope'
  tags: union(tags, { role: 'primary-dc' })
  properties: {
    hardwareProfile: { vmSize: 'Standard_D2s_v3' }
    osProfile: {
      computerName: 'DEMO-DC-NE'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nicDcNE.id }]
    }
  }
}

resource vmDcUS 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'DEMO-DC-US'
  location: 'eastus'
  tags: union(tags, { role: 'secondary-dc' })
  dependsOn: [connNEtoUS, connUStoNE]
  properties: {
    hardwareProfile: { vmSize: 'Standard_D2s_v3' }
    osProfile: {
      computerName: 'DEMO-DC-US'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nicDcUS.id }]
    }
  }
}

resource vmClientUS 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: 'DEMO-CLIENT-US'
  location: 'eastus'
  tags: union(tags, { role: 'client' })
  dependsOn: [connNEtoUS, connUStoNE]
  properties: {
    hardwareProfile: { vmSize: 'Standard_B2s' }
    osProfile: {
      computerName: 'DEMO-CLIENT-US'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nicClientUS.id }]
    }
  }
}

// ─── Outputs ────────────────────────────────────────────────────────────────────

output primaryDcPrivateIp string = nicDcNE.properties.ipConfigurations[0].properties.privateIPAddress
output secondaryDcPrivateIp string = nicDcUS.properties.ipConfigurations[0].properties.privateIPAddress
output bastionPublicIp string = pipBastion.properties.ipAddress
output neVpnPublicIp string = pipVngNE.properties.ipAddress
output usVpnPublicIp string = pipVngUS.properties.ipAddress
output domainNameOut string = domainName
output kerberosTestHint string = 'On DEMO-CLIENT-US, run: klist — after logging in as demo-user@${domainName}. KDC should show 10.1.1.4 (DEMO-DC-NE).'
