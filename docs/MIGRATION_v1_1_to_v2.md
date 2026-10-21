# Moving from v1.1 to v2

v2 expands the twelve-instruction RV32I subset of [v1.1](https://github.com/Gitratter/TD8_To_RISCV_v1.1) to the forty base integer instructions. It retains the non-pipelined execution model, distributed-memory organization, and TD8 board interface.

## Compatibility

Both versions use a 32-bit datapath, separate instruction and data memories, and one instruction per clock-enable pulse. The FPGA top remains `TD4_TOP`, with ports `clk`, `reset`, `in`, `clksel`, `out`, `clk_ind`, `seg`, and `an`.

The input clock is 100 MHz. The board selects one or ten instruction-enable pulses per second. Reset is active high and asynchronous for control state and register validity; the RAM arrays have no runtime reset. `clk_ind` shows completed instructions modulo 16, and the rightmost seven-segment digit displays `out[3:0]`.

The RAM and MMIO addresses are unchanged. Existing aligned `LW` / `SW` accesses remain valid. The default ROM program changes from adding one to the switch input to an XOR, shift, and byte-memory demonstration.

## Instruction additions

| Group | Retained from v1.1 | Added in v2 |
|---|---|---|
| Upper immediate | — | LUI, AUIPC |
| Jump | — | JAL, JALR |
| Branch | BEQ | BNE, BLT, BGE, BLTU, BGEU |
| Load | LW | LB, LH, LBU, LHU |
| Store | SW | SB, SH |
| Immediate ALU | ADDI, SLTI, ANDI, ORI | SLTIU, XORI, SLLI, SRLI, SRAI |
| Register ALU | ADD, SUB, SLT, AND, OR | SLL, SLTU, XOR, SRL, SRA |
| Ordering and environment | — | FENCE, ECALL, EBREAK |

## Datapath changes

`DecoderV2` replaces `MainDecoderV1` and `ALUDecoderV1`. It reads the complete instruction word and selects ALU operands, writeback data, memory access size, and control-transfer behavior. Unsupported encodings disable register and memory writes.

`ALUV2` adds shifts, XOR, and unsigned comparison. `ImmGenV2` supports I, S, B, U, and J immediates. The PC path accepts branch and jump targets; `JAL` and `JALR` write `PC+4` to the destination register.

For subword loads, the selected RAM word is shifted by the byte offset, then sign-extended or zero-extended. Stores shift the source data into position and select the affected byte lanes with a four-bit write strobe. Halfwords require two-byte alignment and words require four-byte alignment.

## Memory implementation

Data RAM remains one `64 x 32-bit` array with asynchronous reads. Byte write enables support `SB` and `SH` without changing the array's declared organization. The largest valid starting addresses are `0xff` for a byte, `0xfe` for a halfword, and `0xfc` for a word.

The register file keeps two copies for the source read ports. A common write updates both copies, and a validity mask supplies logical zeros after reset. Debug ports are disabled in the board configuration. Data RAM retains its contents across CPU reset.

The board's instruction ROM contains 64 words. `IMEM_WORDS` and `IMEM_INIT_FILE` allow other capacities and `$readmemh` initialization. Unused locations contain `ADDI x0,x0,0`.

Distributed-RAM attributes express the intended mapping. Byte enables and additional datapath logic can change synthesis results, so resource and timing comparisons require separate builds of each version with the same device and constraints.

## Control transfers and faults

v2 exposes `debug_trap_cause` and `debug_trap_value` in addition to `fault`. A fault blocks instruction updates; there is no trap vector or return instruction.

One behavior differs from the earlier subset core: an aligned branch target outside instruction memory is accepted, then produces an instruction access fault on the next fetch. Misaligned taken targets still fault at the transfer instruction and suppress its side effects, including the link-register write. Untaken branches do not check their targets.

| Cause | Condition | Trap value |
|---:|---|---|
| 0 | Misaligned fetch or taken target | PC or target address |
| 1 | Fetch outside instruction ROM | PC |
| 2 | Illegal instruction | Instruction word |
| 3 | EBREAK | PC |
| 4 / 5 | Misaligned load / invalid load address | Effective address |
| 6 / 7 | Misaligned store / invalid store address | Effective address |
| 11 | ECALL | Zero |

MMIO remains word-only: `0x100` accepts `LW`, and `0x104` accepts `LW` / `SW`. Subword MMIO, stores to the input register, and accesses to unassigned addresses fault.

## Updating a Vivado project

Replace the old design sources with the files in [sources_1/new](../sources_1/new) and use [TD8_RAM_TO_RISCV_V2.xdc](../constrs_1/new/TD8_RAM_TO_RISCV_V2.xdc). Keep `TD4_TOP` as the top module. Re-run synthesis and implementation before collecting reports.

The principal module replacements are:

| v1.1 | v2 |
|---|---|
| `TD8_RISCV_V1_Core` | `TD8_RISCV_V2_Core` |
| `TD8_RAM_TO_RISCV_V1_TOP` | `TD8_RAM_TO_RISCV_V2_TOP` |
| `MainDecoderV1` + `ALUDecoderV1` | `DecoderV2` |
| `ALUV1`, `ImmGenV1` | `ALUV2`, `ImmGenV2` |
| `InstructionMemoryV1`, `DataMemoryV1` | `InstructionMemoryV2`, `DataMemoryV2` |
| `RegisterFileV1`, `ProgramCounterV1` | `RegisterFileV2`, `ProgramCounterV2` |
| `ClockEnableV1`, `SEG7V1` | `ClockEnableV2`, `SEG7V2` |

See [verification procedures](../VERIFICATION.md) for simulation and implementation checks.
