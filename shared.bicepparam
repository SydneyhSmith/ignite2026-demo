// Values shared by every environment. Dev and prod extend this file.
using none

param appName = 'orders'
param location = 'westus3'

// Platform team's central monitoring (exists in prod, not in dev)
param platformSubscriptionId = '00000000-0000-0000-0000-000000000000' // [replace with the platform subscription ID]
param platformResourceGroupName = 'rg-platform-monitoring'
param sharedLogAnalyticsName = 'law-platform-shared'

param tags = {
  owner: 'platform-engineering'
  costCenter: 'contoso-orders'
}
