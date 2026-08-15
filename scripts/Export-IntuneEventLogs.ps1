<#
.SYNOPSIS
    Exports Windows Event Viewer logs relevant to Intune/MDM device management
    into a CSV format readable by the Intune Log Analyser.

.DESCRIPTION
    Pulls events from:
    - Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin
    - Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational
    - Application log (filtered to Intune/IME/MDM related sources)
    - Microsoft-Windows-AAD/Operational (Entra ID join/auth events)

    Known MDM Event IDs are translated to human-readable descriptions.

.NOTES
    Run as Administrator for full access to all log channels.
    Output is saved to Desktop by default.
#>

param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\IntuneEventLogs-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv",
    [int]$DaysBack = 14
)

Write-Host "Intune Event Log Exporter" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

$startTime = (Get-Date).AddDays(-$DaysBack)
$allEvents = @()

# Known MDM/Intune Event ID translations
$eventIdMap = @{
    # DeviceManagement-Enterprise-Diagnostics-Provider
    75   = "MDM ConfigManager: Set policies completed successfully"
    76   = "MDM ConfigManager: Set policies failed"
    77   = "MDM ConfigManager: Get policies completed successfully"
    78   = "MDM ConfigManager: Get policies failed"
    100  = "MDM Enrollment: Enrollment started"
    101  = "MDM Enrollment: Enrollment completed successfully"
    102  = "MDM Enrollment: Enrollment failed"
    103  = "MDM Enrollment: Auto-enrollment started"
    104  = "MDM Enrollment: Auto-enrollment failed"
    200  = "MDM Sync: Session started"
    201  = "MDM Sync: Session completed successfully"
    202  = "MDM Sync: Session failed"
    203  = "MDM Sync: Server-initiated sync triggered"
    404  = "MDM Sync: HTTP 404 - endpoint not found, check enrollment"
    405  = "MDM Sync: HTTP 405 - method not allowed"
    1001 = "Policy Manager: Configuration applied successfully"
    1002 = "Policy Manager: Configuration failed to apply"
    8200 = "AutoEnrollment: MDM auto-enrollment via scheduled task"
    8201 = "AutoEnrollment: Failed to query AAD device info"
    8202 = "AutoEnrollment: Failed to get nonce"
    8204 = "AutoEnrollment: Auto MDM enroll failed"
    8211 = "AutoEnrollment: Device is already enrolled"
    8300 = "AutoEnrollment: Auto MDM enroll succeeded"
}

function Get-FriendlyEventDescription {
    param($EventId, $Message)
    if ($eventIdMap.ContainsKey([int]$EventId)) {
        return $eventIdMap[[int]$EventId]
    }
    return $null
}

# ── 1. MDM Diagnostics Provider - Admin channel ─────────────────────────
Write-Host "Reading: DeviceManagement-Enterprise-Diagnostics-Provider/Admin..." -ForegroundColor Yellow
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'
        StartTime = $startTime
    } -ErrorAction Stop

    foreach ($e in $events) {
        $friendly = Get-FriendlyEventDescription -EventId $e.Id -Message $e.Message
        $allEvents += [PSCustomObject]@{
            TimeCreated      = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
            Channel          = 'MDM-Admin'
            Level            = $e.LevelDisplayName
            EventId          = $e.Id
            FriendlyMeaning  = $friendly
            ProviderName     = $e.ProviderName
            Message          = ($e.Message -replace "`r`n", ' ' -replace "`n", ' ')
        }
    }
    Write-Host "  Found $($events.Count) events" -ForegroundColor Green
} catch {
    Write-Host "  Skipped (no events found or access denied): $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# ── 2. MDM Diagnostics Provider - Operational channel ───────────────────
Write-Host "Reading: DeviceManagement-Enterprise-Diagnostics-Provider/Operational..." -ForegroundColor Yellow
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational'
        StartTime = $startTime
    } -ErrorAction Stop

    foreach ($e in $events) {
        $friendly = Get-FriendlyEventDescription -EventId $e.Id -Message $e.Message
        $allEvents += [PSCustomObject]@{
            TimeCreated      = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
            Channel          = 'MDM-Operational'
            Level            = $e.LevelDisplayName
            EventId          = $e.Id
            FriendlyMeaning  = $friendly
            ProviderName     = $e.ProviderName
            Message          = ($e.Message -replace "`r`n", ' ' -replace "`n", ' ')
        }
    }
    Write-Host "  Found $($events.Count) events" -ForegroundColor Green
} catch {
    Write-Host "  Skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# ── 3. Application log filtered to Intune-related sources ──────────────
Write-Host "Reading: Application log (Intune/IME providers)..." -ForegroundColor Yellow
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName      = 'Application'
        StartTime    = $startTime
        ProviderName = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider', 'IntuneManagementExtension'
    } -ErrorAction Stop

    foreach ($e in $events) {
        $friendly = Get-FriendlyEventDescription -EventId $e.Id -Message $e.Message
        $allEvents += [PSCustomObject]@{
            TimeCreated      = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
            Channel          = 'Application'
            Level            = $e.LevelDisplayName
            EventId          = $e.Id
            FriendlyMeaning  = $friendly
            ProviderName     = $e.ProviderName
            Message          = ($e.Message -replace "`r`n", ' ' -replace "`n", ' ')
        }
    }
    Write-Host "  Found $($events.Count) events" -ForegroundColor Green
} catch {
    Write-Host "  Skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# ── 4. AAD/Entra join and auth events ───────────────────────────────────
Write-Host "Reading: AAD/Operational (Entra join/auth)..." -ForegroundColor Yellow
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Microsoft-Windows-AAD/Operational'
        StartTime = $startTime
    } -ErrorAction Stop

    foreach ($e in $events) {
        $allEvents += [PSCustomObject]@{
            TimeCreated      = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
            Channel          = 'AAD-Operational'
            Level            = $e.LevelDisplayName
            EventId          = $e.Id
            FriendlyMeaning  = $null
            ProviderName     = $e.ProviderName
            Message          = ($e.Message -replace "`r`n", ' ' -replace "`n", ' ')
        }
    }
    Write-Host "  Found $($events.Count) events" -ForegroundColor Green
} catch {
    Write-Host "  Skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# ── Export ────────────────────────────────────────────────────────────────
if ($allEvents.Count -eq 0) {
    Write-Host ""
    Write-Host "No events found. This usually means:" -ForegroundColor Red
    Write-Host "  - Script wasn't run as Administrator (some channels need elevation)" -ForegroundColor Red
    Write-Host "  - This device isn't Intune-enrolled" -ForegroundColor Red
    Write-Host "  - The DeviceManagement-Enterprise-Diagnostics-Provider log channel is disabled" -ForegroundColor Red
    Write-Host ""
    Write-Host "To enable the Operational log channel, run:" -ForegroundColor Yellow
    Write-Host '  wevtutil set-log "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Operational" /enabled:true' -ForegroundColor White
    exit 1
}

$allEvents = $allEvents | Sort-Object TimeCreated
$allEvents | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "==========================" -ForegroundColor Cyan
Write-Host "Export complete!" -ForegroundColor Green
Write-Host "Total events: $($allEvents.Count)" -ForegroundColor Green
Write-Host "Saved to: $OutputPath" -ForegroundColor Green
Write-Host ""
Write-Host "Drop this CSV file into the Intune Log Analyser alongside your .log files." -ForegroundColor Cyan

# Open the containing folder
Start-Process explorer.exe -ArgumentList "/select,`"$OutputPath`""
