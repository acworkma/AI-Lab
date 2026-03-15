// Azure Container App Module
// Deploys a container app into an existing ACA environment with managed identity,
// ACR pull configuration, internal ingress, and health probes
//
// Usage: Deploy application containers to an existing Container Apps environment
// Dependencies: ACA environment, private ACR

targetScope = 'resourceGroup'

// ============================================================================
// REQUIRED PARAMETERS
// ============================================================================

@description('Name of the container app')
@minLength(2)
@maxLength(32)
param appName string

@description('Azure region for deployment')
param location string

@description('Resource ID of the Container Apps Environment')
param environmentId string

@description('Container image to deploy (e.g., myacr.azurecr.io/app:v1)')
param containerImage string

@description('ACR login server (e.g., myacr.azurecr.io)')
param acrLoginServer string

// ============================================================================
// OPTIONAL PARAMETERS
// ============================================================================

@description('Target port for the container')
param targetPort int = 3333

@description('Enable external ingress (false = internal only)')
param externalIngress bool = false

@description('CPU cores allocated to the container')
param cpu string = '0.25'

@description('Memory allocated to the container (e.g., 0.5Gi)')
param memory string = '0.5Gi'

@description('Minimum number of replicas')
param minReplicas int = 1

@description('Maximum number of replicas')
param maxReplicas int = 3

@description('Environment variables as array of {name, value} objects')
param envVars array = []

@description('Health probe path for liveness and readiness checks')
param healthProbePath string = '/health'

@description('Resource tags')
param tags object = {}

// ============================================================================
// CONTAINER APP
// ============================================================================

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: externalIngress
        targetPort: targetPort
        transport: 'http'
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: appName
          image: containerImage
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: envVars
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: healthProbePath
                port: targetPort
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: healthProbePath
                port: targetPort
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Container app resource ID')
output id string = containerApp.id

@description('Container app name')
output name string = containerApp.name

@description('Container app FQDN')
output fqdn string = containerApp.properties.configuration.ingress.fqdn

@description('Container app latest revision name')
output latestRevision string = containerApp.properties.latestRevisionName

@description('System-assigned managed identity principal ID')
output principalId string = containerApp.identity.principalId
