<# 
Bootstrap Managed Identity pull + CI permissions for an Azure Web App (Linux container).
Run once locally before enabling CI.

Grants:
- Web App's system-assigned MI -> AcrPull on ACR (for runtime pull)
- CI Service Principal -> Contributor on Web App (so CI can set image:tag)
- CI Service Principal -> AcrPush on ACR (so CI can push images)

USAGE:
.\infra\setup-managed-identity.ps1 `
  -ResourceGroup "bookrec-rg" -WebAppName "bookrec-api" `
  -AcrName "bookrecacr1234" -ImageName "bookrecommenderapi" -Tag "latest" -Port 8080 `
  -CiPrincipal "<appId-or-objectId-of-your-CI-SP>" `
  -OpenAiApiKey $env:OPENAI_API_KEY

  To get CiPrincipal: az ad sp list --display-name github-deploy-proto --query "[0].appId" -o tsv
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string]$ResourceGroup,
  [Parameter(Mandatory)] [string]$WebAppName,
  [Parameter(Mandatory)] [string]$AcrName,         # short name, e.g. myacr
  [Parameter(Mandatory)] [string]$ImageName,       # ACR repo, e.g. bookrecommenderapi
  [string]$Tag = "latest",
  [int]$Port = 8080,
  [string]$OpenAiApiKey,
  [string]$CiPrincipal,                            # appId or objectId of CI SP (clientId from creds)
  [switch]$DryRun
)

$script:DryRun = [bool]$DryRun
function Do-Az { param([Parameter(Mandatory)][string]$Cmd)
  if ($script:DryRun) { Write-Host "DRYRUN> $Cmd" } else { Invoke-Expression $Cmd | Out-Null }
}
function Require-Command($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Missing required command: $cmd" }
}

function Ensure-WebAppMI {
  param([string]$RG,[string]$Name)
  $type = az webapp show -g $RG -n $Name --query "identity.type" -o tsv 2>$null
  if ([string]::IsNullOrWhiteSpace($type) -or ($type -notmatch '^SystemAssigned')) {
    Do-Az "az webapp identity assign -g $RG -n $Name"
  } else { Write-Host "System-assigned identity already enabled on $Name." }
  $azurepid = az webapp show -g $RG -n $Name --query "identity.principalId" -o tsv 2>$null
  if ([string]::IsNullOrWhiteSpace($azurepid)) { throw "Could not resolve principalId for $Name." }
  Write-Host "Web App principalId: $azurepid"
  return $azurepid
}

function Get-AcrResourceGroup { param([string]$Acr)
  $rg = az acr show -n $Acr --query resourceGroup -o tsv
  if ([string]::IsNullOrWhiteSpace($rg)) { throw "ACR '$Acr' not found or no permission to read it." }
  return $rg
}

function Ensure-RoleOnScope {
  param(
    [Parameter(Mandatory)][string]$AssigneeObjectId,
    [Parameter(Mandatory)][string]$RoleName,
    [Parameter(Mandatory)][string]$Scope,
    [string]$AssigneeType = "ServicePrincipal"
  )
  $has = az role assignment list `
          --assignee-object-id $AssigneeObjectId `
          --assignee-principal-type $AssigneeType `
          --scope $Scope `
          --query "[?roleDefinitionName=='$RoleName'] | length(@)" -o tsv 2>$null
  if (($has -as [int]) -gt 0) { Write-Host "$RoleName already present on $Scope for $AssigneeObjectId."; return }
  Do-Az "az role assignment create --assignee-object-id $AssigneeObjectId --assignee-principal-type $AssigneeType --role '$RoleName' --scope $Scope"
}

function Ensure-AcrPull {
  param([string]$PrincipalId,[string]$Acr,[string]$AcrRg,[string]$SubId)
  if ([string]::IsNullOrWhiteSpace($PrincipalId)) { throw "Ensure-AcrPull: PrincipalId is empty." }
  $scope = "/subscriptions/$SubId/resourceGroups/$AcrRg/providers/Microsoft.ContainerRegistry/registries/$Acr"
  Ensure-RoleOnScope -AssigneeObjectId $PrincipalId -RoleName "AcrPull" -Scope $scope
}

function Resolve-ServicePrincipal {
  param([Parameter(Mandatory)][string]$IdOrAppId)
  # Try by objectId first, then appId
  $sp = az ad sp show --id $IdOrAppId -o json 2>$null
  if (-not $sp) { $sp = az ad sp list --filter "appId eq '$IdOrAppId'" -o json 2>$null | ConvertFrom-Json | Select-Object -First 1 | ConvertTo-Json -Depth 5 }
  if (-not $sp) { throw "Could not resolve CI service principal by '$IdOrAppId'. Provide its appId (clientId) or objectId." }
  $obj = $sp | ConvertFrom-Json
  return @{ appId = $obj.appId; objectId = $obj.id }
}

function Ensure-CiPermissions {
  param([string]$CiIdOrAppId,[string]$RG,[string]$Site,[string]$SubId,[string]$Acr,[string]$AcrRg)
  if ([string]::IsNullOrWhiteSpace($CiIdOrAppId)) {
    Write-Warning "CiPrincipal not provided - skipping CI role assignments."
    return
  }
  $sp = Resolve-ServicePrincipal -IdOrAppId $CiIdOrAppId
  $ciObjId = $sp.objectId

  $siteScope = "/subscriptions/$SubId/resourceGroups/$RG/providers/Microsoft.Web/sites/$Site"
  $acrScope  = "/subscriptions/$SubId/resourceGroups/$AcrRg/providers/Microsoft.ContainerRegistry/registries/$Acr"

  # CI needs to configure the site container => Contributor on the site
  Ensure-RoleOnScope -AssigneeObjectId $ciObjId -RoleName "Contributor" -Scope $siteScope

  # CI needs to push to ACR => AcrPush on the registry
  Ensure-RoleOnScope -AssigneeObjectId $ciObjId -RoleName "AcrPush" -Scope $acrScope
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

  # 1) Enable MI pulls first (site config) - use temp file for complex JSON
  $tempFile = [System.IO.Path]::GetTempFileName()
  try {
    '{"acrUseManagedIdentityCreds": true}' | Out-File -FilePath $tempFile -Encoding UTF8 -NoNewline
    if ($script:DryRun) { 
      Write-Host "DRYRUN> az webapp config set -g $RG -n $Name --generic-configurations @$tempFile"
    } else {
      & az webapp config set -g $RG -n $Name --generic-configurations "@$tempFile" | Out-Null
    }
  } finally {
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
  }

  # 2) Point to the image using new flags (no deprecated --docker-*)
  Do-Az "az webapp config container set -g $RG -n $Name --container-image-name $image --container-registry-url https://$LoginServer"

  # 3) Port + optional OpenAI key
  Do-Az "az webapp config appsettings set -g $RG -n $Name --settings WEBSITES_PORT=$Port"
  if ($OpenAI) {
    Do-Az "az webapp config appsettings set -g $RG -n $Name --settings OpenAI__ApiKey=$OpenAI"
  }

  return $image
}

# ---- main ----
Require-Command az
$subId = az account show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($subId)) { throw "Not logged in to Azure CLI. Run 'az login'." }
Write-Host "Using subscription: $subId"

# Make sure provider is registered (safe to re-run)
Do-Az "az provider register -n Microsoft.Web"

# 1) Enable MI and get principalId of the Web App
$webAppMiPrincipalId = Ensure-WebAppMI -RG $ResourceGroup -Name $WebAppName

# 2) ACR RG + grant MI AcrPull (runtime)
$acrRg = Get-AcrResourceGroup -Acr $AcrName
Write-Host "ACR '$AcrName' is in RG: $acrRg"
Ensure-AcrPull -PrincipalId $webAppMiPrincipalId -Acr $AcrName -AcrRg $acrRg -SubId $subId

# 3) Grant CI the rights it needs (configure site + push image)
Ensure-CiPermissions -CiIdOrAppId $CiPrincipal -RG $ResourceGroup -Site $WebAppName -SubId $subId -Acr $AcrName -AcrRg $acrRg

# 4) Wait briefly for RBAC propagation
Start-Sleep -Seconds 5

# 5) Configure the Web App to use the ACR image via MI
$loginServer = "$AcrName.azurecr.io"
Configure-WebAppContainerMI -RG $ResourceGroup -Name $WebAppName -LoginServer $loginServer `
  -ImageRepo $ImageName -Tag $Tag -Port $Port -OpenAI $OpenAiApiKey

Write-Host 'Done. Bootstrapped MI pull + CI permissions. CI can now push to ACR and set image:tag; Web App will pull via MI.'

