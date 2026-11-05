targetScope = 'resourceGroup'

extension microsoftGraphV1

@description('Environment of the already-deployed Contoso Orders stack.')
@allowed([
  'dev'
  'prod'
])
param environmentName string

@description('Workload name. Must match main.bicep.')
@minLength(3)
@maxLength(12)
param appName string = 'orders'

@description('Storage account and Key Vault names from main.bicep dataServices output.')
param dataServices {
  storageAccountName: string
  keyVaultName: string
}

@description('System-assigned managed identity object ID from main.bicep webPrincipalId output.')
@minLength(36)
@maxLength(36)
param webPrincipalId string

var suffix = '${appName}-${environmentName}'
var identityKey = uniqueString(tenant().tenantId, resourceGroup().id, appName, environmentName)

resource dataAccessGroup 'Microsoft.Graph/groups@v1.0' = {
  uniqueName: 'orders-data-${identityKey}'
  displayName: 'sg-${suffix}-data'
  mailNickname: 'orders-data-${identityKey}'
  mailEnabled: false
  securityEnabled: true
}

resource githubApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'orders-github-${identityKey}'
  displayName: 'app-${suffix}-github'
  signInAudience: 'AzureADMyOrg'

  resource githubCredential 'federatedIdentityCredentials' = {
    name: 'github-${environmentName}'
    description: 'GitHub Actions ${environmentName} environment for sydneyhsmith/ignite2026-demo.'
    issuer: 'https://token.actions.githubusercontent.com'
    audiences: [
      'api://AzureADTokenExchange'
    ]
    subject: 'repo:sydneyhsmith/ignite2026-demo:environment:${environmentName}'
  }
}

resource githubPrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: githubApp.appId
  accountEnabled: true
}

module githubContributor 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  params: {
    principalId: githubPrincipal.id
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: 'Contributor'
    enableTelemetry: false
  }
}

// The module boundary makes Graph's runtime object ID available for RBAC names.
module dataAccess 'data-access.bicep' = {
  params: {
    dataServices: dataServices
    webPrincipalId: webPrincipalId
    securityGroupId: dataAccessGroup.id
  }
}

@description('Non-secret IDs for configuring GitHub Actions and managing group membership.')
output identities {
  tenantId: string
  clientId: string
  servicePrincipalId: string
  securityGroupId: string
} = {
  tenantId: tenant().tenantId
  clientId: githubApp.appId
  servicePrincipalId: githubPrincipal.id
  securityGroupId: dataAccessGroup.id
}
