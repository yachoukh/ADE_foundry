# ADE Foundry Catalog

Azure Deployment Environment catalog: one item per supported Foundry model.

## Items
- gpt-5.5, gpt-5.4, gpt-4.1, gpt-4.1-mini, gpt-4.1-nano

## User params
foundryName, projectName, deploymentName, mode (new|existing), principalId (new mode only).

SKU, TPM (30K), model version and region are locked in Bicep.

## Catalog path
Register this repo's /Environments path as the ADE catalog path.
