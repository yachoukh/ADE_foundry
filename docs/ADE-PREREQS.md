# ADE prerequisites for end-to-end validation

These are the Azure resources + role assignments that must exist **before** an
end-user can deploy this catalog through Azure Deployment Environments. They
are not deliverables of this repo — they are the operational environment.

The exact set below is what was used to validate this catalog. Names are
illustrative; values in `<angle brackets>` are placeholders.

## 1. Resource group + region

```bash
az group create -n <rg> -l swedencentral
```

The Foundry / Cognitive Services models in this catalog must be available in
the chosen region — see Model Explorer.

## 2. DevCenter (with system-assigned identity)

```bash
az devcenter admin devcenter create -g <rg> -n <devcenter> \
  -l <region> --identity-type SystemAssigned
```

Grant the DevCenter's managed identity **Owner** on the deployment
subscription (Contributor for resource creation + User Access Administrator
so it can assign Foundry User role):

```bash
DC_MI=$(az devcenter admin devcenter show -g <rg> -n <devcenter> --query identity.principalId -o tsv)
az role assignment create --role Owner \
  --assignee-object-id $DC_MI --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/<subId>
```

## 3. Catalog (GitHub-backed)

Store a GitHub PAT (with `repo` scope, or use a fine-grained read-only PAT for
this repo) in a Key Vault, grant the DevCenter MI **Key Vault Secrets User**
on the vault, then:

```bash
az devcenter admin catalog create -g <rg> -d <devcenter> -n foundry-models \
  --git-hub uri=https://github.com/<owner>/ADE_foundry.git \
            branch=main path=/Environments \
            secret-identifier=<https://...vault.azure.net/secrets/gh-pat/...>
```

Verify the sync is clean:

```bash
az devcenter admin catalog show -g <rg> -d <devcenter> -n foundry-models \
  --query "lastSyncStats" -o jsonc
```

`synchronizationErrors` and `validationErrors` must both be `0`.

## 4. Environment type on the DevCenter

```bash
az devcenter admin environment-type create -g <rg> -d <devcenter> -n sandbox
```

## 5. Project

```bash
DC_ID=$(az devcenter admin devcenter show -g <rg> -n <devcenter> --query id -o tsv)
az devcenter admin project create -g <rg> -n <project> --dev-center-id $DC_ID -l <region>
```

## 6. Project environment type

Binds the env type to the project, picks the deployment identity, and lists
roles to grant to the **end user** on the deployed env's resource group.

```bash
az devcenter admin project-environment-type create \
  -g <rg> --project <project> -n sandbox \
  --deployment-target-id /subscriptions/<subId> \
  --identity-type SystemAssigned \
  --status Enabled \
  --roles '{"b24988ac-6180-42a0-ab88-20f7382dd24c":{}}' \
  --location <region>
```

Grant the project-environment-type managed identity **Owner** on the
subscription as well (it's the identity that actually executes the Bicep,
including the role assignment in `rbac.bicep`):

```bash
PET_MI=$(az devcenter admin project-environment-type show -g <rg> --project <project> -n sandbox --query identity.principalId -o tsv)
az role assignment create --role Owner \
  --assignee-object-id $PET_MI --assignee-principal-type ServicePrincipal \
  --scope /subscriptions/<subId>
```

## 7. End-user RBAC on the project

```bash
PROJ_ID=$(az devcenter admin project show -g <rg> -n <project> --query id -o tsv)
az role assignment create --role "DevCenter Project Admin"    --assignee <user-objectId> --scope $PROJ_ID
az role assignment create --role "Deployment Environments User" --assignee <user-objectId> --scope $PROJ_ID
```

`Deployment Environments User` is the minimum role to create environments.
`DevCenter Project Admin` allows managing environments belonging to others;
needed for the end-to-end test, optional in normal operation.

## 8. Smoke test

Create an environment in `mode=new`:

```bash
cat > params.json <<EOF
{
  "foundryName": "ade-e2e",
  "projectName": "e2eproj",
  "deploymentName": "miniE2E",
  "mode": "new",
  "principalId": "<user-objectId>"
}
EOF

az devcenter dev environment create \
  --dev-center-name <devcenter> --project <project> -n ade-e2e-mini \
  --environment-type sandbox \
  --catalog-name foundry-models \
  --environment-definition-name gpt-4.1-mini \
  --parameters @params.json
```

Then `mode=existing`, pointing at the account/RG from step (a):

```jsonc
{
  "foundryName": "<account-name-from-step-a>",
  "projectName": "e2eproj",
  "deploymentName": "nanoE2E",
  "mode": "existing",
  "existingResourceGroup": "<rg-from-step-a>"
}
```

Verify:

- New mode created the account+project+deployment in its own ADE-managed RG
  and assigned **Foundry User** to the requesting user on the account.
- Existing mode added a second deployment to the same account, in the
  account's original RG (not the new ADE env's RG), and **did not** add
  another role assignment.
