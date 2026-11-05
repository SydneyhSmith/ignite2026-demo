// =====================================================================
// Contoso Orders - web app, storage and Key Vault
// Deployed as a Deployment Stack per environment (dev, prod).
// =====================================================================

targetScope = 'resourceGroup'

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

@description('Tags applied to every resource.')
param tags object = {}

var suffix = '${appName}-${environmentName}'
var allTags = union(tags, {
  workload: 'contoso-orders'
  environment: environmentName
})

// ---------------------------------------------------------------------
// Data services (Entra authentication only)
// ---------------------------------------------------------------------

module storage 'br/public:avm/res/storage/storage-account:0.33.1' = {
  params: {
    name: 'storders${uniqueString(resourceGroup().id, appName, environmentName)}'
    location: location
    tags: allTags
    skuName: 'Standard_LRS'
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'None'
    }
    blobServices: {
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 7
      containers: [
        {
          name: 'orders-data'
          publicAccess: 'None'
        }
      ]
    }
    enableTelemetry: false
  }
}

module keyVault 'br/public:avm/res/key-vault/vault:0.14.2' = {
  params: {
    name: 'kv-orders-${uniqueString(resourceGroup().id, appName, environmentName)}'
    location: location
    tags: allTags
    sku: 'standard'
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    enableVaultForDeployment: false
    enableVaultForTemplateDeployment: false
    enableVaultForDiskEncryption: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'None'
    }
    enableTelemetry: false
  }
}

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
              name: 'LEGACY_STORAGE_NAME'
              value: legacyStorage.name
            }
            {
              name: 'STORAGE_BLOB_ENDPOINT'
              value: storage.outputs.primaryBlobEndpoint
            }
            {
              name: 'KEYVAULT_URI'
              value: keyVault.outputs.uri
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

output siteUrl string = 'https://${web.properties.configuration.ingress.fqdn}'
output webPrincipalId string = web.identity.principalId
output usingSharedWorkspace bool = sharedLaw.?properties != null
output legacyStorageAccountName string = legacyStorage.name

@description('Pass these outputs to entra.bicep after deploying the stack.')
output dataServices {
  storageAccountName: string
  keyVaultName: string
} = {
  storageAccountName: storage.outputs.name
  keyVaultName: keyVault.outputs.name
}

@description('Object ID of the group that should read blobs.')
param blobReaderGroupId string
module data 'br:ghcr.io/sydneyhsmith/modules/orders-data:v1' = {
  name: 'orders-data'
  params: {
    name: 'orders'
    location: location
    containerName: 'orders-data'
    readerPrincipalIds: [blobReaderGroupId]
    readerPrincipalType: 'Group'
    tags: { env: 'prod' }
  }
}
