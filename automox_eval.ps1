# Check if "PowerSyncPro Migration Agent" service is present
$service = Get-Service -Name "PowerSyncPro Migration Agent" -ErrorAction SilentlyContinue

if ($null -ne $service) {
    # Service exists
    Write-Host "Service 'PowerSyncPro Migration Agent' is present."
    exit 0
}
else {
    # Service does not exist
    Write-Host "Service 'PowerSyncPro Migration Agent' is NOT present."
    exit 1
}
