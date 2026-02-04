# BlueBox ⚡📦

```
██████╗ ██╗     ██╗   ██╗███████╗██████╗  ██████╗ ██╗  ██╗
██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔═══██╗██║  ██║
██████╔╝██║     ██║   ██║█████╗  ██████╔╝██║   ██║███████║
██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██║   ██║██╔══██║
██████╔╝███████╗╚██████╔╝███████╗██████╔╝╚██████╔╝██║  ██║
╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝
                    System Diagnostics Report
```

BlueBox is a PowerShell-based diagnostics report generator. It collects common Windows event logs (Application/System/Hardware errors, criticals, and warnings), hardware specifications, and installed applications, then produces a self-contained HTML dashboard and a portable ZIP bundle. ✨

## Features 🧭

- Collects Application, System, and Hardware-related event logs (Error/Critical/Warning). 🧾
- Gathers hardware specs (CPU, RAM, disks, GPU, BIOS, baseboard, OS, NICs). 🧩
- Lists installed applications from common registry locations. 📦
- Generates a single-page HTML dashboard with filters and search. 🖥️
- Creates a ZIP bundle for easy sharing or later viewing. 🧰
- Shows a colored ASCII logo, progress bar, and post-run options to open the folder or report. 🎛️

## Requirements ✅

- Windows 10/11
- PowerShell 7+ (recommended)
- Permission to read event logs and registry keys

## Usage 🚀

Run from the project root:

```powershell
.\bluebox.ps1
```

Optional parameters:

```powershell
.\bluebox.ps1 -StartTime "2026-01-01" -EndTime "2026-02-03" -EventIds 41,1000 -MaxEvents 5000
```

Parameters:

- `-StartTime` / `-EndTime`: Date/time range for events.
- `-EventIds`: Filter by event IDs when collecting (comma-separated list).
- `-MaxEvents`: Maximum events per query (default `2000`).
- `-IncludeWarnings`: No longer required for warnings (warnings are included by default).
- `-OutputDir`: Custom output folder.

## Output 📁

A new folder is created under:

```
.\out\BlueBox_YYYYMMDD_HHMMSS\
```

Contents:

- `report.html` — self-contained dashboard
- `data.json` — raw data payload
- `BlueBox_YYYYMMDD_HHMMSS.zip` — portable bundle

## Notes 📝

- If no hardware events exist on a system, the report will show zero hardware events without an error.
- The HTML is fully offline and can be opened on another machine.

## Project Name 💠

BlueBox
