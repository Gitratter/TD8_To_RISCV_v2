# TD8_To_RISCV_v2

A non-pipelined RV32I processor in Verilog for the Digilent Basys 3. This version extends [v1.1](https://github.com/Gitratter/TD8_To_RISCV_v1.1) with the remaining base integer operations, jumps, byte and halfword accesses, and trap diagnostics.

The core executes one instruction per `cpu_enable` pulse. It uses a 32-bit datapath, 32 general-purpose registers, separate instruction and data memories, and little-endian data storage.

## Instruction set

| Group | Instructions |
|---|---|
| Upper immediate | LUI, AUIPC |
| Jump | JAL, JALR |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Load | LB, LH, LW, LBU, LHU |
| Store | SB, SH, SW |
| Immediate ALU | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| Register ALU | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| Ordering and environment | FENCE, ECALL, EBREAK |

`FENCE` completes as a no-op in this single-hart system with ordered memory accesses and no cache or store buffer. `ECALL` and `EBREAK` halt execution with distinct trap causes. The core has no privileged CSRs, interrupts, trap handler, or optional ISA extensions. See [instruction behavior](docs/RV32I_COVERAGE.md) for encoding and execution details.

## Memory and reset

| Address space | Range | Function |
|---|---|---|
| Instruction | `0x00000000`–`0x000000ff` by default | 64-word ROM; capacity and initialization file are parameters |
| Data | `0x00000000`–`0x000000ff` | 256-byte RAM; byte, halfword, and word accesses |
| Data | `0x00000100` | Eight-bit switch input, aligned `LW` only |
| Data | `0x00000104` | Eight-bit LED output/readback, aligned `LW` / `SW` only |

Halfwords require two-byte alignment and words require four-byte alignment. Invalid accesses cause a trap. Data RAM retains its contents across CPU reset. Register-file reset clears validity bits, making `x1`–`x31` read as zero without resetting the RAM arrays; `x0` always reads as zero.

Data RAM is a single `64 x 32-bit` array with four byte write enables. Two register-file arrays provide the source read ports. Both memories use distributed-RAM attributes, with debug reads disabled in the board top.

## Trap behavior

`fault` suppresses updates to the PC, registers, RAM, output port, and instruction indicator. It is a combinational indication of the current faulting instruction or fetch; holding the PC normally keeps it asserted until reset. `debug_trap_cause` and `debug_trap_value` expose the reason and associated value. They are debug ports, not CSRs.

| Cause | Condition |
|---:|---|
| 0 / 1 | Instruction address misaligned / instruction access fault |
| 2 | Illegal instruction |
| 3 | EBREAK |
| 4 / 5 | Load address misaligned / load access fault |
| 6 / 7 | Store address misaligned / store access fault |
| 11 | ECALL |

A taken branch or jump to a misaligned target faults at the transfer instruction. An aligned target outside ROM is accepted by the transfer, then faults on the next fetch. A branch that is not taken does not check target alignment.

## FPGA setup and demo

Create a Vivado project for `xc7a35tcpg236-1`, add [sources_1/new](sources_1/new) as design sources and [TD8_RAM_TO_RISCV_V2.xdc](constrs_1/new/TD8_RAM_TO_RISCV_V2.xdc) as constraints, and set the top to `TD4_TOP`.

The board uses its 100 MHz clock with one or ten instruction-enable pulses per second, selected by `clksel`. The default ROM computes:

```text
value = ((switch_input XOR 0x5a) << 1) AND 0xff
RAM[1] = value
LED_output = zero_extend(RAM[1])
```

The loop exercises `XORI`, `SLLI`, `SB`, `LBU`, and `JAL`. Input `0x05` produces LED output `0xbe` and `E` on the rightmost seven-segment digit. An output update takes several instructions.

## Simulation and synthesis checks

From the repository root, with PowerShell and Icarus Verilog installed:

```powershell
pwsh -File scripts/run_tests.ps1
```

The runner executes 11 self-checking testbenches for decoding, arithmetic, control flow, memory, MMIO, traps, reset behavior, and the board demo. With Yosys available:

```powershell
pwsh -File scripts/run_yosys_check.ps1
```

See [verification procedures](VERIFICATION.md) for test coverage, tool options, and Vivado report generation. The report script runs after synthesis and implementation; it does not build the design. The 100 MHz input clock and slow instruction enable do not establish timing closure.

## Further reading

- [Changes from v1.1](docs/MIGRATION_v1_1_to_v2.md)
- [RV32I instruction behavior](docs/RV32I_COVERAGE.md)
- [RISC-V RV32I specification, version 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html)

## License

[MIT](LICENSE).
