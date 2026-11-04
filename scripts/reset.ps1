<#
.SYNOPSIS
  Resets the Contoso Orders demo to its starting state.

.DESCRIPTION
  1. Deletes the deployment stacks (and the resources they manage)
  2. Purges soft-deleted Key Vaults
  3. Permanently deletes the Entra objects (uniqueName clashes otherwise)
  4. Redeploys the STARTING template from the repo root
  5. Pins the website image to v42 (prod only)

  Run it from the repo root with the starting template checked out
  (git checkout 00-ticket). Requires Az.Resources and an `az` login that can
  delete Entra apps and groups.
#>
[CmdletBinding()]
param(
  [ValidateSet('dev', 'prod')]
  [string[]] $Environments = @('prod'),

  [string] $AppName = 'orders',

  [string] $Location = 'westus3',

  [switch] $Force
)

$ErrorActionPreference = 'Stop'

if (-not $Force) {
  $answer = Read-Host "This deletes stacks, Key Vaults and Entra objects for: $($Environments -join ', '). Type 'reset' to continue"
  if ($answer -ne 'reset') { return }
}

function Remove-EntraObjectPermanently {
  param([string] $Collection, [string] $DisplayNamePrefix, [string] $DeletedType)

  $filter = [uri]::EscapeDataString("startswith(displayName,'$DisplayNamePrefix')")

  $live = az rest --method GET --url "https://graph.microsoft.com/v1.0/$Collection`?`$filter=$filter&`$select=id,displayName" --query 'value[].id' -o tsv
  foreach ($id in $live) {
    if ($id) { az rest --method DELETE --url "https://graph.microsoft.com/v1.0/$Collection/$id" | Out-Null }
  }

  $deleted = az rest --method GET --url "https://graph.microsoft.com/v1.0/directory/deletedItems/$DeletedType`?`$filter=$filter&`$select=id" --query 'value[].id' -o tsv
  foreach ($id in $deleted) {
    if ($id) { az rest --method DELETE --url "https://graph.microsoft.com/v1.0/directory/deletedItems/$id" | Out-Null }
  }
}

foreach ($environmentName in $Environments) {
  $stackName = "contoso-orders-$environmentName"
  $resourceGroupName = "rg-contoso-orders-$environmentName"
  $suffix = "$AppName-$environmentName"

  Write-Host "== $environmentName ==" -ForegroundColor Cyan

  Write-Host '1. Deleting the stack'
  $stack = Get-AzResourceGroupDeploymentStack -ResourceGroupName $resourceGroupName -Name $stackName -ErrorAction SilentlyContinue
  if ($stack) {
    Remove-AzResourceGroupDeploymentStack -ResourceGroupName $resourceGroupName -Name $stackName `
      -ActionOnUnmanage DeleteResources -Force
  }

  Write-Host '2. Purging soft-deleted Key Vaults'
  Get-AzKeyVault -InRemovedState |
    Where-Object { $_.VaultName -like "kv-$suffix-*" } |
    ForEach-Object { Remove-AzKeyVault -VaultName $_.VaultName -Location $_.Location -InRemovedState -Force }

  Write-Host '3. Permanently deleting Entra objects'
  Remove-EntraObjectPermanently -Collection 'groups' -DisplayNamePrefix "sg-$suffix" -DeletedType 'microsoft.graph.group'
  Remove-EntraObjectPermanently -Collection 'applications' -DisplayNamePrefix "app-$suffix" -DeletedType 'microsoft.graph.application'

  Write-Host '4. Redeploying the starting template'
  if (-not (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $resourceGroupName -Location $Location | Out-Null
  }
  New-AzResourceGroupDeploymentStack -Name $stackName -ResourceGroupName $resourceGroupName `
    -TemplateFile './main.bicep' -TemplateParameterFile "./$environmentName.bicepparam" `
    -ActionOnUnmanage DeleteResources -DenySettingsMode None -Force | Out-Null

  if ($environmentName -eq 'prod') {
    Write-Host '5. Pinning the website to v42'
    New-AzResourceGroupDeploymentStack -Name $stackName -ResourceGroupName $resourceGroupName `
      -TemplateFile './main.bicep' -TemplateParameterFile './release-v42.bicepparam' `
      -ActionOnUnmanage DeleteResources -DenySettingsMode None -Force | Out-Null
  }
}

Write-Host 'Reset complete. Check the site shows the starting page (Not set up yet, legacy connected).' -ForegroundColor Green
