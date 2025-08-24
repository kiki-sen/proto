# BookRecommender Container App Infrastructure Teardown Script
# This script is re-entrant and can be safely executed multiple times
# Removes all Azure resources created by Deploy-ContainerApp.ps1

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-bookrecommender-proto",
    
    [Parameter(Mandatory = $false)]
    [string]$ContainerAppName = "bookrecommender-api",
    
    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName = "bookrecommender-env",
    
    [Parameter(Mandatory = $false)]
    [switch]$KeepResourceGroup = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force = $false
)

# Set error action preference for better error handling
$ErrorActionPreference = "Stop"

Write-Host "BookRecommender Container App Infrastructure Teardown" -ForegroundColor Red
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Cyan
Write-Host "Container App: $ContainerAppName" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentName" -ForegroundColor Cyan

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

    # Check if resource group exists
    Write-Host "Checking if resource group exists..." -ForegroundColor Yellow
    try {
        $existingRg = az group show --name $ResourceGroup --query "name" -o tsv 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($existingRg)) {
            Write-Host "Resource group '$ResourceGroup' does not exist. Nothing to clean up." -ForegroundColor Yellow
            
            # Clean up any local files that might exist
            if (Test-Path "container-app-url.txt") {
                Write-Host "Removing local file: container-app-url.txt" -ForegroundColor Yellow
                Remove-Item "container-app-url.txt" -Force
                Write-Host "Local file removed" -ForegroundColor Green
            }
            
            Write-Host ""
            Write-Host "Container App Infrastructure Teardown Summary" -ForegroundColor Green
            Write-Host "" 
            Write-Host "Completed Actions:" -ForegroundColor Green
            Write-Host "- No Azure resources found to delete"
            Write-Host "- Local configuration files cleaned up (if any)"
            Write-Host ""
            Write-Host "This script is re-entrant and can be safely run multiple times." -ForegroundColor Blue
            exit 0
        }
    } catch {
        Write-Host "Resource group '$ResourceGroup' does not exist. Nothing to clean up." -ForegroundColor Yellow
        
        # Clean up any local files that might exist
        if (Test-Path "container-app-url.txt") {
            Write-Host "Removing local file: container-app-url.txt" -ForegroundColor Yellow
            Remove-Item "container-app-url.txt" -Force
            Write-Host "Local file removed" -ForegroundColor Green
        }
        
        Write-Host ""
        Write-Host "Container App Infrastructure Teardown Summary" -ForegroundColor Green
        Write-Host "" 
        Write-Host "Completed Actions:" -ForegroundColor Green
        Write-Host "- No Azure resources found to delete"
        Write-Host "- Local configuration files cleaned up (if any)"
        Write-Host ""
        Write-Host "This script is re-entrant and can be safely run multiple times." -ForegroundColor Blue
        exit 0
    }
    Write-Host "Resource group '$ResourceGroup' found" -ForegroundColor Green

    # Safety confirmation (unless -Force is specified)
    if (!$Force) {
        Write-Host ""
        Write-Host "WARNING: DESTRUCTIVE OPERATION" -ForegroundColor Red
        Write-Host ""
        Write-Host "This will permanently DELETE the following resources:" -ForegroundColor Yellow
        Write-Host "- Container App: $ContainerAppName"
        Write-Host "- Container Environment: $EnvironmentName"
        Write-Host "- Log Analytics Workspace: ${ContainerAppName}-logs"
        if (!$KeepResourceGroup) {
            Write-Host "- Resource Group: $ResourceGroup (and ALL resources within it)"
        }
        Write-Host ""
        
        $confirmation = Read-Host "Are you sure you want to proceed? (Type 'DELETE' to confirm)"
        if ($confirmation -ne "DELETE") {
            Write-Host "Operation cancelled. No resources were deleted." -ForegroundColor Yellow
            exit 0
        }
    }

    # If keeping resource group, delete individual resources
    if ($KeepResourceGroup) {
        Write-Host ""
        Write-Host "Deleting individual Container App resources..." -ForegroundColor Yellow

        # Delete Container App
        Write-Host "Checking Container App: $ContainerAppName" -ForegroundColor Yellow
        $existingApp = az containerapp show --name $ContainerAppName --resource-group $ResourceGroup 2>$null
        if ($existingApp) {
            Write-Host "Deleting Container App: $ContainerAppName" -ForegroundColor Red
            az containerapp delete --name $ContainerAppName --resource-group $ResourceGroup --yes
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Container App '$ContainerAppName' deleted successfully" -ForegroundColor Green
            } else {
                Write-Host "Failed to delete Container App '$ContainerAppName'" -ForegroundColor Red
            }
        } else {
            Write-Host "Container App '$ContainerAppName' does not exist" -ForegroundColor Yellow
        }

        # Delete Container Apps Environment
        Write-Host "Checking Container Apps Environment: $EnvironmentName" -ForegroundColor Yellow
        $existingEnv = az containerapp env show --name $EnvironmentName --resource-group $ResourceGroup 2>$null
        if ($existingEnv) {
            Write-Host "Deleting Container Apps Environment: $EnvironmentName" -ForegroundColor Red
            az containerapp env delete --name $EnvironmentName --resource-group $ResourceGroup --yes
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Container Apps Environment '$EnvironmentName' deleted successfully" -ForegroundColor Green
            } else {
                Write-Host "Failed to delete Container Apps Environment '$EnvironmentName'" -ForegroundColor Red
            }
        } else {
            Write-Host "Container Apps Environment '$EnvironmentName' does not exist" -ForegroundColor Yellow
        }

        # Delete Log Analytics Workspace
        $logAnalyticsName = "${ContainerAppName}-logs"
        Write-Host "Checking Log Analytics Workspace: $logAnalyticsName" -ForegroundColor Yellow
        $existingLogs = az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $logAnalyticsName 2>$null
        if ($existingLogs) {
            Write-Host "Deleting Log Analytics Workspace: $logAnalyticsName" -ForegroundColor Red
            az monitor log-analytics workspace delete --resource-group $ResourceGroup --workspace-name $logAnalyticsName --yes --force
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Log Analytics Workspace '$logAnalyticsName' deleted successfully" -ForegroundColor Green
            } else {
                Write-Host "Failed to delete Log Analytics Workspace '$logAnalyticsName'" -ForegroundColor Red
            }
        } else {
            Write-Host "Log Analytics Workspace '$logAnalyticsName' does not exist" -ForegroundColor Yellow
        }

    } else {
        # Delete entire resource group
        Write-Host ""
        Write-Host "Deleting entire resource group..." -ForegroundColor Yellow
        
        Write-Host "Listing resources in resource group..." -ForegroundColor Yellow
        az resource list --resource-group $ResourceGroup --output table
        
        Write-Host ""
        Write-Host "Deleting resource group: $ResourceGroup" -ForegroundColor Red
        Write-Host "This may take several minutes..." -ForegroundColor Yellow
        
        az group delete --name $ResourceGroup --yes --no-wait
        
        Write-Host "Resource group deletion initiated" -ForegroundColor Green
        Write-Host "Deletion is running in the background. It may take 5-10 minutes to complete." -ForegroundColor Yellow
        
        # Optional: Wait for deletion to complete
        $waitForCompletion = Read-Host "Do you want to wait for deletion to complete? (y/n)"
        
        if ($waitForCompletion -eq "y" -or $waitForCompletion -eq "Y") {
            Write-Host "Waiting for resource group deletion to complete..." -ForegroundColor Yellow
            
            do {
                Write-Host "." -NoNewline
                Start-Sleep -Seconds 10
                $rgExists = $null
                try {
                    $rgExists = az group show --name $ResourceGroup 2>$null
                } catch {
                    # Resource group no longer exists
                    break
                }
            } while ($rgExists)
            
            Write-Host ""
            Write-Host "Resource group deletion completed" -ForegroundColor Green
        }
    }

    # Clean up local files
    if (Test-Path "container-app-url.txt") {
        Write-Host "Removing local file: container-app-url.txt" -ForegroundColor Yellow
        Remove-Item "container-app-url.txt" -Force
        Write-Host "Local file removed" -ForegroundColor Green
    }

    # Success summary
    Write-Host ""
    Write-Host "Container App Infrastructure Teardown Summary" -ForegroundColor Green
    Write-Host ""
    if ($KeepResourceGroup) {
        Write-Host "Completed Actions:" -ForegroundColor Green
        Write-Host "- Container App resources deleted from resource group: $ResourceGroup"
        Write-Host "- Resource group preserved as requested"
    } else {
        Write-Host "Completed Actions:" -ForegroundColor Green
        Write-Host "- Resource group deletion initiated: $ResourceGroup"
        Write-Host "- All Container App resources will be deleted"
    }
    Write-Host "- Local configuration files cleaned up"
    Write-Host ""
    Write-Host "This script is re-entrant and can be safely run multiple times." -ForegroundColor Blue

} catch {
    Write-Host ""
    Write-Host "Teardown failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "1. Make sure you're logged into Azure: az login"
    Write-Host "2. Check that you have the right permissions on the subscription"
    Write-Host "3. Verify the resource group exists: az group show --name $ResourceGroup"
    Write-Host "4. Check Azure CLI version: az --version"
    exit 1
}
