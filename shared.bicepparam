// Values shared by every environment. Dev and prod extend this file.
using none

param appName = 'orders'
param location = 'westus3'

// Platform team's central monitoring (exists in prod, not in dev)
param platformSubscriptionId = '214eeb00-e5bc-4ff6-ab4c-170688d8174b' // [replace with the platform subscription ID]
param platformResourceGroupName = 'rg-platform-monitoring'
param sharedLogAnalyticsName = 'law-platform-shared'

param tags = {
  owner: 'platform-engineering'
  costCenter: 'contoso-orders'
}
