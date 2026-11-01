`timescale 1ns / 1ps
// Exercise scaffold translated from superscalercore/vsrc/core/ctrl_unit.sv.
// Core control outputs remain unfinished at their original TODO positions.
// Preserve reference parameter/port/signal/process/condition/statement ordering.
// State transitions, defaults, saved recovery metadata and resets are supplied.
// Each TODO can replace several consecutive reference assignments; retain their order.
`include "config_pkg.vh"
`include "ctrl_pkg.vh"


module ctrl_unit #(
    parameter FU0WB_WIDTH   =   2,
    parameter FU1WB_WIDTH   =   1
) (
    input wire            clk,
    input wire            rst,

    input wire                    ctrl_restore_req,
    input wire[`PRD_WIDTH:0]       flnum,
    input wire[`DATA_WIDTH-1:0]    brdest,
    input wire                    lockstep_recover_req,
    input wire[`PC_WIDTH-1:0]      lockstep_recover_pc,
    input wire[`PRD_WIDTH:0]       lockstep_recover_flnum,
    input wire                    lockstep_rollback_done,
    output wire[`DATA_WIDTH-1:0]    nxtpc_flush,
    input wire                    ctrl_restoreend_req,

    input wire                    ctrl_stall_req_icache,
    input wire                    ctrl_stall_req_rat,
    input wire                    ctrl_stall_req_rob,
    input wire                    ctrl_stall_req_iq,
    input wire                    ctrl_stall_req_fu_mem,

    output reg                    ctrl_stall_if,
    output reg                    ctrl_stall_dff_if_id,
    output reg                    ctrl_stall_dff_id_rr,
    output reg                    ctrl_stall_rr,
    output reg                    ctrl_stall_dff_rr_iq,
    output reg                    ctrl_stall_dff_rr_rob,
    output reg                    ctrl_stall_iq,
    output reg                    ctrl_stall_rob,
    output reg[FU0WB_WIDTH-1:0]   ctrl_stall_dff_0_iq_ro,
    output reg[FU1WB_WIDTH-1:0]   ctrl_stall_dff_1_iq_ro,
    output reg[FU0WB_WIDTH-1:0]   ctrl_stall_dff_0_ro_fu,
    output reg[FU1WB_WIDTH-1:0]   ctrl_stall_dff_1_ro_fu,
    output reg[FU0WB_WIDTH-1:0]   ctrl_stall_dff_0_fu_wb,
    output reg[FU1WB_WIDTH-1:0]   ctrl_stall_dff_1_fu_wb,

    output reg                ctrl_clear,
    output reg                ctrl_restore,
    output reg                ctrl_restore_sig,
    output reg                ctrl_restoreend,
    output reg[`PRD_WIDTH:0]   ctrl_flnum,
    output wire                lockstep_restore_pulse,
    output wire[`PRD_WIDTH:0]   lockstep_restore_flnum,

    input wire                ctrl_error_req_rat,
    input wire                ctrl_error_req_rob,

    input wire                ctrl_restart,

    input wire                    ctrl_except_req,
    input wire[`EXCPT_WIDTH-1:0]   ctrl_except_req_code,
    output reg                    ctrl_except,
    output reg[`EXCPT_WIDTH-1:0]   ctrl_except_code,
    input wire                    ctrl_exceptend,
    output reg                    ctrl_except_resp,
    output reg                    ctrl_rt_hold
);

reg[`CTRL_STATE_WIDTH-1:0]    currState;
reg[`CTRL_STATE_WIDTH-1:0]    nextState;
reg[`CTRL_STATE_WIDTH-1:0]    prevState;

always @( posedge clk or posedge rst ) begin : proc_1
    if(rst) begin
        currState <= `CTRL_NORMAL;
        prevState <= `CTRL_NORMAL;
    end else begin
        prevState <= currState;
        currState <= nextState;
    end
end

always @* begin : proc_2
    nextState = `CTRL_NORMAL;
    case(currState)
        `CTRL_NORMAL: begin
            if(lockstep_recover_req) begin
                nextState = `CTRL_LOCKSTEP_CLEAR;
            end else if(ctrl_error_req_rat | ctrl_error_req_rob) begin
                nextState = `CTRL_ERROR;
            end else if(ctrl_except_req) begin
                nextState = `CTRL_EXCEPT;
            end else if(ctrl_restore_req && !ctrl_restoreend_req) begin
                nextState = `CTRL_RESTORE;
            end
        end
        `CTRL_EXCEPT: begin
            if(ctrl_exceptend) begin
                nextState = `CTRL_NORMAL;
            end else begin
                nextState = `CTRL_EXCEPT;
            end
        end
        `CTRL_RESTORE: begin
            if(ctrl_exceptend) begin
                nextState = `CTRL_NORMAL;
            end else if(ctrl_restoreend_req) begin
                nextState = `CTRL_NORMAL;
            end else begin
                nextState = `CTRL_RESTORE;
            end
        end
        `CTRL_LOCKSTEP_CLEAR: begin
            nextState = `CTRL_LOCKSTEP_RESTORE;
        end
        `CTRL_LOCKSTEP_RESTORE: begin
            if(lockstep_rollback_done) begin
                nextState = `CTRL_NORMAL;
            end else begin
                nextState = `CTRL_LOCKSTEP_RESTORE;
            end
        end
        `CTRL_ERROR: begin
            if(ctrl_restart) begin
                nextState = `CTRL_NORMAL;
            end else begin
                nextState = `CTRL_ERROR;
            end
        end
        default: begin
            nextState = `CTRL_NORMAL;
        end
    endcase
end

reg               stall_kill;

reg               sig_restore;
reg[`PRD_WIDTH:0]  reg_ctrl_flnum_merge;
reg[`PRD_WIDTH:0]  reg_lockstep_flnum;
reg[`PC_WIDTH-1:0] reg_lockstep_pc;

assign nxtpc_flush =
    ((currState == `CTRL_LOCKSTEP_CLEAR) ||
     (currState == `CTRL_LOCKSTEP_RESTORE))
    ? reg_lockstep_pc : brdest;

assign lockstep_restore_pulse =
    (currState == `CTRL_LOCKSTEP_RESTORE) &&
    (prevState == `CTRL_LOCKSTEP_CLEAR);
assign lockstep_restore_flnum = reg_lockstep_flnum;

always @(posedge clk or posedge rst) begin : proc_3
    if(rst) begin
        reg_ctrl_flnum_merge <= 0;
    end else if(sig_restore) begin
        reg_ctrl_flnum_merge <= flnum;
    end
end

always @(posedge clk or posedge rst) begin : proc_4
    if(rst) begin
        reg_lockstep_flnum <= 0;
        reg_lockstep_pc    <= 0;
    end else if(lockstep_recover_req) begin
        reg_lockstep_flnum <= lockstep_recover_flnum;
        reg_lockstep_pc    <= lockstep_recover_pc;
    end
end

always @* begin : proc_5

    ctrl_restore        =   1'b0;
    ctrl_restore_sig    =   ctrl_restore_req;
    ctrl_restoreend     =   ctrl_restoreend_req;
    ctrl_flnum          =   0;
    sig_restore         =   1'b0;

    ctrl_except         =   1'b0;
    ctrl_clear          =   ctrl_exceptend;
    ctrl_except_code    =   `EXCPT_NOEX;
    ctrl_except_resp    =   1'b0;

    stall_kill          =   1'b0;

    ctrl_rt_hold        =   1'b0;
    case(currState)
        `CTRL_NORMAL: begin
            if(ctrl_restore_req && !ctrl_restoreend_req) begin
               sig_restore         =   1'b1;
            end else if(ctrl_restore_req && ctrl_restoreend_req) begin
                sig_restore         =   1'b0;
            end
            if(ctrl_restore_req) begin
                ctrl_restore        =   1'b1;
                ctrl_flnum          =   flnum;
                stall_kill          =   1'b1;
            end
        end
        `CTRL_EXCEPT: begin
            if(ctrl_exceptend) begin
                ctrl_except         =   1'b1;
                ctrl_except_code    =   ctrl_except_req_code;
                ctrl_except_resp    =   1'b1;
                stall_kill          =   1'b1;
            end else begin
                ctrl_except         =   1'b1;
                ctrl_except_code    =   ctrl_except_req_code;
                stall_kill          =   1'b1;
            end
        end
        `CTRL_RESTORE: begin
            if(ctrl_exceptend) begin
               ctrl_except         =   1'b1;
                ctrl_except_code    =   ctrl_except_req_code;
                ctrl_except_resp    =   1'b1;
                stall_kill          =   1'b1; 
            end else begin
                if(ctrl_restore_req) begin
                   ctrl_flnum          =   flnum; 
                end else begin
                    ctrl_flnum          =   reg_ctrl_flnum_merge;
                end

                if(ctrl_restore_req && !ctrl_restoreend_req) begin
                    sig_restore         =   1'b1;
                end else if(ctrl_restore_req && ctrl_restoreend_req) begin
                    sig_restore         =   1'b0;
                end

              ctrl_restore        =   1'b1;
                stall_kill          =   1'b1;  
            end
        end
        `CTRL_ERROR: begin
           ctrl_rt_hold        =   1'b1; 
        end
        `CTRL_LOCKSTEP_CLEAR: begin
           ctrl_clear          =   1'b1;
            ctrl_flnum          =   reg_lockstep_flnum;
            stall_kill          =   1'b1;
            ctrl_rt_hold        =   1'b1; 
        end
        `CTRL_LOCKSTEP_RESTORE: begin
           ctrl_restore        =   1'b1;
            ctrl_restore_sig    =   1'b0;
            ctrl_flnum          =   reg_lockstep_flnum;
            stall_kill          =   1'b1;
            ctrl_rt_hold        =   1'b1; 
        end
    endcase
end

always @* begin : proc_6
    ctrl_stall_if           =   1'b0;
    ctrl_stall_dff_if_id    =   1'b0;
    ctrl_stall_dff_id_rr    =   1'b0;
    ctrl_stall_rr           =   1'b0;
    ctrl_stall_dff_rr_iq    =   1'b0;
    ctrl_stall_dff_rr_rob   =   1'b0;
    ctrl_stall_iq           =   1'b0;
    ctrl_stall_rob          =   1'b0;
    ctrl_stall_dff_0_iq_ro  =   0;
    ctrl_stall_dff_1_iq_ro  =   0;
    ctrl_stall_dff_0_ro_fu  =   0;
    ctrl_stall_dff_1_ro_fu  =   0;
    ctrl_stall_dff_0_fu_wb  =   0;
    ctrl_stall_dff_1_fu_wb  =   0;

    if(!stall_kill) begin
        if(ctrl_stall_req_icache) begin
             ctrl_stall_if           =   1'b1;
            ctrl_stall_dff_if_id    =   1'b1;
        end
        if(ctrl_stall_req_rat) begin
           ctrl_stall_if           =   1'b1;
            ctrl_stall_dff_if_id    =   1'b1;
            ctrl_stall_dff_id_rr    =   1'b1;
        end
        if(ctrl_stall_req_rob) begin
            ctrl_stall_if           =   1'b1;
            ctrl_stall_dff_if_id    =   1'b1;
            ctrl_stall_dff_id_rr    =   1'b1;
            ctrl_stall_rr           =   1'b1;
            ctrl_stall_dff_rr_iq    =   1'b1;
            ctrl_stall_dff_rr_rob   =   1'b1;
            ctrl_stall_iq           =   1'b1; 
        end
        if(ctrl_stall_req_iq) begin
            ctrl_stall_if           =   1'b1;
            ctrl_stall_dff_if_id    =   1'b1;
            ctrl_stall_dff_id_rr    =   1'b1;
            ctrl_stall_rr           =   1'b1;
            ctrl_stall_dff_rr_iq    =   1'b1;
            ctrl_stall_dff_rr_rob   =   1'b1;
            ctrl_stall_rob          =   1'b1;
        end
    end
    
    if(ctrl_stall_req_fu_mem) begin
        ctrl_stall_dff_1_iq_ro  =   {FU1WB_WIDTH{1'b1}};
        ctrl_stall_dff_1_ro_fu  =   {FU1WB_WIDTH{1'b1}};
    end
end

endmodule
