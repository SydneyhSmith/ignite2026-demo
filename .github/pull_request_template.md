<!-- Infra PRs: delete sections that don't apply. -->

## What and why

<!-- One or two sentences. Link the ticket. -->

## Checklist

- [ ] `bicep build` passes for every changed `.bicep` / `.bicepparam`
- [ ] Snapshots updated and committed if the deployed result is meant to change
      (`bicep snapshot prod.bicepparam --subscription-id <id> --resource-group <rg> --location <region>`)
- [ ] The **Stack what-if (prod)** job output reviewed: only the expected changes, and every **Delete** is intended
- [ ] Entra resources use `uniqueName` (no `@nullIfNotFound()` or `existing` on them)
- [ ] No secrets, tenant IDs or subscription IDs committed outside the snapshots

## Snapshot diff

<!-- Paste the diff of *.snapshot.json, or write "none (pure refactor)". -->
