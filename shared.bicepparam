// Values shared by every environment. Dev and prod extend this file.
using none

param appName = 'orders'
param location = 'westus3'

// Platform team's central monitoring (exists in prod, not in dev)
param platformSubscriptionId = '214eeb00-e5bc-4ff6-ab4c-170688d8174b' // [replace with the platform subscription ID]
param platformResourceGroupName = 'ignite2026'
param sharedLogAnalyticsName = 'law-platform-shared'

// Object IDs of the Entra objects created by entra.bicep. Supplied through environment
// variables at deploy time; the placeholder keeps snapshots deterministic.
param blobReaderGroupObjectId = readEnvironmentVariable('BLOB_READER_GROUP_ID', '00000000-0000-0000-0000-000000000000')
param appTeamPrincipalId = readEnvironmentVariable('ORDERS_API_SP_ID', '00000000-0000-0000-0000-000000000000')

param tags = {
  owner: 'platform-engineering'
  costCenter: 'contoso-orders'
}
