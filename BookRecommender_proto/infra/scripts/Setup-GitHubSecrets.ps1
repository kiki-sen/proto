# GitHub Secrets Setup Script for BookRecommender Proto
param(
    [string]$ConfigFile = "../config/azure-config.json"
)

$ErrorActionPreference = "Stop"

Write-Host "[STEP] Checking GitHub CLI installation..." -ForegroundColor Blue
try {
    $ghVersion = gh version 2>$null
    Write-Host "[SUCCESS] GitHub CLI found" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] GitHub CLI is not installed. Please install it first." -ForegroundColor Red
    Write-Host "[ERROR] Download from: https://cli.github.com/" -ForegroundColor Red
    exit 1
}

Write-Host "[STEP] Checking GitHub CLI authentication..." -ForegroundColor Blue
try {
    $ghAuth = gh auth status 2>&1
    Write-Host "[SUCCESS] GitHub CLI authenticated" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Please run 'gh auth login' first" -ForegroundColor Red
    exit 1
}

Write-Host "[STEP] Loading Azure configuration..." -ForegroundColor Blue
if (-not (Test-Path $ConfigFile)) {
    Write-Host "[ERROR] Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "[ERROR] Please run '.\Setup-Azure.ps1' first" -ForegroundColor Red
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json
Write-Host "[SUCCESS] Configuration loaded successfully" -ForegroundColor Green

$SubscriptionId = $config.subscriptionId
$TenantId = $config.tenantId
$ResourceGroupName = $config.resourceGroupName
$ClientId = $config.managedIdentity.clientId
$GitHubRepo = $config.github.repository
$StaticWebAppName = $config.staticWebApp.name
$PostgresConnectionString = $config.postgresql.connectionString

Write-Host "[STEP] Setting GitHub repository context to: $GitHubRepo" -ForegroundColor Blue

Write-Host "[STEP] Creating GitHub secret: BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID" -ForegroundColor Blue
$ClientId | gh secret set BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID -R $GitHubRepo
Write-Host "[SUCCESS] Secret BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID created" -ForegroundColor Green

Write-Host "[STEP] Creating GitHub secret: BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID" -ForegroundColor Blue
$TenantId | gh secret set BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID -R $GitHubRepo
Write-Host "[SUCCESS] Secret BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID created" -ForegroundColor Green

Write-Host "[STEP] Creating GitHub secret: BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID" -ForegroundColor Blue
$SubscriptionId | gh secret set BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID -R $GitHubRepo
Write-Host "[SUCCESS] Secret BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID created" -ForegroundColor Green

Write-Host "[STEP] Creating GitHub secret: BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP" -ForegroundColor Blue
$ResourceGroupName | gh secret set BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP -R $GitHubRepo
Write-Host "[SUCCESS] Secret BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP created" -ForegroundColor Green

Write-Host "[STEP] Creating GitHub secret: BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING" -ForegroundColor Blue
$PostgresConnectionString | gh secret set BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING -R $GitHubRepo
Write-Host "[SUCCESS] Secret BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING created" -ForegroundColor Green

Write-Host "[STEP] Retrieving Static Web App deployment token..." -ForegroundColor Blue
try {
    $deploymentToken = az staticwebapp secrets list --name $StaticWebAppName --resource-group $ResourceGroupName --query "properties.apiKey" -o tsv
    if ([string]::IsNullOrEmpty($deploymentToken)) {
        Write-Host "[ERROR] Failed to retrieve deployment token. Make sure the Static Web App exists." -ForegroundColor Red
        exit 1
    }
    Write-Host "[SUCCESS] Deployment token retrieved" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to retrieve deployment token. Make sure the Static Web App exists and you have access." -ForegroundColor Red
    exit 1
}

Write-Host "[STEP] Creating GitHub secret: AZURE_STATIC_WEB_APPS_API_TOKEN" -ForegroundColor Blue
$deploymentToken | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN -R $GitHubRepo
Write-Host "[SUCCESS] Secret AZURE_STATIC_WEB_APPS_API_TOKEN created" -ForegroundColor Green

Write-Host "[STEP] Verifying GitHub secrets..." -ForegroundColor Blue
$secretsList = gh secret list -R $GitHubRepo --json name | ConvertFrom-Json

$expectedSecrets = @(
    "BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID",
    "BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID", 
    "BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID",
    "BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP",
    "BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING",
    "AZURE_STATIC_WEB_APPS_API_TOKEN"
)

$allFound = $true
foreach ($secretName in $expectedSecrets) {
    $found = $false
    foreach ($secret in $secretsList) {
        if ($secret.name -eq $secretName) {
            $found = $true
            break
        }
    }
    if ($found) {
        Write-Host "[SUCCESS] Secret found: $secretName" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Secret missing: $secretName" -ForegroundColor Red
        $allFound = $false
    }
}

Write-Host ""
if ($allFound) {
    Write-Host "GitHub Secrets Created Successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Created Secrets:"
    Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID"
    Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID"
    Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID"
    Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP"
    Write-Host "- BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING"
    Write-Host "- AZURE_STATIC_WEB_APPS_API_TOKEN"
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "1. Push changes to trigger the deployment workflow"
    Write-Host "2. The workflow will use managed identity for Azure authentication"
    Write-Host "3. Monitor GitHub Actions for deployment status"
} else {
    Write-Host "Some secrets failed to create. Please check the output above." -ForegroundColor Red
    exit 1
}
