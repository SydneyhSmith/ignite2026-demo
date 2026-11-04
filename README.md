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
| `main.bicep`, `shared.bicepparam`, `dev.bicepparam`, `prod.bicepparam` | The **starting template**: container app, Application Insights, shared-or-local Log Analytics, legacy storage |
| `release-v42.bicepparam` | Extends prod and sets `webImage` to deploy a release through Bicep |
| `entra.bicep`, `entra.dev.bicepparam`, `entra.prod.bicepparam` | *(`after-ticket` branch)* Entra group, app registration, service principal and federated credential, deployed before the stack |
| `scripts/deploy.ps1` | *(`after-ticket` branch)* Deploys Entra, then the stack, for one environment |
| `bicepconfig.json` | Enables `ociEnabled` and adds the Microsoft Graph extension |
| `scripts/reset.ps1` | Resets the demo to the starting state between runs |
| `.github/workflows/deploy.yml` | Snapshot validate, stack what-if on PRs, stack create on merge (gated by the `prod` environment) |
| `.github/workflows/lint.yml` | Builds every `.bicep` and `.bicepparam` on PRs (no Azure login) |
| `.github/workflows/build-image.yml` | Stands in for the app team's pipeline that builds `orders-web:<version>` |
| `Dockerfile` | Minimal demo website on port 80, with the build version at `/version.txt` |
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
  - The snapshot validate job runs on both, so it also needs the `pull_request` credential, or the `ref:refs/heads/main` one for pushes
- The `orders-web` package on GitHub Container Registry set to **public**

## Build the demo image locally

```sh
docker build --build-arg APP_VERSION=v42 -t orders-web:v42 .
docker run --rm -p 8080:80 orders-web:v42
```

Open `http://localhost:8080` for the demo landing page or `/version.txt` for the image version.
This is a minimal stand-in for the app team's website, not the full Orders application.

## Deploy

On `after-ticket`, run `./scripts/deploy.ps1 -Environment prod` (Entra first, then the stack). On `main` the stack alone is enough:

```powershell
New-AzResourceGroupDeploymentStack -Name 'contoso-orders-prod' -ResourceGroupName 'rg-contoso-orders-prod' `
  -TemplateFile './main.bicep' -TemplateParameterFile './prod.bicepparam' `
  -ActionOnUnmanage DeleteResources -DenySettingsMode None
```

Add `-Force` to update an existing stack. To pin the website image: use `release-v42.bicepparam` as the parameter file.

## Snapshots

Snapshots embed the subscription and resource group, so generate them with the same values the workflow uses:

```powershell
bicep snapshot prod.bicepparam --subscription-id <id> --resource-group rg-contoso-orders-prod --location westus3
```

Commit `prod.snapshot.json`. CI runs the same command with `--mode validate`.

## Preview a change to the stack

```powershell
az stack-whatif group create --name contoso-orders-prod --resource-group rg-contoso-orders-prod `
  --template-file main.bicep --parameters prod.bicepparam --action-on-unmanage deleteResources --deny-settings-mode none
```

The PR workflow runs the equivalent with `azure/bicep-deploy`; read the result in the **Stack what-if (prod)** job log.

## Reset between runs

```powershell
./scripts/reset.ps1 -Environments prod
```

Deletes the stack, purges Key Vault, permanently deletes the Entra objects (otherwise `uniqueName` clashes), redeploys the starting template and pins v42. Run it with the starting template checked out.

## Notes

- Entra lives in `entra.bicep`, not the stack template, because `bicep snapshot --mode validate` crashes (`KeyNotFoundException` in `SnapshotDiffer`) on a snapshot that contains Graph resources, in Bicep 0.47.16 and 0.48.1. The stack template reads the Entra object IDs from the `BLOB_READER_GROUP_ID` and `ORDERS_API_SP_ID` environment variables (placeholders when unset, so snapshots stay deterministic; the CI snapshot validate job must not set them).
- Key Vault purge protection is **off** so the demo can be reset. Do not copy that setting to production.
- Do not use `@nullIfNotFound()` or `existing` on Entra resources; use `uniqueName`.
- Not yet tested against Azure: the Entra deployment, the stack with the new role assignments, and the Graph permissions the pipeline identity needs.
