// Shared module: deploys one model on an existing Foundry (CognitiveServices)
// account. Used by both mode=new and mode=existing branches in main.bicep.
//
// The account is referenced via an 'existing' resource on accountName, which
// works whether the account was just created in the same deployment (ARM
// resolves it after creation) or was already present.

param accountName string
param deploymentName string
param modelName string
param modelVersion string
param skuName string
@minValue(1)
param capacity int
param format string = 'OpenAI'

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: account
  name: deploymentName
  sku: {
    name: skuName
    capacity: capacity
  }
  properties: {
    model: {
      format: format
      name: modelName
      version: modelVersion
    }
  }
}

output deploymentId string = deployment.id
output endpoint string = account.properties.endpoint
