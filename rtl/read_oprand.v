`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/23 20:27:08
// Design Name: 
// Module Name: read_oprand
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// Exercise scaffold translated from superscalercore/vsrc/core/read_oprand.sv.
// Edit this Vivado source; core assignments remain at their original TODO positions.
// Keep all original parameter/port/signal/process/condition/loop ordering.
// The reference is combinational: clk/rst are unused and no reset logic is added.
// Multi-port lane i occupies bus[i*WIDTH +: WIDTH].
`include "config_pkg.vh"
`include "payload_defs.vh"

module read_oprand #(
    parameter FU0WB_WIDTH   = 2,
    parameter FU1WB_WIDTH   = 1
) (
    input wire            clk,
    input wire            rst,
    // ROB read interface.
    output reg [2*(`PRD_WIDTH)-1:0] rob_robaddr,
    input wire [2*(`DATA_WIDTH)-1:0] rob_rdata,
    input wire[1:0]                   rob_ready,
    // Execution writeback bypass inputs.
    input wire [FU0WB_WIDTH*(`PRD_WIDTH)-1:0] wb0_prd,
    input wire [FU0WB_WIDTH*(`PRD_WIDTH+1)-1:0] wb0_fifonum,
    input wire[FU0WB_WIDTH-1:0]                   wb0_valid,
    input wire[FU0WB_WIDTH-1:0]                   wb0_regw,
    input wire [FU0WB_WIDTH*(`DATA_WIDTH)-1:0] wb0_data,
    input wire [FU1WB_WIDTH*(`PRD_WIDTH)-1:0] wb1_prd,
    input wire [FU1WB_WIDTH*(`PRD_WIDTH+1)-1:0] wb1_fifonum,
    input wire[FU1WB_WIDTH-1:0]                   wb1_valid,
    input wire[FU1WB_WIDTH-1:0]                   wb1_regw,
    input wire [FU1WB_WIDTH*(`DATA_WIDTH)-1:0] wb1_data,
    // Issue queue inputs.
    input wire                        have_inst_i,
    input wire [`RS_PAYLOAD_RAM_WIDTH-1:0] is_payload_ram,
    input wire[`PRD_WIDTH-1:0]         is_prs1,
    input wire                        is_prs1_v,
    input wire[`PRD_WIDTH-1:0]         is_prs2,
    input wire                        is_prs2_v,
    input wire[`PRD_WIDTH-1:0]         is_prd,
    input wire                        is_prd_v,
    input wire[`PRD_WIDTH:0]           is_rob_fifonum,
    // Execution outputs.
    output reg                        have_inst,
    output reg [`RS_PAYLOAD_RAM_WIDTH-1:0] payload_ram,
    output reg[`DATA_WIDTH-1:0]        src1,
    output reg[`DATA_WIDTH-1:0]        src2,
    output reg[`PRD_WIDTH-1:0]         prd,
    output reg                        prd_v,
    output reg[`PRD_WIDTH:0]           rob_fifonum,
    // Issue queue response interface.
    input wire[`ISSUE_WIDTH-1:0]       is_iqid,
    output reg[`ISSUE_WIDTH-1:0]       resp_isid,
    output reg                        resp_valid,
    output reg                        resp_issued,
    // Control inputs.
    input wire                        ctrl_restore,
    input wire                        ctrl_stall,
    input wire[`PRD_WIDTH:0]           flush_num
);

reg [`RS_PAYLOAD_RAM_WIDTH-1:0] payload_ram_mem;
reg[`DATA_WIDTH-1:0]           src1_mem;
reg[`DATA_WIDTH-1:0]           src2_mem;
reg[`PRD_WIDTH-1:0]            prd_mem;
reg                           prd_v_mem;
reg[`PRD_WIDTH:0]              rob_fifonum_mem;

`include "fifoid_functions.vh"

always @* begin : proc_1
    payload_ram = payload_ram_mem;
    src1        = src1_mem;
    src2        = src2_mem;
    prd         = prd_mem;
    prd_v       = prd_v_mem;
    rob_fifonum = rob_fifonum_mem;
    resp_isid   = is_iqid;
end

always @* begin : proc_2
    payload_ram_mem = is_payload_ram;
    prd_mem         = is_prd;
    prd_v_mem       = is_prd_v;
    rob_fifonum_mem = is_rob_fifonum;
end

always @* begin : proc_3
    rob_robaddr[0*(`PRD_WIDTH) +: (`PRD_WIDTH)]  = is_prs1;
    rob_robaddr[1*(`PRD_WIDTH) +: (`PRD_WIDTH)]  = is_prs2;
end

reg           src1_rdy;
reg           src2_rdy;

always @* begin : proc_4
    integer i;
    if(is_prs1_v) begin
        src1_rdy = 1'b0;
        for(i=0; i<FU0WB_WIDTH; i=i+1) begin
            if(wb0_valid[i] && wb0_regw[i] && wb0_prd[i*(`PRD_WIDTH) +: (`PRD_WIDTH)]==is_prs1) begin
                src1_rdy = 1'b1;
            end
        end
        for(i=0; i<FU1WB_WIDTH; i=i+1) begin
            if(wb1_valid[i] && wb1_regw[i] && wb1_prd[i*(`PRD_WIDTH) +: (`PRD_WIDTH)]==is_prs1) begin
                src1_rdy = 1'b1;
            end
        end
        if(rob_ready[0]) begin
            src1_rdy = 1'b1;
        end
    end else begin
        src1_rdy = 1'b1;
    end
end

always @* begin : proc_5
    integer i;
    if(is_prs2_v) begin
        src2_rdy = 1'b0;
        for(i=0; i<FU0WB_WIDTH; i=i+1) begin
            if(wb0_valid[i] && wb0_regw[i] && wb0_prd[i*(`PRD_WIDTH) +: (`PRD_WIDTH)]==is_prs2) begin
               src2_rdy = 1'b1; 
            end
        end
        for(i=0; i<FU1WB_WIDTH; i=i+1) begin
            if(wb1_valid[i] && wb1_regw[i] && wb1_prd[i*(`PRD_WIDTH) +: (`PRD_WIDTH)]==is_prs2) begin
                src2_rdy = 1'b1;
            end
        end
        if(rob_ready[1]) begin
            src2_rdy = 1'b1;
        end
    end else begin
        src2_rdy = 1'b1;
    end
end

always @* begin : proc_6
    integer i;
    src1_mem = 0;
    if(rob_ready[0]) begin
        src1_mem = rob_rdata[0];
    end
    for(i=0; i<FU0WB_WIDTH; i=i+1) begin
        if(wb0_valid[i] && wb0_regw[i] && (wb0_prd[i*(`PRD_WIDTH) +: (`PRD_WIDTH)]==is_prs1) && !(ctrl_restore && fifoid_lt(flush_num, wb0_fifonum[i*(`PRD_WIDTH+1) +: (`PRD_WIDTH+1)]))) begin
             src1_mem = wb0_data[i];
        end
    end
    for(i=0; i<FU1WB_WIDTH; i=i+1) begin
        if(wb1_valid[i] && wb1_regw[i] && (wb1_prd[i*(`PRD_WIDTH) +: (`PRD_WIDTH)]==is_prs1) && !(ctrl_restore && fifoid_lt(flush_num, wb1_fifonum[i*(`PRD_WIDTH+1) +: (`PRD_WIDTH+1)]))) begin
             src1_mem = wb1_data[i];
        end
    end
end

always @* begin : proc_7
    integer i;
    src2_mem = 0;
    if(rob_ready[1]) begin
        src2_mem = rob_rdata[1];
    end
    for(i=0; i<FU0WB_WIDTH; i=i+1) begin
        if(wb0_valid[i] && wb0_regw[i] && (wb0_prd[i*(`PRD_WIDTH) +: (`PRD_WIDTH)]==is_prs2) && !(ctrl_restore && fifoid_lt(flush_num, wb0_fifonum[i*(`PRD_WIDTH+1) +: (`PRD_WIDTH+1)]))) begin
           src2_mem = wb0_data[i]; 
        end
    end
    for(i=0; i<FU1WB_WIDTH; i=i+1) begin
        if(wb1_valid[i] && wb1_regw[i] && (wb1_prd[i*(`PRD_WIDTH) +: (`PRD_WIDTH)]==is_prs2) && !(ctrl_restore && fifoid_lt(flush_num, wb1_fifonum[i*(`PRD_WIDTH+1) +: (`PRD_WIDTH+1)]))) begin
            src2_mem = wb1_data[i];
        end
    end
end

always @* begin : proc_8
     have_inst   =   have_inst_i & src1_rdy & src2_rdy;
    resp_valid  =   have_inst_i && !ctrl_stall;
    resp_issued =   have_inst_i & src1_rdy & src2_rdy;

end

endmodule
