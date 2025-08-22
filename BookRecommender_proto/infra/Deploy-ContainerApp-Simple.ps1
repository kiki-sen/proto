# BookRecommender Container App Infrastructure Deployment Script
# Run this once to set up the Azure Container Apps infrastructure

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-bookrecommender-proto",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory = $false)]
    [string]$ContainerAppName = "bookrecommender-api",
    
    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName = "bookrecommender-env",
    
    [Parameter(Mandatory = $false)]
    [string]$ContainerImage = "ghcr.io/kiki-sen/proto/bookrecommender-api:latest"
)

Write-Host "Deploying BookRecommender Container App Infrastructure..." -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Cyan
Write-Host "Location: $Location" -ForegroundColor Cyan
Write-Host "Container App: $ContainerAppName" -ForegroundColor Cyan

try {
    # Check if Azure CLI is installed and user is logged in
    if (!(Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI is not installed. Please install it first."
    }

    # Check if logged into Azure
    $accountInfo = az account show 2>$null
    if (!$accountInfo) {
        throw "Not logged into Azure. Please run 'az login' first."
    }

    $currentAccount = $accountInfo | ConvertFrom-Json
    Write-Host "Logged into Azure as: $($currentAccount.user.name)" -ForegroundColor Green

    # Register required Azure providers (one-time setup)
    Write-Host "Registering Azure providers..." -ForegroundColor Yellow
    Write-Host "   Registering Microsoft.App provider..."
    az provider register --namespace Microsoft.App --wait
    Write-Host "   Registering Microsoft.OperationalInsights provider..."
    az provider register --namespace Microsoft.OperationalInsights --wait
    Write-Host "   Registering Microsoft.ContainerRegistry provider..."
    az provider register --namespace Microsoft.ContainerRegistry --wait
    Write-Host "Azure providers registered successfully" -ForegroundColor Green

    # Create resource group if it doesn't exist
    Write-Host "Creating resource group..." -ForegroundColor Yellow
    az group create --name $ResourceGroup --location $Location --tags project=bookrecommender environment=proto

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create resource group"
    }

    # Deploy the Bicep template
    Write-Host "Deploying Container App infrastructure..." -ForegroundColor Yellow
    $deploymentOutput = az deployment group create --resource-group $ResourceGroup --template-file "./container-app.bicep" --parameters containerAppName=$ContainerAppName environmentName=$EnvironmentName location=$Location containerImage=$ContainerImage --query 'properties.outputs' --output json

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to deploy infrastructure"
    }

    # Parse the deployment outputs
    $outputs = $deploymentOutput | ConvertFrom-Json
    $containerAppUrl = $outputs.containerAppUrl.value
    $deployedContainerAppName = $outputs.containerAppName.value

    # Success message
    Write-Host ""
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
    Write-Host "Container App URL: $containerAppUrl" -ForegroundColor Cyan
    Write-Host "Container App Name: $deployedContainerAppName" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Update the Angular app's API URL to: $containerAppUrl"
    Write-Host "2. Push your API code to trigger the build and deploy workflows"
    Write-Host "3. The API will be available at: $containerAppUrl/api/health"
    Write-Host ""
    Write-Host "This script only needs to be run once (or when infrastructure changes)." -ForegroundColor Blue

    # Optional: Save the URL to a file for easy reference
    $containerAppUrl | Out-File -FilePath "container-app-url.txt" -Encoding UTF8
    Write-Host "Container App URL saved to: container-app-url.txt" -ForegroundColor Gray

} catch {
    Write-Host ""
    Write-Host "Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "1. Make sure you're logged into Azure: az login"
    Write-Host "2. Check that you have the right permissions on the subscription"
    Write-Host "3. Verify the Bicep file exists: ./container-app.bicep"
    Write-Host "4. Check Azure CLI version: az --version"
    exit 1
}
