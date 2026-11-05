// Reusable data module: a private, Entra-only storage account with one blob container.
// Published as br:ghcr.io/<owner>/modules/orders-data:<version> by the publish-module workflow.

@description('Short name used to build the storage account name.')
@minLength(2)
@maxLength(12)
param name string

@description('Azure region.')
param location string = resourceGroup().location

@description('Name of the blob container to create.')
param containerName string = 'orders-data'

@description('Principal IDs that get Storage Blob Data Reader on the account.')
param readerPrincipalIds array = []

@description('Type of the principals in readerPrincipalIds.')
@allowed([
  'Group'
  'ServicePrincipal'
  'User'
])
param readerPrincipalType string = 'ServicePrincipal'

@description('Set to Disabled once a private endpoint is in place.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

param tags object = {}

var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('st${toLower(replace(name, '-', ''))}${uniqueString(resourceGroup().id, name)}', 24)
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    publicNetworkAccess: publicNetworkAccess
  }

  resource blobService 'blobServices' = {
    name: 'default'

    resource container 'containers' = {
      name: containerName
    }
  }
}

resource readers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for principalId in readerPrincipalIds: {
    name: guid(storage.id, principalId, storageBlobDataReaderRoleId)
    scope: storage
    properties: {
      principalId: principalId
      principalType: readerPrincipalType
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    }
  }
]

output storageAccountName string = storage.name
output storageAccountId string = storage.id
output blobEndpoint string = storage.properties.primaryEndpoints.blob
output containerName string = containerName
