<# 
Re-setup Managed Identity pull from ACR for an Azure Web App (Linux container).
Run in PowerShell on Windows. Re-entrant and safe to re-run.

USAGE EXAMPLE:
.\setup-mi-acr.ps1 -ResourceGroup "bookrec-rg" -WebAppName "bookrec-api" `
  -AcrName "bookrecacr1234" -ImageName "bookrecommenderapi" -Tag "latest" -Port 8080 `
  -OpenAiApiKey $env:OPENAI_API_KEY
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$ResourceGroup,     # RG that contains the Web App
  [Parameter(Mandatory)] [string]$WebAppName,        # e.g., bookrec-api
  [Parameter(Mandatory)] [string]$AcrName,           # SHORT ACR name, e.g., bookrecacr1234
  [Parameter(Mandatory)] [string]$ImageName,         # repo name in ACR, e.g., bookrecommenderapi
  [string]$Tag = "latest",
  [int]$Port = 8080,                                 # WEBSITES_PORT
  [string]$OpenAiApiKey,                              # optional; sets OpenAI__ApiKey if provided
  [switch]$DryRun
)

# expose DryRun to helpers
$script:DryRun = [bool]$DryRun

function Do-Az {
  param([Parameter(Mandatory)][string]$Cmd)
  if ($script:DryRun) { Write-Host "DRYRUN> $Cmd" }
  else { Invoke-Expression $Cmd | Out-Null }
}

function Require-Command($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $cmd"
  }
}

function Ensure-WebAppMI {
  param([string]$RG,[string]$Name)

  $type = az webapp show -g $RG -n $Name --query "identity.type" -o tsv 2>$null
  if ([string]::IsNullOrWhiteSpace($type) -or ($type -notmatch '^SystemAssigned')) {
    Do-Az "az webapp identity assign -g $RG -n $Name"
  } else {
    Write-Host "System-assigned identity already enabled on $Name."
  }

  $azurepid = az webapp show -g $RG -n $Name --query "identity.principalId" -o tsv 2>$null
  if ([string]::IsNullOrWhiteSpace($pid)) {
    if ($script:DryRun) {
      Write-Warning "principalId unknown in DryRun (identity would be enabled)."
      return ""
    } else {
      throw "Could not resolve principalId for $Name."
    }
  }

  Write-Host "Web App principalId: $azurepid"
  return $azurepid
}

function Get-AcrResourceGroup {
  param([string]$Acr)
  $rg = az acr show -n $Acr --query resourceGroup -o tsv
  if ([string]::IsNullOrWhiteSpace($rg)) { throw "ACR '$Acr' not found or no permission to read it." }
  return $rg
}

function Ensure-AcrPull {
  param(
    [string]$PrincipalId,
    [string]$Acr,            # short name, e.g. myacr
    [string]$AcrRg,          # ACR's resource group
    [string]$SubId
  )
  if ([string]::IsNullOrWhiteSpace($PrincipalId)) {
    throw "Ensure-AcrPull: PrincipalId is empty."
  }

  $scope = "/subscriptions/$SubId/resourceGroups/$AcrRg/providers/Microsoft.ContainerRegistry/registries/$Acr"
  $has = az role assignment list `
          --assignee-object-id $PrincipalId `
          --assignee-principal-type ServicePrincipal `
          --scope $scope `
          --query "[?roleDefinitionName=='AcrPull'] | length(@)" -o tsv 2>$null

  if (($has -as [int]) -gt 0) {
    Write-Host "AcrPull already present on $scope for $PrincipalId."
    return $true
  }

  Do-Az "az role assignment create --assignee-object-id $PrincipalId --assignee-principal-type ServicePrincipal --role AcrPull --scope $scope"
  return $true
}

function Configure-WebAppContainerMI {
  param(
    [string]$RG,
    [string]$Name,
    [string]$LoginServer,   # e.g. myacr.azurecr.io
    [string]$ImageRepo,     # e.g. bookrecommenderapi (NOT GitHub repo)
    [string]$Tag,
    [int]$Port,
    [string]$OpenAI
  )
  if ([string]::IsNullOrWhiteSpace($ImageRepo)) { throw "ImageRepo (ACR repository name) is required." }

  $image = "$LoginServer/$($ImageRepo):$Tag"
  Write-Host "Set image -> $image"
  Do-Az "az webapp config container set -g $RG -n $Name --docker-custom-image-name $image --docker-registry-server-url https://$LoginServer"
  Do-Az "az webapp config set -g $RG -n $Name --acr-use-managed-identity true"
  Do-Az "az webapp config appsettings set -g $RG -n $Name --settings WEBSITES_PORT=$Port"

  if ($OpenAI) {
    Do-Az "az webapp config appsettings set -g $RG -n $Name --settings OpenAI__ApiKey=$OpenAI"
  }

  return $image
}

# ---- main ----
Require-Command az

# Confirm subscription context
$subId = az account show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($subId)) { throw "Not logged in to Azure CLI. Run 'az login'." }
Write-Host "Using subscription: $subId"

# 1) Ensure MI and get principalId
$azurepid = Ensure-WebAppMI -RG $ResourceGroup -Name $WebAppName
Write-Host "Web App principalId: $azurepid"

# 2) Find ACR RG and ensure AcrPull on ACR scope
$acrRg = Get-AcrResourceGroup -Acr $AcrName
Write-Host "ACR '$AcrName' is in RG: $acrRg"
Ensure-AcrPull -PrincipalId $azurepid -Acr $AcrName -AcrRg $acrRg -SubId $subId

# 3) (optional) tiny wait for RBAC propagation
Start-Sleep -Seconds 5

# 4) Configure Web App to use MI with the ACR image
$loginServer = "$AcrName.azurecr.io"
Configure-WebAppContainerMI -RG $ResourceGroup -Name $WebAppName -LoginServer $loginServer `
  -ImageRepo $ImageName -Tag $Tag -Port $Port -OpenAI $OpenAiApiKey

Write-Host "Done. The Web App '$WebAppName' in RG '$ResourceGroup' is configured to pull from ACR '$AcrName' using Managed Identity."
