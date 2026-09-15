<#
.SYNOPSIS
  FPGA flow for conv_system on Windows - wraps fpga/scripts/run_all.tcl.

.DESCRIPTION
  Steps (run in this order, whichever are selected):
    board_sim  self-checking xsim test of the board AXI wrapper
    synth      fpga/synth/<tag>/      checkpoint, utilization, timing
    impl       fpga/impl/<tag>/       routed checkpoint, utilization, timing, DRC, vectorless power
    power      fpga/reports/<tag>/    benchmark SAIF power, FoM, summary.md, results.csv
    bitstream  fpga/bitstream/        PYNQ-Z2 overlay conv_demo.bit + conv_demo.hwh
  <tag> is "default" for the competition build (N 3, W 32, K 1, no ReLU, 4.000 ns).

.EXAMPLE
  .\fpga\run.ps1                                   # synth, impl, power, bitstream
.EXAMPLE
  .\fpga\run.ps1 -Steps synth,impl,power -N 5 -W 64
.EXAMPLE
  .\fpga\run.ps1 -Steps board_sim
#>
param(
   [ValidateSet('board_sim', 'synth', 'impl', 'power', 'bitstream')]
   [string[]]$Steps = @('synth', 'impl', 'power', 'bitstream'),
   [int]$N = 3,
   [int]$W = 32,
   [int]$K = 1,
   [int]$Relu = 0,
   [string]$Period = '4.000',
   [string]$Tag = '',
   [int]$Jobs = 4,
   [string]$Vivado = ''
)
$ErrorActionPreference = 'Stop'
$fpga = $PSScriptRoot

if (-not $Vivado) {
   if ($env:XILINX_VIVADO) {
      $Vivado = Join-Path $env:XILINX_VIVADO 'bin\vivado.bat'
   } elseif (Get-Command vivado.bat -ErrorAction SilentlyContinue) {
      $Vivado = (Get-Command vivado.bat).Source
   } else {
      foreach ($c in @('D:\Vivado\2018.2\bin\vivado.bat', 'C:\Xilinx\Vivado\2018.2\bin\vivado.bat')) {
         if (Test-Path $c) { $Vivado = $c; break }
      }
   }
}
if (-not $Vivado -or -not (Test-Path $Vivado)) {
   throw 'Vivado not found: pass -Vivado <path to vivado.bat> or set XILINX_VIVADO'
}

$tclArgs = @('N', $N, 'W', $W, 'K', $K, 'RELU', $Relu, 'PERIOD', $Period, 'JOBS', $Jobs, 'STEPS', ($Steps -join '+'))
if ($Tag) { $tclArgs += @('TAG', $Tag) }

$logs = Join-Path $fpga 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$log = '{0}_{1}.log' -f ($Steps -join '_'), (Get-Date -Format 'yyyyMMdd_HHmmss')

Push-Location $logs
try {
   & $Vivado -mode batch -notrace -nojournal -log $log -source (Join-Path $fpga 'scripts\run_all.tcl') -tclargs @tclArgs 2>&1 |
      ForEach-Object { if ("$_" -match '^(###|   \[BOARD|ERROR|CRITICAL WARNING)') { "$_" } }
   if ($LASTEXITCODE -ne 0) { throw "Vivado failed (exit $LASTEXITCODE), see fpga\logs\$log" }
} finally {
   Pop-Location
}
"log: fpga\logs\$log"
