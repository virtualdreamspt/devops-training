// main.bicepparam
// Fill in all secure values before deploying.
// Deploy with:
//   az deployment group create \
//     --resource-group 2605260050001177 \
//     --template-file main.bicep \
//     --parameters main.bicepparam

using './main.bicep'

param adminUsername        = 'demoadmin'
param adminPassword        = 'REPLACE_WITH_STRONG_PASSWORD'

param domainName           = 'demo.local'
param domainNetbios        = 'DEMO'

param safeModePassword     = 'REPLACE_WITH_DSRM_PASSWORD'
param vpnSharedKey         = 'REPLACE_WITH_VPN_PSK'

param domainAdminPassword  = 'REPLACE_WITH_DOMAIN_ADMIN_PWD'
param domainUserPassword   = 'REPLACE_WITH_DOMAIN_USER_PWD'
