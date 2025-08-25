# Azure Infrastructure Setup Script for BookRecommender UI
param(
    [string]$SubscriptionId = "",
    [string]$ResourceGroupName = "rg-bookrecommender-proto",
    [string]$Location = "northeurope",
    [string]$StaticWebAppLocation = "westeurope",
    [string]$ManagedIdentityName = "id-bookrecommender-github",
    [string]$GitHubRepo = "kiki-sen/proto",
    [string]$PostgresServerName = "pg-bookrecommender-proto",
    [string]$PostgresAdminUser = "pgadmin",
    [string]$PostgresAdminPassword = "Secure123!",
    [string]$PostgresDatabase = "bookrecommender"
)

$ErrorActionPreference = "Stop"


Write-Host "[STEP] Checking Azure CLI installation..." -ForegroundColor Blue
try {
    $azVersion = az version 2>$null | ConvertFrom-Json
    Write-Host "[SUCCESS] Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Azure CLI is not installed. Please install it first." -ForegroundColor Red
    exit 1
}

Write-Host "[STEP] Checking Azure CLI authentication..." -ForegroundColor Blue
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Host "[SUCCESS] Logged in as: $($account.user.name)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Please run 'az login' first" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrEmpty($SubscriptionId)) {
    $SubscriptionId = az account show --query id -o tsv
    Write-Host "[SUCCESS] Using subscription: $SubscriptionId" -ForegroundColor Green
}

Write-Host "[STEP] Setting subscription context..." -ForegroundColor Blue
az account set --subscription $SubscriptionId

Write-Host "[STEP] Creating Resource Group: $ResourceGroupName" -ForegroundColor Blue
try {
    $existingRg = az group show --name $ResourceGroupName 2>$null | ConvertFrom-Json
    Write-Host "[SUCCESS] Resource Group already exists" -ForegroundColor Green
} catch {
    az group create --name $ResourceGroupName --location $Location --output table
    Write-Host "[SUCCESS] Resource Group created successfully" -ForegroundColor Green
}

Write-Host "[STEP] Creating Managed Identity: $ManagedIdentityName" -ForegroundColor Blue
$managedIdentityResult = $null
try {
    $managedIdentityResult = az identity show --name $ManagedIdentityName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    Write-Host "[SUCCESS] Managed Identity already exists" -ForegroundColor Green
} catch {
    Write-Host "[INFO] Creating new Managed Identity..." -ForegroundColor Blue
    $managedIdentityResult = az identity create --name $ManagedIdentityName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    Write-Host "[SUCCESS] Managed Identity created successfully" -ForegroundColor Green
    
    # Wait a moment for the identity to be fully provisioned
    Write-Host "[INFO] Waiting for Managed Identity to be fully provisioned..." -ForegroundColor Blue
    Start-Sleep -Seconds 15
}

if (-not $managedIdentityResult) {
    Write-Host "[ERROR] Failed to create or retrieve Managed Identity" -ForegroundColor Red
    exit 1
}

$ClientId = $managedIdentityResult.clientId
$PrincipalId = $managedIdentityResult.principalId

if ([string]::IsNullOrEmpty($ClientId) -or [string]::IsNullOrEmpty($PrincipalId)) {
    Write-Host "[ERROR] Managed Identity creation failed - missing ClientId or PrincipalId" -ForegroundColor Red
    Write-Host "[DEBUG] ClientId: '$ClientId'" -ForegroundColor Yellow
    Write-Host "[DEBUG] PrincipalId: '$PrincipalId'" -ForegroundColor Yellow
    exit 1
}

Write-Host "[SUCCESS] Client ID: $ClientId" -ForegroundColor Green
Write-Host "[SUCCESS] Principal ID: $PrincipalId" -ForegroundColor Green

Write-Host "[STEP] Assigning Contributor role to Managed Identity for Resource Group" -ForegroundColor Blue
$rgScope = az group show --name $ResourceGroupName --query id -o tsv
try {
    $existingAssignment = az role assignment list --assignee $PrincipalId --scope $rgScope --role "Contributor" 2>$null | ConvertFrom-Json
    if ($existingAssignment.Count -gt 0) {
        Write-Host "[SUCCESS] Contributor role already assigned to Resource Group" -ForegroundColor Green
    } else {
        az role assignment create --assignee $PrincipalId --role "Contributor" --scope $rgScope
        Write-Host "[SUCCESS] Contributor role assigned to Resource Group" -ForegroundColor Green
    }
} catch {
    az role assignment create --assignee $PrincipalId --role "Contributor" --scope $rgScope
    Write-Host "[SUCCESS] Contributor role assigned to Resource Group" -ForegroundColor Green
}

Write-Host "[STEP] Cleaning up old App Registration approaches (if any)" -ForegroundColor Blue
try {
    $oldApps = az ad app list --display-name "github-deploy-proto" --query "[].{appId:appId,displayName:displayName}" | ConvertFrom-Json
    if ($oldApps -and $oldApps.Count -gt 0) {
        foreach ($app in $oldApps) {
            Write-Host "[INFO] Found old App Registration: $($app.displayName) ($($app.appId))" -ForegroundColor Yellow
            Write-Host "[INFO] Deleting old App Registration to ensure clean Managed Identity setup..." -ForegroundColor Yellow
            az ad app delete --id $app.appId
            Write-Host "[SUCCESS] Old App Registration deleted" -ForegroundColor Green
        }
    } else {
        Write-Host "[INFO] No old App Registrations found" -ForegroundColor Green
    }
} catch {
    Write-Host "[INFO] No cleanup needed for App Registrations" -ForegroundColor Green
}

Write-Host "[STEP] Setting up GitHub OIDC federation with Managed Identity" -ForegroundColor Blue

# Delete and recreate main branch credential to ensure correct format
try {
    az identity federated-credential delete --name "github-main" --identity-name $ManagedIdentityName --resource-group $ResourceGroupName --yes 2>$null
    Write-Host "[INFO] Deleted existing main branch credential" -ForegroundColor Yellow
} catch {
    Write-Host "[INFO] No existing main branch credential to delete" -ForegroundColor Green
}

$mainSubject = "repo:${GitHubRepo}:ref:refs/heads/main"
Write-Host "[INFO] Creating main credential with subject: $mainSubject" -ForegroundColor Blue
Write-Host "[DEBUG] GitHubRepo variable is: '$GitHubRepo'" -ForegroundColor Cyan
try {
    az identity federated-credential create --name "github-main" --identity-name $ManagedIdentityName --resource-group $ResourceGroupName --issuer "https://token.actions.githubusercontent.com" --subject "$mainSubject" --audience "api://AzureADTokenExchange"
    Write-Host "[SUCCESS] GitHub main branch credential created with correct subject" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to create main branch federated credential" -ForegroundColor Red
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Delete and recreate PR credential to ensure correct format
try {
    az identity federated-credential delete --name "github-pr" --identity-name $ManagedIdentityName --resource-group $ResourceGroupName --yes 2>$null
    Write-Host "[INFO] Deleted existing PR credential" -ForegroundColor Yellow
} catch {
    Write-Host "[INFO] No existing PR credential to delete" -ForegroundColor Green
}

$prSubject = "repo:${GitHubRepo}:pull_request"
Write-Host "[INFO] Creating PR credential with subject: $prSubject" -ForegroundColor Blue
try {
    az identity federated-credential create --name "github-pr" --identity-name $ManagedIdentityName --resource-group $ResourceGroupName --issuer "https://token.actions.githubusercontent.com" --subject "$prSubject" --audience "api://AzureADTokenExchange"
    Write-Host "[SUCCESS] GitHub PR credential created with correct subject" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to create PR federated credential" -ForegroundColor Red
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "[SUCCESS] GitHub OIDC federation configured" -ForegroundColor Green

Write-Host "[STEP] Creating Azure Static Web App..." -ForegroundColor Blue
$StaticWebAppName = "swa-bookrecommender-ui"
try {
    $existingSwa = az staticwebapp show --name $StaticWebAppName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    Write-Host "[SUCCESS] Static Web App already exists" -ForegroundColor Green
} catch {
    Write-Host "[INFO] Creating new Static Web App: $StaticWebAppName" -ForegroundColor Blue
    # Create Static Web App without GitHub integration (we'll handle deployment via GitHub Actions)
    $swaResult = az staticwebapp create --name $StaticWebAppName --resource-group $ResourceGroupName --location $StaticWebAppLocation --output json | ConvertFrom-Json
    Write-Host "[SUCCESS] Static Web App created successfully" -ForegroundColor Green
    
    # Wait a moment for the resource to be fully provisioned
    Write-Host "[INFO] Waiting for Static Web App to be fully provisioned..." -ForegroundColor Blue
    Start-Sleep -Seconds 10
}


Write-Host "[STEP] Creating PostgreSQL Flexible Server..." -ForegroundColor Blue
try {
    $existingPostgres = az postgres flexible-server show --name $PostgresServerName --resource-group $ResourceGroupName 2>$null | ConvertFrom-Json
    Write-Host "[SUCCESS] PostgreSQL server already exists" -ForegroundColor Green
} catch {
    Write-Host "[INFO] Creating new PostgreSQL Flexible Server: $PostgresServerName" -ForegroundColor Blue
    
    # Generate a unique server name if the default is taken
    $actualServerName = $PostgresServerName
    $attempts = 0
    $serverCreated = $false
    
    while ($attempts -lt 5 -and -not $serverCreated) {
        try {
            Write-Host "[INFO] Attempting to create server: $actualServerName in location: $Location" -ForegroundColor Blue
            
            # Use Start-Process to better handle Azure CLI output and avoid PowerShell parsing issues
            $processArgs = @(
                'postgres', 'flexible-server', 'create',
                '--name', $actualServerName,
                '--resource-group', $ResourceGroupName,
                '--location', $Location,
                '--admin-user', $PostgresAdminUser,
                '--admin-password', $PostgresAdminPassword,
                '--sku-name', 'Standard_B2s',
                '--tier', 'Burstable',
                '--storage-size', '32',
                '--version', '16',
                '--public-access', '0.0.0.0',
                '--yes'
            )
            
            $process = Start-Process -FilePath 'az' -ArgumentList $processArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\postgres-create-stdout.txt" -RedirectStandardError "$env:TEMP\postgres-create-stderr.txt"
            $stdout = Get-Content "$env:TEMP\postgres-create-stdout.txt" -Raw -ErrorAction SilentlyContinue
            $stderr = Get-Content "$env:TEMP\postgres-create-stderr.txt" -Raw -ErrorAction SilentlyContinue
            
            # Clean up temp files
            Remove-Item "$env:TEMP\postgres-create-stdout.txt" -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\postgres-create-stderr.txt" -ErrorAction SilentlyContinue
            
            if ($process.ExitCode -eq 0) {
                Write-Host "[SUCCESS] PostgreSQL server created: $actualServerName" -ForegroundColor Green
                $PostgresServerName = $actualServerName
                $serverCreated = $true
            } else {
                $errorOutput = if ($stderr) { $stderr } else { $stdout }
                if ($errorOutput -match "location is restricted" -or $errorOutput -match "not available in the location") {
                    Write-Host "[ERROR] Location '$Location' does not support PostgreSQL Flexible Server" -ForegroundColor Red
                    Write-Host "[INFO] Please try with a different location such as: North Europe, West Europe, UK South, or other supported regions" -ForegroundColor Yellow
                    exit 1
                } elseif ($errorOutput -match "already exists" -or $errorOutput -match "already taken") {
                    $attempts++
                    $actualServerName = "$PostgresServerName-$attempts"
                    Write-Host "[INFO] Name taken, trying: $actualServerName" -ForegroundColor Yellow
                } else {
                    Write-Host "[ERROR] Failed to create PostgreSQL server. Exit code: $($process.ExitCode)" -ForegroundColor Red
                    if ($errorOutput) {
                        Write-Host "[ERROR] Error details: $errorOutput" -ForegroundColor Red
                    }
                    exit 1
                }
            }
        } catch {
            Write-Host "[ERROR] Exception during PostgreSQL server creation: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    
    if (-not $serverCreated) {
        Write-Host "[ERROR] Could not create PostgreSQL server after $attempts attempts" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[INFO] Waiting for PostgreSQL server to be fully provisioned..." -ForegroundColor Blue
    Start-Sleep -Seconds 30
}

Write-Host "[STEP] Creating PostgreSQL database..." -ForegroundColor Blue
try {
    $existingDb = az postgres flexible-server db show --server-name $PostgresServerName --resource-group $ResourceGroupName --database-name $PostgresDatabase 2>$null | ConvertFrom-Json
    Write-Host "[SUCCESS] Database already exists" -ForegroundColor Green
} catch {
    Write-Host "[INFO] Creating database: $PostgresDatabase" -ForegroundColor Blue
    az postgres flexible-server db create `
        --server-name $PostgresServerName `
        --resource-group $ResourceGroupName `
        --database-name $PostgresDatabase
    Write-Host "[SUCCESS] Database created successfully" -ForegroundColor Green
}

Write-Host "[STEP] Configuring PostgreSQL firewall rules..." -ForegroundColor Blue
try {
    # Allow Azure services - check for existing firewall rules
    $existingRules = az postgres flexible-server firewall-rule list --server-name $PostgresServerName --resource-group $ResourceGroupName --query "[?name=='AllowAllAzureServicesAndResourcesWithinAzureIps']" 2>$null | ConvertFrom-Json
    if ($existingRules -and $existingRules.Count -gt 0) {
        Write-Host "[SUCCESS] Azure services firewall rule already exists" -ForegroundColor Green
    } else {
        Write-Host "[INFO] Creating Azure services firewall rule" -ForegroundColor Blue
        az postgres flexible-server firewall-rule create `
            --name $PostgresServerName `
            --rule-name "AllowAllAzureServicesAndResourcesWithinAzureIps" `
            --resource-group $ResourceGroupName `
            --start-ip-address 0.0.0.0 `
            --end-ip-address 0.0.0.0
        Write-Host "[SUCCESS] Azure services firewall rule created" -ForegroundColor Green
    }
} catch {
    Write-Host "[INFO] Creating Azure services firewall rule (fallback)" -ForegroundColor Blue
    az postgres flexible-server firewall-rule create `
        --name $PostgresServerName `
        --rule-name "AllowAllAzureServicesAndResourcesWithinAzureIps" `
        --resource-group $ResourceGroupName `
        --start-ip-address 0.0.0.0 `
        --end-ip-address 0.0.0.0 2>$null
    Write-Host "[SUCCESS] Azure services firewall rule created" -ForegroundColor Green
}

Write-Host "[STEP] Creating configuration file..." -ForegroundColor Blue
$TenantId = az account show --query tenantId -o tsv
$ConfigFile = "../config/azure-config.json"

# Ensure config directory exists
$ConfigDir = Split-Path -Path $ConfigFile -Parent
if (-not (Test-Path -Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    Write-Host "[INFO] Created config directory: $ConfigDir" -ForegroundColor Blue
}

$config = @{
    subscriptionId = $SubscriptionId
    tenantId = $TenantId
    resourceGroupName = $ResourceGroupName
    location = $Location
    managedIdentity = @{
        name = $ManagedIdentityName
        clientId = $ClientId
        principalId = $PrincipalId
    }
    github = @{
        repository = $GitHubRepo
        secrets = @{
            clientId = "BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID"
            tenantId = "BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID"
            subscriptionId = "BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID"
            resourceGroup = "BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP"
            postgresConnectionString = "BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING"
        }
    }
    staticWebApp = @{
        name = "swa-bookrecommender-ui"
        appLocation = "/BookRecommender_proto/ui"
        outputLocation = "dist"
    }
    postgresql = @{
        serverName = $PostgresServerName
        adminUser = $PostgresAdminUser
        adminPassword = $PostgresAdminPassword
        database = $PostgresDatabase
        connectionString = "Host=$PostgresServerName.postgres.database.azure.com;Database=$PostgresDatabase;Username=$PostgresAdminUser;Password=$PostgresAdminPassword;SSL Mode=Require;Trust Server Certificate=true"
    }
}

$config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigFile -Encoding UTF8
Write-Host "[SUCCESS] Configuration saved to $ConfigFile" -ForegroundColor Green

Write-Host ""
Write-Host "Azure Infrastructure Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:"
Write-Host "- Resource Group: $ResourceGroupName"
Write-Host "- Managed Identity: $ManagedIdentityName"
Write-Host "- Client ID: $ClientId"
Write-Host "- Static Web App: $StaticWebAppName"
Write-Host "- PostgreSQL Server: $PostgresServerName"
Write-Host "- PostgreSQL Database: $PostgresDatabase"
Write-Host "- GitHub OIDC configured for: $GitHubRepo"
Write-Host ""
Write-Host "GitHub Secrets (with unique names):"
Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID: $ClientId"
Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID: $TenantId"
Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID: $SubscriptionId"
Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP: $ResourceGroupName"
$postgresConnectionString = "Host=$PostgresServerName.postgres.database.azure.com;Database=$PostgresDatabase;Username=$PostgresAdminUser;Password=$PostgresAdminPassword;SSL Mode=Require;Trust Server Certificate=true"
Write-Host "- BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING: $postgresConnectionString"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "1. Run 'Setup-GitHubSecrets.ps1' to automatically create GitHub secrets"
Write-Host "2. Update your GitHub Actions workflow to use the managed identity"
Write-Host "3. Push changes to trigger deployment"
