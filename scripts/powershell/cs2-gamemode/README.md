# Autom8ed CS2 GameMode

> Automatically starve background browsers and boost CS2 when you play — restore everything when you quit. A lightweight, Process Lasso-style optimizer built entirely in PowerShell.

## What it does

| CS2 launches | CS2 exits |
|---|---|
| Browsers (Edge, Chrome, Brave, Opera, Firefox) → **BelowNormal** priority + **EcoQoS** throttled | Browsers → **Normal** priority, EcoQoS disabled |
| CS2 → **High** priority, pinned to P-cores 1-7 (avoids core 0 DPC/interrupt traffic) | CS2 affinity reset to all cores |

The polling loop re-applies settings to **newly spawned** browser processes too, so tabs opened mid-game are throttled immediately.

## Requirements

- **Windows 10 / 11** (EcoQoS requires Windows 11 22H2+ for full effect)
- **PowerShell 5.1** or **PowerShell 7+**
- **Administrator** privileges (needed for process priority/affinity/EcoQoS APIs)

## Files

| File | Purpose |
|---|---|
| `Start-Autom8ed_CS2_GameMode.ps1` | **Entrypoint** — launches CS2 via Steam, auto-elevates to admin, then starts the GameMode polling loop. This is what you run (or point a shortcut at). |
| `Autom8ed_CS2_GameMode.ps1` | **Core engine** — polling loop, browser starving, CS2 boosting, EcoQoS P/Invoke, hybrid CPU detection. Called by the starter; can also be run standalone. |

## Quick start

### Option 1: One-click (recommended)

```powershell
.\Start-Autom8ed_CS2_GameMode.ps1
```

Launches CS2 via Steam (if not already running) and starts the GameMode polling loop in the same window. The script auto-elevates via UAC — no need to open an admin shell first.

### Option 2: GameMode only (CS2 already running)

```powershell
.\Start-Autom8ed_CS2_GameMode.ps1 -NoCS2
```

### Option 3: Run the core engine directly

```powershell
# Auto-detect loop (must be admin)
.\Autom8ed_CS2_GameMode.ps1

# One-shot: apply game mode right now
.\Autom8ed_CS2_GameMode.ps1 -GameOn

# One-shot: restore browsers right now
.\Autom8ed_CS2_GameMode.ps1 -GameOff

# Custom poll interval
.\Autom8ed_CS2_GameMode.ps1 -PollSeconds 5
```

## Desktop shortcut (one-time setup)

Run this once **from the script's directory** in an admin PowerShell to create a "CS2 GameMode" shortcut on your Desktop:

```powershell
$ScriptDir = $PSScriptRoot   # or set to the folder where you placed the scripts
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut("$env:USERPROFILE\Desktop\CS2 GameMode.lnk")
$sc.TargetPath       = "powershell.exe"
$sc.Arguments         = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\Start-Autom8ed_CS2_GameMode.ps1`""
$sc.WorkingDirectory  = $ScriptDir
$sc.Description       = "Launch CS2 + Autom8ed GameMode"
$sc.Save()
```

The shortcut auto-elevates via the script's built-in UAC prompt.

## How it works

```
Start-Autom8ed_CS2_GameMode.ps1
  ├─ Elevate to admin (UAC)
  ├─ Start CS2 via steam://rungameid/730
  └─ & Autom8ed_CS2_GameMode.ps1   ← polling loop
        ├─ Detect P-core / E-core topology
        └─ Loop every 3s:
             CS2 detected?
             ├─ YES → Starve browsers (BelowNormal + EcoQoS)
             │        Boost CS2 (High + P-core affinity)
             └─ NO  → Restore browsers (Normal + EcoQoS off)
```

## Logs

All events are logged to:

```
C:\Tools\autom8ed\Logs\GameMode.log
```

The directory is created automatically on first run.

## CPU affinity notes

The script pins CS2 to **cores 1-7** by default, deliberately avoiding core 0 which typically handles DPCs and hardware interrupts on Windows. This is tuned for a system with 8 P-cores (HT disabled / E-cores disabled). If your topology differs, edit the `$script:GameCoreIndices` array in `Autom8ed_CS2_GameMode.ps1`.

## Stopping

- **Close the window** running the script, or press **Ctrl+C**.
- The `finally` block automatically restores browser priorities on exit.

## License

[MIT](../../../LICENSE)

---

*Part of [autom8edIT/main](https://github.com/autom8edIT/main) — I got tired of doing things manually, so I autom8ed.it.*
