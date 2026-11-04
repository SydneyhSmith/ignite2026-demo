// =====================================================================
// Contoso Orders - AFTER the ticket
// Baseline + AVM storage + AVM Key Vault + Entra (Microsoft Graph).
// Deployed as a Deployment Stack per environment (dev, prod).
// =====================================================================

targetScope = 'resourceGroup'

extension microsoftGraphV1

@description('Short environment name used in resource names.')
@allowed([
  'dev'
  'prod'
])
param environmentName string

@description('Workload name used in resource names.')
@minLength(3)
@maxLength(12)
param appName string = 'orders'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Subscription that holds the platform team\'s shared Log Analytics workspace.')
param platformSubscriptionId string

@description('Resource group that holds the platform team\'s shared Log Analytics workspace.')
param platformResourceGroupName string

@description('Name of the platform team\'s shared Log Analytics workspace. It exists in prod, not in dev.')
param sharedLogAnalyticsName string

@description('Image used only on the very first deployment, when no image is running yet.')
param placeholderImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Optional image to deploy (a release). When omitted, the image currently running is kept.')
param webImage string?

@description('GitHub account or organization that owns the app team\'s orders-api repository.')
param githubOwner string

@description('Tags applied to every resource.')
param tags object = {}

var suffix = '${appName}-${environmentName}'
var allTags = union(tags, {
  workload: 'contoso-orders'
  environment: environmentName
})

// Names are built up front, and the endpoints are built from NAMES rather than
// module outputs. That keeps the web app independent of the modules that grant it
// access to them, which would otherwise be a dependency cycle.
var newStorageName = take('st${toLower(appName)}${environmentName}${uniqueString(resourceGroup().id)}', 24)
var keyVaultName = take('kv-${appName}-${environmentName}-${uniqueString(resourceGroup().id)}', 24)
var storageBlobEndpoint = 'https://${newStorageName}.blob.${environment().suffixes.storage}/'
var keyVaultUri = 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/'

// uniqueName is also used in the role assignment name, which must be known at the start of the deployment.
var ordersApiUniqueName = 'app-${suffix}-orders-api'

// ---------------------------------------------------------------------
// Monitoring
// ---------------------------------------------------------------------

// The platform team's central workspace. Exists in prod, not (yet) in dev.
// Without @nullIfNotFound() this reference fails the whole dev deployment.
@nullIfNotFound()
resource sharedLaw 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: sharedLogAnalyticsName
  scope: resourceGroup(platformSubscriptionId, platformResourceGroupName)
}

// Small local workspace used as the fallback when the shared one isn't there.
resource localLaw 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${suffix}'
  location: location
  tags: allTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Check a runtime property: .id is constructed even when the workspace is missing.
var logAnalyticsWorkspaceId = sharedLaw.?properties != null ? sharedLaw.id : localLaw.id

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${suffix}'
  location: location
  tags: allTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
  }
}

// ---------------------------------------------------------------------
// Website: Azure Container Apps
// ---------------------------------------------------------------------

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${suffix}'
  location: location
  tags: allTags
  properties: {
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
  }
}

// Send Container Apps logs to whichever workspace we resolved above.
resource envDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: env
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

resource web 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-${suffix}-web'
  location: location
  tags: allTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
      }
    }
    template: {
      containers: [
        {
          name: 'web'
          // Precedence: an explicit release, then whatever the app team's pipeline
          // shipped (orders-web:v42, ...), and only then the placeholder.
          // Demo beat: delete the this.existingResource() line and the site resets.
          image: webImage ?? this.existingResource().?properties.?template.?containers[?0].?image ?? placeholderImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
            {
              name: 'STORAGE_BLOB_ENDPOINT'
              value: storageBlobEndpoint
            }
            {
              name: 'KEYVAULT_URI'
              value: keyVaultUri
            }
            {
              name: 'LEGACY_STORAGE_NAME'
              value: legacyStorage.name
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// ---------------------------------------------------------------------
// Legacy storage (to be retired by the ticket)
// Used by v1 of the app with shared-key access. Removing it (and its
// LEGACY_STORAGE_NAME env var) is the Stacks What-If "Delete" moment.
// ---------------------------------------------------------------------

resource legacyStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('stlegacy${uniqueString(resourceGroup().id, environmentName)}', 24)
  location: location
  tags: union(allTags, {
    status: 'legacy-retire-after-migration'
  })
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true // the reason it's being retired
    supportsHttpsTrafficOnly: true
  }

  resource blobService 'blobServices' = {
    name: 'default'

    resource exportsContainer 'containers' = {
      name: 'orders-export'
    }
  }
}

// ---------------------------------------------------------------------
// New RBAC-only storage (Azure Verified Module)
// ---------------------------------------------------------------------

module storage 'br/public:avm/res/storage/storage-account:0.33.1' = {
  params: {
    name: newStorageName
    location: location
    tags: allTags
    kind: 'StorageV2'
    skuName: environmentName == 'prod' ? 'Standard_ZRS' : 'Standard_LRS'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    blobServices: {
      containers: [
        {
          name: 'orders-data'
          publicAccess: 'None'
        }
      ]
    }
    roleAssignments: [
      {
        principalId: web.identity.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Storage Blob Data Reader'
        description: 'The web app lists containers'
      }
      {
        // The Entra group declared below: no copied object IDs.
        principalId: blobReaders.id
        principalType: 'Group'
        roleDefinitionIdOrName: 'Storage Blob Data Reader'
        description: 'Members of the blob readers group can read blob data'
      }
    ]
  }
}

// ---------------------------------------------------------------------
// Key Vault (Azure Verified Module), RBAC authorization
// ---------------------------------------------------------------------

module keyVault 'br/public:avm/res/key-vault/vault:0.14.2' = {
  params: {
    name: keyVaultName
    location: location
    tags: allTags
    sku: 'standard'
    enableRbacAuthorization: true
    enablePurgeProtection: false // demo only: lets the reset script purge and recreate it
    softDeleteRetentionInDays: 7
    secrets: [
      {
        name: 'orders-welcome'
        value: 'Welcome to Contoso Orders'
      }
    ]
    roleAssignments: [
      {
        principalId: web.identity.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        description: 'The web app reads secrets'
      }
    ]
  }
}

// ---------------------------------------------------------------------
// Entra ID (Microsoft Graph Bicep extension)
// uniqueName makes these idempotent: Graph uses POST, ARM uses PUT.
// Do NOT use @nullIfNotFound() or `existing` on Entra resources.
// ---------------------------------------------------------------------

resource blobReaders 'Microsoft.Graph/groups@v1.0' = {
  uniqueName: 'sg-${suffix}-blob-readers'
  displayName: 'sg-${suffix}-blob-readers'
  description: 'Read access to the ${suffix} blob storage data'
  mailEnabled: false
  mailNickname: 'sg-${suffix}-blob-readers'
  securityEnabled: true
}

resource ordersApi 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: ordersApiUniqueName
  displayName: 'app-${suffix}-orders-api'
  signInAudience: 'AzureADMyOrg'

  // GitHub OIDC: the app team's repo signs in as this app, with no secrets.
  resource githubMain 'federatedIdentityCredentials@v1.0' = {
    name: '${ordersApiUniqueName}/github-main'
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

// The app team's pipeline can ship new images, scoped to the container app only.
resource appTeamDeploys 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: web
  name: guid(web.id, ordersApiUniqueName, 'Contributor')
  properties: {
    principalId: ordersApiSp.id
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitions('Contributor').id
  }
}

output siteUrl string = 'https://${web.properties.configuration.ingress.fqdn}'
output webPrincipalId string = web.identity.principalId
output usingSharedWorkspace bool = sharedLaw.?properties != null
output legacyStorageAccountName string = legacyStorage.name
output storageAccountName string = storage.outputs.name
output keyVaultName string = keyVault.outputs.name
output ordersApiClientId string = ordersApi.appId
output blobReadersGroupId string = blobReaders.id
