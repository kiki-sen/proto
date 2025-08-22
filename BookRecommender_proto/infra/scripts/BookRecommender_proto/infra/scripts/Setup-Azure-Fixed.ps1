# Azure Infrastructure Setup Script for BookRecommender UI
# Creates Managed Identity and GitHub OIDC integration
# Static Web App will be created by GitHub Actions workflow

param(
    [string]$SubscriptionId = "",
    [string]$ResourceGroupName = "rg-bookrecommender-proto",
    [string]$Location = "East US",
    [string]$ManagedIdentityName = "id-bookrecommender-github",
    [string]$GitHubRepo = "kiki-sen/proto"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Colors for output
function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check if Azure CLI is installed
Write-Step "Checking Azure CLI installation..."
try {
    $azVersion = az version 2>$null | ConvertFrom-Json
    Write-Success "Azure CLI version: $($azVersion.'azure-cli')"
} catch {
    Write-Error "Azure CLI is not installed. Please install it first."
    Write-Error "Download from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
}

# Check if user is logged in
Write-Step "Checking Azure CLI authentication..."
try {
    $account = az account show 2>$null | ConvertFrom-Json
    Write-Success "Logged in as: $($account.user.name)"
} catch {
    Write-Error "Please run 'az login' first"
    exit 1
}

# Get subscription ID if not provided
if ([string]::IsNullOrEmpty($SubscriptionId)) {
    $SubscriptionId = az account show --query id -o tsv
    Write-Success "Using subscription: $SubscriptionId"
}

# Set the subscription
Write-Step "Setting subscription context..."
az account set --subscription $SubscriptionId

Write-Step "Creating Resource Group: $ResourceGroupName"
az group create --name $ResourceGroupName --location $Location --output table

Write-Success "Resource Group created successfully"

Write-Step "Creating Managed Identity: $ManagedIdentityName"
$managedIdentityResult = az identity create `
    --name $ManagedIdentityName `
    --resource-group $ResourceGroupName `
    --output json | ConvertFrom-Json

$ClientId = $managedIdentityResult.clientId
$PrincipalId = $managedIdentityResult.principalId

Write-Success "Managed Identity created successfully"
Write-Success "Client ID: $ClientId"

Write-Step "Assigning Contributor role to Managed Identity for Resource Group"
az role assignment create `
    --assignee $PrincipalId `
    --role "Contributor" `
    --resource-group $ResourceGroupName

Write-Success "Contributor role assigned to Resource Group"

Write-Step "Setting up GitHub OIDC federation"
# Create federated identity credential for main branch
az identity federated-credential create `
    --name "github-main" `
    --identity-name $ManagedIdentityName `
    --resource-group $ResourceGroupName `
    --issuer "https://token.actions.githubusercontent.com" `
    --subject "repo:$GitHubRepo:ref:refs/heads/main" `
    --audience "api://AzureADTokenExchange"

# Create federated identity credential for pull requests
az identity federated-credential create `
    --name "github-pr" `
    --identity-name $ManagedIdentityName `
    --resource-group $ResourceGroupName `
    --issuer "https://token.actions.githubusercontent.com" `
    --subject "repo:$GitHubRepo:pull_request" `
    --audience "api://AzureADTokenExchange"

Write-Success "GitHub OIDC federation configured"

Write-Step "Creating configuration file..."
$TenantId = az account show --query tenantId -o tsv
$ConfigFile = "../config/azure-config.json"

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
        }
    }
    staticWebApp = @{
        name = "swa-bookrecommender-ui"
        appLocation = "/BookRecommender_proto/ui"
        outputLocation = "dist"
    }
}

$config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigFile -Encoding UTF8
Write-Success "Configuration saved to $ConfigFile"

Write-Host ""
Write-Host "Azure Infrastructure Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:"
Write-Host "- Resource Group: $ResourceGroupName"
Write-Host "- Managed Identity: $ManagedIdentityName"
Write-Host "- Client ID: $ClientId"
Write-Host "- GitHub OIDC configured for: $GitHubRepo"
Write-Host ""
Write-Host "GitHub Secrets (with unique names):"
Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID: $ClientId"
Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID: $TenantId"
Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID: $SubscriptionId"
Write-Host "- BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP: $ResourceGroupName"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "1. Run '.\Setup-GitHubSecrets.ps1' to automatically create GitHub secrets"
Write-Host "2. Update your GitHub Actions workflow to use the managed identity"
Write-Host "3. Push changes to trigger deployment"
Write-Host ""
Write-Host "The GitHub Actions workflow will handle:"
Write-Host "- Creating the Azure Static Web App"
Write-Host "- Building the Angular application"
Write-Host "- Deploying to Azure Static Web Apps"
Write-Host ""
