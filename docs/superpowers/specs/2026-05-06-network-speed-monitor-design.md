# Network Speed Monitor — Design Spec
Date: 2026-05-06

## Goal

Add a new tool to the IT Tools Hub that lets IT staff investigate the upload/download speed of a specific Intune-enrolled device on demand. Results are stored historically in SharePoint so that repeated investigations of the same device build a trend over time. IT can export a PDF report to share with department heads or leadership.

---

## Approach

On-demand, investigation-driven. No fleet-wide background collection — a device only accumulates history if IT has had reason to investigate it. This keeps scope tight, avoids red tape around mass script deployment, and ensures all stored data is meaningful.

---

## Architecture

```
IT Admin (browser)
      │
      │  1. Enter device name → search
      ▼
IT Tools Hub (MSAL auth, Graph API)
      │
      │  2. Graph API → Intune managedDevices
      │     Resolve machine name → Intune device ID + user/dept metadata
      │
      │  3. Graph API → SharePoint list
      │     Load all prior test results for this device (filtered by DeviceName)
      │
      │  4. "Run Fresh Test" → Graph API →
      │     Intune deviceHealthScripts (trigger on specific device only)
      ▼
Intune-enrolled Device
      │
      │  5. PowerShell remediation script runs Speedtest CLI
      │     Captures: download, upload, latency, jitter, ISP, external IP
      │
      │  6. Script POSTs result to SharePoint list
      │     via Graph API (dedicated app registration / service principal)
      ▼
SharePoint List (data store)
      │
      │  7. IT admin refreshes tool → new result appears in history
      ▼
PDF Export (in-browser)
      └─ Chart + table rendered client-side → jsPDF → file download
```

---

## SharePoint List Schema

List name: `NetworkSpeedTests`

| Column | Type | Notes |
|--------|------|-------|
| `DeviceName` | Single line text | Machine name (e.g. DESKTOP-RX9421) |
| `IntuneDeviceId` | Single line text | Intune managed device GUID |
| `Timestamp` | Date/Time | UTC, set by the device script |
| `DownloadMbps` | Number | Decimal, one place |
| `UploadMbps` | Number | Decimal, one place |
| `LatencyMs` | Number | Integer |
| `JitterMs` | Number | Decimal, one place |
| `ISP` | Single line text | From Speedtest CLI output |
| `ExternalIP` | Single line text | Masked in UI (72.xxx.xxx.xxx) |
| `TriggeredBy` | Single line text | UPN of IT admin who triggered the test |

---

## Graph API Permissions Required

| Permission | Purpose |
|-----------|---------|
| `DeviceManagementManagedDevices.Read.All` | Look up device by machine name, get user/dept metadata |
| `DeviceManagementConfiguration.ReadWrite.All` | Trigger the Intune remediation script on a specific device |
| `Sites.ReadWrite.All` | Read all prior test results and write new results to SharePoint list |

---

## UI Components

### 1. Search Bar
- Text input: accepts machine name or serial number
- Search button → calls Intune Graph API to resolve device
- Error state: "Device not found in Intune — check the name and try again"

### 2. Device Header
- Machine name (bold), user display name, department, last Intune check-in time
- Badge: "N prior tests" (amber) or "No prior tests" (grey)
- Action buttons:
  - **⚡ Run Fresh Test** — triggers remediation script on this device only; sets UI to pending state
  - **↓ Export PDF** — generates and downloads the report

### 3. Pending State Banner
Shown after triggering a fresh test, until the device checks in and a new result appears:
> "Test triggered — results will appear after the device checks in (typically 15–30 min). Refresh to check."

### 4. Latest Result Stats
Four stat pills showing the most recent test: Download (Mbps), Upload (Mbps), Latency (ms), Jitter (ms). Hidden when no prior tests exist.

### 5. ISP / External IP pill
Shows ISP name and partially masked external IP from the most recent test.

### 6. Speed History Chart
Horizontal bar chart — one row group per test date, each group has a Download bar and an Upload bar. Layout:
- Date label on left
- Mbps value to the left of each bar (colored: blue for download, green for upload)
- Bar fills proportionally to the highest value in the dataset (scale adjusts dynamically; minimum scale is 100 Mbps)
- "Mbps" label to the right of each bar
- Most recent test highlighted with blue left border and light blue background

### 7. Full Test Log Table
Columns: Date & Time · Down (Mbps) · Up (Mbps) · Latency (ms) · Jitter (ms) · Triggered by
Most recent row highlighted in blue tint. Rows in reverse-chronological order.

---

## PDF Export Layout

Generated client-side using jsPDF. Single-page portrait layout:

1. **Header** — "Network Speed Report", generated date/time, prepared by (IT admin UPN), "Corro Health IT / Confidential"
2. **Device Info row** — Device name, user, department, test count, ISP
3. **Most Recent Test callout** — Four large stat tiles (Download, Upload, Latency, Jitter) with color coding
4. **Speed Trend chart** — Same horizontal bar layout as in-app, with Mbps values labeled on each bar; most recent test highlighted
5. **Full Test Log table** — All stored results for this device
6. **Footer note** — "Tests triggered on-demand via Intune Remediation Script. Results measured using Speedtest CLI on the device and stored in SharePoint."

---

## PowerShell Remediation Script (device-side)

The script runs on the target device when triggered via Intune. Responsibilities:
- Download `speedtest.exe` (Ookla Speedtest CLI) from an internally-hosted location (Azure Blob Storage or SharePoint document library) to `$env:TEMP` at runtime — no pre-installation required on devices
- Run `speedtest.exe --format=json --accept-license --accept-gdpr`
- Parse JSON output: download, upload, latency, jitter, ISP, external IP
- Authenticate to Graph API using a dedicated app registration (client ID + secret stored as Intune script parameters or Intune-managed secret)
- POST result to SharePoint `NetworkSpeedTests` list via Graph API
- Delete the temp `speedtest.exe` after use
- Exit 0 on success, exit 1 on failure (Intune reports compliance state)

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Device not found in Intune | Error message below search bar; no panel shown |
| Device found, no prior tests | Panel shows device header + "No prior tests yet" message + Run Fresh Test button; stat tiles and chart hidden |
| Fresh test triggered, device not yet checked in | Pending banner shown; existing history still visible |
| Speedtest CLI download fails (no internet or hosting URL unreachable) | Script exits 1; Intune marks remediation as failed; tool shows no new result after polling window |
| SharePoint list empty for device | Same as no prior tests |

---

## Out of Scope

- Automatic scheduled collection across all devices (deferred — requires broader Intune policy approval)
- Email or Teams notifications (IT manually exports and shares the PDF)
- Azure Log Analytics integration (deferred — viable v2 upgrade path if Log Analytics is enabled)
- Threshold alerting (deferred)
- Non-Intune devices

---

## Config Entry

```json
{
  "id": "network-speed-monitor",
  "name": "Network Speed Monitor",
  "description": "Investigate upload/download speeds on a specific Intune-enrolled device and export a trend report for leadership.",
  "status": "beta",
  "path": "tools/network-speed-monitor/",
  "permissions": [
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementConfiguration.ReadWrite.All",
    "Sites.ReadWrite.All"
  ],
  "accent": "#1a56db",
  "iconBg": "#e8f0fe",
  "category": "reporting-audit"
}
```
