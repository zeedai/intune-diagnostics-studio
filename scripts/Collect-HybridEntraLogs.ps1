# Collect-HybridEntraLogs.ps1
# Zahin Memon — cloudadminhub.com
#
# Grabs everything I need to diagnose Hybrid/Entra join and Intune issues
# on a remote machine. Run this on the problem device, send me the ZIP.
#
# What gets collected:
#   - dsregcmd /status + /verbose
#   - All IME log files from IntuneManagementExtension\Logs
#   - MDM Diagnostics report (MdmDiagnosticsTool)
#   - Event Viewer: MDM Admin/Operational, AAD, User Device Registration,
#     Application (Intune), System errors
#   - Hybrid Join scheduled task state
#   - gpresult (GPO can break hybrid join silently)
#   - Device info, IP config, DNS + connectivity tests to Microsoft endpoints
#   - MDM cert inventory
#
# How to run:
#   Right-click the script -> Run with PowerShell (as Administrator)
#   Or: powershell.exe -ExecutionPolicy Bypass -File .\Collect-HybridEntraLogs.ps1
#
# Output: C:\temp\sendme.zip
# Works on any Windows 10/11 regardless of join state. Sections that don't
# apply just get skipped — won't crash on unenrolled or domain-only machines.

[CmdletBinding()]
param(
    [int]$DaysBack = 14,
    [string]$ZipPath = "C:\temp\sendme.zip"
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$hostname  = $env:COMPUTERNAME
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$workRoot  = "C:\temp\HybridEntraCollect-$timestamp"
$outDir    = Join-Path $workRoot $hostname
$startTime = (Get-Date).AddDays(-$DaysBack)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Zahin Memon - cloudadminhub.com" -ForegroundColor Cyan
Write-Host "  Hybrid / Entra / Intune Log Collector" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Device  : $hostname" -ForegroundColor White
Write-Host "  Admin   : $isAdmin" -ForegroundColor $(if ($isAdmin) { 'Green' } else { 'Yellow' })
Write-Host "  Output  : $ZipPath" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $isAdmin) {
    Write-Host "Not running as admin - some event log channels and dsregcmd /verbose" -ForegroundColor Yellow
    Write-Host "may be incomplete. Re-run as Administrator for a full collection." -ForegroundColor Yellow
    Write-Host ""
}

try {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
} catch {
    Write-Host "Can't create working folder at $outDir" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

# Simple wrapper - runs a block, marks it done or skipped in the summary
$summary = @()
function Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Host "  $Name..." -ForegroundColor Yellow -NoNewline
    try {
        & $Action
        Write-Host " OK" -ForegroundColor Green
        $script:summary += [PSCustomObject]@{ Step = $Name; Status = 'OK'; Note = '' }
    } catch {
        Write-Host " skipped" -ForegroundColor DarkYellow
        $script:summary += [PSCustomObject]@{ Step = $Name; Status = 'SKIPPED'; Note = $_.Exception.Message }
    }
}

Write-Host ""
Write-Host "Collecting..." -ForegroundColor White
Write-Host ""

# dsregcmd - I always start here, tells you everything about join state
Step "dsregcmd /status" {
    dsregcmd /status | Out-File -FilePath (Join-Path $outDir "dsregcmd-status.txt") -Encoding UTF8
}

Step "dsregcmd /status /verbose" {
    dsregcmd /status /verbose | Out-File -FilePath (Join-Path $outDir "dsregcmd-status-verbose.txt") -Encoding UTF8
}

# MDM Diagnostics Tool - Microsoft's own bundler, pulls certs/CSP/registry state
Step "MDM Diagnostics Report (MdmDiagnosticsTool)" {
    $mdmDir = Join-Path $outDir "MDMDiagnosticsReport"
    New-Item -ItemType Directory -Path $mdmDir -Force | Out-Null
    $p = Start-Process -FilePath "MdmDiagnosticsTool.exe" `
        -ArgumentList "-area DeviceEnrollment;DeviceProvisioning;Autopilot -zip `"$mdmDir\MDMDiagReport.zip`"" `
        -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    if ($p.ExitCode -ne 0) { throw "Exit code $($p.ExitCode)" }
}

# IME logs - the main one I look at for app/script/agent failures
Step "IntuneManagementExtension logs" {
    $src = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
    if (-not (Test-Path $src)) { throw "IME not installed or log path missing" }
    $dst = Join-Path $outDir "IME-Logs"
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item -Path "$src\*" -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
}

# Event log exports - translating known MDM event IDs to plain English
$knownEventIds = @{
    75   = "MDM ConfigManager: Set policies - success"
    76   = "MDM ConfigManager: Set policies - FAILED"
    77   = "MDM ConfigManager: Get policies - success"
    78   = "MDM ConfigManager: Get policies - FAILED"
    100  = "MDM Enrollment: started"
    101  = "MDM Enrollment: completed OK"
    102  = "MDM Enrollment: FAILED"
    103  = "MDM Auto-enrollment: started"
    104  = "MDM Auto-enrollment: FAILED"
    200  = "MDM Sync: session started"
    201  = "MDM Sync: completed OK"
    202  = "MDM Sync: FAILED"
    203  = "MDM Sync: server-triggered"
    404  = "MDM Sync: 404 - enrollment endpoint not found"
    405  = "MDM Sync: 405 - method not allowed"
    1001 = "Policy: applied OK"
    1002 = "Policy: FAILED to apply"
    8200 = "AutoEnroll: triggered via scheduled task"
    8201 = "AutoEnroll: failed to query AAD device info"
    8202 = "AutoEnroll: failed to get nonce"
    8204 = "AutoEnroll: FAILED"
    8211 = "AutoEnroll: already enrolled (skipped)"
    8300 = "AutoEnroll: succeeded"
}
function Translate-EventId($id) {
    if ($knownEventIds.ContainsKey([int]$id)) { return $knownEventIds[[int]$id] }
    return ""
}

function Export-EventLog {
    param([string]$LogName, [string]$Label, [string]$OutFile, [string[]]$Providers = $null)
    $rows = @()
    try {
        $filter = @{ LogName = $LogName; StartTime = $startTime }
        if ($Providers) { $filter['ProviderName'] = $Providers }
        $events = Get-WinEvent -FilterHashtable $filter -ErrorAction Stop
        foreach ($e in $events) {
            $rows += [PSCustomObject]@{
                TimeCreated     = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                Channel         = $Label
                Level           = $e.LevelDisplayName
                EventId         = $e.Id
                FriendlyMeaning = Translate-EventId $e.Id
                ProviderName    = $e.ProviderName
                Message         = ($e.Message -replace "`r`n", ' ' -replace "`n", ' ')
            }
        }
        if ($rows.Count -gt 0) {
            $rows | Sort-Object TimeCreated | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
        }
        return $rows.Count
    } catch {
        return -1
    }
}

$evtDir = Join-Path $outDir "EventLogs"
New-Item -ItemType Directory -Path $evtDir -Force | Out-Null

Step "Event log: MDM Diagnostics Admin" {
    $n = Export-EventLog -LogName 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin' `
        -Label 'MDM-Admin' -OutFile (Join-Path $evtDir "MDM-Admin.csv")
    if ($n -lt 0) { throw "Channel not accessible" }
}

Step "Event log: MDM Diagnostics Operational" {
    $n = Export-EventLog -LogName 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational' `
        -Label 'MDM-Operational' -OutFile (Join-Path $evtDir "MDM-Operational.csv")
    if ($n -lt 0) { throw "Channel not accessible - enable with: wevtutil set-log 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational' /enabled:true" }
}

Step "Event log: AAD/Entra Operational" {
    $n = Export-EventLog -LogName 'Microsoft-Windows-AAD/Operational' `
        -Label 'AAD-Operational' -OutFile (Join-Path $evtDir "AAD-Operational.csv")
    if ($n -lt 0) { throw "Channel not accessible" }
}

Step "Event log: User Device Registration" {
    $n = Export-EventLog -LogName 'Microsoft-Windows-User Device Registration/Admin' `
        -Label 'UserDeviceReg' -OutFile (Join-Path $evtDir "UserDeviceRegistration.csv")
    if ($n -lt 0) { throw "Channel not accessible" }
}

Step "Event log: Application (Intune providers)" {
    $n = Export-EventLog -LogName 'Application' -Label 'Application' `
        -OutFile (Join-Path $evtDir "Application-Intune.csv") `
        -Providers @('Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider', 'IntuneManagementExtension')
    if ($n -lt 0) { throw "Channel not accessible" }
}

Step "Event log: System (errors + warnings)" {
    $rows = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $startTime; Level = 1, 2, 3 } -ErrorAction Stop |
        Select-Object @{N='TimeCreated';E={$_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')}},
                      @{N='Level';E={$_.LevelDisplayName}},
                      @{N='EventId';E={$_.Id}},
                      @{N='ProviderName';E={$_.ProviderName}},
                      @{N='Message';E={$_.Message -replace "`r`n",' ' -replace "`n",' '}}
    if ($rows) {
        $rows | Export-Csv -Path (Join-Path $evtDir "System-Errors.csv") -NoTypeInformation -Encoding UTF8
    } else { throw "No errors/warnings in system log" }
}

# Hybrid join task - if this has never run or is erroring, that's usually why hybrid join is broken
Step "Hybrid Join scheduled task state" {
    $task     = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Workplace Join\" -TaskName "Automatic-Device-Join" -ErrorAction Stop
    $taskInfo = Get-ScheduledTaskInfo -InputObject $task
    @"
Task State         : $($task.State)
Last Run Time      : $($taskInfo.LastRunTime)
Last Result        : $($taskInfo.LastTaskResult)  (0 = success)
Next Run Time      : $($taskInfo.NextRunTime)
Missed Runs        : $($taskInfo.NumberOfMissedRuns)
"@ | Out-File -FilePath (Join-Path $outDir "HybridJoin-Task.txt") -Encoding UTF8
}

# GPO - hybrid join breaks silently when GPO blocks device registration
Step "Group Policy result (gpresult)" {
    $gpOut = Join-Path $outDir "gpresult.html"
    gpresult /h $gpOut /f 2>$null | Out-Null
    if (-not (Test-Path $gpOut)) { throw "gpresult produced no output" }
}

# Device context + connectivity checks
Step "Device info and connectivity tests" {
    $out = @()
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $tpm = $null; try { $tpm = Get-Tpm -ErrorAction Stop } catch {}

    $out += "Device: $hostname  |  Collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $out += ""
    $out += "OS             : $($os.Caption) Build $($os.BuildNumber)"
    $out += "Domain         : $($cs.Domain)"
    $out += "Domain Joined  : $($cs.PartOfDomain)"
    $out += "Make / Model   : $($cs.Manufacturer) $($cs.Model)"
    $out += "Logged on user : $env:USERNAME"
    $out += ""
    if ($tpm) {
        $out += "TPM Present    : $($tpm.TpmPresent)"
        $out += "TPM Ready      : $($tpm.TpmReady)"
        $out += "TPM Enabled    : $($tpm.TpmEnabled)"
    } else {
        $out += "TPM            : info unavailable (needs elevation)"
    }
    $out += ""
    $out += "--- IP Config ---"
    $out += (ipconfig /all | Out-String)
    $out += "--- DNS Test (login.microsoftonline.com) ---"
    try { $out += (Resolve-DnsName -Name "login.microsoftonline.com" -ErrorAction Stop | Out-String) }
    catch { $out += "FAILED: $($_.Exception.Message)" }
    $out += ""
    $out += "--- Endpoint Connectivity (port 443) ---"
    $endpoints = @(
        "login.microsoftonline.com",
        "device.login.microsoftonline.com",
        "enterpriseregistration.windows.net",
        "graph.microsoft.com",
        "enrollment.manage.microsoft.com",
        "fef.msub03.manage.microsoft.com"
    )
    foreach ($ep in $endpoints) {
        try {
            $r = Test-NetConnection -ComputerName $ep -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
            $out += "$ep : $(if ($r.TcpTestSucceeded) { 'OK' } else { 'FAILED' })"
        } catch {
            $out += "$ep : ERROR - $($_.Exception.Message)"
        }
    }
    $out | Out-File -FilePath (Join-Path $outDir "DeviceContext.txt") -Encoding UTF8
}

# MDM certs - expired or missing cert = total loss of Intune comms
Step "MDM certificate inventory" {
    $certs = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction Stop |
        Where-Object { $_.Issuer -like "*Intune*" -or $_.Issuer -like "*MDM*" -or $_.Subject -like "*MDM*" }
    $certOut = Join-Path $outDir "MDM-Certs.txt"
    if ($certs) {
        $certs | Select-Object Subject, Issuer, NotBefore, NotAfter, Thumbprint | Format-List |
            Out-File -FilePath $certOut -Encoding UTF8
    } else {
        "No MDM certificates found in LocalMachine\My." | Out-File -FilePath $certOut -Encoding UTF8
    }
}

# Collection log so I know what made it into the zip
$logOut = Join-Path $outDir "_collection-log.txt"
@("Zahin Memon - cloudadminhub.com",
  "Collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
  "Device: $hostname",
  "Admin: $isAdmin",
  "Days back: $DaysBack",
  "") | Out-File -FilePath $logOut -Encoding UTF8
foreach ($s in $summary) {
    "[{0,-8}] {1}" -f $s.Status, $s.Step | Out-File -FilePath $logOut -Append -Encoding UTF8
    if ($s.Note) { "           $($s.Note)" | Out-File -FilePath $logOut -Append -Encoding UTF8 }
}

# Zip it up
Write-Host ""
Write-Host "  Zipping to $ZipPath..." -ForegroundColor Yellow -NoNewline
try {
    $zipDir = Split-Path $ZipPath -Parent
    if (-not (Test-Path $zipDir)) { New-Item -ItemType Directory -Path $zipDir -Force | Out-Null }
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    Compress-Archive -Path $workRoot -DestinationPath $ZipPath -CompressionLevel Optimal
    Write-Host " done" -ForegroundColor Green
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

try { Remove-Item -Path $workRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}

$sizeMB = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Done" -ForegroundColor Green
Write-Host "  $ZipPath  ($sizeMB MB)" -ForegroundColor White
Write-Host "  Send this file to Zahin for analysis." -ForegroundColor White
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$summary | Format-Table -AutoSize

try { Start-Process explorer.exe -ArgumentList "/select,`"$ZipPath`"" } catch {}
