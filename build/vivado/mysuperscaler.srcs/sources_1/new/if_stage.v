`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/13 21:32:49
// Design Name: 
// Module Name: if_stage
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


`include "config_pkg.vh"

module if_stage #(
    parameter PORT_WIDTH = 2,
    parameter IN_WIDTH   = 4
) (
    input wire clk,
    input wire rst,

    // 重定向地址
    input wire [`PC_WIDTH-1:0] nxtpc_interrupt,
    input wire [`PC_WIDTH-1:0] nxtpc_flush,

    // 控制信号
    input wire ctrl_stall,
    input wire ctrl_clear,
    input wire ctrl_restore,
    input wire ctrl_restore_pulse,

    // 输出给译码阶段
    output wire [PORT_WIDTH-1:0] have_inst,
    output wire [PORT_WIDTH*`PC_WIDTH-1:0] pc_o,
    output wire [PORT_WIDTH*`PC_WIDTH-1:0] pc_next,
    output wire [PORT_WIDTH*`DATA_WIDTH-1:0] inst,

    // 调试统计：本周期事件/指令数量
    output wire [31:0] dbg_if_redirect_cycle,
    output wire [31:0] dbg_if_backend_stall_cycle,
    output wire [31:0] dbg_if_bundle_cut_inst,
    output wire [31:0] dbg_ifq_out_inst,
    output wire [31:0] dbg_if_ifq_full_cycle,
    output wire [31:0] dbg_if_icache_busy_cycle,
    output wire [31:0] dbg_if_wait_icache_rvalid_cycle,

    // 指令存储接口
    input wire icache_rvalid,
    input wire icache_busy,
    input wire [IN_WIDTH*`DATA_WIDTH-1:0] inst_i,

    output wire [`PC_WIDTH-1:0] icache_raddr,
    output wire icache_re,

    // 退休反馈：供分支预测器更新
    input wire [PORT_WIDTH-1:0] rt_grant,
    input wire [PORT_WIDTH*`PC_WIDTH-1:0] rt_pc,
    input wire [PORT_WIDTH*`BRTYPE_WIDTH-1:0] rt_brtype,
    input wire [PORT_WIDTH*`DATA_WIDTH-1:0] rt_brdest,
    input wire [PORT_WIDTH-1:0] rt_is_ret,
    input wire [PORT_WIDTH*5-1:0] rt_rd,
    input wire [PORT_WIDTH*`EXCPT_WIDTH-1:0] rt_exception
);

wire ifq_full;
wire redirect;
wire [`PC_WIDTH-1:0] redirect_pc;

wire [`PC_WIDTH-1:0] pcreg_pc;
wire pcreg_have_inst;

wire [IN_WIDTH-1:0] ifq_i_have_inst_o;
wire [IN_WIDTH*`PC_WIDTH-1:0] ifq_i_pc;
wire [IN_WIDTH*`PC_WIDTH-1:0] ifq_i_pc_next;
wire [IN_WIDTH*`DATA_WIDTH-1:0] ifq_i_inst;

wire [31:0] dbg_bp_bundle_cut_inst;


function [31:0] countones_have_inst;
    input [PORT_WIDTH-1:0] value;
    integer bit_idx;
    begin
        countones_have_inst = 32'd0;

        for (bit_idx = 0; bit_idx < PORT_WIDTH;
             bit_idx = bit_idx + 1) begin
            if (value[bit_idx] == 1'b1)
                countones_have_inst =
                    countones_have_inst + 32'd1;
        end
    end
endfunction

// PC寄存器输出连接到指令存储请求接口
assign icache_raddr = pcreg_pc;
assign icache_re    = pcreg_have_inst;

// PC寄存器
pc_reg pc_reg (
    .clk         (clk),
    .rst         (rst),

    .redirect    (redirect),
    .redirect_pc (redirect_pc),

    .icache_busy (icache_busy),
    .ifq_full    (ifq_full),
    .ctrl_stall  (ctrl_stall || ctrl_restore),

    .pc          (pcreg_pc),
    .have_inst   (pcreg_have_inst)
);

// 分支预测器
branch_predict #(
    .BUF_BITS   (3),
    .PORT_WIDTH (PORT_WIDTH),
    .IN_WIDTH   (IN_WIDTH)
) branch_predict (
    .clk                 (clk),
    .rst                 (rst),

    .rt_grant            (rt_grant),
    .rt_rd               (rt_rd),
    .rt_pc               (rt_pc),
    .rt_brtype           (rt_brtype),
    .rt_brdest           (rt_brdest),
    .rt_is_ret           (rt_is_ret),
    .rt_exception        (rt_exception),

    .icache_rvalid       (icache_rvalid),
    .icache_busy         (icache_busy),

    .have_inst_i         (pcreg_have_inst),
    .pc_i                (pcreg_pc),
    .inst_i              (inst_i),

    .have_inst_o         (ifq_i_have_inst_o),
    .pc                  (ifq_i_pc),
    .pc_next             (ifq_i_pc_next),
    .inst                (ifq_i_inst),

    .dbg_bundle_cut_inst (dbg_bp_bundle_cut_inst),

    .ctrl_restore_pulse  (ctrl_restore_pulse),
    .ctrl_clear          (ctrl_clear),

    .nxtpc_flush         (nxtpc_flush),
    .nxtpc_interrupt     (nxtpc_interrupt),

    .redirect            (redirect),
    .redirect_pc         (redirect_pc)
);

// 取指队列
ifq #(
    .IFQ_BITS   (6),
    .IN_WIDTH   (IN_WIDTH),
    .PORT_WIDTH (PORT_WIDTH)
) ifq (
    .clk                (clk),
    .rst                (rst),

    .have_inst_i        (ifq_i_have_inst_o),
    .pc_i               (ifq_i_pc),
    .pc_next_i          (ifq_i_pc_next),
    .inst_i             (ifq_i_inst),

    .have_inst          (have_inst),
    .pc                 (pc_o),
    .pc_next            (pc_next),
    .inst               (inst),

    .ctrl_clear         (ctrl_clear),
    .ctrl_restore_pulse (ctrl_restore_pulse),
    .ctrl_stall         (ctrl_stall || ctrl_restore),

    .ifq_full           (ifq_full)
);


assign dbg_if_redirect_cycle =
    (ctrl_clear || ctrl_restore_pulse || redirect)
    ? 32'd1 : 32'd0;

assign dbg_if_backend_stall_cycle =
    ((!ctrl_clear) &&
     (!ctrl_restore_pulse) &&
     (!redirect) &&
     (ctrl_stall || ctrl_restore || ifq_full))
    ? 32'd1 : 32'd0;

assign dbg_if_bundle_cut_inst =
    dbg_bp_bundle_cut_inst;

assign dbg_ifq_out_inst =
    countones_have_inst(have_inst);

assign dbg_if_ifq_full_cycle =
    ifq_full ? 32'd1 : 32'd0;

assign dbg_if_icache_busy_cycle =
    icache_busy ? 32'd1 : 32'd0;

assign dbg_if_wait_icache_rvalid_cycle =
    (pcreg_have_inst && (!icache_busy) && (!icache_rvalid))
    ? 32'd1 : 32'd0;

endmodule
