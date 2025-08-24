# Azure Infrastructure Teardown Script for BookRecommender UI
# Removes all Azure resources created by Setup-Azure.ps1

param(
    [string]$ConfigFile = "../config/azure-config.json"
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

# Load configuration if it exists
if (Test-Path $ConfigFile) {
    Write-Step "Loading configuration from $ConfigFile"
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    
    $SubscriptionId = $config.subscriptionId
    $ResourceGroupName = $config.resourceGroupName
    $GitHubRepo = $config.github.repository
    
    Write-Success "Configuration loaded"
} else {
    Write-Warning "Configuration file not found. Using default values."
    $ResourceGroupName = "rg-bookrecommender-proto"
    $SubscriptionId = az account show --query id -o tsv
    $GitHubRepo = "kiki-sen/proto"
}

# Set the subscription
az account set --subscription $SubscriptionId

# Confirmation prompt
Write-Host ""
Write-Warning "WARNING: DESTRUCTIVE OPERATION"
Write-Host ""
Write-Host "This will permanently DELETE the following resources:"
Write-Host "- Resource Group: $ResourceGroupName"
Write-Host "- All resources within the resource group"
Write-Host "- Managed Identity"
Write-Host "- Static Web App (if created)"
Write-Host "- PostgreSQL Flexible Server (if created)"
Write-Host "- PostgreSQL Database (if created)"
Write-Host "- All associated configurations"
Write-Host ""
Write-Host "GitHub secrets will remain and need to be manually removed if desired."
Write-Host ""

$confirmation = Read-Host "Are you sure you want to proceed? (Type 'DELETE' to confirm)"

if ($confirmation -ne "DELETE") {
    Write-Error "Operation cancelled. Resource group was not deleted."
    exit 1
}

# Check if resource group exists
Write-Step "Checking if resource group exists: $ResourceGroupName"
try {
    $rg = az group show --name $ResourceGroupName 2>$null | ConvertFrom-Json
    Write-Success "Resource group found"
    
    Write-Step "Listing resources in resource group..."
    az resource list --resource-group $ResourceGroupName --output table
    
    Write-Host ""
    Write-Step "Deleting resource group: $ResourceGroupName"
    Write-Warning "This may take several minutes..."
    
    az group delete --name $ResourceGroupName --yes --no-wait
    
    Write-Success "Resource group deletion initiated"
    Write-Warning "Deletion is running in the background. It may take 5-10 minutes to complete."
    
    # Wait for deletion to complete (optional)
    $waitForCompletion = Read-Host "Do you want to wait for deletion to complete? (y/n)"
    
    if ($waitForCompletion -eq "y" -or $waitForCompletion -eq "Y") {
        Write-Step "Waiting for resource group deletion to complete..."
        
        do {
            Write-Host "." -NoNewline
            Start-Sleep -Seconds 10
            $rgExists = $null
            try {
                $rgExists = az group show --name $ResourceGroupName 2>$null
            } catch {
                # Resource group no longer exists
                break
            }
        } while ($rgExists)
        
        Write-Host ""
        Write-Success "Resource group deletion completed"
    }
    
} catch {
    Write-Warning "Resource group '$ResourceGroupName' does not exist or has already been deleted"
}

# Remove configuration file
if (Test-Path $ConfigFile) {
    Write-Step "Removing configuration file: $ConfigFile"
    Remove-Item $ConfigFile -Force
    Write-Success "Configuration file removed"
}

Write-Host ""
Write-Host "Azure Infrastructure Teardown Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "Completed Actions:"
Write-Host "- Resource group deletion initiated: $ResourceGroupName"
Write-Host "- Configuration file removed"
Write-Host "- All Azure resources will be deleted (including PostgreSQL)"
Write-Host ""
Write-Host "Manual Cleanup (Optional):"
Write-Host "- Remove GitHub secrets if no longer needed:"
Write-Host "  - BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID"
Write-Host "  - BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID"
Write-Host "  - BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID"
Write-Host "  - BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP"
Write-Host "  - BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING"
Write-Host "  - AZURE_STATIC_WEB_APPS_API_TOKEN"
Write-Host "- Remove deployment workflow if no longer needed"
Write-Host ""
Write-Host "To remove GitHub secrets, run:"
Write-Host "   gh secret delete BOOKRECOMMENDER_PROTO_AZURE_CLIENT_ID -R $GitHubRepo"
Write-Host "   gh secret delete BOOKRECOMMENDER_PROTO_AZURE_TENANT_ID -R $GitHubRepo"
Write-Host "   gh secret delete BOOKRECOMMENDER_PROTO_AZURE_SUBSCRIPTION_ID -R $GitHubRepo"
Write-Host "   gh secret delete BOOKRECOMMENDER_PROTO_AZURE_RESOURCE_GROUP -R $GitHubRepo"
Write-Host "   gh secret delete BOOKRECOMMENDER_PROTO_POSTGRES_CONNECTION_STRING -R $GitHubRepo"
Write-Host "   gh secret delete AZURE_STATIC_WEB_APPS_API_TOKEN -R $GitHubRepo"
Write-Host ""
