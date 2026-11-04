// =====================================================================
// Contoso Orders - Entra ID objects (Microsoft Graph Bicep extension)
// Deployed as a regular deployment BEFORE the stack: Graph resources can't be
// snapshotted and validated, so they live apart from main.bicep.
// uniqueName makes these idempotent: Graph uses POST, ARM uses PUT.
// Do NOT use @nullIfNotFound() or `existing` on Entra resources.
// =====================================================================

targetScope = 'resourceGroup'

extension microsoftGraphV1

@description('Short environment name used in names.')
@allowed([
  'dev'
  'prod'
])
param environmentName string

@description('Workload name used in names.')
@minLength(3)
@maxLength(12)
param appName string = 'orders'

@description('GitHub account or organization that owns the app team\'s orders-api repository.')
param githubOwner string

var suffix = '${appName}-${environmentName}'

// Members of this group are granted Storage Blob Data Reader in main.bicep.
resource blobReaders 'Microsoft.Graph/groups@v1.0' = {
  uniqueName: 'sg-${suffix}-blob-readers'
  displayName: 'sg-${suffix}-blob-readers'
  description: 'Read access to the ${suffix} blob storage data'
  mailEnabled: false
  mailNickname: 'sg-${suffix}-blob-readers'
  securityEnabled: true
}

resource ordersApi 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'app-${suffix}-orders-api'
  displayName: 'app-${suffix}-orders-api'
  signInAudience: 'AzureADMyOrg'

  // GitHub OIDC: the app team's repo signs in as this app, with no secrets.
  resource githubMain 'federatedIdentityCredentials@v1.0' = {
    name: '${ordersApi.uniqueName}/github-main'
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOwner}/orders-api:ref:refs/heads/main'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

resource ordersApiSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: ordersApi.appId
}

// Passed to main.bicep as BLOB_READER_GROUP_ID and ORDERS_API_SP_ID.
output blobReaderGroupObjectId string = blobReaders.id
output ordersApiClientId string = ordersApi.appId
output ordersApiServicePrincipalObjectId string = ordersApiSp.id
