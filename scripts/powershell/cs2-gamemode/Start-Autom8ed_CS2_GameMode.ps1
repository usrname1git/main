# Start-Autom8ed_CS2_GameMode.ps1
# Starts CS2 via Steam and launches Autom8ed_CS2_GameMode in auto-detect polling mode.
# Right-click > Run with PowerShell, or create a desktop shortcut (see bottom of file).
#
# Usage:
#   .\Start-Autom8ed_CS2_GameMode.ps1          # Launch CS2 + GameMode polling loop
#   .\Start-Autom8ed_CS2_GameMode.ps1 -NoCS2   # Only start GameMode (CS2 already running)

param(
    [switch]$NoCS2
)

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$GameMode   = Join-Path $ScriptDir 'Autom8ed_CS2_GameMode.ps1'
$LogDir     = 'C:\Tools\autom8ed\Logs'
$LogFile    = Join-Path $LogDir 'GameMode.log'
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

# --- Elevate if needed ---
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$identity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Re-launch self elevated, passing through parameters
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`""
    if ($NoCS2) { $argList += " -NoCS2" }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    exit 0
}

# --- Launch CS2 via Steam ---
if (-not $NoCS2) {
    $cs2Running = Get-Process -Name 'cs2' -ErrorAction SilentlyContinue
    if (-not $cs2Running) {
        Write-Host "[*] Launching CS2 via Steam..."
        "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] [*] Launching CS2 via Steam" | Out-File $LogFile -Append -Encoding UTF8
        Start-Process 'steam://rungameid/730'
    } else {
        Write-Host "[*] CS2 already running, skipping launch."
    }
}

# --- Start GameMode polling loop (stays resident in this window) ---
Write-Host "[*] Starting Autom8ed_CS2_GameMode in auto-detect mode..."
Write-Host "[*] This window will stay open. Close it or Ctrl+C to stop GameMode."
Write-Host ""
& $GameMode

# ─────────────────────────────────────────────────────────
# DESKTOP SHORTCUT SETUP (one-time, run from the script's directory in admin PowerShell):
#
#   $ScriptDir = $PSScriptRoot   # or set manually if running interactively
#   $ws = New-Object -ComObject WScript.Shell
#   $sc = $ws.CreateShortcut("$env:USERPROFILE\Desktop\CS2 GameMode.lnk")
#   $sc.TargetPath       = "powershell.exe"
#   $sc.Arguments         = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Start-Autom8ed_CS2_GameMode.ps1`""
#   $sc.WorkingDirectory  = $ScriptDir
#   $sc.Description       = "Launch CS2 + Autom8ed GameMode"
#   $sc.Save()
#   Write-Host "[+] Shortcut created on Desktop"
#
# The shortcut auto-elevates via the script's built-in UAC prompt.
# ─────────────────────────────────────────────────────────
