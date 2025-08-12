# Add this to the top of the script
Start-Sleep -Seconds 3  # give Docker time to launch container

# Name of your container (partial match is fine)
$containerName = "BookRecommenderApi"

# Name of the Docker Compose network
$networkName = "bookrecommender_default"

# Get container ID based on name
$containerId = docker ps --filter "name=$containerName" --format "{{.ID}}"

if (-not $containerId) {
    Write-Host "Could not find a running container matching '$containerName'. Is it running?"
    exit 1
}

# Check if already connected
$networkInfo = docker inspect $containerId | ConvertFrom-Json
$networks = $networkInfo[0].NetworkSettings.Networks.PSObject.Properties.Name

if ($networks -contains $networkName) {
    Write-Host "Container is already connected to '$networkName'."
} else {
    Write-Host "Connecting container $containerId to network '$networkName'..."
    docker network connect $networkName $containerId
    Write-Host "Connected."
}
