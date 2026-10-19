param location string = resourceGroup().location
param baseName string = 'agrosig'
param deployApp bool = false
param imageTag string = 'v1'

param dbAdminUser string = 'agrosigadmin'
@secure()
param dbAdminPassword string
@secure()
param jwtSecret string
@secure()
param jwtRefreshSecret string
@secure()
param apiClima string
@secure()
param firebasePrivateKey string
param plainEnv object = {}

var suffix = uniqueString(resourceGroup().id)
var appName = 'ca-${baseName}-api'

// ---------- Observabilidad ----------
resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${baseName}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: json('0.5') }
  }
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${baseName}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

// ---------- Registro e identidad ----------
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acr${baseName}${suffix}'
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${baseName}'
  location: location
}

// ---------- Key Vault ----------
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${baseName}-${take(suffix, 8)}'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// Secretos en Key Vault — array fijo para evitar limitaciones de for-loop en propiedades anidadas
var kvSecretList = [
  { name: 'db-password',         value: dbAdminPassword   }
  { name: 'jwt-secret',          value: jwtSecret         }
  { name: 'jwt-refresh-secret',  value: jwtRefreshSecret  }
  { name: 'api-clima',           value: apiClima          }
  { name: 'firebase-private-key',value: firebasePrivateKey}
]

resource kvSecretRes 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for s in kvSecretList: {
  parent: kv
  name: s.name
  properties: { value: s.value }
}]

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, identity.id, 'acrpull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, identity.id, 'kvsecretsuser')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------- PostgreSQL ----------
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: 'pg-${baseName}-${suffix}'
  location: location
  sku: { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: dbAdminUser
    administratorLoginPassword: dbAdminPassword
    storage: { storageSizeGB: 32 }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
    network: { publicNetworkAccess: 'Enabled' }
  }
}

resource pgExtensions 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: pg
  name: 'azure.extensions'
  properties: { value: 'POSTGIS', source: 'user-override' }
}

resource pgDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: 'agrosig_db'
  dependsOn: [pgExtensions]
}

resource pgFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pg
  name: 'AllowAzureServices'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
  dependsOn: [pgDb]
}

// ---------- API ----------
var appUrl = 'https://${appName}.${cae.properties.defaultDomain}'

// Secretos referenciados en Container Apps (array fijo, igual estructura que kvSecretList)
var caSecrets = [
  { name: 'db-password',          keyVaultUrl: '${kv.properties.vaultUri}secrets/db-password',          identity: identity.id }
  { name: 'jwt-secret',           keyVaultUrl: '${kv.properties.vaultUri}secrets/jwt-secret',           identity: identity.id }
  { name: 'jwt-refresh-secret',   keyVaultUrl: '${kv.properties.vaultUri}secrets/jwt-refresh-secret',   identity: identity.id }
  { name: 'api-clima',            keyVaultUrl: '${kv.properties.vaultUri}secrets/api-clima',            identity: identity.id }
  { name: 'firebase-private-key', keyVaultUrl: '${kv.properties.vaultUri}secrets/firebase-private-key', identity: identity.id }
]

// Variables de entorno base (sin secretos)
var baseEnv = [
  { name: 'NODE_ENV',          value: 'production'                        }
  { name: 'PORT',              value: '4000'                              }
  { name: 'TZ',                value: 'America/Mexico_City'               }
  { name: 'DB_HOST',           value: pg.properties.fullyQualifiedDomainName }
  { name: 'DB_PORT',           value: '5432'                              }
  { name: 'DB_NAME',           value: 'agrosig_db'                        }
  { name: 'DB_USER',           value: dbAdminUser                         }
  { name: 'ENDPOINT_SWAGGER',  value: appUrl                              }
  { name: 'BASE_URL',          value: appUrl                              }
]

// Variables de entorno con secretos (secretRef)
var secretEnv = [
  { name: 'DB_PASSWORD',           secretRef: 'db-password'          }
  { name: 'JWT_SECRET',            secretRef: 'jwt-secret'           }
  { name: 'JWT_REFRESH_SECRET',    secretRef: 'jwt-refresh-secret'   }
  { name: 'API_CLIMA',             secretRef: 'api-clima'            }
  { name: 'FIREBASE_PRIVATE_KEY',  secretRef: 'firebase-private-key' }
]

// Variables de entorno planas adicionales (pasadas como objeto desde parámetros)
var plainEnvArray = [for e in items(plainEnv): { name: e.key, value: e.value }]

resource app 'Microsoft.App/containerApps@2024-03-01' = if (deployApp) {
  name: appName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: { external: true, targetPort: 4000, allowInsecure: false }
      registries: [
        { server: acr.properties.loginServer, identity: identity.id }
      ]
      secrets: caSecrets
    }
    template: {
      containers: [
        {
          name: 'api'
          image: '${acr.properties.loginServer}/agrosig-api:${imageTag}'
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          env: concat(baseEnv, secretEnv, plainEnvArray)
          probes: [
            {
              type: 'Startup'
              httpGet: { path: '/health', port: 4000 }
              periodSeconds: 5
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: { path: '/health', port: 4000 }
              periodSeconds: 30
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health/db', port: 4000 }
              periodSeconds: 15
            }
          ]
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
  dependsOn: [kvSecretRes, kvSecretsRole, acrPullRole, pgFirewall]
}

output acrLoginServer string = acr.properties.loginServer
output keyVaultName string = kv.name
output apiUrl string = appUrl
