// Shared module: assigns 'Azure AI User' role on a Foundry account to a
// caller-supplied principalId. Only invoked from main.bicep in mode=new.

param accountName string
param principalId string

// Azure AI User (built-in)
var roleDefinitionId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(account.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'User'
  }
}
