# autom8ed: main

→ **[Releases](../../releases)** for binaries.

[![CI](https://github.com/usrname1git/main/actions/workflows/CI.yml/badge.svg)](https://github.com/usrname1git/main/actions/workflows/CI.yml)
[![Gitleaks](https://github.com/usrname1git/main/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/usrname1git/main/actions/workflows/gitleaks.yml)
[![Release](https://github.com/usrname1git/main/actions/workflows/release.yaml/badge.svg)](https://github.com/usrname1git/main/actions/workflows/release.yaml)

This is the central hub. If you only want binaries, go to **Releases**.  
If you want to build or tweak, start here:

- **/apps/Autom8ed** – Windows GUI and modules
- **/apps/TOTP-Agent** – local TOTP engine + browser hooks
- **/scripts/powershell** – admin/cleanup/ISO tooling
- **/iso-builder** – minimal Win11 ISO pipeline (DISM, packages, steps.json)
- **/docs** – user + dev docs (published via GitHub Pages)

## Quick start
Requires: Windows 11, PowerShell 7+, Git LFS.
- Windows: `.\scripts\powershell\Setup-Env.ps1 -Force`
- Build ISO: `.\iso-builder\Build-MinISO.ps1 -Preset Minimal`

## Security
Secret scanning enforced via CI. If you find a leak, rotate the key and open a PR to scrub history (we’ll help).
