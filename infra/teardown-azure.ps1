<#
.SYNOPSIS
  Tear down Azure resources for the Book Recommender project.

.DESCRIPTION
  - By default deletes the entire resource group (fastest).
  - With -KeepResourceGroup, deletes known resources inside but keeps the RG.
  - Re-entrant: skips items that don't exist.

.PARAMETERS
  -Subscription        Subscription id or name
  -ResourceGroup       Resource group name
  -KeepResourceGroup   If set, keeps RG and deletes resources inside it

.EXAMPLES
  pwsh ./infra/teardown-azure.ps1 -Subscription "SUB-ID" -ResourceGroup "bookrec-rg"
  pwsh ./infra/teardown-azure.ps1 -Subscription "SUB-ID" -ResourceGroup "bookrec-rg" -KeepResourceGroup
#>

param(
  [Parameter(Mandatory)] [string] $Subscription,
  [Parameter(Mandatory)] [string] $ResourceGroup,
  [switch] $KeepResourceGroup = $false
)

$ErrorActionPreference = "Stop"

function Exists-Az {
  param([string]$Cmd)
  try { $null = Invoke-Expression $Cmd; return $true } catch { return $false }
}

Write-Host ">> Selecting subscription..."
az account set --subscription $Subscription | Out-Null

if (-not (Exists-Az "az group show -n $ResourceGroup")) {
  Write-Host ">> Resource group '$ResourceGroup' does not exist. Nothing to delete."
  return
}

if (-not $KeepResourceGroup) {
  Write-Host ">> Deleting entire resource group '$ResourceGroup' (no-wait)..."
  az group delete -n $ResourceGroup --yes --no-wait
  Write-Host ">> Deletion requested. It will complete asynchronously."
  return
}

Write-Host ">> Keeping resource group. Deleting known resources inside '$ResourceGroup'..."

# ---------------- Static Web Apps ----------------
try {
  $swas = az staticwebapp list -g $ResourceGroup --query "[].name" -o tsv
  if ($swas) {
    foreach ($swa in $swas) {
      Write-Host "   - Deleting Static Web App: $swa"
      az staticwebapp delete -g $ResourceGroup -n $swa --yes | Out-Null
    }
  } else { Write-Host "   - No Static Web Apps." }
} catch { Write-Host "   - Static Web Apps: $_" -ForegroundColor Yellow }

# ---------------- Web Apps ----------------
try {
  $apps = az webapp list -g $ResourceGroup --query "[].name" -o tsv
  if ($apps) {
    foreach ($app in $apps) {
      Write-Host "   - Deleting Web App: $app"
      az webapp delete -g $ResourceGroup -n $app | Out-Null
    }
  } else { Write-Host "   - No Web Apps." }
} catch { Write-Host "   - Web Apps: $_" -ForegroundColor Yellow }

# ---------------- App Service Plans ----------------
try {
  # Primary query
  $plans = az appservice plan list -g $ResourceGroup --query "[].name" -o tsv 2>$null

  # Fallback via raw resource listing
  $planFallback = az resource list -g $ResourceGroup --resource-type "Microsoft.Web/serverfarms" --query "[].name" -o tsv 2>$null

  # Merge & de-dupe
  $planNames = @()
  if ($plans) { $planNames += $plans -split "`n" }
  if ($planFallback) { $planNames += $planFallback -split "`n" }
  $planNames = $planNames | Where-Object { $_ -and $_.Trim() -ne "" } | Sort-Object -Unique

  if ($planNames.Count -gt 0) {
    foreach ($plan in $planNames) {
      Write-Host "   - Deleting App Service Plan: $plan"
      az appservice plan delete -g $ResourceGroup -n $plan --yes 2>$null | Out-Null
    }
  } else {
    Write-Host "   - No App Service Plans."
  }
} catch {
  Write-Host "   - App Service Plans: $_" -ForegroundColor Yellow
}

# ---------------- ACR ----------------
try {
  $acrs = az acr list -g $ResourceGroup --query "[].name" -o tsv
  if ($acrs) {
    foreach ($acr in $acrs) {
      Write-Host "   - Deleting ACR: $acr"
      az acr delete -g $ResourceGroup -n $acr --yes | Out-Null
    }
  } else { Write-Host "   - No ACRs." }
} catch { Write-Host "   - ACR: $_" -ForegroundColor Yellow }

# ---------------- PostgreSQL Flexible Servers ----------------
try {
  $pgs = az postgres flexible-server list -g $ResourceGroup --query "[].name" -o tsv
  if ($pgs) {
    foreach ($pg in $pgs) {
      Write-Host "   - Deleting Postgres Flexible Server: $pg"
      az postgres flexible-server delete -g $ResourceGroup -n $pg --yes | Out-Null
    }
  } else { Write-Host "   - No Postgres Flexible Servers." }
} catch { Write-Host "   - Postgres: $_" -ForegroundColor Yellow }

Write-Host ">> Done. Resource group '$ResourceGroup' kept."
