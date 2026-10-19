# AgroSig — Backend DevOps en Azure

Sistema de gestión agrícola desplegado en Azure como proyecto del bootcamp de DevOps.
El backend original (Node.js + Express + PostgreSQL/PostGIS) se empaquetó en contenedor
y se llevó a un flujo CI/CD completo sobre Azure.

## Temas del bootcamp que cubre

- **Contenedores** — imagen Docker multi-stage, Docker Compose para desarrollo local
- **Infraestructura como código** — todos los recursos de Azure definidos en Bicep (`infra/main.bicep`)
- **Registro de contenedores** — Azure Container Registry (ACR)
- **Cómputo serverless** — Azure Container Apps
- **Base de datos** — Azure Database for PostgreSQL Flexible Server con extensión PostGIS
- **Gestión de secretos** — Azure Key Vault + Managed Identity (sin credenciales en la imagen)
- **Observabilidad** — Log Analytics Workspace integrado con Container Apps
- **CI/CD** — Pipeline de Azure DevOps: test → build → push ACR → deploy

## URL del backend en producción

```
https://ca-agrosig-api.salmonbeach-34a9e766.mexicocentral.azurecontainerapps.io
```

Endpoints de salud:
- `GET /health` — liveness (servidor corriendo)
- `GET /health/db` — readiness (conexión a base de datos)
- `GET /api-docs` — documentación Swagger

## Arquitectura

```
┌─────────────────────────────────────────────────────┐
│                   Azure (mexicocentral)              │
│                                                      │
│  ┌─────────┐    ┌──────────────────────────────┐    │
│  │   ACR   │───▶│     Container Apps           │    │
│  │ (image) │    │     ca-agrosig-api           │    │
│  └─────────┘    │     Node.js + Express        │    │
│                 └──────────────┬───────────────┘    │
│                                │                    │
│  ┌─────────┐    ┌──────────────▼───────────────┐    │
│  │Key Vault│◀───│     Managed Identity         │    │
│  │(secrets)│    │     id-agrosig               │    │
│  └─────────┘    └──────────────────────────────┘    │
│                                │                    │
│  ┌─────────────────────────────▼───────────────┐    │
│  │  PostgreSQL Flexible Server + PostGIS        │    │
│  │  pg-agrosig-...                              │    │
│  └─────────────────────────────────────────────┘    │
│                                                      │
│  ┌─────────────────────────────────────────────┐    │
│  │  Log Analytics Workspace — log-agrosig       │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

## Estructura del repositorio

```
agrosig-devops/
├── infra/
│   ├── main.bicep                    # IaC: todos los recursos de Azure
│   └── main.parameters.example.json  # Plantilla de parámetros (sin secretos)
├── server/                           # Backend Node.js/Express
│   ├── src/
│   ├── migrations/                   # Migraciones db-migrate (schema + seeds)
│   ├── Dockerfile                    # Build multi-stage con tini
│   ├── package.json
│   └── config.js
├── docker-compose.yml                # Desarrollo local (api + postgis)
├── azure-pipelines.yml               # Pipeline CI/CD de Azure DevOps
└── docs/                             # Capturas de evidencia y diagrama
```

## Desarrollo local

Requisitos: Docker Desktop o Docker Engine con Compose.

```bash
# Levantar API + PostgreSQL localmente
docker compose up

# La API queda disponible en http://localhost:4000
# Las migraciones corren automáticamente al iniciar
```

## Despliegue en Azure

### Prerrequisitos

- Azure CLI instalado y sesión activa (`az login`)
- Bicep CLI (`az bicep install`)
- Docker con acceso al ACR (`az acr login --name <acr-name>`)

### 1. Crear el Resource Group

```bash
az group create --name rg-agrosig-mx --location mexicocentral
```

### 2. Desplegar infraestructura base

```bash
az deployment group create \
  --resource-group rg-agrosig-mx \
  --template-file infra/main.bicep \
  --parameters \
      dbAdminPassword='<password>' \
      jwtSecret='<secret>' \
      jwtRefreshSecret='<secret>' \
      apiClima='<openweather-key>' \
      firebasePrivateKey='disabled' \
      deployApp=false
```

### 3. Build y push de la imagen

```bash
ACR=$(az acr list --resource-group rg-agrosig-mx --query "[0].loginServer" -o tsv)
az acr login --name ${ACR%%.*}
docker build -t $ACR/agrosig-api:v1 ./server
docker push $ACR/agrosig-api:v1
```

### 4. Desplegar la Container App

```bash
az deployment group create \
  --resource-group rg-agrosig-mx \
  --template-file infra/main.bicep \
  --parameters \
      dbAdminPassword='<password>' \
      jwtSecret='<secret>' \
      jwtRefreshSecret='<secret>' \
      apiClima='<openweather-key>' \
      firebasePrivateKey='disabled' \
      deployApp=true
```

## Pipeline CI/CD

El archivo `azure-pipelines.yml` en la raíz define el pipeline de Azure DevOps con los stages:

1. **Test** — ejecuta los tests de Jest
2. **Build & Push** — construye la imagen Docker y la publica en ACR
3. **Deploy** — actualiza la revisión activa en Container Apps

## Notas de costos

Los recursos de Azure generan consumo. Para cuentas con créditos de prueba:
- Configurar alertas de presupuesto en Azure Cost Management
- Eliminar el resource group al terminar las pruebas: `az group delete --name rg-agrosig-mx`
- PostgreSQL Flexible Server es el recurso de mayor costo (~$13-15 USD/mes en Standard_B1ms)
