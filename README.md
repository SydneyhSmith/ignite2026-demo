# Contoso Orders: Azure deployments demo

Demo repo for the Ignite 2026 session *"The Ignite Special: Azure deployments in 2026"*. A platform engineer picks up one ticket and works it end to end, using a new Azure Deployments feature at each step. The full walkthrough is in [DEMO-SCRIPT.md](./DEMO-SCRIPT.md).

> **The ticket:** An app team needs storage + Key Vault in dev and prod, added to our existing Contoso Orders web app template. They also need an Entra app registration their GitHub repo can sign in as (no secrets), and a security group whose members can read the blob data. Must be safe to redeploy. Prod changes need review. Retire the legacy storage account once the new one is in.

## Features covered

| Step | Features |
|------|----------|
| Author | Bicep MCP server, Azure Verified Modules, Microsoft Graph Bicep extension |
| Harden | `uniqueName` on Entra resources, `@nullIfNotFound()`, `this.existingResource()`, optional parameters, extendable `.bicepparam` files |
| Prove | `bicep snapshot` (generate and `--mode validate`) |
| Share | OCI registry support (`ociEnabled`) with GitHub Container Registry |
| Preview | Deployment Stacks, Stacks What-If |
| Ship | `azure/bicep-deploy@v2`, OIDC login, environment approvals |

## Layout

| Path | What it is |
|------|-----------|
| `main.bicep`, `shared.bicepparam`, `dev.bicepparam`, `prod.bicepparam` | Container app, monitoring, legacy storage, AVM Entra-only storage with `orders-data`, and AVM RBAC Key Vault |
| `release-v42.bicepparam` | Extends prod and sets `webImage` to deploy a release through Bicep |
| `entra.bicep`, `data-access.bicep` | Entra group, app registration, service principal, GitHub federated credential and RBAC; bootstrap after the stack |
| `entra.preview.bicepparam`, `entra.preview.snapshot.json` | Offline-only Entra/RBAC preview with a synthetic managed identity ID; never deploy these parameters |
| `scripts/deploy.ps1` | *(`after-ticket` branch)* Deploys Entra, then the stack, for one environment |
| `app/` | The Contoso Orders status page (Flask, managed identity). Shows Storage, Key Vault and Legacy storage cards that flip as the infrastructure changes; the code never changes between demo steps |
| `bicepconfig.json` | Enables `ociEnabled` and adds the Microsoft Graph extension |
| `scripts/reset.ps1` | Resets the demo to the starting state between runs |
| `.github/workflows/deploy.yml` | Snapshot validate, stack what-if on PRs, stack create on merge (gated by the `prod` environment) |
| `.github/workflows/deploy-only.yml` | Manually triggered stack create only, with no snapshot validation or what-if (gated by the `prod` environment) |
| `.github/workflows/lint.yml` | Builds every `.bicep` and `.bicepparam` on PRs (no Azure login) |
| `.github/workflows/build-image.yml` | Stands in for the app team's pipeline that builds `orders-web:<version>` |
| `.github/pull_request_template.md`, `CODEOWNERS`, `dependabot.yml` | PR automation |

## Branches and tags

- `main` (tag `00-ticket`): the starting template.
- `after-ticket`: the finished template after the ticket (AVM storage, AVM Key Vault, Entra group, app registration, federated credential, role assignments).

The workflows run against the template at the repo root of whichever branch is checked out.

## Prerequisites

**Tools**
- Bicep CLI v0.48.x (the workflows pin `v0.48.1`) and the VS Code Bicep extension
- Azure CLI new enough to have `az stack-whatif` (2.67.0 does not)
- PowerShell 7 with `Az.Resources` and `Az.KeyVault`
- GitHub Copilot with the Bicep MCP server

**Azure**
- Resource groups `rg-contoso-orders-dev` and `rg-contoso-orders-prod`
- The platform team's shared Log Analytics workspace (`law-platform-shared`), reachable from prod only
- Set `platformSubscriptionId` in `shared.bicepparam` (it is a placeholder)

**Deployment identity**
- Owner, User Access Administrator or RBAC Administrator on the demo resource groups
- Microsoft Graph application permissions with admin consent: `Application.ReadWrite.OwnedBy` and `Group.Create` (or `Group.ReadWrite.All`)

**GitHub**
- Repository variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- `after-ticket` only: `BLOB_READER_GROUP_ID` and `ORDERS_API_SP_ID`, used by the PR what-if. Copy them from the deploy job summary after the first deploy.
- A `prod` environment with required reviewers, and branch protection on `main`
- Federated credentials on the deployment identity (the OIDC subject depends on how the job runs):
  - Jobs that use the `prod` environment: `repo:<owner>/<repo>:environment:prod`
  - The what-if job on pull requests: `repo:<owner>/<repo>:pull_request`
- The snapshot validate job runs offline and needs no Azure credentials or subscription access.
- The `orders-web` package on GitHub Container Registry set to **public**. Publish it by running the `build-image` workflow (version `v42`), then deploy with `release-v42.bicepparam` so the container app pulls it.

Starting state of the site: Storage and Key Vault show "Not set up yet", Legacy storage shows "Connected with a shared key". After the ticket deploys, Storage and Key Vault go green and Legacy storage shows "Retired". Test locally with `pip install -r app/requirements.txt` and `flask --app app/app.py run`.

## Build the demo image locally

```sh
docker build --build-arg APP_VERSION=v42 -t orders-web:v42 ./app
docker run --rm -p 8080:80 orders-web:v42
```

Open `http://localhost:8080` for the status page. Locally every card shows "Not set up yet" except Legacy storage, which is controlled by `LEGACY_STORAGE_NAME`.

## Deploy

To run only the stack create in GitHub Actions, manually run **Contoso Orders deploy only** (`deploy-only.yml`). It uses the same deployment settings and `prod` environment approvals as `deploy.yml`, but skips snapshot validation and what-if. It is manual-only to avoid duplicate deployments on pushes; the existing deployment workflow is unchanged.

On `after-ticket`, run `./scripts/deploy.ps1 -Environment prod` (Entra first, then the stack). On `main` the stack alone is enough:

```powershell
New-AzResourceGroupDeploymentStack -Name 'contoso-orders-prod' -ResourceGroupName 'rg-contoso-orders-prod' `
  -TemplateFile './main.bicep' -TemplateParameterFile './prod.bicepparam' `
  -ActionOnUnmanage DeleteResources -DenySettingsMode None
```

Add `-Force` to update an existing stack. To pin the website image: use `release-v42.bicepparam` as the parameter file.

## Snapshots

Snapshots embed the subscription and resource group. Generate them with the fixed, non-secret scope used by snapshot validation, independent of the actual deployment target:

```powershell
bicep snapshot prod.bicepparam --subscription-id 214eeb00-e5bc-4ff6-ab4c-170688d8174b --resource-group rg-contoso-orders-prod --location westus3
```

Commit `prod.snapshot.json`. CI runs the same command with `--mode validate`, without Azure login.

The new storage and vault use pinned AVM modules. Legacy storage and its app
setting remain unchanged. The web app receives `STORAGE_BLOB_ENDPOINT` and
`KEYVAULT_URI`; existing image-preservation behavior is unchanged.

Generate the separate Entra preview with the same fixed scope:

```sh
bicep snapshot entra.preview.bicepparam --subscription-id 214eeb00-e5bc-4ff6-ab4c-170688d8174b --resource-group rg-contoso-orders-prod --location westus3
```

This preview contains the group, single-tenant app registration, service principal,
one GitHub OIDC credential and five role assignments. Graph object IDs remain
unevaluated expressions offline. **Never deploy the preview parameter file**:
its managed identity ID is synthetic and its resource names are for the fixed
snapshot scope. Graph snapshot validation is not added to CI because of the
documented Bicep `SnapshotDiffer` bug below. Snapshots predict template changes;
they do not query Azure or prove tenant permissions, name availability or live access.
Regeneration also refreshes two previously stale monitoring workspace references
in the committed prod snapshot to match the already-existing shared parameters;
the monitoring template itself is unchanged.

## Bootstrap Entra and access

On this branch, deploy the stack first, then deploy `entra.bicep` as an ordinary
resource-group deployment in the **same resource group**. Use the stack outputs
`dataServices` and `webPrincipalId`, not the offline preview values:

```sh
az deployment group create --name contoso-orders-entra-prod \
  --resource-group <actual-resource-group> --template-file entra.bicep \
  --parameters environmentName=prod \
    'dataServices={"storageAccountName":"<dataServices.storageAccountName>","keyVaultName":"<dataServices.keyVaultName>"}' \
    webPrincipalId=<webPrincipalId>
```

For dev, use `environmentName=dev` and that stack's outputs. If `appName` differs
from its default, pass the same value to both templates. Stable Graph `uniqueName`
values include tenant, resource group, workload and environment; RBAC assignment
GUIDs include scope, principal and role so redeployment preserves identity.
Do not move Graph objects into the deployment stack.

| Principal | Role | Scope |
|-----------|------|-------|
| Web system-assigned managed identity | Storage Blob Data Contributor | New storage account |
| Entra security group | Storage Blob Data Contributor | New storage account |
| Web system-assigned managed identity | Key Vault Secrets User | New vault |
| Entra security group | Key Vault Secrets User | New vault |
| GitHub service principal | Contributor | This resource group only |

The bootstrap identity needs Graph permissions/admin consent from the prerequisites
and Azure role-assignment write access. Contributor **cannot** create or change
RBAC assignments, so do not run the Entra/RBAC bootstrap under the newly created
GitHub identity. The resource-level data roles use native Bicep because standalone
AVM RBAC modules only support resource group, subscription and management group
scopes; the Contributor assignment uses AVM.

The group starts empty; add approved members separately. No client secret or
Key Vault secret value is created. To satisfy the status page's Key Vault check,
an authorized operator must securely provision the `orders-welcome` secret.
Allow time for Entra and RBAC propagation.

The `identities` output supplies the client and tenant IDs for GitHub configuration.
The current workflows consume `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and
`AZURE_SUBSCRIPTION_ID` as GitHub **secrets**. The prod credential trusts only
`repo:sydneyhsmith/ignite2026-demo:environment:prod`, with issuer
`https://token.actions.githubusercontent.com` and audience `api://AzureADTokenExchange`.
For dev deployments it trusts the corresponding `environment:dev` subject.
No branch or pull-request credential is created. The existing non-environment
PR what-if job needs a separate, appropriately restricted identity; the new
prod-only identity cannot sign in from that job. Workflows are not reconfigured
automatically, and the existing bootstrap identity can remain in use.

Authenticated public endpoints are explicitly enabled because the current
Container Apps baseline has no private-endpoint networking. Blob anonymous
access and storage shared-key authentication are disabled. The new vault has
90-day soft delete and purge protection enabled: the existing reset helper cannot
immediately purge it. Do not expect the old reset/purge demo flow to work on this
branch; retain the vault or wait for the retention period before reusing its name.

## Preview a change to the stack

```powershell
az stack-whatif group create --name contoso-orders-prod --resource-group rg-contoso-orders-prod `
  --template-file main.bicep --parameters prod.bicepparam --action-on-unmanage deleteResources --deny-settings-mode none
```

The PR workflow runs the equivalent with `azure/bicep-deploy`; read the result in the **Stack what-if (prod)** job log. What-if runs after snapshot validation even if validation fails, unless the workflow is cancelled. Deployment still requires snapshot validation to pass.

## Reset between runs

```powershell
./scripts/reset.ps1 -Environments prod
```

Deletes the stack, purges Key Vault, permanently deletes the Entra objects (otherwise `uniqueName` clashes), redeploys the starting template and pins v42. Run it with the starting template checked out.

## Notes

- Entra lives in `entra.bicep`, not the stack template, because `bicep snapshot --mode validate` crashes (`KeyNotFoundException` in `SnapshotDiffer`) on a snapshot that contains Graph resources, in Bicep 0.47.16 and 0.48.1. This branch passes stack outputs into the separate Entra/RBAC deployment instead of reading Entra IDs into the stack.
- This branch enables Key Vault purge protection; the older `after-ticket` reset walkthrough assumes it is off.
- Do not use `@nullIfNotFound()` or `existing` on Entra resources; use `uniqueName`.
- Not yet tested against Azure: the Entra deployment, the stack with the new role assignments, and the Graph permissions the pipeline identity needs.
