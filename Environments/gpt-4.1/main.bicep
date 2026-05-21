// Canonical main.bicep template — one catalog item per model.
// Placeholders (replaced at codegen time per Environments/<model>/):
//   gpt-4.1       e.g. gpt-4.1-mini
//   2025-04-14    e.g. 2025-04-14
//   GlobalStandard         e.g. GlobalStandard
//   30       integer TPM-in-thousands, e.g. 30
//
// User-visible parameters (also surfaced in environment.yaml):
//   foundryName, projectName, deploymentName, mode, principalId

targetScope = 'resourceGroup'

@minLength(2)
@maxLength(50)
@description('Foundry (Cognitive Services) account name. In mode=new this is used as a prefix and the actual account name + customSubDomainName is suffixed with uniqueString(rg) for global uniqueness. In mode=existing it must match an existing account in this resource group.')
param foundryName string

@minLength(2)
@maxLength(50)
@description('Foundry project name (child of the account).')
param projectName string

@minLength(2)
@maxLength(50)
@description('Model deployment name on the Foundry account.')
param deploymentName string

@allowed([
  'new'
  'existing'
])
@description('Whether to create a new Foundry account+project or reference existing ones in this resource group.')
param mode string = 'new'

@description('Principal id (objectId) to receive the Azure AI User role on the new account. Required in mode=new; ignored in mode=existing. ADE supplies the requesting user\'s objectId here via the project environment type configuration.')
param principalId string = ''

var isNew = mode == 'new'
var location = resourceGroup().location
var newAccountName = '${foundryName}-${uniqueString(resourceGroup().id)}'
var accountName = isNew ? newAccountName : foundryName

// ---------- existing branch ----------
resource existingAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = if (!isNew) {
  name: foundryName
}

resource existingProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = if (!isNew) {
  parent: existingAccount
  name: projectName
}

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

// ---------- model deployment (account-scoped) ----------
// Explicit dependsOn covers both branches; ARM removes false-conditional
// resources from the graph automatically.
module deploy 'modules/model-deployment.bicep' = {
  name: 'dep-${uniqueString(deploymentName)}'
  dependsOn: [
    newProject
    existingProject
  ]
  params: {
    accountName: accountName
    deploymentName: deploymentName
    modelName: 'gpt-4.1'
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
    accountName: accountName
    principalId: principalId
  }
}

output accountName string = accountName
output projectName string = projectName
output deploymentName string = deploymentName
output endpoint string = deploy.outputs.endpoint
