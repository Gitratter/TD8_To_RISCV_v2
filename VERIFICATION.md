# Verification

The repository includes eleven self-checking testbenches, a Yosys synthesis check, and a Vivado report script. This page describes how to run them and what each check covers.

## Functional simulation

Install PowerShell and Icarus Verilog with `iverilog` and `vvp` on `PATH`. Run from the repository root:

```powershell
pwsh -File scripts/run_tests.ps1
```

The runner compiles with `-g2012 -Wall` and stops when compilation or simulation returns a nonzero exit code. Generated files are placed in `.sim_build`.

For a portable Icarus installation, executable and backend paths can be supplied explicitly:

```powershell
./scripts/run_tests.ps1 `
  -Iverilog 'C:/tools/iverilog/bin/iverilog.exe' `
  -Vvp 'C:/tools/iverilog/bin/vvp.exe' `
  -IverilogBase 'C:/tools/iverilog/lib/ivl'
```

| Testbench | Coverage |
|---|---|
| `tb_v2_decoder` | Forty instruction names and rejection of unsupported/reserved encodings |
| `tb_v2_immediates` | I, S, B, U, and J immediate boundaries and sign extension |
| `tb_v2_integer` | Register/immediate ALU operations, LUI, AUIPC, FENCE, and `x0` |
| `tb_v2_boundaries` | Arithmetic wraparound, immediate limits, FENCE fields, and `JALR rd=rs1` |
| `tb_v2_control_flow` | Six branch conditions, forward/backward transfers, JAL/JALR, and link values |
| `tb_v2_memory` | All load/store sizes, lane selection, endianness, and extension |
| `tb_v2_memory_boundaries` | Negative offsets and the final valid byte, halfword, and word |
| `tb_v2_mmio` | Input reads, output writes, and output readback |
| `tb_v2_faults` | Illegal instructions, SYSTEM traps, fetch/target/data faults, and side-effect suppression |
| `tb_v2_lutram_reset` | RAM retention, register validity reset, and suppression of writes during reset |
| `tb_v2_board` | Default ROM, output `0xbe` for input `0x05`, seven-segment `E`, and instruction count |

To elaborate the board hierarchy without running a test:

```powershell
$rtl = (Get-ChildItem ./sources_1/new -Filter *.v | Sort-Object Name).FullName
iverilog -g2012 -Wall -s TD4_TOP -tnull $rtl
if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
```

## Yosys memory inference

The synthesis script targets Xilinx 7-series primitives and contains a structural regression signature for Yosys 0.68:

```powershell
pwsh -File scripts/run_yosys_check.ps1
```

It runs `synth_xilinx -family xc7`, `check -assert`, and assertions for 32 `RAM64X1S` instances, 12 `RAM32M` instances, and no `RAMB18E1` or `RAMB36E1` instances. These are script expectations, not Vivado utilization results. A different synthesis version may use a different valid mapping.

## Vivado implementation

Use a project containing the v2 sources, `TD4_TOP`, part `xc7a35tcpg236-1`, and the supplied XDC. Complete synthesis and implementation, then run this command in the Vivado Tcl console from the repository root:

```tcl
source scripts/vivado_reports.tcl
```

The script checks the part, top, presence of the v2 core, and absence of V1-named sources. It opens `synth_1` and `impl_1` and writes hierarchical utilization, RAM utilization, timing, pulse-width, and power reports to `reports/v2`. It does not launch synthesis or implementation.

Inspect distributed-RAM inference for the data memory and register file, debug-port removal in the board top, and setup/hold timing under the 10 ns clock constraint. The one-hertz or ten-hertz enable is independent of that clock constraint.

## Evidence available in this checkout

Test sources and checking scripts are included. Simulation logs, routed Vivado reports, board measurements, architectural-compliance results, and formal proofs are not included. Running the checks produces evidence for the selected source revision and tool versions; their presence in the repository alone is not a passing result.
