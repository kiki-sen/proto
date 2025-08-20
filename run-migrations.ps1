# Script to run EF migrations using the API endpoint
param(
    [string] $ResourceGroup = "bookrec-rg",
    [string] $WebAppName = "bookrec-api"
)

Write-Host "Running database migrations for $WebAppName..." -ForegroundColor Cyan

# Get the web app URL
$webAppUrl = "https://$WebAppName.azurewebsites.net"
Write-Host "Calling migration endpoint: $webAppUrl/admin/migrate"

try {
    $response = Invoke-RestMethod -Uri "$webAppUrl/admin/migrate" -Method POST -TimeoutSec 60
    Write-Host "Migration completed successfully!" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json -Depth 3)"
}
catch {
    Write-Host "Migration failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $errorResponse = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $errorContent = $reader.ReadToEnd()
        Write-Host "Error details: $errorContent" -ForegroundColor Red
    }
}
