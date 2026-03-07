# Autom8ed_CS2_GameMode.ps1
# Auto "starve browsers + boost CS2" when cs2.exe is running, restore when it exits.
# Replaces Process Lasso for CS2 gaming sessions.
# Run elevated (Admin required for process priority/affinity/EcoQoS).
# Works in PS5.1 and PS7+.
#
# PSScriptAnalyzer: disable unapproved verb warnings (this script uses system-level performance tuning verbs)
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
#
# Usage:
#   .\Autom8ed_CS2_GameMode.ps1              # Auto-detect CS2 start/stop (polling loop, stays resident)
#   .\Autom8ed_CS2_GameMode.ps1 -GameOn      # One-shot: starve browsers + boost CS2 now, then exit
#   .\Autom8ed_CS2_GameMode.ps1 -GameOff     # One-shot: restore browsers, then exit
#   .\Autom8ed_CS2_GameMode.ps1 -PollSeconds 5  # Change poll interval (default 3s)

param(
    [switch]$GameOn,
    [switch]$GameOff,
    [int]$PollSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Admin check ---
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires elevation. Run as Administrator."
    exit 1
}

# --- Config ---
[string[]]$Browsers = @('msedge','brave','chrome','opera','firefox')
[string]$GameExe    = 'cs2'

$LogDir  = 'C:\Tools\autom8ed\Logs'
$LogFile = Join-Path $LogDir 'GameMode.log'
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$ts $Message" | Out-File -FilePath $LogFile -Encoding UTF8 -Append -Force
}

# --- Detect P-core / E-core topology (Intel 12th gen+) ---
# Returns array of P-core logical processor indices, or $null if not hybrid.
function Get-PerformanceCoreIndices {
    try {
        $logical = Get-CimInstance -ClassName Win32_Processor | Select-Object -ExpandProperty NumberOfLogicalProcessors
        # Heuristic: on hybrid CPUs (e.g. 8P+8E = 24 threads with HT on P-cores, 16 total cores),
        # P-cores are the first N logical processors with hyperthreading.
        # If logical > cores*1 but the system has an even split, we approximate P-cores as first half.
        # More accurate: read EfficiencyClass from Win32_Processor on Win11 22H2+
        $procs = Get-CimInstance -ClassName Win32_Processor
        if ($procs.Count -gt 1) {
            # Multi-socket or CIM returns per-core objects with EfficiencyClass
            $pCores = @()
            $idx = 0
            foreach ($p in $procs) {
                $count = $p.NumberOfLogicalProcessors
                if ($null -eq $p.CimInstanceProperties['EfficiencyClass'] -or $p.EfficiencyClass -eq 0) {
                    # EfficiencyClass 0 = Performance core
                    for ($i = 0; $i -lt $count; $i++) { $pCores += $idx + $i }
                }
                $idx += $count
            }
            if ($pCores.Count -gt 0 -and $pCores.Count -lt $logical) { return $pCores }
        }
        return $null  # Non-hybrid or can't detect
    } catch {
        return $null
    }
}

# Build affinity mask from core index array
function ConvertTo-AffinityMask {
    param([int[]]$CoreIndices)
    [long]$mask = 0
    foreach ($i in $CoreIndices) { $mask = $mask -bor (1L -shl $i) }
    return [IntPtr]$mask
}

$script:PCoreIndices = Get-PerformanceCoreIndices
# E-cores and HT disabled: 8 P-cores = logical processors 0-7.
# Exclude core 0 (Windows DPC/interrupt magnet). CS2 gets cores 1-7.
$script:GameCoreIndices = @(1, 2, 3, 4, 5, 6, 7)
$script:PCoreMask = ConvertTo-AffinityMask -CoreIndices $script:GameCoreIndices
Write-Log "[*] CS2 affinity: cores $($script:GameCoreIndices -join ',') (mask=$($script:PCoreMask))"

# --- P/Invoke for EcoQoS / Process Power Throttling ---
$src = @"
using System;
using System.Runtime.InteropServices;
public static class ProcPower {
    public const int ProcessPowerThrottling = 4;  // ProcessInformationClass
    public const uint PROCESS_POWER_THROTTLING_CURRENT_VERSION = 1;
    public const uint PROCESS_POWER_THROTTLING_EXECUTION_SPEED = 0x1;

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_POWER_THROTTLING_STATE {
        public uint Version;
        public uint ControlMask;
        public uint StateMask;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetProcessInformation(
        IntPtr hProcess,
        int ProcessInformationClass,
        ref PROCESS_POWER_THROTTLING_STATE ProcessInformation,
        int ProcessInformationSize);
}
"@
if (-not ([System.Management.Automation.PSTypeName]'ProcPower').Type) {
    Add-Type -TypeDefinition $src -Language CSharp
}

function Set-EcoQos {
    param(
        [System.Diagnostics.Process]$Proc,
        [bool]$Enable
    )
    try {
        $state = New-Object ProcPower+PROCESS_POWER_THROTTLING_STATE
        $state.Version     = [ProcPower]::PROCESS_POWER_THROTTLING_CURRENT_VERSION
        $state.ControlMask = [ProcPower]::PROCESS_POWER_THROTTLING_EXECUTION_SPEED
        $state.StateMask   = if ($Enable) { [ProcPower]::PROCESS_POWER_THROTTLING_EXECUTION_SPEED } else { 0 }
        $size = [System.Runtime.InteropServices.Marshal]::SizeOf([type][ProcPower+PROCESS_POWER_THROTTLING_STATE])
        $ok = [ProcPower]::SetProcessInformation(
            $Proc.Handle,
            [ProcPower]::ProcessPowerThrottling,
            [ref]$state,
            $size)
        if (-not $ok) {
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-Log "[!] EcoQoS($Enable) failed for $($Proc.ProcessName) PID=$($Proc.Id) Win32Error=$err"
        }
    } catch {
        Write-Log "[!] EcoQoS($Enable) exception for $($Proc.ProcessName): $($_.Exception.Message)"
    }
}

# --- Apply / Restore functions ---
function Invoke-StarveBrowsers {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $Browsers }
    foreach ($p in $procs) {
        try {
            if ($p.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::BelowNormal) {
                $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
            }
            Set-EcoQos -Proc $p -Enable $true
            Write-Log "[-] STARVE $($p.Name) PID=$($p.Id)"
        } catch {
            Write-Log "[!] STARVE fail $($p.Name) PID=$($p.Id): $($_.Exception.Message)"
        }
    }
}

function Invoke-RestoreBrowsers {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $Browsers }
    foreach ($p in $procs) {
        try {
            if ($p.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::Normal) {
                $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
            }
            Set-EcoQos -Proc $p -Enable $false
            Write-Log "[+] RESTORE $($p.Name) PID=$($p.Id)"
        } catch {
            Write-Log "[!] RESTORE fail $($p.Name) PID=$($p.Id): $($_.Exception.Message)"
        }
    }
}

function Invoke-BoostGame {
    $procs = Get-Process -Name $GameExe -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        try {
            # High priority
            if ($p.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::High) {
                $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
                Write-Log "[+] CS2 PID=$($p.Id) -> High priority"
            }
            # EcoQoS OFF (ensure full performance scheduling)
            Set-EcoQos -Proc $p -Enable $false
            # Pin to P-cores (excluding core 0) — core 0 handles DPCs/interrupts
            $p.ProcessorAffinity = $script:PCoreMask
            Write-Log "[+] CS2 PID=$($p.Id) -> Affinity set to cores $($script:GameCoreIndices -join ',') (mask=$($script:PCoreMask))"
        } catch {
            Write-Log "[!] BOOST CS2 fail PID=$($p.Id): $($_.Exception.Message)"
        }
    }
}

function Invoke-UnboostGame {
    $procs = Get-Process -Name $GameExe -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        try {
            $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
            # Reset affinity to all cores
            $allCores = (1L -shl [Environment]::ProcessorCount) - 1L
            $p.ProcessorAffinity = [IntPtr]$allCores
        } catch { }
    }
}

# --- One-shot modes ---
if ($GameOn) {
    Write-Log "[cmd] GameOn (manual)"
    Invoke-StarveBrowsers
    Invoke-BoostGame
    Write-Log "[+] GameOn applied. Exiting."
    exit 0
}
if ($GameOff) {
    Write-Log "[cmd] GameOff (manual)"
    Invoke-RestoreBrowsers
    Invoke-UnboostGame
    Write-Log "[+] GameOff applied. Exiting."
    exit 0
}

# --- Polling loop: auto-detect CS2 start/stop ---
Write-Log "[*] Autom8ed_CS2_GameMode starting in auto-detect mode (poll=${PollSeconds}s)"
Write-Host "[*] Autom8ed CS2 GameMode active. Polling every ${PollSeconds}s for $GameExe. Press Ctrl+C to stop."

$script:Gaming = $false
$script:BoostedPIDs = @{}   # Track PIDs we've already configured

try {
    while ($true) {
        $cs2 = Get-Process -Name $GameExe -ErrorAction SilentlyContinue

        if ($cs2 -and -not $script:Gaming) {
            # CS2 just started
            $script:Gaming = $true
            $script:BoostedPIDs = @{}
            Write-Log "[*] CS2 DETECTED -> Entering game mode"
            Write-Host "[*] CS2 detected! Starving browsers, boosting CS2..."
            Invoke-StarveBrowsers
            Invoke-BoostGame
            foreach ($p in $cs2) { $script:BoostedPIDs[$p.Id] = $true }
        }
        elseif ($cs2 -and $script:Gaming) {
            # CS2 still running - check for new PIDs and re-apply to new browser instances
            foreach ($p in $cs2) {
                if (-not $script:BoostedPIDs.ContainsKey($p.Id)) {
                    Invoke-BoostGame
                    $script:BoostedPIDs[$p.Id] = $true
                }
            }
            # Re-starve any newly spawned browser processes
            $newBrowsers = Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -in $Browsers -and $_.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::BelowNormal }
            if ($newBrowsers) { Invoke-StarveBrowsers }
        }
        elseif (-not $cs2 -and $script:Gaming) {
            # CS2 just exited
            $script:Gaming = $false
            $script:BoostedPIDs = @{}
            Write-Log "[*] CS2 EXITED -> Restoring browsers"
            Write-Host "[*] CS2 exited. Restoring browser priorities..."
            Invoke-RestoreBrowsers
        }
        # else: no CS2 and not gaming — idle, nothing to do

        Start-Sleep -Seconds $PollSeconds
    }
} finally {
    # Ctrl+C or termination: clean up
    if ($script:Gaming) {
        Write-Log "[*] Script interrupted during game mode. Restoring browsers."
        Invoke-RestoreBrowsers
    }
    Write-Log "[*] Autom8ed_CS2_GameMode stopped."
    Write-Host "[*] GameMode stopped. Browsers restored."
}
