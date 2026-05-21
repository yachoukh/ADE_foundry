// Canonical main.bicep template — one catalog item per model.
// Placeholders (replaced at codegen time per Environments/<model>/):
//   gpt-4.1-nano       e.g. gpt-4.1-mini
//   2025-04-14    e.g. 2025-04-14
//   GlobalStandard         e.g. GlobalStandard
//   30       integer TPM-in-thousands, e.g. 30
//
// User-visible parameters (also surfaced in environment.yaml):
//   foundryName, projectName, deploymentName, mode, principalId, existingResourceGroup

targetScope = 'resourceGroup'

@minLength(2)
@maxLength(50)
@description('Foundry (Cognitive Services) account name. In mode=new this is used as a prefix; the actual account name is suffixed with a hash for global subdomain uniqueness. In mode=existing it must match an existing account.')
param foundryName string

@minLength(2)
@maxLength(50)
@description('Foundry project name (child of the account). In mode=new this is created; in mode=existing it is informational (the model deployment is account-scoped).')
param projectName string

@minLength(2)
@maxLength(50)
@description('Model deployment name on the Foundry account.')
param deploymentName string

@allowed([
  'new'
  'existing'
])
@description('Whether to create a new Foundry account+project or reference an existing one.')
param mode string = 'new'

@description('Principal id (objectId) to receive the Azure AI User / Foundry User role on the new account. Required in mode=new; ignored in mode=existing.')
param principalId string = ''

@description('In mode=existing, the resource group that contains the existing Foundry account. Defaults to this deployment\'s resource group (ADE typically creates a new RG per environment, so this should usually be set in existing mode).')
param existingResourceGroup string = ''

var isNew = mode == 'new'
var location = resourceGroup().location
var newAccountName = '${foundryName}-${uniqueString(resourceGroup().id)}'
var existingRg = empty(existingResourceGroup) ? resourceGroup().name : existingResourceGroup

// ---------- new branch ----------
resource newAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = if (isNew) {
  name: newAccountName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: newAccountName
    publicNetworkAccess: 'Enabled'
  }
}

resource newProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = if (isNew) {
  parent: newAccount
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// ---------- model deployment (new mode, same RG) ----------
module deployNew 'modules/model-deployment.bicep' = if (isNew) {
  name: 'dep-new-${uniqueString(deploymentName)}'
  dependsOn: [
    newProject
  ]
  params: {
    accountName: newAccountName
    deploymentName: deploymentName
    modelName: 'gpt-4.1-nano'
    modelVersion: '2025-04-14'
    skuName: 'GlobalStandard'
    capacity: 30
    format: 'OpenAI'
  }
}

// ---------- model deployment (existing mode, cross-RG) ----------
module deployExisting 'modules/model-deployment.bicep' = if (!isNew) {
  name: 'dep-exist-${uniqueString(deploymentName)}'
  scope: resourceGroup(existingRg)
  params: {
    accountName: foundryName
    deploymentName: deploymentName
    modelName: 'gpt-4.1-nano'
    modelVersion: '2025-04-14'
    skuName: 'GlobalStandard'
    capacity: 30
    format: 'OpenAI'
  }
}

// ---------- RBAC (new mode only) ----------
module rbac 'modules/rbac.bicep' = if (isNew && !empty(principalId)) {
  name: 'rbac-aiuser'
  dependsOn: [
    newAccount
  ]
  params: {
    accountName: newAccountName
    principalId: principalId
  }
}

output accountName string = isNew ? newAccountName : foundryName
output projectName string = projectName
output deploymentName string = deploymentName
