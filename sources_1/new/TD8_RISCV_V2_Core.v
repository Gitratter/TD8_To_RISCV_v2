`timescale 1ns/1ps
`default_nettype none

// TD8-derived, non-pipelined RV32I v2 core.
//
// Implemented ISA: all 40 instructions in the unprivileged RV32I base.
// Execution environment: 256-byte RAM, word-only MMIO, fatal synchronous
// trap indication, no privileged CSRs/trap vector/interrupts.
module TD8_RISCV_V2_Core #(
    parameter integer IMEM_WORDS = 64,
    parameter integer INIT_DEMO = 1,
    parameter IMEM_INIT_FILE = "",
    parameter integer ENABLE_RF_DEBUG = 0,
    parameter integer ENABLE_MEM_DEBUG = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        cpu_enable,
    input  wire [7:0]  input_port,
    input  wire [4:0]  debug_reg_addr,
    output reg  [7:0]  output_port,
    output wire [31:0] debug_pc,
    output wire [31:0] debug_instruction,
    output wire [31:0] debug_reg_data,
    output wire [31:0] debug_mem_word0,
    output reg  [4:0]  debug_trap_cause,
    output reg  [31:0] debug_trap_value,
    output wire        fault
);
    localparam [31:0] IO_IN_ADDR  = 32'h0000_0100;
    localparam [31:0] IO_OUT_ADDR = 32'h0000_0104;
    localparam [31:0] IMEM_BYTES  = IMEM_WORDS * 4;

    // Project-visible trap cause values follow the standard synchronous
    // exception numbers. These are debug outputs, not an mcause CSR.
    localparam [4:0] CAUSE_INST_ADDR_MISALIGNED = 5'd0;
    localparam [4:0] CAUSE_INST_ACCESS_FAULT    = 5'd1;
    localparam [4:0] CAUSE_ILLEGAL_INSTRUCTION  = 5'd2;
    localparam [4:0] CAUSE_BREAKPOINT           = 5'd3;
    localparam [4:0] CAUSE_LOAD_ADDR_MISALIGNED = 5'd4;
    localparam [4:0] CAUSE_LOAD_ACCESS_FAULT    = 5'd5;
    localparam [4:0] CAUSE_STORE_ADDR_MISALIGNED= 5'd6;
    localparam [4:0] CAUSE_STORE_ACCESS_FAULT   = 5'd7;
    localparam [4:0] CAUSE_ECALL_FROM_M_MODE    = 5'd11;

    localparam [1:0] ALU_A_RS1  = 2'd0;
    localparam [1:0] ALU_A_PC   = 2'd1;
    localparam [1:0] ALU_A_ZERO = 2'd2;

    localparam [1:0] RESULT_ALU = 2'd0;
    localparam [1:0] RESULT_MEM = 2'd1;
    localparam [1:0] RESULT_PC4 = 2'd2;

    localparam [1:0] SIZE_BYTE = 2'd0;
    localparam [1:0] SIZE_HALF = 2'd1;
    localparam [1:0] SIZE_WORD = 2'd2;

    wire [31:0] pc;
    wire [31:0] instruction;
    wire [31:0] immediate;
    wire [31:0] read_data1;
    wire [31:0] read_data2;

    wire        instruction_legal;
    wire [3:0]  alu_control;
    wire [1:0]  alu_a_select;
    wire        alu_b_immediate;
    wire        reg_write;
    wire [1:0]  result_select;
    wire        mem_read;
    wire        mem_write;
    wire [1:0]  mem_size;
    wire        load_unsigned;
    wire        branch;
    wire [2:0]  branch_funct3;
    wire        jump;
    wire        jalr;
    wire        fence;
    wire        ecall;
    wire        ebreak;

    reg  [31:0] alu_operand_a;
    wire [31:0] alu_operand_b;
    wire [31:0] alu_result;
    wire [31:0] pc_plus_four;
    wire [31:0] pc_relative_target;
    wire [31:0] jalr_sum;
    wire [31:0] transfer_target;
    reg         branch_condition_true;
    wire        control_transfer_taken;
    wire [31:0] next_pc;

    wire        is_ram_address;
    wire        is_input_address;
    wire        is_output_address;
    wire        valid_load_address;
    wire        valid_store_address;
    wire        data_alignment_fault;
    wire        load_access_fault;
    wire        store_access_fault;

    wire [31:0] ram_read_word;
    wire [31:0] memory_read_word;
    wire [4:0]  byte_shift;
    wire [31:0] shifted_load_word;
    reg  [31:0] load_data;
    reg  [3:0]  store_strobe_raw;
    wire [31:0] store_write_data;
    wire [3:0]  ram_write_strobe;
    reg  [31:0] write_back_data;

    wire fetch_alignment_fault;
    wire fetch_access_fault;
    wire target_alignment_fault;
    wire commit_enable;

    DecoderV2 decoder (
        .instruction(instruction),
        .legal(instruction_legal),
        .alu_control(alu_control),
        .alu_a_select(alu_a_select),
        .alu_b_immediate(alu_b_immediate),
        .reg_write(reg_write),
        .result_select(result_select),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_size(mem_size),
        .load_unsigned(load_unsigned),
        .branch(branch),
        .branch_funct3(branch_funct3),
        .jump(jump),
        .jalr(jalr),
        .fence(fence),
        .ecall(ecall),
        .ebreak(ebreak)
    );

    ImmGenV2 immediate_generator (
        .instruction(instruction),
        .immediate(immediate)
    );

    always @(*) begin
        case (alu_a_select)
            ALU_A_PC:   alu_operand_a = pc;
            ALU_A_ZERO: alu_operand_a = 32'd0;
            default:    alu_operand_a = read_data1;
        endcase
    end

    assign alu_operand_b = alu_b_immediate ? immediate : read_data2;

    ALUV2 alu (
        .operand_a(alu_operand_a),
        .operand_b(alu_operand_b),
        .control(alu_control),
        .result(alu_result)
    );

    always @(*) begin
        case (branch_funct3)
            3'b000: branch_condition_true = (read_data1 == read_data2);                    // BEQ
            3'b001: branch_condition_true = (read_data1 != read_data2);                    // BNE
            3'b100: branch_condition_true = ($signed(read_data1) < $signed(read_data2));   // BLT
            3'b101: branch_condition_true = ($signed(read_data1) >= $signed(read_data2));  // BGE
            3'b110: branch_condition_true = (read_data1 < read_data2);                     // BLTU
            3'b111: branch_condition_true = (read_data1 >= read_data2);                    // BGEU
            default: branch_condition_true = 1'b0;
        endcase
    end

    assign pc_plus_four       = pc + 32'd4;
    assign pc_relative_target = pc + immediate;
    assign jalr_sum           = read_data1 + immediate;
    assign transfer_target    = jalr ? {jalr_sum[31:1], 1'b0} : pc_relative_target;
    assign control_transfer_taken = jump || (branch && branch_condition_true);
    assign next_pc = control_transfer_taken ? transfer_target : pc_plus_four;

    // RAM occupies byte addresses 0x000..0x0ff. To preserve v1.1 board I/O,
    // MMIO registers remain exact-address, aligned word accesses only.
    assign is_ram_address    = (alu_result < IO_IN_ADDR);
    assign is_input_address  = (alu_result == IO_IN_ADDR);
    assign is_output_address = (alu_result == IO_OUT_ADDR);

    assign valid_load_address = is_ram_address ||
                                ((is_input_address || is_output_address) &&
                                 (mem_size == SIZE_WORD));
    assign valid_store_address = is_ram_address ||
                                 (is_output_address && (mem_size == SIZE_WORD));

    assign data_alignment_fault = ((mem_size == SIZE_HALF) && alu_result[0]) ||
                                  ((mem_size == SIZE_WORD) && (alu_result[1:0] != 2'b00));
    assign load_access_fault  = mem_read  && !valid_load_address;
    assign store_access_fault = mem_write && !valid_store_address;

    assign memory_read_word = is_input_address  ? {24'd0, input_port} :
                              is_output_address ? {24'd0, output_port} :
                              is_ram_address    ? ram_read_word :
                                                  32'd0;
    assign byte_shift        = {alu_result[1:0], 3'b000};
    assign shifted_load_word = memory_read_word >> byte_shift;

    always @(*) begin
        case (mem_size)
            SIZE_BYTE: begin
                if (load_unsigned)
                    load_data = {24'd0, shifted_load_word[7:0]};
                else
                    load_data = {{24{shifted_load_word[7]}}, shifted_load_word[7:0]};
            end
            SIZE_HALF: begin
                if (load_unsigned)
                    load_data = {16'd0, shifted_load_word[15:0]};
                else
                    load_data = {{16{shifted_load_word[15]}}, shifted_load_word[15:0]};
            end
            default:
                load_data = shifted_load_word;
        endcase
    end

    always @(*) begin
        case (mem_size)
            SIZE_BYTE: store_strobe_raw = 4'b0001 << alu_result[1:0];
            SIZE_HALF: store_strobe_raw = 4'b0011 << alu_result[1:0];
            SIZE_WORD: store_strobe_raw = 4'b1111;
            default:   store_strobe_raw = 4'b0000;
        endcase
    end

    assign store_write_data = read_data2 << byte_shift;

    always @(*) begin
        case (result_select)
            RESULT_MEM: write_back_data = load_data;
            RESULT_PC4: write_back_data = pc_plus_four;
            default:    write_back_data = alu_result;
        endcase
    end

    assign fetch_alignment_fault = (pc[1:0] != 2'b00);
    assign fetch_access_fault    = (pc >= IMEM_BYTES);
    assign target_alignment_fault = control_transfer_taken &&
                                    (transfer_target[1:0] != 2'b00);

    // An out-of-range aligned branch/jump is allowed to retire. The following
    // fetch reports the instruction access fault, matching RV32I behavior.
    assign fault = fetch_alignment_fault || fetch_access_fault ||
                   !instruction_legal || ecall || ebreak ||
                   (mem_read  && data_alignment_fault) || load_access_fault ||
                   (mem_write && data_alignment_fault) || store_access_fault ||
                   target_alignment_fault;

    always @(*) begin
        debug_trap_cause = 5'd0;
        debug_trap_value = 32'd0;

        if (fetch_alignment_fault) begin
            debug_trap_cause = CAUSE_INST_ADDR_MISALIGNED;
            debug_trap_value = pc;
        end else if (fetch_access_fault) begin
            debug_trap_cause = CAUSE_INST_ACCESS_FAULT;
            debug_trap_value = pc;
        end else if (!instruction_legal) begin
            debug_trap_cause = CAUSE_ILLEGAL_INSTRUCTION;
            debug_trap_value = instruction;
        end else if (ebreak) begin
            debug_trap_cause = CAUSE_BREAKPOINT;
            debug_trap_value = pc;
        end else if (mem_read && data_alignment_fault) begin
            debug_trap_cause = CAUSE_LOAD_ADDR_MISALIGNED;
            debug_trap_value = alu_result;
        end else if (load_access_fault) begin
            debug_trap_cause = CAUSE_LOAD_ACCESS_FAULT;
            debug_trap_value = alu_result;
        end else if (mem_write && data_alignment_fault) begin
            debug_trap_cause = CAUSE_STORE_ADDR_MISALIGNED;
            debug_trap_value = alu_result;
        end else if (store_access_fault) begin
            debug_trap_cause = CAUSE_STORE_ACCESS_FAULT;
            debug_trap_value = alu_result;
        end else if (ecall) begin
            debug_trap_cause = CAUSE_ECALL_FROM_M_MODE;
            debug_trap_value = 32'd0;
        end else if (target_alignment_fault) begin
            debug_trap_cause = CAUSE_INST_ADDR_MISALIGNED;
            debug_trap_value = transfer_target;
        end
    end

    // No architectural state changes while reset or a fatal trap is asserted.
    assign commit_enable = cpu_enable && !reset && !fault;

    ProgramCounterV2 program_counter (
        .clk(clk),
        .reset(reset),
        .enable(commit_enable),
        .next_pc(next_pc),
        .pc(pc)
    );

    InstructionMemoryV2 #(
        .WORDS(IMEM_WORDS),
        .INIT_DEMO(INIT_DEMO),
        .INIT_FILE(IMEM_INIT_FILE)
    ) instruction_memory (
        .address(pc),
        .instruction(instruction)
    );

    RegisterFileV2 #(.ENABLE_DEBUG(ENABLE_RF_DEBUG)) register_file (
        .clk(clk),
        .reset(reset),
        .enable(commit_enable),
        .write_enable(reg_write),
        .read_addr1(instruction[19:15]),
        .read_addr2(instruction[24:20]),
        .write_addr(instruction[11:7]),
        .write_data(write_back_data),
        .debug_addr(debug_reg_addr),
        .read_data1(read_data1),
        .read_data2(read_data2),
        .debug_data(debug_reg_data)
    );

    assign ram_write_strobe = (commit_enable && mem_write && is_ram_address)
                            ? store_strobe_raw : 4'b0000;

    DataMemoryV2 #(.ENABLE_DEBUG(ENABLE_MEM_DEBUG)) data_memory (
        .clk(clk),
        .enable(commit_enable),
        .write_strobe(ram_write_strobe),
        .address(alu_result),
        .write_data(store_write_data),
        .read_data(ram_read_word),
        .debug_word0(debug_mem_word0)
    );

    always @(posedge clk or posedge reset) begin
        if (reset)
            output_port <= 8'd0;
        else if (commit_enable && mem_write && is_output_address)
            output_port <= read_data2[7:0];
    end

    assign debug_pc          = pc;
    assign debug_instruction = instruction;

    // FENCE is intentionally a no-op in this single-hart, strictly ordered,
    // non-pipelined implementation. Referencing it documents that choice.
    wire unused_fence = fence;
endmodule

`default_nettype wire
