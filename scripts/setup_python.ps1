# setup_python.ps1 - create a project-local Python environment (.venv) with
# pyserial for the dashboard. Does not modify any system or bundled Python.
#
#   powershell -ExecutionPolicy Bypass -File scripts\setup_python.ps1 [-Python C:\path\to\python.exe]
param([string]$Python = "")
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Python) {
    $cands = @("$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe")
    $cands += (Get-Command py, python -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' }).Source
    $Python = $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Python) { throw "No usable Python found. Pass -Python C:\path\to\python.exe" }
Write-Host "Base interpreter: $Python"
& $Python -c "import sys, tkinter; print('Python', sys.version.split()[0], '/ Tk', tkinter.TkVersion)"
$venv = Join-Path $root '.venv'
if (-not (Test-Path $venv)) { & $Python -m venv $venv }
$vpy = Join-Path $venv 'Scripts\python.exe'
& $vpy -m pip install --upgrade pip | Out-Null
& $vpy -m pip install -r (Join-Path $root 'requirements.txt')
& $vpy -c "import serial, tkinter; print('pyserial', serial.__version__, 'OK; tkinter OK')"
& $vpy (Join-Path $root 'dashboard\fly_dashboard.py') --selftest 100
Write-Host "`nActivate with:  .venv\Scripts\Activate.ps1"
