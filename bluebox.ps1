param(
  [Nullable[datetime]]$StartTime,
  [Nullable[datetime]]$EndTime,
  [int[]]$EventIds,
  [int]$MaxEvents = 2000,
  [switch]$IncludeWarnings,
  [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Timestamp {
  Get-Date -Format 'yyyyMMdd_HHmmss'
}

function Normalize-Events {
  param(
    [System.Diagnostics.Eventing.Reader.EventRecord[]]$Events,
    [string]$Category
  )

  $out = @()
  foreach ($e in $Events) {
    $out += [pscustomobject]@{
      Category = $Category
      LogName = $e.LogName
      TimeCreated = $e.TimeCreated.ToString('o')
      Level = $e.LevelDisplayName
      EventId = $e.Id
      Provider = $e.ProviderName
      Task = $e.TaskDisplayName
      RecordId = $e.RecordId
      Message = $e.Message
    }
  }
  return $out
}

function Get-EventLogData {
  param(
    [string]$LogName,
    [string]$Category,
    [string[]]$ProviderName,
    [int[]]$Levels,
    [Nullable[datetime]]$StartTime,
    [Nullable[datetime]]$EndTime,
    [int[]]$EventIds,
    [int]$MaxEvents
  )

  $filter = @{ LogName = $LogName }
  if ($ProviderName) { $filter.ProviderName = $ProviderName }
  if ($Levels) { $filter.Level = $Levels }
  if ($StartTime) { $filter.StartTime = $StartTime }
  if ($EndTime) { $filter.EndTime = $EndTime }
  if ($EventIds) { $filter.Id = $EventIds }

  try {
    $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop
  } catch {
    if ($_.Exception.Message -match 'No events were found') {
      return @()
    }
    throw
  }
  return Normalize-Events -Events $events -Category $Category
}

function Get-HardwareSpecs {
  $cs = Get-CimInstance -ClassName Win32_ComputerSystem
  $os = Get-CimInstance -ClassName Win32_OperatingSystem
  $cpu = Get-CimInstance -ClassName Win32_Processor
  $bios = Get-CimInstance -ClassName Win32_BIOS
  $baseboard = Get-CimInstance -ClassName Win32_BaseBoard
  $memory = Get-CimInstance -ClassName Win32_PhysicalMemory
  $disks = Get-CimInstance -ClassName Win32_DiskDrive
  $gpus = Get-CimInstance -ClassName Win32_VideoController
  $nics = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -and $_.NetEnabled }

  $totalRamBytes = ($memory | Measure-Object -Property Capacity -Sum).Sum

  return [pscustomobject]@{
    ComputerSystem = [pscustomobject]@{
      Manufacturer = $cs.Manufacturer
      Model = $cs.Model
      SystemType = $cs.SystemType
      TotalPhysicalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    }
    OperatingSystem = [pscustomobject]@{
      Caption = $os.Caption
      Version = $os.Version
      BuildNumber = $os.BuildNumber
      InstallDate = $os.InstallDate.ToString('o')
      LastBootUpTime = $os.LastBootUpTime.ToString('o')
      Architecture = $os.OSArchitecture
    }
    BIOS = [pscustomobject]@{
      Manufacturer = $bios.Manufacturer
      SMBIOSBIOSVersion = $bios.SMBIOSBIOSVersion
      ReleaseDate = $bios.ReleaseDate.ToString('o')
      SerialNumber = $bios.SerialNumber
    }
    BaseBoard = [pscustomobject]@{
      Manufacturer = $baseboard.Manufacturer
      Product = $baseboard.Product
      SerialNumber = $baseboard.SerialNumber
    }
    CPU = @($cpu | ForEach-Object {
      [pscustomobject]@{
        Name = $_.Name
        Cores = $_.NumberOfCores
        LogicalProcessors = $_.NumberOfLogicalProcessors
        MaxClockMHz = $_.MaxClockSpeed
      }
    })
    MemoryModules = @($memory | ForEach-Object {
      [pscustomobject]@{
        Manufacturer = $_.Manufacturer
        PartNumber = $_.PartNumber
        CapacityGB = [math]::Round($_.Capacity / 1GB, 2)
        SpeedMHz = $_.Speed
      }
    })
    TotalMemoryGB = [math]::Round($totalRamBytes / 1GB, 2)
    Disks = @($disks | ForEach-Object {
      [pscustomobject]@{
        Model = $_.Model
        InterfaceType = $_.InterfaceType
        SizeGB = [math]::Round($_.Size / 1GB, 2)
        SerialNumber = $_.SerialNumber
      }
    })
    GPUs = @($gpus | ForEach-Object {
      [pscustomobject]@{
        Name = $_.Name
        DriverVersion = $_.DriverVersion
        AdapterRAMGB = if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1GB, 2) } else { $null }
      }
    })
    NetworkAdapters = @($nics | ForEach-Object {
      [pscustomobject]@{
        Name = $_.Name
        MACAddress = $_.MACAddress
        SpeedMbps = if ($_.Speed) { [math]::Round($_.Speed / 1MB, 2) } else { $null }
      }
    })
  }
}

function Get-InstalledApps {
  $paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )

  $apps = foreach ($p in $paths) {
    Get-ItemProperty -Path $p -ErrorAction SilentlyContinue | Where-Object {
      $_.PSObject.Properties.Match('DisplayName').Count -gt 0 -and $_.DisplayName
    }
  }

  $apps | ForEach-Object {
    $props = $_.PSObject.Properties
    [pscustomobject]@{
      Name = $props['DisplayName']?.Value
      Version = $props['DisplayVersion']?.Value
      Publisher = $props['Publisher']?.Value
      InstallDate = $props['InstallDate']?.Value
      InstallLocation = $props['InstallLocation']?.Value
      UninstallString = $props['UninstallString']?.Value
    }
  } | Sort-Object Name -Unique
}

function Show-BlueBoxLogo {
  Write-Host ""
  Write-Host "██████╗ ██╗     ██╗   ██╗███████╗██████╗  ██████╗ ██╗  ██╗" -ForegroundColor Cyan
  Write-Host "██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔═══██╗██║  ██║" -ForegroundColor Cyan
  Write-Host "██████╔╝██║     ██║   ██║█████╗  ██████╔╝██║   ██║███████║" -ForegroundColor Blue
  Write-Host "██╔══██╗██║     ██║   ██║██╔══╝  ██╔══██╗██║   ██║██╔══██║" -ForegroundColor Blue
  Write-Host "██████╔╝███████╗╚██████╔╝███████╗██████╔╝╚██████╔╝██║  ██║" -ForegroundColor Cyan
  Write-Host "╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝" -ForegroundColor Cyan
  Write-Host "                    System Diagnostics Report" -ForegroundColor DarkCyan
  Write-Host ""
}

$timestamp = New-Timestamp
if (-not $OutputDir) {
  $OutputDir = Join-Path -Path (Get-Location) -ChildPath "out\\BlueBox_$timestamp"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Show-BlueBoxLogo
$progressStep = 0
function Step-Progress {
  param([string]$Activity, [int]$Total)
  $script:progressStep++
  $pct = [math]::Round(($script:progressStep / $Total) * 100)
  Write-Progress -Activity "BlueBox Diagnostics" -Status $Activity -PercentComplete $pct
}

$levels = @(1,2,3)

$hardwareProviders = @(
  'Microsoft-Windows-WHEA-Logger',
  'Microsoft-Windows-Kernel-Power',
  'Microsoft-Windows-Storage-Storport',
  'Microsoft-Windows-Partition',
  'Microsoft-Windows-Disk',
  'Disk',
  'Ntfs',
  'volmgr',
  'iaStorA',
  'stornvme',
  'storahci'
)
$hardwareProviders = $hardwareProviders | Where-Object {
  $null -ne (Get-WinEvent -ListProvider $_ -ErrorAction SilentlyContinue)
}

$errors = @()

Step-Progress -Activity "Collecting Application events" -Total 8
try {
  $appEvents = Get-EventLogData -LogName 'Application' -Category 'Application' -Levels $levels -StartTime $StartTime -EndTime $EndTime -EventIds $EventIds -MaxEvents $MaxEvents
} catch {
  $errors += "Failed to query Application log: $($_.Exception.Message)"
  $appEvents = @()
}

Step-Progress -Activity "Collecting System events" -Total 8
try {
  $sysEvents = Get-EventLogData -LogName 'System' -Category 'System' -Levels $levels -StartTime $StartTime -EndTime $EndTime -EventIds $EventIds -MaxEvents $MaxEvents
} catch {
  $errors += "Failed to query System log: $($_.Exception.Message)"
  $sysEvents = @()
}

Step-Progress -Activity "Collecting Hardware events" -Total 8
try {
  if ($hardwareProviders.Count -gt 0) {
    $hwEvents = Get-EventLogData -LogName 'System' -Category 'Hardware' -ProviderName $hardwareProviders -Levels $levels -StartTime $StartTime -EndTime $EndTime -EventIds $EventIds -MaxEvents $MaxEvents
  } else {
    $hwEvents = @()
    $errors += "Hardware events: no matching providers found on this machine."
  }
} catch {
  $errors += "Failed to query Hardware events: $($_.Exception.Message)"
  $hwEvents = @()
}

Step-Progress -Activity "Collecting hardware specifications" -Total 8
$hardware = Get-HardwareSpecs
Step-Progress -Activity "Collecting installed applications" -Total 8
$apps = Get-InstalledApps

$data = [pscustomobject]@{
  Meta = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o')
    MachineName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    StartTime = if ($StartTime) { $StartTime.ToString('o') } else { $null }
    EndTime = if ($EndTime) { $EndTime.ToString('o') } else { $null }
    EventIds = $EventIds
    MaxEvents = $MaxEvents
    IncludeWarnings = [bool]$IncludeWarnings
    Errors = $errors
  }
  Events = [pscustomobject]@{
    Application = $appEvents
    System = $sysEvents
    Hardware = $hwEvents
  }
  Hardware = $hardware
  InstalledApps = $apps
}

$json = $data | ConvertTo-Json -Depth 6
$json = $json -replace '</script', '<\/script'

$jsonPath = Join-Path $OutputDir 'data.json'
Set-Content -Path $jsonPath -Value $json -Encoding UTF8

Step-Progress -Activity "Generating HTML report" -Total 8
$html = @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>BlueBox Report</title>
  <style>
    :root {
      --bg-primary: #0a0e1a;
      --bg-secondary: #0f1419;
      --panel-primary: #151b26;
      --panel-secondary: #1a2332;
      --panel-tertiary: #1f2937;
      --accent-blue: #3b82f6;
      --accent-cyan: #06b6d4;
      --accent-gradient: linear-gradient(135deg, #3b82f6 0%, #06b6d4 100%);
      --text-primary: #f1f5f9;
      --text-secondary: #94a3b8;
      --text-muted: #64748b;
      --border-subtle: #1e293b;
      --border-medium: #334155;
      --warn: #f59e0b;
      --error: #ef4444;
      --success: #10b981;
      --critical: #dc2626;
      --shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.3);
      --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.4);
      --shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.5);
      --shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.6);
    }
    
    * { 
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    
    body {
      background: linear-gradient(135deg, #0a0e1a 0%, #151b26 50%, #0f1419 100%);
      background-attachment: fixed;
      color: var(--text-primary);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      line-height: 1.6;
      min-height: 100vh;
    }
    
    /* Header Styles */
    header {
      padding: 32px 32px 24px;
      background: linear-gradient(180deg, rgba(21, 27, 38, 0.8) 0%, rgba(21, 27, 38, 0) 100%);
      border-bottom: 1px solid var(--border-subtle);
      backdrop-filter: blur(10px);
      position: sticky;
      top: 0;
      z-index: 100;
    }
    
    .header-content {
      max-width: 1600px;
      margin: 0 auto;
    }
    
    h1 { 
      margin: 0 0 8px;
      font-size: 32px;
      font-weight: 700;
      background: var(--accent-gradient);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      letter-spacing: -0.5px;
    }
    
    .sub { 
      color: var(--text-secondary);
      font-size: 14px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    
    .sub::before {
      content: '';
      display: inline-block;
      width: 6px;
      height: 6px;
      background: var(--accent-cyan);
      border-radius: 50%;
      animation: pulse 2s ease-in-out infinite;
    }
    
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }
    
    /* Container */
    .container { 
      max-width: 1600px;
      margin: 0 auto;
      padding: 24px 32px 48px;
      display: grid;
      gap: 24px;
    }
    
    /* Panel Styles */
    .panel {
      background: var(--panel-primary);
      border: 1px solid var(--border-subtle);
      border-radius: 16px;
      padding: 24px;
      box-shadow: var(--shadow-lg);
      transition: all 0.3s ease;
      position: relative;
      overflow: hidden;
    }
    
    .panel::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      height: 2px;
      background: var(--accent-gradient);
      opacity: 0;
      transition: opacity 0.3s ease;
    }
    
    .panel:hover::before {
      opacity: 1;
    }
    
    .panel.tight { 
      padding: 16px;
    }
    
    .panel h2 { 
      margin: 0 0 20px;
      font-size: 20px;
      font-weight: 600;
      color: var(--text-primary);
      display: flex;
      align-items: center;
      gap: 12px;
      letter-spacing: -0.3px;
    }
    
    .panel h2::before {
      content: '';
      display: block;
      width: 4px;
      height: 20px;
      background: var(--accent-gradient);
      border-radius: 2px;
    }
    
    .panel h3 {
      margin: 0 0 12px;
      font-size: 14px;
      font-weight: 600;
      color: var(--text-secondary);
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    
    /* Split Layout */
    .split {
      display: grid;
      gap: 24px;
      grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr);
      align-items: start;
    }
    
    @media (max-width: 1200px) {
      .split { grid-template-columns: 1fr; }
    }
    
    /* Grid Layouts */
    .grid { 
      display: grid;
      gap: 16px;
    }
    
    .grid-2 { 
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    }
    
    /* Key-Value Pairs */
    .kv { 
      display: grid;
      grid-template-columns: minmax(140px, 45%) 1fr;
      gap: 8px 16px;
      font-size: 13px;
      align-items: start;
    }
    
    .kv div {
      padding: 6px 0;
      min-width: 0;
      word-wrap: break-word;
      overflow-wrap: break-word;
      word-break: break-word;
      hyphens: auto;
    }
    
    .kv div:first-child { 
      color: var(--text-muted);
      font-weight: 500;
    }
    
    .kv div:last-child { 
      color: var(--text-primary);
      font-family: 'Consolas', 'Monaco', monospace;
      font-size: 12px;
    }
    
    /* Forms & Inputs */
    .filters { 
      display: grid;
      gap: 16px;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    }
    .filter-span {
      grid-column: 1 / -1;
    }
    
    label { 
      font-size: 12px;
      font-weight: 500;
      color: var(--text-muted);
      display: block;
      margin-bottom: 6px;
      text-transform: uppercase;
      letter-spacing: 0.3px;
    }
    
    input, select {
      width: 100%;
      padding: 10px 12px;
      border-radius: 10px;
      border: 1px solid var(--border-medium);
      background: var(--panel-secondary);
      color: var(--text-primary);
      font-size: 13px;
      transition: all 0.2s ease;
      font-family: inherit;
    }
    
    input:focus, select:focus {
      outline: none;
      border-color: var(--accent-blue);
      box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1);
    }
    
    input::placeholder {
      color: var(--text-muted);
    }
    
    /* Tables */
    table { 
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    
    th, td { 
      padding: 12px;
      border-bottom: 1px solid var(--border-subtle);
      vertical-align: top;
      text-align: left;
      word-wrap: break-word;
      overflow-wrap: break-word;
      max-width: 300px;
    }
    
    th { 
      color: var(--text-muted);
      font-weight: 600;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.3px;
      background: var(--panel-secondary);
      position: sticky;
      top: 0;
      z-index: 10;
    }
    
    tbody tr {
      transition: background 0.15s ease;
    }
    
    tbody tr:hover { 
      background: rgba(59, 130, 246, 0.05);
    }
    
    /* Badges */
    .badge { 
      display: inline-block;
      padding: 4px 10px;
      border-radius: 8px;
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.3px;
    }
    
    .lvl-Error { 
      background: rgba(239, 68, 68, 0.15);
      color: var(--error);
      border: 1px solid rgba(239, 68, 68, 0.3);
    }
    
    .lvl-Critical { 
      background: rgba(220, 38, 38, 0.15);
      color: var(--critical);
      border: 1px solid rgba(220, 38, 38, 0.3);
    }
    
    .lvl-Warning { 
      background: rgba(245, 158, 11, 0.15);
      color: var(--warn);
      border: 1px solid rgba(245, 158, 11, 0.3);
    }
    
    /* Details/Summary */
    details {
      margin-top: 4px;
    }
    
    details summary { 
      cursor: pointer;
      color: var(--accent-blue);
      font-weight: 500;
      transition: color 0.2s ease;
      user-select: none;
      list-style: none;
    }
    
    details summary::-webkit-details-marker {
      display: none;
    }
    
    details summary::before {
      content: '▶';
      display: inline-block;
      margin-right: 6px;
      transition: transform 0.2s ease;
      font-size: 10px;
    }
    
    details[open] summary::before {
      transform: rotate(90deg);
    }
    
    details summary:hover { 
      color: var(--accent-cyan);
    }
    
    pre { 
      white-space: pre-wrap;
      word-break: break-word;
      background: var(--panel-tertiary);
      padding: 12px;
      border-radius: 8px;
      margin-top: 8px;
      font-size: 12px;
      line-height: 1.5;
      max-width: 100%;
      overflow-x: auto;
      border: 1px solid var(--border-medium);
    }
    
    /* ID Chips */
    .id-list {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }
    .id-chip {
      background: var(--panel-tertiary);
      border: 1px solid var(--border-medium);
      color: var(--text-secondary);
      border-radius: 999px;
      padding: 4px 10px;
      font-size: 11px;
      cursor: pointer;
      transition: all 0.15s ease;
    }
    .id-chip.active {
      background: rgba(59, 130, 246, 0.15);
      border-color: var(--accent-blue);
      color: var(--text-primary);
    }
    .id-chip:hover {
      border-color: var(--accent-cyan);
      color: var(--text-primary);
    }

    /* Scroll Panels */
    .scroll-panel {
      max-height: 65vh;
      overflow: auto;
      padding-right: 8px;
      margin: -8px;
      padding: 8px;
    }
    
    .scroll-panel table { 
      min-width: 100%;
    }
    
    .scroll-panel .panel {
      margin-bottom: 16px;
    }
    
    .scroll-panel::-webkit-scrollbar {
      height: 12px;
      width: 12px;
    }
    
    .scroll-panel::-webkit-scrollbar-track {
      background: var(--panel-secondary);
      border-radius: 6px;
    }
    
    .scroll-panel::-webkit-scrollbar-thumb {
      background: var(--border-medium);
      border-radius: 6px;
      border: 2px solid var(--panel-secondary);
    }
    
    .scroll-panel::-webkit-scrollbar-thumb:hover {
      background: var(--accent-blue);
    }
    
    /* Search */
    .search { 
      margin-bottom: 16px;
    }
    
    /* Footer */
    .footer { 
      color: var(--text-muted);
      font-size: 12px;
      background: var(--panel-secondary);
      display: flex;
      flex-wrap: wrap;
      gap: 16px;
      align-items: center;
    }
    
    .footer-item {
      display: flex;
      align-items: center;
      gap: 8px;
    }
    
    .footer-item::before {
      content: '•';
      color: var(--accent-cyan);
      font-weight: bold;
    }
    
    .footer-item:first-child::before {
      display: none;
    }
    
    /* Stats Cards */
    .stat-card {
      background: var(--panel-secondary);
      border: 1px solid var(--border-medium);
      border-radius: 12px;
      padding: 16px;
      transition: all 0.3s ease;
    }
    
    .stat-card:hover {
      transform: translateY(-2px);
      box-shadow: var(--shadow-md);
      border-color: var(--accent-blue);
    }
    
    /* Responsive */
    @media (max-width: 768px) {
      .container {
        padding: 16px;
        gap: 16px;
      }
      
      header {
        padding: 20px 16px;
      }
      
      h1 {
        font-size: 24px;
      }
      
      .panel {
        padding: 16px;
        border-radius: 12px;
      }
      
      .filters {
        grid-template-columns: 1fr;
      }
      
      .kv {
        grid-template-columns: 1fr;
        gap: 4px;
      }
      
      .scroll-panel {
        max-height: 50vh;
      }
      
      th, td {
        padding: 8px;
        font-size: 12px;
      }
    }
    
    /* Loading Animation */
    @keyframes shimmer {
      0% { background-position: -1000px 0; }
      100% { background-position: 1000px 0; }
    }
    
    /* Empty State */
    .empty-state {
      text-align: center;
      padding: 48px 24px;
      color: var(--text-muted);
    }
    
    .empty-state::before {
      content: '📊';
      display: block;
      font-size: 48px;
      margin-bottom: 16px;
      opacity: 0.5;
    }
  </style>
</head>
<body>
  <header>
    <div class="header-content">
      <h1>BlueBox Report</h1>
      <div class="sub" id="meta-line"></div>
    </div>
  </header>

  <div class="container">
    <section class="panel">
      <h2>Hardware Specifications</h2>
      <div class="grid grid-2" id="hardware-grid"></div>
    </section>

    <div class="split">
      <section class="panel">
        <h2>Events</h2>
        <div class="scroll-panel">
          <div class="panel tight stat-card">
            <h3>Filters</h3>
            <div class="filters">
              <div>
                <label for="log-filter">Log Source</label>
                <select id="log-filter">
                  <option value="All">All Sources</option>
                  <option value="Application">Application</option>
                  <option value="System">System</option>
                  <option value="Hardware">Hardware</option>
                </select>
              </div>
              <div>
                <label for="start-time">Start Time</label>
                <input type="datetime-local" id="start-time" />
              </div>
              <div>
                <label for="end-time">End Time</label>
                <input type="datetime-local" id="end-time" />
              </div>
              <div class="filter-span">
                <label>Event IDs</label>
                <div id="event-id-list" class="id-list" aria-live="polite"></div>
              </div>
            </div>
          </div>
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Level</th>
                <th>Event ID</th>
                <th>Provider</th>
                <th>Log</th>
                <th>Details</th>
              </tr>
            </thead>
            <tbody id="event-rows"></tbody>
          </table>
        </div>
      </section>

      <section class="panel">
        <h2>Software</h2>
        <div class="scroll-panel">
          <div class="search">
            <label for="app-search">Search Applications</label>
            <input type="text" id="app-search" placeholder="Filter by name, publisher, or version..." />
          </div>
          <table>
            <thead>
              <tr>
                <th>Name</th>
                <th>Version</th>
                <th>Publisher</th>
                <th>Install Date</th>
              </tr>
            </thead>
            <tbody id="app-rows"></tbody>
          </table>
        </div>
      </section>
    </div>

    <section class="panel footer" id="footer"></section>
  </div>

  <script id="data" type="application/json">__DATA__</script>
  <script>
    const data = JSON.parse(document.getElementById('data').textContent);

    const meta = data.Meta;
    const metaLine = `Generated ${new Date(meta.GeneratedAt).toLocaleString()} on ${meta.MachineName} (${meta.UserName})`;
    document.getElementById('meta-line').textContent = metaLine;

    const allEvents = [
      ...data.Events.Application,
      ...data.Events.System,
      ...data.Events.Hardware,
    ];

    const eventIdState = {
      allIds: [],
      selected: new Set()
    };

    function escapeHtml(text) {
      const div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    }

    function buildEventIdChips() {
      const container = document.getElementById('event-id-list');
      const uniqueIds = Array.from(new Set(allEvents.map(e => e.EventId))).filter(id => id !== null && id !== undefined);
      uniqueIds.sort((a, b) => a - b);
      eventIdState.allIds = uniqueIds;
      eventIdState.selected = new Set(uniqueIds);

      if (!uniqueIds.length) {
        container.innerHTML = '<div class="empty-state">No Event IDs available</div>';
        return;
      }

      const chips = uniqueIds.map(id => `
        <button type="button" class="id-chip active" data-id="${id}">
          ${escapeHtml(String(id))}
        </button>
      `).join('');
      container.innerHTML = chips;

      container.querySelectorAll('.id-chip').forEach(btn => {
        btn.addEventListener('click', () => {
          const id = parseInt(btn.dataset.id, 10);
          if (eventIdState.selected.has(id)) {
            eventIdState.selected.delete(id);
            btn.classList.remove('active');
          } else {
            eventIdState.selected.add(id);
            btn.classList.add('active');
          }
          applyFilters();
        });
      });
    }

    function applyFilters() {
      const logFilter = document.getElementById('log-filter').value;
      const startRaw = document.getElementById('start-time').value;
      const endRaw = document.getElementById('end-time').value;

      const start = startRaw ? new Date(startRaw) : null;
      const end = endRaw ? new Date(endRaw) : null;

      const idFilter = eventIdState.selected.size ? eventIdState.selected : null;

      const filtered = allEvents.filter(ev => {
        if (logFilter !== 'All' && ev.Category !== logFilter) return false;
        const t = new Date(ev.TimeCreated);
        if (start && t < start) return false;
        if (end && t > end) return false;
        if (idFilter && !idFilter.has(ev.EventId)) return false;
        return true;
      }).sort((a, b) => new Date(b.TimeCreated) - new Date(a.TimeCreated));

      const rows = filtered.slice(0, 2000).map(ev => {
        const lvlClass = ev.Level ? `lvl-${ev.Level}` : '';
        const message = ev.Message || '';
        const safeMessage = escapeHtml(message);
        return `
          <tr>
            <td>${escapeHtml(new Date(ev.TimeCreated).toLocaleString())}</td>
            <td><span class="badge ${lvlClass}">${escapeHtml(ev.Level || '')}</span></td>
            <td>${escapeHtml(String(ev.EventId))}</td>
            <td>${escapeHtml(ev.Provider || '')}</td>
            <td>${escapeHtml(ev.Category)}</td>
            <td>
              <details>
                <summary>View</summary>
                <pre>${safeMessage}</pre>
              </details>
            </td>
          </tr>
        `;
      }).join('');

      document.getElementById('event-rows').innerHTML = rows || '<tr><td colspan="6"><div class="empty-state">No matching events found</div></td></tr>';
    }

    ['log-filter', 'start-time', 'end-time'].forEach(id => {
      document.getElementById(id).addEventListener('input', applyFilters);
    });

    function renderHardware() {
      const hw = data.Hardware;
      const sections = [
        { title: 'Computer', entries: hw.ComputerSystem },
        { title: 'Operating System', entries: hw.OperatingSystem },
        { title: 'BIOS', entries: hw.BIOS },
        { title: 'Baseboard', entries: hw.BaseBoard },
      ];

      const container = document.getElementById('hardware-grid');
      const blocks = sections.map(section => {
        const rows = Object.entries(section.entries).map(([k, v]) => 
          `<div>${escapeHtml(k)}</div><div>${escapeHtml(String(v ?? ''))}</div>`
        ).join('');
        return `
          <div class="panel tight stat-card">
            <h3>${escapeHtml(section.title)}</h3>
            <div class="kv">${rows}</div>
          </div>
        `;
      });

      const cpuRows = hw.CPU.map(cpu => 
        `<div>${escapeHtml(cpu.Name)}</div><div>${cpu.Cores}C / ${cpu.LogicalProcessors}T @ ${cpu.MaxClockMHz}MHz</div>`
      ).join('');
      
      const memRows = hw.MemoryModules.map(mem => 
        `<div>${escapeHtml(mem.Manufacturer || '')} ${escapeHtml(mem.PartNumber || '')}</div><div>${mem.CapacityGB} GB @ ${mem.SpeedMHz} MHz</div>`
      ).join('');
      
      const diskRows = hw.Disks.map(d => 
        `<div>${escapeHtml(d.Model)}</div><div>${d.SizeGB} GB (${escapeHtml(d.InterfaceType)})</div>`
      ).join('');
      
      const gpuRows = hw.GPUs.map(g => 
        `<div>${escapeHtml(g.Name)}</div><div>Driver ${escapeHtml(g.DriverVersion)} / ${g.AdapterRAMGB ?? ''} GB</div>`
      ).join('');

      blocks.push(`
        <div class="panel tight stat-card">
          <h3>CPU</h3>
          <div class="kv">${cpuRows}</div>
        </div>
        <div class="panel tight stat-card">
          <h3>Memory (${hw.TotalMemoryGB} GB total)</h3>
          <div class="kv">${memRows}</div>
        </div>
        <div class="panel tight stat-card">
          <h3>Disks</h3>
          <div class="kv">${diskRows}</div>
        </div>
        <div class="panel tight stat-card">
          <h3>Graphics</h3>
          <div class="kv">${gpuRows}</div>
        </div>
      `);

      container.innerHTML = blocks.join('');
    }

    function renderApps() {
      const tbody = document.getElementById('app-rows');
      const input = document.getElementById('app-search');

      function draw() {
        const q = input.value.trim().toLowerCase();
        const rows = data.InstalledApps.filter(app => {
          if (!q) return true;
          return (app.Name || '').toLowerCase().includes(q) ||
            (app.Publisher || '').toLowerCase().includes(q) ||
            (app.Version || '').toLowerCase().includes(q);
        }).slice(0, 3000).map(app => `
          <tr>
            <td>${escapeHtml(app.Name || '')}</td>
            <td>${escapeHtml(app.Version || '')}</td>
            <td>${escapeHtml(app.Publisher || '')}</td>
            <td>${escapeHtml(app.InstallDate || '')}</td>
          </tr>
        `).join('');
        tbody.innerHTML = rows || '<tr><td colspan="4"><div class="empty-state">No applications match your search</div></td></tr>';
      }

      input.addEventListener('input', draw);
      draw();
    }

    function renderFooter() {
      const footer = document.getElementById('footer');
      const errors = meta.Errors || [];
      const items = [
        `Application Events: ${data.Events.Application.length}`,
        `System Events: ${data.Events.System.length}`,
        `Hardware Events: ${data.Events.Hardware.length}`,
        `Installed Apps: ${data.InstalledApps.length}`,
        errors.length ? `Errors: ${errors.join('; ')}` : 'No Errors'
      ];
      footer.innerHTML = items.map(item => `<div class="footer-item">${escapeHtml(item)}</div>`).join('');
    }

    buildEventIdChips();
    applyFilters();
    renderHardware();
    renderApps();
    renderFooter();
  </script>
</body>
</html>
'@

$html = $html -replace '__DATA__', $json
$htmlPath = Join-Path $OutputDir 'report.html'
Set-Content -Path $htmlPath -Value $html -Encoding UTF8

Step-Progress -Activity "Creating zip bundle" -Total 8
$zipPath = Join-Path $OutputDir "BlueBox_$timestamp.zip"
Compress-Archive -Path (Join-Path $OutputDir '*') -DestinationPath $zipPath -Force

Write-Progress -Activity "BlueBox Diagnostics" -Completed -Status "Done"
Write-Host ""
Write-Host "BlueBox report generated:" -ForegroundColor Cyan
Write-Host "  Folder: $OutputDir"
Write-Host "  HTML:   $htmlPath"
Write-Host "  ZIP:    $zipPath"
Write-Host ""
Write-Host "Open now? [F]older / [H]TML / [N]o" -ForegroundColor Yellow -NoNewline
$choice = Read-Host " "
switch ($choice.ToUpperInvariant()) {
  'F' { Start-Process -FilePath "explorer.exe" -ArgumentList $OutputDir }
  'H' { Start-Process -FilePath $htmlPath }
  default { }
}

