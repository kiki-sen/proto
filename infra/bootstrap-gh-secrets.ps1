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
  $AcrName = az acr list -g $ResourceGroup --query "[0].name" -o tsv 2>$null
  if (-not $AcrName -or $AcrName -eq "null" -or [string]::IsNullOrWhiteSpace($AcrName)) { 
    Write-Error "No ACR found in resource group '$ResourceGroup'. Pass -AcrName explicitly."; exit 1 
  }
}
# Validate ACR name format
if ($AcrName -match '[^a-z0-9]' -or $AcrName.Length -lt 5 -or $AcrName.Length -gt 50) {
  Write-Error "Invalid ACR name '$AcrName'. ACR names must be 5-50 lowercase alphanumeric characters only."; exit 1
}
Write-Host "ACR: $AcrName"

# AZURE_WEBAPP_MI_PRINCIPAL_ID 
$azurepid = az webapp show -n $WebAppName -g $ResourceGroup --query identity.principalId -o tsv 2>$null
if (-not $azurepid -or $azurepid -eq "null" -or [string]::IsNullOrWhiteSpace($azurepid)) { 
  Write-Error "Could not get managed identity principal ID for Web App '$WebAppName' in RG '$ResourceGroup'. Make sure the Web App exists and has system-assigned managed identity enabled."; exit 1 
}
Write-Host "AZURE_WEBAPP_MI_PRINCIPAL_ID: $azurepid"

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
    $spJsonRaw = az ad sp create-for-rbac --name $SpName --sdk-auth --role contributor --scopes $scope
    if ($LASTEXITCODE -eq 0 -and $spJsonRaw) {
      # Clean up the raw JSON output
      $spJsonLines = $spJsonRaw | Where-Object { $_ -and $_.Trim() }
      $spJson = ($spJsonLines -join "").Trim()
      
      # Validate it's proper JSON
      try { $spJson | ConvertFrom-Json | Out-Null } catch { throw "Invalid JSON from az create-for-rbac: $spJson" }
    }
  } catch {
    # Reuse existing SP, rotate secret only if requested (or if AZURE_CREDENTIALS missing)
    $appId = az ad sp list --display-name $SpName --query "[0].appId" -o tsv
    if (-not $appId -or $appId -eq "null") { throw "Service principal '$SpName' not found and could not be created." }
    
    if ($RotateSpCredential -or (-not $existing.ContainsKey('AZURE_CREDENTIALS')) -or $Force) {
      $password = az ad app credential reset --id $appId --append --query password -o tsv
      $tenantId = az account show --query tenantId -o tsv
      
      # Validate all required fields
      if (-not $appId -or $appId -eq "null" -or [string]::IsNullOrWhiteSpace($appId)) { throw "Failed to get app ID" }
      if (-not $password -or $password -eq "null" -or [string]::IsNullOrWhiteSpace($password)) { throw "Failed to get client secret" }
      if (-not $tenantId -or $tenantId -eq "null" -or [string]::IsNullOrWhiteSpace($tenantId)) { throw "Failed to get tenant ID" }
      if (-not $SubscriptionId -or $SubscriptionId -eq "null" -or [string]::IsNullOrWhiteSpace($SubscriptionId)) { throw "Subscription ID is missing" }
      
      # Use ordered hashtable to ensure consistent JSON structure
      $spObj = [ordered]@{
        clientId = $appId.Trim()
        clientSecret = $password.Trim()
        subscriptionId = $SubscriptionId.Trim()
        tenantId = $tenantId.Trim()
        activeDirectoryEndpointUrl = "https://login.microsoftonline.com"
        resourceManagerEndpointUrl = "https://management.azure.com/"
        activeDirectoryGraphResourceId = "https://graph.windows.net/"
        sqlManagementEndpointUrl = "https://management.core.windows.net:8443/"
        galleryEndpointUrl = "https://gallery.azure.com/"
        managementEndpointUrl = "https://management.core.windows.net/"
      }
      $spJson = ($spObj | ConvertTo-Json -Compress -Depth 10)
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
if ($spJson) { 
  # Validate JSON before setting secrets
  try {
    $testObj = $spJson | ConvertFrom-Json
    if (-not $testObj.clientId -or -not $testObj.clientSecret) {
      throw "Invalid JSON structure - missing required fields"
    }
  } catch {
    Write-Error "Generated JSON is invalid: $_"
    Write-Host "JSON content: $spJson"
    exit 1
  }
  
  Set-Secret "AZURE_CREDENTIALS" $spJson 
  
  # Also create base64 encoded version for workflows that need it
  try {
    $spJsonBytes = [System.Text.Encoding]::UTF8.GetBytes($spJson)
    $spJsonB64 = [Convert]::ToBase64String($spJsonBytes)
    
    # Validate the base64 encoding by decoding it back
    $testDecode = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($spJsonB64))
    if ($testDecode -ne $spJson) {
      throw "Base64 encoding/decoding test failed"
    }
    
    Write-Host "Base64 validation successful (length: $($spJsonB64.Length))"
    Set-Secret "AZURE_CREDENTIALS_B64" $spJsonB64
  } catch {
    Write-Error "Failed to create base64 encoded credentials: $_"
    exit 1
  }
}
Set-Secret "AZURE_RG" $ResourceGroup
Set-Secret "AZURE_WEBAPP_NAME" $WebAppName
Set-Secret "AZURE_ACR_NAME" $AcrName
Set-Secret "AZURE_WEBAPP_MI_PRINCIPAL_ID" $azurepid
if ($OpenAiApiKey) { Set-Secret "OPENAI_API_KEY" $OpenAiApiKey }
if ($SwaToken) { Set-Secret "AZURE_STATIC_WEB_APPS_API_TOKEN" $SwaToken } else { Write-Host "No SWA token set." }

Write-Host "Done."
