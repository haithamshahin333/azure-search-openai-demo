metadata description = 'Sets up private networking for all resources, using VNet, private endpoints, and DNS zones.'

@description('The name of the VNet to create')
param vnetName string

@description('The location to create the VNet and private endpoints')
param location string = resourceGroup().location

@description('The tags to apply to all resources')
param tags object = {}

@description('The name of an existing App Service Plan to connect to the VNet')
param appServicePlanName string

param usePrivateEndpoint bool = false

@allowed(['appservice', 'containerapps'])
param deploymentTarget string

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' existing = if (deploymentTarget == 'appservice') {
  name: appServicePlanName
}

module vnet './core/networking/vnet.bicep' = if (usePrivateEndpoint) {
  name: 'vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    subnets: [
      {
        name: 'backend-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'app-int-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              id: appServicePlan.id
              name: appServicePlan.name
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'vm-subnet'
        properties: {
          addressPrefix: '10.0.4.0/24'
        }
      }
      {
        name: 'apim-subnet'
        properties: {
          addressPrefix: '10.0.5.0/24'
        }
      }
      {
        name: 'aca-subnet'
        properties: {
          addressPrefix: '10.0.6.0/24'
        }
      }
    ]
  }
}


output vnetName string = usePrivateEndpoint ? vnet.outputs.name : ''


//return as outputs all the subnet IDs with the proper names - don't rely on the order of the subnet creation
output backendSubnetId string = vnet.outputs.vnetSubnets[0].id
output azureBastionSubnetId string = vnet.outputs.vnetSubnets[1].id
output appSubnetId string = vnet.outputs.vnetSubnets[2].id
output vmSubnetId string = vnet.outputs.vnetSubnets[3].id
output apimSubnetId string = vnet.outputs.vnetSubnets[4].id
output acaSubnetId string = vnet.outputs.vnetSubnets[5].id
