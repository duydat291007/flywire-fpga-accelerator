# inspect_env.ps1 - read-only inventory of this Windows machine and every WSL
# distro. Installs nothing, changes nothing.
#
# Run from the project folder in PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\inspect_env.ps1
#
# Writes reports\env\windows.txt and reports\env\linux_<distro>.txt
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'reports\env'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = Join-Path $outDir 'windows.txt'
$env:WSL_UTF8 = '1'

function Section($t) { "`n== $t" }

& {
  Section 'timestamp'; Get-Date -Format o
  Section 'Windows'
  (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture | Format-List | Out-String).Trim()
  "PowerShell $($PSVersionTable.PSVersion)"
  "Project folder: $root"

  Section 'WSL'
  wsl.exe --version 2>&1
  wsl.exe --status 2>&1
  wsl.exe --list --verbose 2>&1

  Section 'Vivado on Windows'
  $cmd = Get-Command vivado, vivado.bat -ErrorAction SilentlyContinue
  if ($cmd) { $cmd | ForEach-Object { "on PATH: $($_.Source)" } } else { 'vivado not on PATH' }
  $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null } | ForEach-Object { $_.Root }
  $bases = foreach ($d in $drives) { foreach ($n in 'Xilinx','AMDDesign','AMD','Program Files\Xilinx','Program Files\AMD') { Join-Path $d $n } }
  $found = $false
  foreach ($b in $bases) {
    if (Test-Path $b) {
      Get-ChildItem -Path $b -Filter vivado.bat -Recurse -Depth 5 -ErrorAction SilentlyContinue |
        ForEach-Object { $found = $true; "found: $($_.FullName)"
          $v = & $_.FullName -version 2>&1 | Select-Object -First 2; $v }
    }
  }
  if (-not $found) { "no vivado.bat under $($bases -join ', ')" }
  Section 'Installed programs mentioning Vivado/Xilinx/AMD Design'
  $keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  $apps = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'Vivado|Xilinx|AMD Design|Vitis|Digilent|FTDI' } |
    Select-Object DisplayName, DisplayVersion, InstallLocation
  if ($apps) { ($apps | Format-Table -AutoSize | Out-String).Trim() } else { '(none)' }

  Section 'USB serial / board'
  Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '\(COM\d+\)|FTDI|Digilent|USB Serial' } |
    ForEach-Object { "$($_.Name)   [$($_.Status)]" }
  if (Get-Command usbipd -ErrorAction SilentlyContinue) { Section 'usbipd list'; usbipd list 2>&1 }

  Section 'Python / git'
  $codexPy = "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
  # Skip the WindowsApps 'python' alias: running it can open the Microsoft Store.
  $cands = @($codexPy) + @((Get-Command python, py -ErrorAction SilentlyContinue).Source | Where-Object { $_ -notmatch 'WindowsApps' })
  foreach ($p in $cands) {
    if ($p -and (Test-Path $p)) {
      "$p"
      & $p -c "import sys, importlib.util; print(' ', sys.version.split()[0]); [print(' ', m, 'yes' if importlib.util.find_spec(m) else 'no') for m in ('venv','tkinter','numpy','serial','pytest')]" 2>&1
    }
  }
  (Get-Command git -ErrorAction SilentlyContinue).Source
} *>&1 | Out-File -FilePath $out -Encoding utf8
Write-Host "Windows report: $out"

# Linux side: run the read-only inventory inside every WSL distro
$raw = wsl.exe --list --quiet 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host 'No WSL distributions reported.'; $raw = @() }
$distros = $raw | ForEach-Object { ($_ -replace "`0", '').Trim() } |
  Where-Object { $_ -and $_ -notmatch '^docker-desktop' }
foreach ($d in $distros) {
  Write-Host "Inspecting WSL distro '$d' (may take a minute if Vivado is found)..."
  wsl.exe -d $d --cd "$root" -- bash ./scripts/inspect_env.sh
}
Write-Host "Done. Reports are in $outDir"
