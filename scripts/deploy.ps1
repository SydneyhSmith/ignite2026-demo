<#
.SYNOPSIS
  Deploys an environment of the finished template: Entra first, then the stack.

.DESCRIPTION
  Entra objects (entra.bicep) are a regular deployment because Graph resources
  aren't part of the snapshotted stack template. Their object IDs reach the stack
  through the environment variables that shared.bicepparam reads.
#>
[CmdletBinding()]
param(
  [ValidateSet('dev', 'prod')]
  [string] $Environment = 'prod',

  [string] $ParameterFile = "./$Environment.bicepparam"
)

$ErrorActionPreference = 'Stop'
$resourceGroupName = "rg-contoso-orders-$Environment"

$entra = New-AzResourceGroupDeployment -Name "contoso-orders-entra-$Environment" `
  -ResourceGroupName $resourceGroupName `
  -TemplateFile './entra.bicep' -TemplateParameterFile "./entra.$Environment.bicepparam"

$env:BLOB_READER_GROUP_ID = $entra.Outputs.blobReaderGroupObjectId.Value
$env:ORDERS_API_SP_ID = $entra.Outputs.ordersApiServicePrincipalObjectId.Value

New-AzResourceGroupDeploymentStack -Name "contoso-orders-$Environment" -ResourceGroupName $resourceGroupName `
  -TemplateFile './main.bicep' -TemplateParameterFile $ParameterFile `
  -ActionOnUnmanage DeleteResources -DenySettingsMode None -Force
