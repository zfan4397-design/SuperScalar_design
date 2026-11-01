`timescale 1ns / 1ps
// Verilog exercise scaffold; core TODOs are intentionally unfinished.
// Reference: D:/zz/superscalercore/vsrc/core/retire_ctrl.sv
// Preserve reference parameter/port/signal/process/branch/assignment ordering.
// Packed multi-lane ports are flattened: lane i = bus[i*WIDTH +: WIDTH].
// State transitions, original defaults, reset and direct wiring are supplied.
// Restore each missing core assignment at its TODO; do not add a second module.
`include "config_pkg.vh"
`include "retire_pkg.vh"

module retire_ctrl #(
    parameter PORT_WIDTH    =   2
) (
    input                           clk,
    input                           rst,
    //ROB接口
    output reg[PORT_WIDTH-1:0]                        rob_grant,
    input wire[PORT_WIDTH-1:0]                        rob_ready,
    input wire[PORT_WIDTH*(`TYPE_WIDTH)-1:0]        rob_wrtype,
    input wire[PORT_WIDTH*(`EXCPT_WIDTH)-1:0]       rob_exception,
    input wire[PORT_WIDTH*(`PC_WIDTH)-1:0]          rob_pc,
    input wire[PORT_WIDTH*(`BRTYPE_WIDTH)-1:0]      rob_brtype,
    input wire[PORT_WIDTH*(`DATA_WIDTH)-1:0]        rob_brdest,
    input wire[PORT_WIDTH*(5)-1:0]                   rob_rd,
    input wire[PORT_WIDTH*(`DATA_WIDTH)-1:0]        rob_rddata,
    input wire[PORT_WIDTH*(`STBF_WIDTH+1)-1:0]          rob_stbfid,
    
    //STORE_BUFFER接口
    output reg[PORT_WIDTH-1:0]                        stbf_grant,
    output reg[PORT_WIDTH*(`STBF_WIDTH+1)-1:0]          stbf_id,
    //ARF接口
    output reg[PORT_WIDTH-1:0]                        arf_v,
    output reg[PORT_WIDTH*(5)-1:0]                   arf_rd,
    output reg[PORT_WIDTH*(`DATA_WIDTH)-1:0]        arf_wdata,
    //控制接口
    input wire                        ctrl_hold,
    input wire                        ctrl_restore,
    output reg                        ctrl_except_req,
    input wire                        ctrl_except_resp,
    input wire                        ctrl_exceptend,//
    output reg[`EXCPT_WIDTH-1:0]       ctrl_except_code,

    output reg[`PC_WIDTH-1:0]          retire_ctrl_pc,//
    output reg[`PC_WIDTH-1:0]          retire_ctrl_nxtpc,//
    input wire[PORT_WIDTH-1:0]        core_retire_grant
);

reg [PORT_WIDTH-1:0]      can_retire;
reg [PORT_WIDTH-1:0]      grant/*verilator split_var*/;
reg [PORT_WIDTH-1:0]      ready_msk/*verilator split_var*/;
wire [PORT_WIDTH-1:0]      grant_tmp;

wire                       signal_exception;


assign signal_exception = (ready_msk != grant);
assign grant_tmp        = grant;

genvar rtidx;
generate
    for (rtidx = 0; rtidx<PORT_WIDTH; rtidx=rtidx+1) begin : gen_rt
        always @* begin : proc_1
            if(rtidx==0) begin
               grant[rtidx] = rob_ready[rtidx] & can_retire[rtidx];
                ready_msk[rtidx] = rob_ready[rtidx] & core_retire_grant[rtidx];
            
            end else begin
                if(can_retire[rtidx]) begin
                    grant[rtidx] = grant[rtidx-1] & rob_ready[rtidx];
                end else begin
                    grant[rtidx] = 1'b0;
                end

                if(rob_ready[rtidx] & core_retire_grant[rtidx]) begin
                    ready_msk[rtidx] = ready_msk[rtidx-1];
                end else begin
                    ready_msk[rtidx] = 1'b0;
                end
            end
        end
    end
endgenerate

genvar mididx;
generate
    for (mididx = 0; mididx<PORT_WIDTH; mididx=mididx+1) begin : gen_can_retire
        always @* begin : proc_2
           can_retire[mididx] =
    ((rob_exception[mididx*`EXCPT_WIDTH +: `EXCPT_WIDTH] == `EXCPT_NOEX)
  || (rob_exception[mididx*`EXCPT_WIDTH +: `EXCPT_WIDTH] == `EXCPT_BRWRONG)
  || (rob_exception[mididx*`EXCPT_WIDTH +: `EXCPT_WIDTH] == `EXCPT_MMIO_TRAN))
    && core_retire_grant[mididx]; 
        end
    end
endgenerate

genvar aidx;
generate
    for (aidx = 0; aidx<PORT_WIDTH; aidx=aidx+1) begin : gen_retire_outputs
        always @* begin : proc_3
stbf_grant[aidx] =
    rob_grant[aidx]
    && (rob_wrtype[aidx*`TYPE_WIDTH +: `TYPE_WIDTH]
        == `RETIRE_WR_MEM)
    && (rob_exception[aidx*`EXCPT_WIDTH +: `EXCPT_WIDTH]
        != `EXCPT_MMIO_TRAN);
            stbf_id[aidx*(`STBF_WIDTH+1) +: (`STBF_WIDTH+1)]    = rob_stbfid[aidx*(`STBF_WIDTH+1) +: (`STBF_WIDTH+1)];
            arf_v[aidx] =
    rob_grant[aidx]
    && (rob_wrtype[aidx*`TYPE_WIDTH +: `TYPE_WIDTH]
        == `RETIRE_WR_ARF);
            arf_rd[aidx*5 +: 5]     = rob_rd[aidx*5 +: 5];
            arf_wdata[aidx*`DATA_WIDTH +: `DATA_WIDTH]  = rob_rddata[aidx*`DATA_WIDTH +: `DATA_WIDTH];
        end
    end
endgenerate

always @* begin : proc_4
    integer i;
    ctrl_except_code = `EXCPT_NOEX;
    if(!grant_tmp[0]) begin
       ctrl_except_code = rob_exception[0 +: `EXCPT_WIDTH]; 
    end
    for(i=1; i<PORT_WIDTH; i=i+1) begin
        if((!grant_tmp[i]) && grant_tmp[i-1]) begin // e.g. 0111，只�??�??1->0的跳变，选取刚刚跳变的异常码
            ctrl_except_code =
            rob_exception[i*`EXCPT_WIDTH +: `EXCPT_WIDTH]; 
        end
    end
end

reg [`RT_STATE_WIDTH-1:0] currState;
reg [`RT_STATE_WIDTH-1:0] nextState;

always @( posedge clk or posedge rst ) begin : proc_5
    if(rst) begin
        currState <= `RT_NORMAL;      
    end else begin
        currState <= nextState;
    end
end

always @* begin : proc_6
    nextState = `RT_NORMAL;
    case (currState)
        `RT_NORMAL: begin
            if(ctrl_hold || ctrl_restore) begin
                nextState = `RT_STALL;
            end else if(signal_exception && ~ctrl_exceptend) begin
                nextState = `RT_EXCECPT_HANDLE;
            end else if(signal_exception && ctrl_exceptend) begin
                nextState = `RT_NORMAL;
            end else begin
                nextState = `RT_NORMAL;
            end
        end
        `RT_STALL: begin
            if(ctrl_hold || ctrl_restore) begin
                nextState = `RT_STALL;
            end else begin
                nextState = `RT_NORMAL;
            end
        end
        `RT_EXCECPT_HANDLE: begin
            if(ctrl_exceptend) begin
                nextState = `RT_NORMAL;
            end else begin
                nextState = `RT_EXCECPT_HANDLE;
            end
        end
        default: begin
            nextState = `RT_NORMAL;
        end
    endcase
end

always @* begin : proc_7
    rob_grant = grant;
    ctrl_except_req  = 1'b0;
    case (currState)
        `RT_NORMAL: begin
            if(ctrl_hold || ctrl_restore) begin
                rob_grant = {PORT_WIDTH{1'b0}};
            end else if(signal_exception && ~ctrl_exceptend) begin
                ctrl_except_req = 1'b1;
            end else if(signal_exception && ctrl_exceptend) begin
              rob_grant = {PORT_WIDTH{1'b0}};
            end
        end
        `RT_STALL: begin
            if(ctrl_hold || ctrl_restore) begin
                rob_grant = {PORT_WIDTH{1'b0}};
            end
        end
        `RT_EXCECPT_HANDLE: begin
            if(ctrl_except_resp) begin//收到异常处理完成的回应后，将这条异常指令�??�??
                rob_grant = {{(PORT_WIDTH-1){1'b0}}, 1'b1};
            end else begin
                rob_grant = {PORT_WIDTH{1'b0}};
            end
        end
        default: begin
        end
    endcase
end

always @* begin : proc_8
    integer i;
    retire_ctrl_pc      = rob_pc[0*`PC_WIDTH +: `PC_WIDTH];
    retire_ctrl_nxtpc   = rob_pc[0*`PC_WIDTH +: `PC_WIDTH];
    for(i=0; i<PORT_WIDTH; i=i+1) begin
        if(rob_grant[i]) begin
            retire_ctrl_pc =
    rob_pc[i*`PC_WIDTH +: `PC_WIDTH];

retire_ctrl_nxtpc =
    rob_brdest[i*`DATA_WIDTH +: `DATA_WIDTH];
        end
    end
end

endmodule
