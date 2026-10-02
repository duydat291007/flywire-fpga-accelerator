# run_vivado.ps1 - Vivado builds, comparisons and board programming from Windows.
#
#   powershell -ExecutionPolicy Bypass -File scripts\vivado\run_vivado.ps1 <command> [args]
#
#   find                       locate vivado.bat and print its version
#   build <config> [top|mvu]   one build (see build.tcl for configs)
#   compare                    all MVU out-of-context builds + top builds used in docs
#   program [bitfile]          program the Basys 3 (default: 4x4 banked WBUF=2 top build)
#
# Vivado is located from $env:VIVADO_BIN, PATH, or C:\Xilinx / C:\AMDDesign / D:\...
# If Vivado lives inside WSL, use scripts/vivado/run_vivado.sh from WSL instead.
param([Parameter(Position = 0)][string]$Command = "find",
      [Parameter(Position = 1)][string]$Arg1 = "",
      [Parameter(Position = 2)][string]$Arg2 = "")
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $root

function Find-Vivado {
    if ($env:VIVADO_BIN -and (Test-Path $env:VIVADO_BIN)) { return $env:VIVADO_BIN }
    $c = Get-Command vivado.bat, vivado -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null }).Root) {
        foreach ($pat in 'Xilinx\Vivado\*\bin\vivado.bat', 'Xilinx\*\Vivado\bin\vivado.bat',
                         'AMDDesign\*\Vivado\bin\vivado.bat', 'AMD\*\Vivado\bin\vivado.bat') {
            $hit = Get-ChildItem (Join-Path $d $pat) -ErrorAction SilentlyContinue |
                   Sort-Object FullName -Descending | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    throw "vivado.bat not found. Set `$env:VIVADO_BIN to its full path, or run from WSL."
}

$viv = Find-Vivado
$common = @('-mode', 'batch', '-nojournal', '-nolog', '-notrace')

switch ($Command) {
    'find' {
        Write-Host "Vivado: $viv"
        & $viv -version | Select-Object -First 2
    }
    'build' {
        if (-not $Arg1) { throw "usage: build <config> [top|mvu]" }
        $tgt = if ($Arg2) { $Arg2 } else { 'top' }
        & $viv @common -source scripts/vivado/build.tcl -tclargs $Arg1 $tgt
        if ($LASTEXITCODE -ne 0) { throw "build failed" }
        python scripts/collect_impl.py
    }
    'compare' {
        foreach ($cfg in 'serial', 'sys2x2_simple', 'sys2x2_banked', 'sys4x4_simple',
                         'sys4x4_banked', 'sys4x4_banked_wbuf2', 'sys4x4_banked_wbuf3', 'sys8x8_banked_wbuf2') {
            & $viv @common -source scripts/vivado/build.tcl -tclargs $cfg mvu
        }
        foreach ($cfg in 'serial', 'sys4x4_banked_wbuf2') {
            & $viv @common -source scripts/vivado/build.tcl -tclargs $cfg top
        }
        python scripts/collect_impl.py
    }
    'program' {
        $bit = if ($Arg1) { $Arg1 } else { 'build\vivado\top_sys4x4_banked_wbuf2\basys3_top.bit' }
        & $viv @common -source scripts/vivado/program.tcl -tclargs $bit
    }
    default { throw "unknown command $Command" }
}
