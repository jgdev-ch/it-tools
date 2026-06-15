#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "  >> $msg" -ForegroundColor Cyan }
function Write-OK($msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "  ERR $msg" -ForegroundColor Red }

Write-Host ""

Write-Step "Trusting PSGallery..."
try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Write-OK "PSGallery trusted"
} catch {
    Write-Fail "Could not trust PSGallery: $_"
    exit 1
}

Write-Step "Installing PowerShellGet..."
try {
    Install-Module PowerShellGet -Scope CurrentUser -Force -AllowClobber
    $v = (Get-Module PowerShellGet -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-OK "PowerShellGet v$v"
} catch {
    Write-Fail "PowerShellGet failed: $_"
    exit 1
}

Write-Step "Installing ExchangeOnlineManagement..."
try {
    Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
    $v = (Get-Module ExchangeOnlineManagement -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-OK "ExchangeOnlineManagement v$v"
} catch {
    Write-Fail "ExchangeOnlineManagement failed: $_"
    exit 1
}

Write-Host ""
Write-Host "  All prerequisites installed. You are ready to run the Mailbox Health Audit." -ForegroundColor Green
Write-Host ""
