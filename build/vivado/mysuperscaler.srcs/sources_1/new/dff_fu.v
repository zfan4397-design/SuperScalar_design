`timescale 1ns / 1ps
// Complete Verilog translation of superscalercore/vsrc/core/dff_fu.sv.
// Preserve the reference reset, stall and age-kill behavior.
// reg_we intentionally uses its own reset/stall update, independent of clear and restore.
`include "config_pkg.vh"


module dff_fu (
    input wire                        clk,
    input wire                        rst,

    input wire                        ctrl_clear,
    input wire                        ctrl_stall,
    input wire                        ctrl_restore,
    input wire[`PRD_WIDTH:0]           flnum,

    input wire                        i_have_inst,
    input wire[`PRD_WIDTH:0]           i_rob_fifonum,
    input wire[`DATA_WIDTH-1:0]        i_ldata,
    input wire[3:0]                   i_lmask,
    input wire[`REG_INFO_WIDTH-1:0]    i_reg_info,
    input wire[3:0]                   i_reg_wstrb,
    input wire                        i_regw,
    input wire[`STBF_WIDTH:0]          i_stbf_id,
    input wire                        i_we,
    input wire[`PRD_WIDTH-1:0]         i_prd,
    input wire[1:0]                   i_mem_offset,
    input wire[`DATA_WIDTH-1:0]        i_mem_addr,
    input wire[`EXCPT_WIDTH-1:0]       i_exception,

    output reg                        o_have_inst,
    output reg[`PRD_WIDTH:0]           o_rob_fifonum,
    output reg[`DATA_WIDTH-1:0]        o_ldata,
    output reg[3:0]                   o_lmask,
    output reg[`REG_INFO_WIDTH-1:0]    o_reg_info,
    output reg[3:0]                   o_reg_wstrb,
    output reg                        o_regw,
    output reg[`STBF_WIDTH:0]          o_stbf_id,
    output reg                        o_we,
    output reg[`PRD_WIDTH-1:0]         o_prd,
    output reg[1:0]                   o_mem_offset,
    output reg[`DATA_WIDTH-1:0]        o_mem_addr,
    output reg[`EXCPT_WIDTH-1:0]       o_exception
);

`include "fifoid_functions.vh"

reg                        reg_have_inst;
reg[`PRD_WIDTH:0]           reg_rob_fifonum;
reg[`DATA_WIDTH-1:0]        reg_ldata;
reg[3:0]                   reg_lmask;
reg[`REG_INFO_WIDTH-1:0]    reg_reg_info;
reg[3:0]                   reg_reg_wstrb;
reg                        reg_regw;
reg[`STBF_WIDTH:0]          reg_stbf_id;
reg                        reg_we;
reg[`PRD_WIDTH-1:0]         reg_prd;
reg[1:0]                   reg_mem_offset;
reg[`DATA_WIDTH-1:0]        reg_mem_addr;
reg[`EXCPT_WIDTH-1:0]       reg_exception;

reg                   kill_in;
reg                   kill_out;

always @ ( posedge clk or posedge rst ) begin : proc_1
    if(rst) begin
        reg_have_inst   <= 0;
        reg_rob_fifonum <= 0;
        reg_ldata       <= 0;
        reg_lmask       <= 0;
        reg_reg_info    <= 0;
        reg_reg_wstrb   <= 0;
        reg_regw        <= 0;
        reg_stbf_id     <= 0;
        reg_prd         <= 0;
        reg_mem_offset  <= 0;
        reg_mem_addr    <= 0;
        reg_exception   <= 0;
    end else if(ctrl_clear) begin
        reg_have_inst   <= 0;
        reg_rob_fifonum <= 0;
        reg_ldata       <= 0;
        reg_lmask       <= 0;
        reg_reg_info    <= 0;
        reg_reg_wstrb   <= 0;
        reg_regw        <= 0;
        reg_stbf_id     <= 0;
        reg_prd         <= 0;
        reg_mem_offset  <= 0;
        reg_mem_addr    <= 0;
        reg_exception   <= 0;
    end else if(!ctrl_stall && !kill_in) begin
        reg_have_inst   <= i_have_inst;
        reg_rob_fifonum <= i_rob_fifonum;
        reg_ldata       <= i_ldata;
        reg_lmask       <= i_lmask;
        reg_reg_info    <= i_reg_info;
        reg_reg_wstrb   <= i_reg_wstrb;
        reg_regw        <= i_regw;
        reg_stbf_id     <= i_stbf_id;
        reg_prd         <= i_prd;
        reg_mem_offset  <= i_mem_offset;
        reg_mem_addr    <= i_mem_addr;
        reg_exception   <= i_exception;
    end else if(kill_out) begin
        reg_have_inst   <= 0;
        reg_rob_fifonum <= 0;
        reg_ldata       <= 0;
        reg_lmask       <= 0;
        reg_reg_info    <= 0;
        reg_reg_wstrb   <= 0;
        reg_regw        <= 0;
        reg_stbf_id     <= 0;
        reg_prd         <= 0;
        reg_mem_offset  <= 0;
        reg_mem_addr    <= 0;
        reg_exception   <= 0;
    end
    
    if(rst) begin
        reg_we          <= 0;
    end else if(!ctrl_stall) begin
        reg_we          <= i_we;
    end

end

always @* begin : proc_2
    kill_in  = fifoid_gt(i_rob_fifonum, flnum) && ctrl_restore && i_have_inst;
end

always @* begin : proc_3
    kill_out = fifoid_gt(reg_rob_fifonum, flnum) && ctrl_restore && reg_have_inst;
end

always @* begin : proc_4
    o_have_inst = reg_have_inst && !kill_out && !ctrl_stall;
    o_rob_fifonum = reg_rob_fifonum;
    o_ldata = reg_ldata;
    o_lmask = reg_lmask;
    o_reg_info = reg_reg_info;
    o_reg_wstrb = reg_reg_wstrb;
    o_regw = reg_regw;
    o_stbf_id = reg_stbf_id;
    o_we = reg_we;
    o_prd = reg_prd;
    o_mem_offset = reg_mem_offset;
    o_mem_addr = reg_mem_addr;
    o_exception = reg_exception;
end

endmodule
