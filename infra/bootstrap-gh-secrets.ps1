param(
  [string]$ResourceGroup = "bookrec-rg",
  [string]$WebAppName = "bookrec-api",
  [string]$AcrName,
  [string]$SwaName,
  [string]$SpName,
  [string]$SubscriptionId,
  [string]$Repo,                  # owner/repo; auto-detected if omitted
  [string]$OpenAiApiKey = $env:OPENAI_API_KEY,
  [switch]$Force,                 # overwrite existing GH secrets
  [switch]$RotateSpCredential,     # rotate SP client secret & update AZURE_CREDENTIALS
  [string]$UserSecretsProject = "BookRecommender/backend/BookRecommenderApi/BookRecommenderApi.csproj"
)

function Require-Command($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Error "Missing required command: $cmd"; exit 1
  }
}
Require-Command az; Require-Command gh

# Repo detection
if (-not $Repo) {
  try {
    $info = gh repo view --json name,owner | ConvertFrom-Json
    $Repo = "$($info.owner.login)/$($info.name)"
  } catch { Write-Error "Cannot detect repo. Pass -Repo owner/repo."; exit 1 }
}
Write-Host "GitHub repo: $Repo"

# Azure subscription
if (-not $SubscriptionId) { $SubscriptionId = az account show --query id -o tsv }
Write-Host "Azure subscription: $SubscriptionId"

# RG check
$rgExists = az group exists -n $ResourceGroup | ConvertFrom-Json
if (-not $rgExists) { Write-Error "Resource group '$ResourceGroup' not found."; exit 1 }

# ACR detect
if (-not $AcrName) {
  $AcrName = az acr list -g $ResourceGroup --query "[0].name" -o tsv
  if (-not $AcrName) { Write-Error "No ACR in RG. Pass -AcrName."; exit 1 }
}
Write-Host "ACR: $AcrName"

# SWA token (optional)
$SwaToken = ""
if ($SwaName) {
  try {
    az extension show -n staticwebapp *> $null
  } catch { az extension add -n staticwebapp *> $null }
  try {
    $SwaToken = az staticwebapp secrets list -n $SwaName -g $ResourceGroup --query "properties.apiKey" -o tsv
  } catch { Write-Warning "Could not fetch SWA token automatically." }
}

# Helpers to check & set GH secrets without clobbering
function Get-SecretNames() {
  $out = gh api -H "Accept: application/vnd.github+json" "/repos/$Repo/actions/secrets" --paginate `
         | ConvertFrom-Json
  $names = @()
  if ($out -is [array]) { $out | ForEach-Object { $names += $_.secrets.name } }
  elseif ($out) { $names = $out.secrets.name }
  return $names
}
$existing = @{}
(Get-SecretNames) | ForEach-Object { $existing[$_] = $true }

function Set-Secret($name, $value) {
  if (-not $value) { Write-Host "Skipping $name (empty)"; return }
  if (-not $Force -and $existing.ContainsKey($name)) {
    Write-Host "Skipping $name (already exists; use -Force to overwrite)"; return
  }
  Write-Host "Setting secret: $name"
  $value | gh secret set $name -R $Repo --body -
}

# Service principal / AZURE_CREDENTIALS
if (-not $SpName) { $SpName = "github-deploy-$($Repo.Split('/')[1])" }
$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

# Only (re)generate credentials if:
#  - AZURE_CREDENTIALS secret doesn't exist, or
#  - user asked to rotate
$needCreds = $Force -or (-not $existing.ContainsKey('AZURE_CREDENTIALS')) -or $RotateSpCredential

$spJson = $null
if ($needCreds) {
  Write-Host "Ensuring service principal '$SpName' and generating credentials..."
  try {
    # Try create; if exists, fall into catch
    $spJson = az ad sp create-for-rbac --name $SpName --sdk-auth --role contributor --scopes $scope | Out-String
  } catch {
    # Reuse existing SP, rotate secret only if requested (or if AZURE_CREDENTIALS missing)
    $appId = az ad sp list --display-name $SpName --query "[0].appId" -o tsv
    if (-not $appId) { throw "Service principal '$SpName' not found and could not be created." }
    if ($RotateSpCredential -or (-not $existing.ContainsKey('AZURE_CREDENTIALS')) -or $Force) {
      $password = az ad app credential reset --id $appId --append --query password -o tsv
      $tenantId = az account show --query tenantId -o tsv
      $spObj = @{
        clientId = $appId
        clientSecret = $password
        subscriptionId = $SubscriptionId
        tenantId = $tenantId
        activeDirectoryEndpointUrl = "https://login.microsoftonline.com"
        resourceManagerEndpointUrl = "https://management.azure.com/"
        activeDirectoryGraphResourceId = "https://graph.windows.net/"
        sqlManagementEndpointUrl = "https://management.core.windows.net:8443/"
        galleryEndpointUrl = "https://gallery.azure.com/"
        managementEndpointUrl = "https://management.core.windows.net/"
      }
      $spJson = ($spObj | ConvertTo-Json -Compress)
    } else {
      Write-Host "AZURE_CREDENTIALS already exists; not rotating SP secret (use -RotateSpCredential to rotate)."
    }
  }
}

if (-not $OpenAiApiKey -and (Get-Command dotnet -ErrorAction SilentlyContinue)) {
  try {
    $OpenAiApiKey =
        dotnet user-secrets list --project $UserSecretsProject 2>&1 |
        ForEach-Object {
            $line = $_.Trim()
            if ($line -like "OpenAI:ApiKey*") {
                return ($line -split '=', 2)[1].Trim()
            }
        } | Select-Object -First 1
    if ($OpenAiApiKey) {
      Write-Host "Found OpenAI key in user-secrets ($UserSecretsProject)."
    } else {
      Write-Warning "No OpenAI key found in user-secrets."
    }
  } catch {
    Write-Warning "Could not read OpenAI key from user-secrets for $UserSecretsProject."
  }
}

# Push secrets
if ($spJson) { Set-Secret "AZURE_CREDENTIALS" $spJson }
Set-Secret "AZURE_RG" $ResourceGroup
Set-Secret "AZURE_WEBAPP_NAME" $WebAppName
Set-Secret "AZURE_ACR_NAME" $AcrName
if ($OpenAiApiKey) { Set-Secret "OPENAI_API_KEY" $OpenAiApiKey }
if ($SwaToken) { Set-Secret "AZURE_STATIC_WEB_APPS_API_TOKEN" $SwaToken } else { Write-Host "No SWA token set." }

Write-Host "Done."
