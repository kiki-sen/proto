# infra/setup-azure.ps1
<#
.SYNOPSIS
  Idempotent setup for Azure resources used by the Book Recommender project.

.PROVISIONS
  - Resource Group
  - Azure Container Registry (ACR)
  - PostgreSQL Flexible Server (+ DB + firewall rule for Azure services)
  - App Service Plan (Linux) + Web App for Containers (API)
  - Managed Identity on Web App + AcrPull role on ACR
  - App Settings (ASPNETCORE_*) and Connection String (DefaultConnection)
  - (Optional) Azure Static Web App for Angular UI

.PREREQS
  az login
  az account set --subscription "<SUB_ID_OR_NAME>"

.EXAMPLE
  pwsh ./infra/setup-azure.ps1 `
    -Subscription "YOUR-SUB-ID" `
    -Location "westeurope" `
    -ResourceGroup "bookrec-rg" `
    -AcrName "bookrecacr1234" `
    -WebAppName "bookrec-api" `
    -PgServerName "bookrecpg1234" `
    -PgAdminUser "bookuser" `
    -PgAdminPassword "SuperS3cure!123" `
    -PgDatabase "bookdb" `
    -Tier "Burstable" `
    -SkuName "Standard_B1ms" `
    -CreateStaticWebApp:$true `
    -StaticWebAppName "bookrec-ui"
#>

param(
  [Parameter(Mandatory)] [string] $Subscription,
  [Parameter(Mandatory)] [string] $Location,
  [Parameter(Mandatory)] [string] $ResourceGroup,

  [Parameter(Mandatory)] [string] $AcrName,          # globally unique
  [Parameter(Mandatory)] [string] $WebAppName,       # unique in *.azurewebsites.net
  [Parameter(Mandatory)] [string] $PgServerName,     # unique in *.postgres.database.azure.com
  [Parameter(Mandatory)] [string] $PgAdminUser,
  [Parameter(Mandatory)] [string] $PgAdminPassword,
  [Parameter(Mandatory)] [string] $PgDatabase,

  [ValidateSet("Burstable","GeneralPurpose","MemoryOptimized")]
  [string] $Tier = "Burstable",

  # Examples:
  #   Burstable:       Standard_B1ms | Standard_B2s | Standard_B2ms | Standard_B4ms ...
  #   GeneralPurpose:  Standard_D2s_v3 | Standard_D4s_v3 ...
  #   MemoryOptimized: Standard_E2s_v3 | Standard_E4s_v3 ...
  [string] $SkuName = "Standard_B1ms",

  [switch] $CreateStaticWebApp = $false,
  [string] $StaticWebAppName = ""
)

# Prevent native stderr from becoming terminating errors
$PSNativeCommandUseErrorActionPreference = $false

$ErrorActionPreference = "Stop"

function Ensure-Providers {
  param([string[]] $Namespaces)

  foreach ($ns in $Namespaces) {
    $state = az provider show -n $ns --query registrationState -o tsv 2>$null
    if (-not $state -or $state -ne "Registered") {
      Write-Host ">> Registering provider '$ns'..."
      az provider register -n $ns | Out-Null

      # Wait until Registered (max ~3 minutes)
      $tries = 0
      do {
        Start-Sleep -Seconds 6
        $state = az provider show -n $ns --query registrationState -o tsv 2>$null
        $tries++
      } while ($state -ne "Registered" -and $tries -lt 30)

      if ($state -ne "Registered") {
        throw "Provider '$ns' did not reach 'Registered' state in time."
      }
    } else {
      Write-Host ">> Provider '$ns' already Registered."
    }
  }
}

function Az-Exists {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]] $AzArgs)
  $args = @($AzArgs + @("--only-show-errors"))
  $cmd  = "az " + ($args -join " ")
  $null = & cmd /c "$cmd >NUL 2>NUL"
  return ($LASTEXITCODE -eq 0)
}
Write-Host ">> Selecting subscription..." -ForegroundColor Cyan
az account set --subscription $Subscription | Out-Null

Ensure-Providers @(
  "Microsoft.DBforPostgreSQL",
  "Microsoft.ContainerRegistry",
  "Microsoft.Web"
)

# ---------- Resource Group ----------
if (-not (Az-Exists group show -n $ResourceGroup)) {
  Write-Host ">> Creating resource group '$ResourceGroup' in $Location..."
  az group create -n $ResourceGroup -l $Location --tags app=bookrec env=dev | Out-Null
} else {
  Write-Host ">> Resource group '$ResourceGroup' already exists. Skipping."
}

# ---------- ACR ----------
if (-not (Az-Exists acr show -g $ResourceGroup -n $AcrName)) {
  Write-Host ">> Creating ACR '$AcrName' (Basic)..."
  az acr create -g $ResourceGroup -n $AcrName --sku Basic --admin-enabled false | Out-Null
} else {
  Write-Host ">> ACR '$AcrName' already exists. Skipping."
}

# ---------- Postgres Flexible Server ----------
if (-not (Az-Exists postgres flexible-server show -g $ResourceGroup -n $PgServerName)) {
  Write-Host ">> Creating Postgres Flexible Server '$PgServerName' ($Tier / $SkuName)..."
  az postgres flexible-server create `
    -g $ResourceGroup -n $PgServerName -l $Location `
    -u $PgAdminUser -p $PgAdminPassword `
    --version 16 --tier $Tier --sku-name $SkuName --storage-size 32 --yes | Out-Null
} else {
  Write-Host ">> Postgres server '$PgServerName' already exists. Skipping."
}

# ---------- Database ----------
if (-not (Az-Exists postgres flexible-server db show -g $ResourceGroup -s $PgServerName -d $PgDatabase)) {
  Write-Host ">> Creating database '$PgDatabase'..."
  az postgres flexible-server db create -g $ResourceGroup -s $PgServerName -d $PgDatabase | Out-Null
} else {
  Write-Host ">> Database '$PgDatabase' already exists. Skipping."
}

# ---------- Firewall rule for Azure services (0.0.0.0) ----------
# List existing rules (fix: use -n for server name)
$fwRules = az postgres flexible-server firewall-rule list `
  -g $ResourceGroup -n $PgServerName `
  --query "[].name" -o tsv 2>$null
if ($LASTEXITCODE -ne 0 -or -not $fwRules) { $fwRules = @() }

$fwRuleName = "AllowAllAzureIPs"
if ($fwRules -notcontains $fwRuleName) {
  Write-Host ">> Adding firewall rule '$fwRuleName'..."
  az postgres flexible-server firewall-rule create `
    -g $ResourceGroup -n $PgServerName `
    --rule-name $fwRuleName `
    --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 | Out-Null
} else {
  Write-Host ">> Firewall rule '$fwRuleName' already exists. Skipping."
}

# ---------- App Service Plan (Linux) ----------
$planName = "$WebAppName-plan"
if (-not (Az-Exists appservice plan show -g $ResourceGroup -n $planName)) {
  Write-Host ">> Creating App Service Plan '$planName' (Linux B1)..."
  az appservice plan create -g $ResourceGroup -n $planName --is-linux --sku B1 | Out-Null
} else {
  Write-Host ">> App Service Plan '$planName' already exists. Skipping."
}

# ---------- Web App (API) ----------
if (-not (Az-Exists webapp show -g $ResourceGroup -n $WebAppName)) {
  Write-Host ">> Creating Web App '$WebAppName' (container placeholder)..."
  az webapp create `
    -g $ResourceGroup `
    -n $WebAppName `
    -p $planName `
    --deployment-container-image-name mcr.microsoft.com/dotnet/aspnet:9.0 | Out-Null
} else {
  Write-Host ">> Web App '$WebAppName' already exists. Skipping."
}

# ---------- Managed Identity on Web App ----------
Write-Host ">> Enabling Managed Identity on Web App..."
$principalId = az webapp identity assign -g $ResourceGroup -n $WebAppName --query principalId -o tsv

# ---------- Grant AcrPull on ACR ----------
Write-Host ">> Granting AcrPull role on ACR to Web App identity..."
$acrId = az acr show -g $ResourceGroup -n $AcrName --query id -o tsv
try {
  az role assignment create --assignee $principalId --role "AcrPull" --scope $acrId | Out-Null
} catch {
  # Ignore if role assignment already exists
}

# ---------- App settings on Web App ----------
$pgHost = "$PgServerName.postgres.database.azure.com"

Write-Host ">> Setting Web App application settings..."
az webapp config appsettings set -g $ResourceGroup -n $WebAppName --settings `
  "ASPNETCORE_URLS=http://+:8080" `
  "WEBSITES_PORT=8080" `
  "ASPNETCORE_ENVIRONMENT=Docker" | Out-Null

# ---------- Connection String (DefaultConnection) ----------
Write-Host ">> Setting connection string in Web App '$WebAppName'..."
$connectionString = "Host=$pgHost;Database=$PgDatabase;Username=$PgAdminUser;Password=$PgAdminPassword;Ssl Mode=Require;Trust Server Certificate=True"
az webapp config connection-string set `
  --resource-group $ResourceGroup `
  --name $WebAppName `
  --settings DefaultConnection="$connectionString" `
  --connection-string-type=PostgreSQL | Out-Null

# ---------- Container settings (use MI for ACR, AlwaysOn) ----------
Write-Host ">> Configuring Web App container settings (Managed Identity for ACR, AlwaysOn)..."
$siteId = az webapp show -g $ResourceGroup -n $WebAppName --query id -o tsv
az resource update --ids $siteId --set properties.siteConfig.alwaysOn=true | Out-Null
az resource update --ids $siteId --set properties.siteConfig.acrUseManagedIdentityCreds=true | Out-Null

# (Your GitHub Action will set the actual container image + tag on each deploy)

# ---------- Optional: Static Web App for Angular ----------
$swaLocation = "westeurope"  # valid SWA region
if ($CreateStaticWebApp -and $StaticWebAppName) {
  if (-not (Az-Exists staticwebapp show -g $ResourceGroup -n $StaticWebAppName)) {
    Write-Host ">> Creating Static Web App '$StaticWebAppName' (Free) in $swaLocation..."
    az staticwebapp create -g $ResourceGroup -n $StaticWebAppName -l $swaLocation --sku Free | Out-Null
    Write-Host "   NOTE: In Azure Portal, copy the Deployment Token and save as GitHub Secret: AZURE_STATIC_WEB_APPS_API_TOKEN"
  } else {
    Write-Host ">> Static Web App '$StaticWebAppName' already exists. Skipping."
  }
}

Write-Host ""
Write-Host "=========== OUTPUTS ===========" -ForegroundColor Cyan
Write-Host "Resource Group:         $ResourceGroup"
Write-Host "ACR:                    $AcrName"
Write-Host "Web App (API):          $WebAppName"
Write-Host "App Service Plan:       $planName"
Write-Host "Postgres Host:          $pgHost"
Write-Host "Postgres Admin User:    $PgAdminUser"
Write-Host "Postgres DB:            $PgDatabase"
Write-Host "PG Tier/SKU:            $Tier / $SkuName"
if ($CreateStaticWebApp -and $StaticWebAppName) {
  Write-Host "Static Web App:         $StaticWebAppName"
}
Write-Host "================================"
Write-Host ""
Write-Host "Next:"
Write-Host "  - Add GitHub Secrets: AZURE_CREDENTIALS, AZURE_RG, AZURE_WEBAPP_NAME, AZURE_ACR_NAME"
Write-Host "  - (optional) OPENAI_API_KEY, AZURE_STATIC_WEB_APPS_API_TOKEN"
Write-Host "  - Push to main to trigger CI/CD"
