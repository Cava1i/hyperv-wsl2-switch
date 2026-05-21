[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Status', 'WSL2', 'VMware')]
    [string]$Mode = 'Menu',

    [switch]$Reboot,
    [switch]$DisableFeaturesForVmware,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedSelf {
    $scriptPath = $PSCommandPath -replace '"', '\"'
    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Mode $Mode"

    if ($Reboot) {
        $argLine += ' -Reboot'
    }
    if ($DisableFeaturesForVmware) {
        $argLine += ' -DisableFeaturesForVmware'
    }

    Write-Warn "需要管理员权限，正在请求 UAC..."
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs
}

function Get-FeatureCatalog {
    @(
        [pscustomobject]@{
            Name = 'Microsoft-Windows-Subsystem-Linux'
            Label = 'Windows Subsystem for Linux (WSL)'
            EnableForWsl = $true
            DisableForVmware = $false
        }
        [pscustomobject]@{
            Name = 'VirtualMachinePlatform'
            Label = 'Virtual Machine Platform'
            EnableForWsl = $true
            DisableForVmware = $true
        }
        [pscustomobject]@{
            Name = 'Microsoft-Hyper-V-All'
            Label = 'Hyper-V'
            EnableForWsl = $false
            DisableForVmware = $true
        }
        [pscustomobject]@{
            Name = 'HypervisorPlatform'
            Label = 'Windows Hypervisor Platform'
            EnableForWsl = $false
            DisableForVmware = $true
        }
    )
}

function Get-OptionalFeatureStateSafe {
    param([string]$Name)

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
        return [pscustomobject]@{
            Exists = $true
            Name = $Name
            State = [string]$feature.State
        }
    }
    catch {
        return [pscustomobject]@{
            Exists = $false
            Name = $Name
            State = 'Unavailable'
        }
    }
}

function Get-HypervisorLaunchType {
    try {
        $output = & bcdedit /enum '{current}' 2>$null
        $line = $output | Where-Object { $_ -match '^\s*hypervisorlaunchtype\s+(.+)$' } | Select-Object -First 1
        if ($line -and $line -match '^\s*hypervisorlaunchtype\s+(.+)$') {
            return $matches[1].Trim()
        }
        return 'Auto (default)'
    }
    catch {
        return 'Unknown'
    }
}

function Get-HypervisorPresentNow {
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        return [bool]$computer.HypervisorPresent
    }
    catch {
        return $null
    }
}

function Get-VbsServicesRunning {
    try {
        $guard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        $map = @{
            1 = 'Credential Guard'
            2 = 'Memory Integrity / HVCI'
            3 = 'System Guard Secure Launch'
            4 = 'SMM Firmware Measurement'
        }

        $services = @()
        foreach ($id in @($guard.SecurityServicesRunning)) {
            if ([int]$id -eq 0) {
                continue
            }

            if ($map.ContainsKey([int]$id)) {
                $services += $map[[int]$id]
            }
            else {
                $services += "Service $id"
            }
        }

        if ($services.Count -eq 0) {
            return 'None'
        }
        return ($services -join ', ')
    }
    catch {
        return 'Unknown'
    }
}

function Show-Status {
    Write-Host ''
    Write-Host '=== WSL2 <-> VMware 嵌套虚拟化切换状态 ===' -ForegroundColor White
    Write-Host ("管理员权限: {0}" -f $(if (Test-IsAdministrator) { 'Yes' } else { 'No' }))
    Write-Host ("BCD hypervisorlaunchtype: {0}" -f (Get-HypervisorLaunchType))

    $present = Get-HypervisorPresentNow
    if ($null -eq $present) {
        Write-Host '当前 Hypervisor 运行状态: Unknown'
    }
    else {
        Write-Host ("当前 Hypervisor 运行状态: {0}" -f $(if ($present) { 'Running' } else { 'Not running' }))
    }

    Write-Host ("VBS / Device Guard 运行项: {0}" -f (Get-VbsServicesRunning))
    Write-Host ''
    Write-Host 'Windows 可选功能:'
    foreach ($item in Get-FeatureCatalog) {
        $state = Get-OptionalFeatureStateSafe -Name $item.Name
        Write-Host ("  - {0}: {1}" -f $item.Label, $state.State)
    }

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        Write-Host ''
        Write-Host 'WSL 状态:'
        try {
            & wsl.exe --status
        }
        catch {
            Write-Warn "无法读取 WSL 状态：$($_.Exception.Message)"
        }
    }
}

function Set-HypervisorLaunchType {
    param(
        [ValidateSet('auto', 'off')]
        [string]$Value
    )

    Write-Info "设置 BCD hypervisorlaunchtype=$Value"
    & bcdedit /set hypervisorlaunchtype $Value
    if ($LASTEXITCODE -ne 0) {
        throw "bcdedit 设置失败，退出码 $LASTEXITCODE"
    }
}

function Enable-FeatureIfAvailable {
    param([pscustomobject]$Item)

    $state = Get-OptionalFeatureStateSafe -Name $Item.Name
    if (-not $state.Exists) {
        Write-Warn "跳过 $($Item.Label)：无法读取或当前 Windows 版本没有这个可选功能"
        return
    }

    if ($state.State -eq 'Enabled' -or $state.State -eq 'EnablePending') {
        Write-Ok "$($Item.Label) 已启用或等待启用"
        return
    }

    Write-Info "启用 $($Item.Label) ($($Item.Name))"
    Enable-WindowsOptionalFeature -Online -FeatureName $Item.Name -All -NoRestart | Out-Null
}

function Disable-FeatureIfAvailable {
    param([pscustomobject]$Item)

    $state = Get-OptionalFeatureStateSafe -Name $Item.Name
    if (-not $state.Exists) {
        Write-Warn "跳过 $($Item.Label)：无法读取或当前 Windows 版本没有这个可选功能"
        return
    }

    if ($state.State -eq 'Disabled' -or $state.State -eq 'DisablePending') {
        Write-Ok "$($Item.Label) 已禁用或等待禁用"
        return
    }

    Write-Info "禁用 $($Item.Label) ($($Item.Name))"
    Disable-WindowsOptionalFeature -Online -FeatureName $Item.Name -NoRestart | Out-Null
}

function Set-WslDefaultVersion2 {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Warn '没有找到 wsl.exe，跳过 WSL 默认版本设置'
        return
    }

    Write-Info '设置新安装的 WSL 发行版默认使用 WSL2'
    & wsl.exe --set-default-version 2
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "wsl --set-default-version 2 返回退出码 $LASTEXITCODE；如果 WSL 已可用，可以忽略"
    }
}

function Request-Reboot {
    param([string]$TargetMode)

    Write-Host ''
    Write-Warn "已写入 $TargetMode 切换设置，必须重启 Windows 后才会真正生效。"

    if ($Reboot) {
        Write-Info '正在重启...'
        Restart-Computer -Force
        return
    }

    $answer = Read-Host '现在重启吗？输入 Y 立即重启，其他输入表示稍后手动重启'
    if ($answer -match '^(y|yes)$') {
        Restart-Computer -Force
    }
    else {
        Write-Info '已保留设置。稍后请手动重启。'
    }
}

function Switch-ToWsl2Mode {
    Write-Host ''
    Write-Host '=== 切换到 WSL2 模式 ===' -ForegroundColor White
    Write-Info '将启用 WSL2 所需功能，并允许 Windows Hypervisor 启动。'

    foreach ($item in Get-FeatureCatalog | Where-Object { $_.EnableForWsl }) {
        Enable-FeatureIfAvailable -Item $item
    }

    Set-HypervisorLaunchType -Value 'auto'
    Set-WslDefaultVersion2

    Write-Ok 'WSL2 模式设置完成'
    Request-Reboot -TargetMode 'WSL2'
}

function Switch-ToVmwareMode {
    Write-Host ''
    Write-Host '=== 切换到 VMware 嵌套虚拟化模式 ===' -ForegroundColor White
    Write-Info '将关闭 Windows Hypervisor 启动，让 VMware 在重启后尽量独占 VT-x/AMD-V。'

    Set-HypervisorLaunchType -Value 'off'

    if ($DisableFeaturesForVmware) {
        Write-Warn '已选择彻底模式：将禁用 Virtual Machine Platform / Hyper-V / Windows Hypervisor Platform。'
        Write-Warn 'WSL 功能本身会保留；回到 WSL2 模式时会重新启用 Virtual Machine Platform。'
        foreach ($item in Get-FeatureCatalog | Where-Object { $_.DisableForVmware }) {
            Disable-FeatureIfAvailable -Item $item
        }
    }
    else {
        Write-Info '快速模式：仅关闭 Windows Hypervisor 启动，不卸载 Windows 功能。'
        Write-Info '这通常足够让 VMware 在重启后重新独占 VT-x/AMD-V。'
    }

    Write-Ok 'VMware 模式设置完成'
    Request-Reboot -TargetMode 'VMware'
}

function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host 'WSL2 <-> VMware 嵌套虚拟化一键切换工具' -ForegroundColor White
        Write-Host '注意：这不是热切换；每次切换后都需要重启 Windows。'
        Show-Status
        Write-Host ''
        Write-Host '[1] 切到 WSL2 模式'
        Write-Host '[2] 切到 VMware 嵌套虚拟化模式'
        Write-Host '[0] 退出'
        Write-Host ''

        $choice = Read-Host '请选择'
        switch ($choice) {
            '1' {
                Switch-ToWsl2Mode
                return
            }
            '2' {
                Switch-ToVmwareMode
                return
            }
            '0' {
                return
            }
            default {
                Write-Warn '无效选项'
                Start-Sleep -Seconds 1
            }
        }
    }
}

try {
    if (-not (Test-IsAdministrator) -and -not $NoElevate) {
        Start-ElevatedSelf
        exit 0
    }

    switch ($Mode) {
        'Menu' { Show-Menu }
        'Status' { Show-Status }
        'WSL2' { Switch-ToWsl2Mode }
        'VMware' { Switch-ToVmwareMode }
    }
}
catch {
    Write-Host ''
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    Write-Warn '如果 VMware 重启后仍提示 Hyper-V/VBS 正在运行，请检查 Windows 安全中心里的“内存完整性”，关闭后再重启。'
    exit 1
}
