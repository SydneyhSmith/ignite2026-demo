# The Ignite Special: Azure deployments in 2026

45 minutes, solo, ride-along with the blog post. Repo tags `00-ticket` … `06-ship`.
Timings: 3 + 10 + 7 + 5 + 6 + 8 + 6 = 45.

## Running scenario

"Our team already runs the Contoso Orders website from this template. The app team builds and ships the container image from their own GitHub repo (`orders-web:v42`). Now they need storage, Key Vault, a way for their repo to sign in without secrets, and a reader group. I'm adding all of that to the existing template. Here's the ticket: watch me take it from start to finish."

**Ticket (on screen):** An app team needs storage + Key Vault in dev and prod, added to our existing Contoso Orders web app template. They also need an Entra app registration their GitHub repo can sign in as (no secrets), and a security group whose members can read the blob data. Must be safe to redeploy. Prod changes need review. Retire the legacy storage account once the new one is in.

**What we build**
- Storage account (AVM): private, RBAC only, replaces the legacy account.
- Key Vault (AVM), RBAC.
- Entra security group → Storage Blob Data Reader on the new storage account.
- Entra app registration + service principal + federated credential (GitHub OIDC) for the app team's `orders-api` repo.
- Role assignments: the container app's managed identity → Storage Blob Data Reader and Key Vault Secrets User (so the site can read both); the app team's service principal → Contributor on the container app only (so their pipeline can ship images).

## Why the website makes this click

The page is a status board (auto-refreshes every 10s): **Storage**, **Key Vault**, **Legacy storage**. It starts with "Not set up yet" / "Connected with a shared key" and turns green as the infrastructure changes. **The app is never changed on stage.**

The pain it sets up: the app team's pipeline updates the image (`orders-web:v42`), but our template only knows a placeholder. Redeploying infrastructure resets production to the placeholder and the site breaks. The usual workarounds were a deployment script or a pipeline-passed "exists" parameter.

---

## 0. Ticket: the live site (3 min) · tag `00-ticket`

- Open the live site (Contoso Orders v42): Storage / Key Vault "Not set up yet", Legacy "Connected with a shared key".
- Show the ticket and the scenario above. Say where we'll land: a PR with a snapshot and a What-If, a gated merge, and this page turning green. "Let's build that."

## 1. Author: AI that knows Bicep (10 min) · tag `01-author`

**Topics:** Bicep MCP server + Azure Verified Modules + Microsoft Graph Bicep extension.

- **Teach:** the MCP server gives the agent real resource schemas, best practices, AVM metadata and diagnostics, so the model checks its work against the compiler instead of guessing.
- **Demo:** in VS Code with Copilot, prompt: *"Extend main.bicep for the ticket: an AVM storage account (no shared key, container `orders-data`) and an AVM Key Vault, an Entra security group, an app registration with a service principal and a GitHub OIDC federated credential for `<owner>/orders-api`, and the role assignments. Use Azure Verified Modules and best practices."*
  - Show the agent calling `list_avm_metadata` and choosing AVM modules from the public registry.
  - **Planned snag:** the agent calls `get_bicep_file_diagnostics`, catches a warning and fixes its own code.
  - **Key moments:** the Entra objects (group, app registration, service principal, federated credential) go in a new `entra.bicep` using the Graph extension. Its outputs (the group's object ID, the service principal's object ID) feed the role assignments in `main.bicep`, so nobody copies an ID by hand. `roleDefinitionIdOrName: 'Storage Blob Data Reader'` / `roleDefinitions('Contributor')` means no role GUIDs.
  - Endpoints (`STORAGE_BLOB_ENDPOINT`, `KEYVAULT_URI`) are built from names, not module outputs, so there's no dependency cycle.
- **Tip:** use the ARM MCP server to validate against the policies and conventions of the target environment.
- **Takeaway:** AVM gives you vetted building blocks; the MCP server makes the AI use them correctly. The Graph extension means Entra is Bicep too: same language, same repo, deployed just before the stack.
- **Bridge:** "We have a working template. But what happens the second time we deploy it?"

## 2. Harden: make redeploys safe (7 min) · tag `02-harden`

**Topics:** `uniqueName` for Entra, `@nullIfNotFound()`, the `this` namespace.

- **Teach:** the classic "create if missing, otherwise leave it alone" problem, which used to need deployment scripts or pipeline flags.
- **Demo:**
  - **Entra (`entra.bicep`):** `uniqueName` makes Graph resources idempotent (Graph creates with POST, ARM with PUT). **Do not** use `@nullIfNotFound()` or `existing` on Entra resources.
  - **ARM only:** `@nullIfNotFound()` on the platform team's shared Log Analytics workspace. It exists in prod, not in dev, so dev falls back to a local workspace. Note: check a runtime property (`sharedLaw.?properties != null`), because `.id` is built even when the workspace doesn't exist.
  - **ARM only:** `this.existingResource()` on the container app image: `webImage ?? this.existingResource().?properties.?template.?containers[?0].?image ?? placeholderImage`.
    - **Beat:** redeploy *without* the `this` line → the site shows the placeholder. Add it back → v42 stays.
- **Takeaway:** the template handles a first deploy and a redeploy, without scripts. Releases can still be pushed through Bicep with the optional `webImage` parameter (`release-v42.bicepparam`).
- **Bridge:** "We changed the logic. How do we prove we didn't change what gets deployed?"

## 3. Prove it locally: no Azure needed (5 min) · tag `03-prove`

**Topic:** `bicep snapshot`.

- **Teach:** a snapshot is a normalized, fully evaluated view of what a `.bicepparam` file deploys. Commit it, validate against it on every change.
- **Demo:**
  1. `bicep snapshot prod.bicepparam` (with `--subscription-id`, `--resource-group`, `--location`) and commit `prod.snapshot.json`. Say why Entra isn't in it: Graph resources are a separate regular deployment (`entra.bicep`), because `--mode validate` currently crashes on a snapshot that contains them.
  2. Refactor `main.bicep` into `web`, `data` and `identity` modules. `bicep snapshot prod.bicepparam --mode validate` shows **no diff**.
  3. Make a real change (a storage SKU). Validate shows **exactly one diff**.
- **Takeaway:** a fast, offline safety net for refactors and code review.
- **Bridge:** "This module is good. Other teams should reuse it."

## 4. Share: publish where your teams already are (6 min) · tag `04-share`

**Topic:** OCI registry support (experimental `ociEnabled`).

- **Teach:** you're no longer tied to ACR. Publish modules and extensions to any OCI registry, such as GitHub Container Registry.
- **Demo:**
  - The refactor in step 3 already made the reusable module. Publish `data`: `bicep publish ./modules/data.bicep --target br:ghcr.io/<owner>/modules/orders-data:v1`.
  - Consume it from a second repo with a `br:ghcr.io/...` reference.
  - **Reveal:** the Microsoft Graph extension is also an OCI artifact (`br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:1.0.0`).
- **Takeaway:** module distribution uses the registry and access controls your org already has.
- **Bridge:** "Now let's put this in a real environment and manage its whole lifecycle."

## 5. Preview: see the deletes before they happen (8 min) · tag `05-preview`

**Topic:** Stacks What-If (GA).

- **Teach:** Deployment Stacks manage resources as one unit, including deletes. Stacks What-If compares against what the stack recorded at its last deployment, so you don't get regular What-If noise.
- **Demo:**
  - The prod stack is `contoso-orders-prod` with `actionOnUnmanage: DeleteResources`.
  - Retire the legacy storage account: remove the resource **and** its `LEGACY_STORAGE_NAME` env var.
  - `az stack-whatif group create …` shows the legacy account as **Delete**, everything else unchanged.
  - If time allows, show the same change with regular What-If side by side to make the noise point.
- **Takeaway:** stacks give you lifecycle and RBAC management; What-If makes it safe.
- **Bridge:** "Nobody should run this from their laptop. Let's automate it."

## 6. Ship: What-If on every PR, deploy on merge (6 min) · tag `06-ship`

**Topic:** Bicep Deploy for GitHub Actions (`azure/bicep-deploy@v2`).

- **Teach:** one action handles deployments and stacks, with validate, whatIf, create and delete. OIDC login, no secrets.
- **Demo (`.github/workflows/deploy.yml`):**
  - Open a PR: a job runs `bicep snapshot --mode validate` (offline gate), then `type: deploymentStack` / `operation: whatIf`. Read the result in the job log.
  - The `prod` environment has required reviewers. Approve; merge runs `operation: create`.
  - **Close the loop:** the federated credential we deployed lets the app team's `orders-api` repo sign in the same way.
  - **Payoff:** refresh the website. Storage and Key Vault are green, Legacy says "Retired".
- **Close with the ticket checklist:** storage ✔ Key Vault ✔ Entra app + group ✔ safe to redeploy ✔ prod reviewed ✔ legacy retired ✔

## Close

- Recap slide: the six steps as one pipeline (author → harden → prove → share → preview → ship).
- Blog post for the full year of releases; demo repo link.
- Blueprints users: retirement is **January 31, 2027**.
- Optional (30 sec): roadmap slide. Take it from the 45 minutes by trimming the "side by side" What-If in step 5.

---

## Presenter notes

- **Azure DevOps** is dropped from the live demo (GitHub Actions only). Mention it in one sentence if asked: same action, different YAML.
- **Entra is deployed separately** (`entra.bicep`, then the stack). In the pipeline the Entra deployment runs after approval and passes its object IDs to the stack as `BLOB_READER_GROUP_ID` and `ORDERS_API_SP_ID`. Locally: `scripts/deploy.ps1`. Still untested: whether Graph resources can deploy inside a stack.
- **Reset between runs:** `scripts/reset.ps1` (delete stacks → purge Key Vault → permanently delete Entra objects → redeploy the starting template → pin v42). Record the AI section and the final refresh as backups. Keep a pre-greened fallback environment.
- **Before going on stage:** upgrade `az` (stack-whatif needs a newer version than 2.67.0), match the local Bicep CLI to the workflow pin (v0.48.1), and fill in `platformSubscriptionId`.
