[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Status', 'WSL2', 'VMware')]
    [string]$Mode = 'Menu',

    [switch]$Reboot,
    [switch]$DisableFeaturesForVmware,
    [switch]$NoElevate
)

$script = Join-Path $PSScriptRoot 'WSL2-VMware-Switch.ps1'
$params = @{
    Mode = $Mode
}

if ($Reboot) {
    $params.Reboot = $true
}
if ($DisableFeaturesForVmware) {
    $params.DisableFeaturesForVmware = $true
}
if ($NoElevate) {
    $params.NoElevate = $true
}

Write-Host 'HyperV-WSL2-Switch.ps1 是旧入口，正在转到 WSL2-VMware-Switch.ps1...' -ForegroundColor Yellow
& $script @params
if ($?) {
    exit 0
}
exit 1
