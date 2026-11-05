targetScope = 'resourceGroup'

@description('Names of the existing data services in this resource group.')
param dataServices {
  storageAccountName: string
  keyVaultName: string
}

@description('Object ID of the web app managed identity.')
param webPrincipalId string

@description('Object ID of the Entra security group.')
param securityGroupId string

resource storage 'Microsoft.Storage/storageAccounts@2025-01-01' existing = {
  name: dataServices.storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: dataServices.keyVaultName
}

var principals = [
  {
    id: webPrincipalId
    type: 'ServicePrincipal'
  }
  {
    id: securityGroupId
    type: 'Group'
  }
]
var blobContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var secretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

// Standalone AVM RBAC modules do not support resource-level scopes.
resource blobContributors 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principal in principals: {
  name: guid(storage.id, principal.id, blobContributorRoleId)
  scope: storage
  properties: {
    roleDefinitionId: blobContributorRoleId
    principalId: principal.id
    principalType: principal.type
  }
}]

resource secretsUsers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principal in principals: {
  name: guid(keyVault.id, principal.id, secretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: secretsUserRoleId
    principalId: principal.id
    principalType: principal.type
  }
}]
