# BookRecommender Container App Infrastructure Deployment Script
# This script is re-entrant and can be safely executed multiple times

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

# Set error action preference for better error handling
$ErrorActionPreference = "Stop"

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

    # Register required Azure providers (idempotent operation)
    Write-Host "Checking and registering Azure providers..." -ForegroundColor Yellow
    
    $providers = @("Microsoft.App", "Microsoft.OperationalInsights", "Microsoft.ContainerRegistry")
    foreach ($provider in $providers) {
        $providerStatus = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
        if ($providerStatus -eq "Registered") {
            Write-Host "   $provider is already registered" -ForegroundColor Green
        } else {
            Write-Host "   Registering $provider provider..." -ForegroundColor Yellow
            az provider register --namespace $provider --wait
            Write-Host "   $provider registered successfully" -ForegroundColor Green
        }
    }
    Write-Host "All Azure providers are registered" -ForegroundColor Green

    # Create resource group if it doesn't exist (idempotent operation)
    Write-Host "Checking resource group..." -ForegroundColor Yellow
    $existingRg = az group show --name $ResourceGroup 2>$null
    if ($existingRg) {
        Write-Host "Resource group '$ResourceGroup' already exists" -ForegroundColor Green
    } else {
        Write-Host "Creating resource group '$ResourceGroup'..." -ForegroundColor Yellow
        az group create --name $ResourceGroup --location $Location --tags project=bookrecommender environment=proto
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create resource group"
        }
        Write-Host "Resource group '$ResourceGroup' created successfully" -ForegroundColor Green
    }

    # Deploy the Bicep template with unique deployment name
    $deploymentName = "container-app-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Deploying Container App infrastructure (deployment: $deploymentName)..." -ForegroundColor Yellow
    
    # Check if Bicep file exists (try multiple locations)
    $bicepFile = $null
    $possiblePaths = @("./container-app.bicep", "./infra/container-app.bicep", "../container-app.bicep")
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $bicepFile = $path
            break
        }
    }
    
    if (!$bicepFile) {
        throw "Bicep template file 'container-app.bicep' not found. Searched in: $($possiblePaths -join ', ')"
    }
    
    Write-Host "Using Bicep template: $bicepFile" -ForegroundColor Green
    
    $deploymentOutput = az deployment group create `
        --resource-group $ResourceGroup `
        --name $deploymentName `
        --template-file $bicepFile `
        --parameters `
            containerAppName=$ContainerAppName `
            environmentName=$EnvironmentName `
            location=$Location `
            containerImage=$ContainerImage `
        --query 'properties.outputs' `
        --output json

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to deploy infrastructure. Check the deployment logs in the Azure portal for details."
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
    Write-Host "This script is re-entrant and can be safely run multiple times." -ForegroundColor Blue

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
