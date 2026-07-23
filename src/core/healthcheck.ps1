#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Health Check - monitors CPU, RAM, disk, services, network, temperature.
.DESCRIPTION
    Runs diagnostic checks on all system components, generates reports,
    and triggers auto-healing for crashed services.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$LogDir = Join-Path $WinVPSDir 'logs'
$ServicesDir = Join-Path $WinVPSDir 'services'

$script:Results = @()
$script:Passed = 0
$script:Failed = 0
$script:Warnings = 0

function Add-Result {
    param([string]$Level, [string]$Message)
    $script:Results += "$Level`: $Message"
}

function Check-Cpu {
    $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
    if ($cpu) {
        $load = $cpu.LoadPercentage
        if ($null -eq $load) { $load = 0 }
        if ($load -gt 90) {
            Add-Result 'WARN' "High CPU load: ${load}%"
            $script:Warnings++
        } else {
            $script:Passed++
        }
    } else {
        $script:Passed++
    }
}

function Check-Memory {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
        $usedMB = $totalMB - $freeMB
        $pct = if ($totalMB -gt 0) { [math]::Round(($usedMB / $totalMB) * 100) } else { 0 }
        if ($pct -gt 90) {
            Add-Result 'WARN' "Memory usage at ${pct}% (${usedMB}MB/${totalMB}MB)"
            $script:Warnings++
        } elseif ($freeMB -lt 256) {
            Add-Result 'WARN' "Low free memory: ${freeMB}MB"
            $script:Warnings++
        } else {
            $script:Passed++
        }
    } else {
        $script:Passed++
    }
}

function Check-Disk {
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    foreach ($disk in $drives) {
        if ($disk.Size -gt 0) {
            $pct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100)
            if ($pct -gt 90) {
                Add-Result 'CRIT' "Disk $($disk.DeviceID) usage at ${pct}%"
                $script:Failed++
            } elseif ($pct -gt 80) {
                Add-Result 'WARN' "Disk $($disk.DeviceID) usage at ${pct}%"
                $script:Warnings++
            } else {
                $script:Passed++
            }
        }
    }
}

function Check-Services {
    $count = 0
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $count++
        $name = $_.BaseName
        $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
            Add-Result 'PASS' "$name running (PID $pid, ${memMB}MB)"
            $script:Passed++
        } else {
            Add-Result 'CRIT' "$name crashed (stale PID $pid)"
            $script:Failed++
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    if ($count -eq 0) {
        Add-Result 'INFO' 'No services registered'
        $script:Passed++
    }
}

function Check-Network {
    $ports = @(7022, 7080, 7443, 7444)
    $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty LocalPort -Unique
    foreach ($port in $ports) {
        if ($listening -contains $port) {
            $script:Passed++
        }
    }

    try {
        $ping = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -TimeoutSeconds 3
        if ($ping) {
            Add-Result 'PASS' 'Internet connectivity OK'
            $script:Passed++
        } else {
            Add-Result 'WARN' 'No internet connectivity'
            $script:Warnings++
        }
    } catch {
        Add-Result 'WARN' 'Internet check failed'
        $script:Warnings++
    }
}

function Check-Temperature {
    try {
        $temps = Get-CimInstance -Namespace 'root/WMI' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        foreach ($t in $temps) {
            $tempC = [math]::Round(($t.CurrentTemperature - 2732) / 10)
            if ($tempC -gt 80) {
                Add-Result 'WARN' "Temperature ${tempC}C - throttling risk"
                $script:Warnings++
                break
            }
        }
    } catch {}
    $script:Passed++
}

function Invoke-AutoHeal {
    $maxRestarts = 5
    $countFile = Join-Path $WinVPSDir 'tmp\.restart_count'
    if (-not (Test-Path (Split-Path $countFile))) {
        New-Item -ItemType Directory -Path (Split-Path $countFile) -Force | Out-Null
    }
    $totalRestarts = 0
    if (Test-Path $countFile) {
        $totalRestarts = [int](Get-Content $countFile -ErrorAction SilentlyContinue)
    }
    if ($totalRestarts -ge $maxRestarts) {
        Write-Host "[healthcheck] Max restarts ($maxRestarts) reached - skipping auto-heal"
        return
    }

    $healed = 0
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.BaseName
        $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if (-not $proc) {
            Write-Host "[healthcheck] Auto-healing $name..."
            Remove-Item $_.FullName -Force
            $script = Join-Path $WinVPSDir "src\core\$name.ps1"
            if (Test-Path $script) {
                Start-Process powershell -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" start" -WindowStyle Hidden -ErrorAction SilentlyContinue
                $healed++
            }
        }
    }
    if ($healed -gt 0) {
        $totalRestarts += $healed
        $totalRestarts | Out-File $countFile -Encoding ascii -Force
        Write-Host "[healthcheck] Auto-healed $healed service(s) (total restarts: $totalRestarts)"
    } else {
        Remove-Item $countFile -Force -ErrorAction SilentlyContinue
    }
}

function Write-Report {
    $total = $script:Passed + $script:Failed + $script:Warnings
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $reportFile = Join-Path $LogDir ("healthcheck_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    $report = @"
=== WinVPS Health Check Report ===
Timestamp: $ts
Results: $($script:Passed) passed, $($script:Warnings) warnings, $($script:Failed) failed
---
$($script:Results -join "`n")
=================================
"@
    $report | Out-File -FilePath $reportFile -Encoding ascii -Append

    if ($script:Failed -gt 0 -or $script:Warnings -gt 5) {
        Write-Host "[healthcheck] SUMMARY: $($script:Passed) passed, $($script:Warnings) warnings, $($script:Failed) failed - issues found"
        Invoke-AutoHeal
    } else {
        Write-Host "[healthcheck] SUMMARY: $($script:Passed) passed, $($script:Warnings) warnings, $($script:Failed) failed - healthy"
    }
    Write-Host "$($script:Passed)/$total"
}

Check-Cpu
Check-Memory
Check-Disk
Check-Services
Check-Network
Check-Temperature
Write-Report
