// Offline preview only. Never deploy: the managed identity ID is synthetic.
using 'entra.bicep'

param environmentName = 'prod'
param dataServices = {
  storageAccountName: 'stordersbbxfone5tdwhg'
  keyVaultName: 'kv-orders-bbxfone5tdwhg'
}
param webPrincipalId = '00000000-0000-0000-0000-000000000001'
