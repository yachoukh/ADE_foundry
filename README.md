# ADE Foundry Catalog

An [Azure Deployment Environment](https://learn.microsoft.com/azure/deployment-environments/)
catalog that deploys **Azure AI Foundry** model deployments with a deliberately
tiny user surface area.

One catalog item per supported model. The user picks:

| Param | Meaning |
|---|---|
| `foundryName` | Foundry (Cognitive Services) account name (or prefix in `new` mode) |
| `projectName` | Foundry project name |
| `deploymentName` | Model deployment name |
| `mode` | `new` = create account + project; `everything else (existing)` = reference existing |
| `principalId` | Object id to receive `Azure AI User` / `Foundry User` role (used only in `new` mode) |
| `existingResourceGroup` | RG holding the existing account (only in `existing` mode) |

The catalog **fixes** everything else in Bicep so users can't deviate:

- model id (one per catalog item)
- model version
- SKU name (`GlobalStandard`)
- capacity (**30K TPM** per deployment)
- location (the deployment RG's `location`)

## Catalog items

| Item | Model | Version | SKU | TPM |
|---|---|---|---|---|
| `gpt-5.5` | `gpt-5.5` | `2026-04-24` | `GlobalStandard` | 30 K |
| `gpt-5.4` | `gpt-5.4` | `2026-03-05` | `GlobalStandard` | 30 K |
| `gpt-4.1` | `gpt-4.1` | `2025-04-14` | `GlobalStandard` | 30 K |
| `gpt-4.1-mini` | `gpt-4.1-mini` | `2025-04-14` | `GlobalStandard` | 30 K |
| `gpt-4.1-nano` | `gpt-4.1-nano` | `2025-04-14` | `GlobalStandard` | 30 K |

Values cross-checked against
[Model Explorer](https://foundry-models.azurewebsites.net/explorer) at catalog
build time. To raise/lower the TPM cap or change the SKU for a model, edit
`shared-templates/models.json` and regenerate (see *Regenerating* below).

## Layout

```
Environments/                # ← register this folder as the ADE catalog path
  gpt-5.5/{environment.yaml, main.bicep, modules/}
  gpt-5.4/...
  gpt-4.1/...
  gpt-4.1-mini/...
  gpt-4.1-nano/...
shared-templates/
  _main.bicep.tmpl           # canonical bicep (placeholders inlined per item)
  _environment.yaml.tmpl
  model-deployment.bicep     # shared module body
  rbac.bicep                 # shared module body
  models.json                # source of truth: per-model values
```

Each `Environments/<model>/` folder is fully self-contained (ADE requires it).

## Important Bicep details

- The model deployment is **account-scoped** (`accounts/deployments`), not
  project-scoped. `projectName` creates the project in `new` mode so the user
  has a Foundry project to work in; the deployment is visible to all projects
  on the account.
- In `new` mode the account name + `customSubDomainName` are suffixed with
  `uniqueString(resourceGroup().id)` to avoid global subdomain collisions.
  `foundryName` becomes a *prefix*.
- In `existing` mode the deployment module is invoked with
  `scope: resourceGroup(existingResourceGroup)` so it works even though ADE
  creates a fresh RG per environment.
- RBAC (Azure AI User / Foundry User,
  `53ca6127-db72-4b80-b1b0-d745d6d5456d`) is only assigned in `new` mode and
  only when `principalId` is non-empty. ADE should populate `principalId` with
  the requesting user's object id via the project environment type.

## Quota / failure modes

`QuotaExceeded` will surface as a hard ADE deployment failure — capacity is
fixed in Bicep on purpose. If a tenant routinely lacks 30K TPM for a model,
edit `models.json` and regenerate; do **not** add a user-facing capacity knob.

## Registering the catalog

Register this repo at path **`/Environments`** in your DevCenter:

```bash
az devcenter admin catalog create -g <rg> -d <devcenter> -n foundry-models \
  --git-hub uri=https://github.com/<owner>/ADE_foundry.git \
            branch=main path=/Environments \
            secret-identifier=<keyvault-secret-id-with-PAT>
```

## End-to-end ADE setup (was used to validate this catalog)

See [`docs/ADE-PREREQS.md`](docs/ADE-PREREQS.md) for the full list of
DevCenter / Project / environment-type / role assignments needed for a real
ADE deployment.

## Regenerating items after editing `models.json`

```pwsh
# from repo root
$models = (Get-Content shared-templates/models.json | ConvertFrom-Json).models
$tplBicep = Get-Content -Raw shared-templates/_main.bicep.tmpl
$tplYaml  = Get-Content -Raw shared-templates/_environment.yaml.tmpl
foreach($name in $models.PSObject.Properties.Name){
  $m = $models.$name
  $bicep = $tplBicep -replace '__MODEL_NAME__',$name -replace '__MODEL_VERSION__',$m.version -replace '__SKU_NAME__',$m.skuName -replace '__CAPACITY_K__',[string]$m.capacityK
  $yaml  = $tplYaml  -replace '__MODEL_NAME__',$name -replace '__SKU_NAME__',$m.skuName -replace '__CAPACITY_K__',[string]$m.capacityK
  Set-Content -NoNewline "Environments/$name/main.bicep" $bicep
  Set-Content -NoNewline "Environments/$name/environment.yaml" $yaml
}
```
