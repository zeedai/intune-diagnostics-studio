# Intune Diagnostics Studio

A lightweight local log reader for common Microsoft Intune, Entra ID, MDM and Intune Management Extension issues.

I built this because I wanted a quicker way to look through the logs I normally collect when troubleshooting Intune and Hybrid Entra Join devices. Instead of opening several log files and Event Viewer exports separately, I can drop them into one page and get the main errors, evidence and checks in one place.

## What it does

- Reads `.log`, `.txt`, `.csv`, `.json` and `.xml` files
- Works in a browser on Windows, macOS and Linux
- Runs locally, so the log files are not uploaded anywhere
- Picks up common Intune, IME, MDM and Entra ID errors
- Shows Critical, Warning, Info and OK findings
- Pulls basic device join and enrollment details when they are present in the logs
- Lets you search and filter the findings
- Exports the results as an HTML report
- Includes PowerShell scripts to collect useful Windows-side logs

## Quick start

1. Download `index.html`.
2. Open it in Chrome, Edge, Firefox or Safari.
3. Drop your Intune or Entra log files into the page.
4. Click **Analyse logs**.
5. Check the finding, evidence and **What to check** section before making any change.

No install is needed for the reader itself.

## Windows log collection

The analyser is cross-platform, but the collection scripts are Windows-only because they use Windows components such as `dsregcmd`, Event Viewer and the Intune Management Extension.

The `scripts` folder contains:

- `Collect-HybridEntraLogs.ps1` for a wider Intune / Hybrid Entra Join collection
- `Export-IntuneEventLogs.ps1` for exporting useful Intune and MDM Event Viewer entries

A normal workflow is:

1. Run the collector on the affected Windows device.
2. Copy the collected logs to the machine you want to troubleshoot from.
3. Open `index.html` on Windows, macOS or Linux.
4. Drop the files into the reader.

## Current checks

The rules currently cover areas such as:

- Intune service/network failures
- Intune Management Extension errors
- Health Script / Remediation retrieval failures
- Win32 app install failures
- assignment and filter exclusions
- MDM enrollment failures
- MDM policy apply/retrieval failures
- auto-enrollment failures
- enrollment nonce failures
- stale or deleted MDM enrollment references
- useful successful enrollment and communication events

## Important

This tool is there to make log review quicker. It does not replace checking the actual evidence, Microsoft documentation, tenant configuration or the device itself.

Some errors can have more than one cause, so I would not run a fix purely because the reader suggests it.

## Roadmap

Things I want to add next:

- direct `sendme.zip` support
- better Hybrid Entra Join health checks
- a simple AD Join → Entra Join → Device Auth → PRT → MDM → IME status chain
- more enrollment and Intune error codes
- Autopilot checks
- Windows Update checks
- SCCM / co-management checks
- better report export

## Author

Zahin Memon
