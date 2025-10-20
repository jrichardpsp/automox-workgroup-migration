#Requires -Module Posh-ACME
#Requires -Module WebAdministration
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Obtains or renews a Let's Encrypt certificate using Posh-ACME and stores it in the Local Machine certificate store.

.DESCRIPTION
    This script requests or renews a Let's Encrypt certificate via Posh-ACME.
    It checks the Local Machine certificate store for an existing cert. If valid and not near expiry,
    it skips renewal. Otherwise, it requests a new one, imports it, and deletes all old ones.

.NOTES
Date            October/2025
Disclaimer:     This script is provided 'AS IS'. No warrantee is provided either expressed or implied. Declaration Software Ltd cannot be held responsible for any misuse of the script.
Version: 0.1
Updated: Initial Release.
Copyright (c) 2025 Declaration Software

.PARAMETER Domain
    The domain for which to request or renew the certificate (e.g., cert-test.rocklightnetworks.com).

.PARAMETER ContactEmail
    The email address for Let's Encrypt account registration.

.PARAMETER DaysBeforeExpiry
    Days before certificate expiry to trigger renewal (default: 30).

.PARAMETER StoreLocation
    The certificate store location (default: Cert:\LocalMachine\My).

.PARAMETER WebRoot
    The web server root for HTTP-01 challenge files (default: C:\inetpub\wwwroot).

.PARAMETER LogPath
    Path to save log file (default: C:\Logs\LetsEncryptRenewal_<date>.txt).

.PARAMETER Help
    Shows usage information.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Domain,

    [Parameter(Mandatory=$false)]
    [string]$ContactEmail,

    [Parameter(Mandatory=$false)]
    [int]$DaysBeforeExpiry = 30,

    [Parameter(Mandatory=$false)]
    [string]$StoreLocation = "Cert:\LocalMachine\My",

    [Parameter(Mandatory=$false)]
    [string]$WebRoot = "C:\inetpub\wwwroot",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Logs\LetsEncryptRenewal_$(Get-Date -Format 'yyyyMMdd').txt",

    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Show usage/help if -Help, no parameters, OR required values missing
if ($PSBoundParameters.Count -eq 0 -or $Help -or -not $Domain -or -not $ContactEmail) {
$usage = @'
Usage: .\Cert-Puller_PoshACME.ps1 -Domain <domain> -ContactEmail <email> [-DaysBeforeExpiry <days>] [-StoreLocation <store>] [-WebRoot <path>] [-LogPath <path>] [-Help]

Parameters:
    -Domain           (Required) Domain name to request or renew a certificate for.
    -ContactEmail     (Required) Email address for Let's Encrypt account registration.
    -DaysBeforeExpiry (Optional) Days before expiry to trigger renewal. Default: 30
    -StoreLocation    (Optional) Certificate store location. Default: Cert:\LocalMachine\My
    -WebRoot          (Optional) Path to web server root for HTTP-01 challenge. Default: C:\inetpub\wwwroot
    -LogPath          (Optional) Path to save log file. Default: C:\Logs\LetsEncryptRenewal_<date>.txt
    -Help             (Optional) Display this usage information.

Example:
    .\Cert-Puller_PoshACME.ps1 -Domain "example.com" -ContactEmail "admin@example.com"
'@
    Write-Output $usage
    return
}

# Initialize logging
if (-not (Test-Path -Path (Split-Path $LogPath -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path $LogPath -Parent) -Force | Out-Null
}
Start-Transcript -Path $LogPath -Append

try {
    # Log Posh-ACME version
    $poshAcmeVersion = (Get-Module -Name Posh-ACME -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-Output "Posh-ACME Module Version: $poshAcmeVersion"

    # Check if certificate exists in the store and is valid
    $renewNeeded = $true
    $existingCert = Get-ChildItem -Path $StoreLocation | Where-Object {
        ($_.Subject -like "*CN=$Domain*" -or $_.DnsNameList -contains $Domain) -and
        $_.Issuer -like "*Let's Encrypt*" -and
        $_.NotAfter -gt (Get-Date)
    } | Sort-Object NotAfter -Descending | Select-Object -First 1

    if ($existingCert) {
        $daysUntilExpiry = ($existingCert.NotAfter - (Get-Date)).Days
        if ($daysUntilExpiry -gt $DaysBeforeExpiry) {
            Write-Output "Certificate for $Domain is valid until $($existingCert.NotAfter). No renewal needed."
            $renewNeeded = $false
        } else {
            Write-Output "Certificate for $Domain expires on $($existingCert.NotAfter). Renewal needed."
        }
    } else {
        Write-Output "No valid certificate found for $Domain in $StoreLocation. Requesting new certificate."
    }

    if (-not $renewNeeded) {
        return
    }

    # Configure Posh-ACME server
    Set-PAServer "LE_PROD"
    Write-Verbose "Set Posh-ACME server to production"

    # Set up account
    $account = Get-PAAccount
    if (-not $account) {
        New-PAAccount -Contact $ContactEmail -AcceptTOS -Force
        Write-Verbose "Created new Posh-ACME account for $ContactEmail"
    } else {
        Set-PAAccount -ID $account.ID -Contact $ContactEmail -Force
        Write-Verbose "Using existing Posh-ACME account for $ContactEmail"
    }

    # Request or renew certificate
    $cert = New-PACertificate $Domain -Plugin WebRoot -PluginArgs @{ WRPath = $WebRoot } -Force
    if (-not $cert) { throw "Failed to obtain/renew certificate for $Domain" }
    Write-Output "Successfully obtained/renewed certificate for $Domain"

    # Get certificate details
    $certDetails = Get-PACertificate -MainDomain $Domain
    if (-not $certDetails) { throw "Failed to retrieve certificate details for $Domain" }

    # Import new cert
    $imported = Import-PfxCertificate -FilePath $certDetails.PfxFullChain `
        -Password $certDetails.PfxPass `
        -CertStoreLocation $StoreLocation `
        -Exportable

    if ($imported) {
        Write-Output "Certificate for $Domain imported to $StoreLocation"
    } else {
        throw "Failed to import certificate for $Domain into $StoreLocation"
    }

    # Clean up old certs
    $newCert = Get-ChildItem -Path $StoreLocation | Where-Object {
        ($_.Subject -like "*CN=$Domain*" -or $_.DnsNameList -contains $Domain) -and
        $_.Issuer -like "*Let's Encrypt*"
    } | Sort-Object NotAfter -Descending | Select-Object -First 1

    if ($newCert) {
        Get-ChildItem -Path $StoreLocation | Where-Object {
            ($_.Subject -like "*CN=$Domain*" -or $_.DnsNameList -contains $Domain) -and
            $_.Issuer -like "*Let's Encrypt*" -and
            $_.Thumbprint -ne $newCert.Thumbprint
        } | ForEach-Object {
            Write-Output "Removing old certificate (Thumbprint=$($_.Thumbprint), Expires=$($_.NotAfter))"
            Remove-Item -Path "$StoreLocation\$($_.Thumbprint)" -Force
        }
    }

    Write-Output "Certificate for $Domain successfully obtained/renewed and old certificates cleaned up."
}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
    Exit 1
}
finally {
    # Clean up challenge files
    $challengeDir = Join-Path -Path $WebRoot -ChildPath ".well-known\acme-challenge"
    if (Test-Path -Path $challengeDir) {
        Remove-Item -Path $challengeDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Verbose "Cleaned up challenge files at $challengeDir"
    }
}

# Update permissions for PSP Service Account
Write-Output "Checking certificate and adding permissions to PSP Service account if necessary..."
$svc = Get-WmiObject Win32_Service -Filter "Name='PowerSyncPro'"
if (-not $svc) {
    Write-Warning "Service 'PowerSyncPro' not found. Skipping key permission check."
} else {
    $svcUser = $svc.StartName
    if ($svcUser -eq "LocalSystem") {
        Write-Output "PowerSyncPro is running as LocalSystem. No permissions update needed."
    } else {
        try {
            $ntAccount = New-Object System.Security.Principal.NTAccount($svcUser)
            $resolvedUser = $ntAccount.Translate([System.Security.Principal.NTAccount]).Value
            Write-Output "PowerSyncPro is running as $resolvedUser. Updating private key ACL..."

            $keyProvInfo = $newCert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
            $machineKeysPath = "$env:ProgramData\Microsoft\Crypto\RSA\MachineKeys"
            $keyPath = Join-Path $machineKeysPath $keyProvInfo

            if (Test-Path $keyPath) {
                $acl = Get-Acl $keyPath
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($resolvedUser, "FullControl", "Allow")
                $acl.SetAccessRule($accessRule)
                Set-Acl -Path $keyPath -AclObject $acl
                Write-Output "Granted FullControl on private key to $resolvedUser"
            } else {
                Write-Warning "Private key file not found at $keyPath"
            }
        } catch {
            Write-Error "Failed to adjust private key permissions for $svcUser : $($_.Exception.Message)"
        }
    }
}

# Update appsettings.json
$appSettingsPath = "C:\Program Files\PowerSyncPro\appsettings.json"

try {
    if (Test-Path $appSettingsPath) {
        $json = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        $actualSubject = $newCert.GetNameInfo('SimpleName', $false)

        if ($json.Kestrel.Endpoints.PSObject.Properties.Name -notcontains "Https") {
            Write-Warning "HTTPS endpoint not found in appsettings.json. Creating one on port 5001."

            $json.Kestrel.Endpoints | Add-Member -MemberType NoteProperty -Name "Https" -Value @{
                Url       = "https://*:5001"
                Protocols = "Http1AndHttp2"
                Certificate = @{
                    Subject      = $actualSubject
                    Store        = "My"
                    Location     = "LocalMachine"
                    AllowInvalid = $true
                }
            }

            $json | ConvertTo-Json -Depth 10 | Set-Content -Path $appSettingsPath -Encoding UTF8
            Write-Output "Added HTTPS endpoint with new certificate subject $actualSubject."
        }
        else {
            $configuredSubject = $json.Kestrel.Endpoints.Https.Certificate.Subject

            if ($configuredSubject -ne $actualSubject) {
                Write-Warning "Configured cert subject ($configuredSubject) does not match new cert ($actualSubject). Updating automatically."
                $json.Kestrel.Endpoints.Https.Certificate.Subject = $actualSubject
                $json | ConvertTo-Json -Depth 10 | Set-Content -Path $appSettingsPath -Encoding UTF8
                Write-Output "Updated appsettings.json with new subject $actualSubject."
            } else {
                Write-Output "appsettings.json already matches the current certificate subject."
            }
        }
    }
    else {
        Write-Warning "appsettings.json not found at $appSettingsPath"
    }
}
catch {
    Write-Error "Failed to update appsettings.json: $($_.Exception.Message)"
}

# Update IIS with new Cert
Import-Module WebAdministration -ErrorAction Stop

$siteName   = "Default Web Site"
$newThumb   = $newCert.Thumbprint
$certObject = Get-Item "Cert:\LocalMachine\My\$newThumb"

$binding = Get-WebBinding -Name $siteName -Protocol "https" -Port 443 -ErrorAction SilentlyContinue

if ($binding) {
    Write-Output "Found existing HTTPS binding for '$siteName'. Updating with cert $newThumb"

    $sslBindings = Get-ChildItem IIS:\SslBindings
    if ($sslBindings) {
        $sslBinding = $sslBindings | Where-Object { $_.Port -eq 443 } | Select-Object -First 1

        if ($sslBinding) {
            Write-Output "Updating SSL binding path $($sslBinding.PSPath)"
            Set-Item -Path $sslBinding.PSPath -Value $certObject -Force
        } else {
            Write-Warning "No SSL binding object found for port 443. Creating one..."
            $sslPath = "IIS:\SslBindings\0.0.0.0!443"
            New-Item $sslPath -Value $certObject -SSLFlags 0 | Out-Null
        }
    } else {
        Write-Warning "No SSL bindings currently exist. Creating one..."
        $sslPath = "IIS:\SslBindings\0.0.0.0!443"
        New-Item $sslPath -Value $certObject -SSLFlags 0 | Out-Null
    }
} else {
    Write-Output "No HTTPS binding found for '$siteName'. Creating new binding with cert $newThumb"
    New-WebBinding -Name $siteName -Protocol https -Port 443 -IPAddress * -HostHeader ""
    $sslPath = "IIS:\SslBindings\0.0.0.0!443"
    New-Item $sslPath -Value $certObject -SSLFlags 0 | Out-Null
}

Write-Output "IIS binding updated successfully."

# Restart the service
Restart-Service -Name "PowerSyncPro" -Force
Write-Output "PowerSyncPro service restarted."

Stop-Transcript
