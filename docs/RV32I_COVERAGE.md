# RV32I instruction behavior

This document describes the instruction behavior implemented by [DecoderV2](../sources_1/new/DecoderV2.v) and [TD8_RISCV_V2_Core](../sources_1/new/TD8_RISCV_V2_Core.v). The implementation has `XLEN=32`, registers `x0`–`x31`, and four-byte instruction alignment.

## Implemented operations

| Instructions | Behavior |
|---|---|
| LUI | Write the U-immediate to `rd` |
| AUIPC | Write the current instruction PC plus the U-immediate |
| JAL | Write `PC+4` to `rd` and jump to `PC+immediate` |
| JALR | Write `PC+4` to `rd` and jump to `(rs1+immediate) & ~1` |
| BEQ, BNE | Branch on equality or inequality |
| BLT, BGE | Branch on a signed comparison |
| BLTU, BGEU | Branch on an unsigned comparison |
| LB, LH | Load a byte or halfword and sign-extend it |
| LBU, LHU | Load a byte or halfword and zero-extend it |
| LW | Load a 32-bit word |
| SB, SH, SW | Write the selected one, two, or four byte lanes |
| ADDI | Add a sign-extended immediate |
| SLTI, SLTIU | Write 0 or 1 from a signed or unsigned comparison with the sign-extended immediate |
| XORI, ORI, ANDI | Apply a bitwise operation with a sign-extended immediate |
| SLLI, SRLI, SRAI | Shift by the encoded five-bit amount |
| ADD, SUB | Add or subtract register operands |
| SLL, SRL, SRA | Shift by `rs2[4:0]` |
| SLT, SLTU | Write 0 or 1 from a signed or unsigned register comparison |
| XOR, OR, AND | Apply a bitwise register operation |
| FENCE | Retire without a datapath side effect |
| ECALL | Assert a fatal trap with cause 11 |
| EBREAK | Assert a fatal trap with cause 3 |

The table covers forty instruction names. Arithmetic wraps modulo `2^32`. Logical right shifts insert zeros; arithmetic right shifts copy the sign bit. Writes to `x0` are discarded, but a load with `rd=x0` still performs address and fault checks.

## Decoding

The decoder checks opcode, `funct3`, and the required `funct7` fields. Register operations reject unsupported function combinations, and immediate shifts accept only the defined upper-bit patterns. `JALR` requires `funct3=000`. `ECALL` and `EBREAK` must match `0x00000073` and `0x00100073` exactly.

For MISC-MEM, `funct3=000` selects `FENCE`; the remaining fields do not affect execution. The ordered, single-hart memory system has no cache or store buffer, so this operation requires no additional state. `FENCE.I`, CSR instructions, multiplication/division, atomics, floating point, and compressed instructions are unsupported.

## Control flow

Branches compare the source registers directly. Branch offsets and `JAL` offsets are relative to the current instruction PC. `JALR` clears target bit 0 after addition; target bit 1 must still be zero because this core uses four-byte instruction alignment.

Misaligned taken targets fault before the transfer commits. Untaken branches ignore target alignment. Transfers to aligned addresses outside ROM complete, and the following fetch raises an instruction access fault. Jump destinations of `x0` discard the link value while retaining the control transfer.

## Memory accesses

Data RAM is little-endian. Byte accesses can start at any address in `0x00`–`0xff`; halfwords require an even address up to `0xfe`; words require an address divisible by four up to `0xfc`. `SB` and `SH` preserve the unselected lanes.

MMIO uses exact word addresses: input at `0x100`, output/readback at `0x104`. Narrow loads and stores are invalid for these registers. The input register is read-only.

## Execution environment

The core reports synchronous faults through `fault`, `debug_trap_cause`, and `debug_trap_value`. Faulting instructions do not retire. The PC remains on the faulting instruction or invalid fetch address, with architectural writes disabled.

There are no privilege modes, CSRs, interrupts, exception vectors, or trap-return instructions. `ECALL` and `EBREAK` are recognized instructions that stop execution. Cause numbers are project-visible diagnostics, not an implemented `mcause` register.

## Tests

[VERIFICATION.md](../VERIFICATION.md) maps the supplied tests to instruction groups and boundary conditions. The suite includes decoder cases, signed and unsigned comparisons, shifts, immediate boundaries, memory lanes, branch outcomes, jump links, and fault side effects. These are project tests; no architectural-compliance or formal-verification suite is included.
