#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WinVPS Uninstaller - cleanly removes WinVPS.
.DESCRIPTION
    Stops all services, removes firewall rules, deletes scheduled tasks, and removes files.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }

Write-Host ''
Write-Host '  WinVPS Uninstaller' -ForegroundColor Yellow
Write-Host '  ----------------------------------------'
Write-Host ''
Write-Host "  This will remove WinVPS from: $WinVPSDir"
Write-Host ''
$input = Read-Host "  Type 'YES' to confirm"
if ($input -ne 'YES') { Write-Host '  Cancelled'; return }

Write-Host ''
Write-Host '  Stopping services...'
$servicesDir = Join-Path $WinVPSDir 'services'
if (Test-Path $servicesDir) {
    Get-ChildItem -Path $servicesDir -Filter '*.pid' | ForEach-Object {
        $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
        if ($pid) { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item $servicesDir -Recurse -Force
}

Write-Host '  Removing firewall rules...'
Get-NetFirewallRule -DisplayName 'WinVPS*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule

Write-Host '  Removing scheduled tasks...'
Unregister-ScheduledTask -TaskName 'WinVPS-Supervisor' -Confirm:$false -ErrorAction SilentlyContinue

Write-Host '  Removing environment variable...'
[System.Environment]::SetEnvironmentVariable('WINVPS_DIR', $null, 'Machine')

Write-Host '  Removing files...'
Remove-Item $WinVPSDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '  WinVPS uninstalled.' -ForegroundColor Green
Write-Host ''
