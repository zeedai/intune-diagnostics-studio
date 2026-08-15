# Intune Diagnostics Studio

A small tool I put together to make Intune troubleshooting a bit easier.

A lot of Intune, Hybrid Entra Join and MDM issues involve checking the same logs in different places, so I wanted one place where I could load the logs, spot the useful errors and quickly see what I should check next.

The analyser runs locally in your browser. It does not upload your logs anywhere.

## What it does

It can read and analyse:

- Intune Management Extension logs
- MDM Event Viewer exports
- Entra ID / Device Registration logs
- `dsregcmd /status`
- Windows device information
- network and DNS checks
- MDM certificate information
- Windows Update related logs
- Autopilot related logs
- SCCM / co-management related logs

Findings are grouped as:

- Critical
- Warning
- Information
- Healthy

It also shows the evidence from the logs and some checks to work through.

## Supported platforms

The log reader works on:

- Windows
- macOS
- Linux

You just need a modern browser.

The collection scripts need to be run on Windows because they use Windows-specific tools such as PowerShell, Event Viewer, `dsregcmd` and the Intune Management Extension logs.

## How to collect the logs

### Full Intune / Hybrid Entra Join collection

Copy this script to the Windows device you are troubleshooting:

```text
scripts/Collect-HybridEntraLogs.ps1
```

Open **PowerShell as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Collect-HybridEntraLogs.ps1
```

If the script is still blocked, use:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Collect-HybridEntraLogs.ps1
```

The script collects useful information including:

- `dsregcmd /status`
- Intune Management Extension logs
- MDM diagnostics
- Intune / MDM Event Viewer logs
- Entra ID / Device Registration events
- Group Policy results
- device information
- network and DNS checks
- MDM certificates
- Hybrid Join related information

When it finishes, it creates:

```text
C:\temp\sendme.zip
```

Copy that ZIP back to your troubleshooting machine.

### Event Viewer logs only

If you only need the Intune / MDM Event Viewer logs, use:

```text
scripts/Export-IntuneEventLogs.ps1
```

Run it from an elevated PowerShell window:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Export-IntuneEventLogs.ps1
```

The script exports the useful Event Viewer entries into a format that Intune Diagnostics Studio can read.

The main areas covered include:

- DeviceManagement-Enterprise-Diagnostics-Provider
- User Device Registration
- Entra ID / AAD
- MDM enrolment
- Autopilot
- Windows Update
- Application
- System

## How to analyse the logs

1. Open `index.html` in Chrome, Edge, Firefox or Safari.
2. Extract `sendme.zip`.
3. Drag the relevant log files into Intune Diagnostics Studio.
4. Click **Analyse logs**.
5. Review the findings, evidence and suggested checks.

Supported file types currently include:

```text
.log
.txt
.csv
.json
.xml
```

## Examples of checks

The current checks include things such as:

- Intune network / web exceptions
- IME errors
- Win32 app installation failures
- remediation script failures
- assignment / filter exclusions
- MDM enrolment failures
- stale MDM enrolment
- Hybrid Join issues
- Device Registration failures
- successful MDM enrolment
- MDM certificate information
- Windows Update related issues

It also checks for useful Event Viewer IDs including:

```text
76
78
102
404
8202
8204
8211
8300
```

## Privacy

Everything in the analyser runs locally in the browser.

The tool does not upload logs anywhere.

I would still check logs before sharing them publicly because they can contain things such as:

- usernames
- tenant names
- device IDs
- email addresses
- certificates
- customer names
- internal server names
- IP addresses

## What I want to add next

A few things I still want to improve:

- direct `sendme.zip` support
- better Hybrid Entra Join diagnosis
- better Event Viewer timeline
- Autopilot troubleshooting
- SCCM / co-management checks
- Windows Update checks
- more Intune and MDM error codes
- clearer device health summary
- exportable troubleshooting reports

The aim is to make the first pass on a problem device quicker instead of opening a load of different logs one by one.

## Project files

```text
intune-diagnostics-studio/
├── index.html
├── README.md
├── LICENSE
├── .gitignore
├── GITHUB.md
└── scripts/
    ├── Collect-HybridEntraLogs.ps1
    └── Export-IntuneEventLogs.ps1
```

## Disclaimer

This is a troubleshooting tool I built for my own use and learning.

Always check the actual logs and understand the environment before making changes to production devices.
