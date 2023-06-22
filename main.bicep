// Parameters
//////////////////////////////////////////////////
@description('The name of the deployment environment.')
@allowed([
  'dev'
  'prod'
])
param environment string

@description('The location of all resources.')
param location string = resourceGroup().location

// Variables
//////////////////////////////////////////////////
var aksSubnetName = 'snet-${environment}-${location}-aks'
var aksSubnetPrefix = '10.0.0.0/24'
var networkSecurityGroupName = 'nsg-${environment}-${location}-redis'
var privateDnsZoneName = 'privatelink.redis.cache.windows.net'
var privateEndpointName = 'pe-${environment}-${location}-redis'
var privateEndpointNicName = 'nic-${environment}-${location}-redis'
var privateEndpointPrivateIpAddress = '10.0.1.4'
var privateEndpointSubnetPrefix = '10.0.1.0/24'
var redisCacheName = 'redis-${environment}-${location}'
var redisSubnetName = 'snet-${environment}-${location}-redis'
var virtualNetworkName = 'vnet-${environment}-${location}'
var virtualNetworkPrefix = '10.0.0.0/16'

// Resource - Network Security Group
//////////////////////////////////////////////////
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: []
  }
}

// Resource - Virtual Network
//////////////////////////////////////////////////
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-11-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkPrefix
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: aksSubnetPrefix
        }
      }
      {
        name: redisSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
  resource aksSubnet 'subnets' existing = {
    name: aksSubnetName
  }
  resource redisSubnet 'subnets' existing = {
    name: redisSubnetName
  }
}

// Resource - Private DNS Zone
//////////////////////////////////////////////////
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
}

// Resource - Virtual Network Link
//////////////////////////////////////////////////
resource virtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${virtualNetworkName}-link'
  location: 'global'
  properties: {
    registrationEnabled: true
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// Resource - Redis Cache
//////////////////////////////////////////////////
resource redisCache 'Microsoft.Cache/redis@2023-04-01' = {
  name: redisCacheName
  location: location
  properties: {
    sku: {
      name: 'Premium'
      family: 'P'
      capacity: 1
    }
    enableNonSslPort: false
    redisVersion: '6'
    replicasPerMaster: 3
    publicNetworkAccess: 'Disabled'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
}

// Resource - Private Endpoint
//////////////////////////////////////////////////
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2022-11-01' = {
  name: privateEndpointName
  location: location
  properties: {
    // This allows you to specify a name for the private endpoint network interface.
    customNetworkInterfaceName: privateEndpointNicName
    // This allows you to specify a static IP address for the private endpoint network interface.
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          groupId: 'redisCache'
          memberName: 'redisCache'
          privateIPAddress: privateEndpointPrivateIpAddress
        }
      }
    ]
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: redisCache.id
          groupIds: [
            'redisCache'
          ]
        }
      }
    ]
    subnet: {
      id: virtualNetwork::redisSubnet.id
    }
  }
}

// Resource - Private Endpoint DNS Zone Group
//////////////////////////////////////////////////
resource privateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-11-01' = {
  parent: privateEndpoint
  name: 'dnsgroupname'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}
