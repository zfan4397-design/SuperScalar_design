// Converted from vsrc/core/dff_iq_ro.sv.
// Unpacked array ports require SystemVerilog compilation.
module dff_iq_ro #(
    parameter integer IS2_PRD_WIDTH = 6, // 默认值：6
    parameter integer IS2_EXCPT_WIDTH = 4, // 默认值：4
    parameter integer IS2_ZIMM_WIDTH = 5, // 默认值：5
    parameter integer IS2_CSRADDR_WIDTH = 12, // 默认值：12
    parameter integer IS2_CSROP_WIDTH = 3, // 默认值：3
    parameter integer IS2_ALU_SRCSEL_WIDTH = 2, // 默认值：2
    parameter integer IS2_ALU_INFO_WIDTH = 5, // 默认值：5
    parameter integer IS2_WSTRB_WIDTH = 4, // 默认值：4
    parameter integer IS2_REG_INFO_WIDTH = 3, // 默认值：3
    parameter integer IS2_TYPE_WIDTH = 3, // 默认值：3
    parameter integer IS2_BRTYPE_WIDTH = 2, // 默认值：2
    parameter integer IS2_BR_INFO_WIDTH = 4, // 默认值：4
    parameter integer IS2_FU_TYPE_WIDTH = 3, // 默认值：3
    parameter integer IS2_PC_WIDTH = 32, // 默认值：32
    parameter integer IS2_PRF_IDX_W = IS2_PRD_WIDTH, // 默认值：6
    parameter integer IS2_AGE_W = IS2_PRD_WIDTH+1, // 默认值：7
    parameter integer IS2_RS_ENTRY_W = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+3*IS2_PRF_IDX_W+IS2_AGE_W+47), // 默认值：192
    parameter integer IS2_ISSUE_WIDTH = 3, // 默认值：3
    parameter integer IS2_RS_CONTROL_ROB_IDX_LSB = (IS2_EXCPT_WIDTH+IS2_ZIMM_WIDTH+IS2_CSRADDR_WIDTH+IS2_CSROP_WIDTH+2*IS2_ALU_SRCSEL_WIDTH+IS2_ALU_INFO_WIDTH+2*IS2_WSTRB_WIDTH+IS2_REG_INFO_WIDTH+IS2_TYPE_WIDTH+IS2_BRTYPE_WIDTH+IS2_BR_INFO_WIDTH+IS2_FU_TYPE_WIDTH+2*IS2_PC_WIDTH+3*IS2_PRF_IDX_W+47), // 默认值：185
    parameter integer IS2_RS_CONTROL_ROB_IDX_W = IS2_AGE_W // 默认值：7
) (
    input  wire clk,
    input  wire rst,

    input  wire ctrl_clear,
    input  wire ctrl_stall,
    input  wire ctrl_restore,
    input  wire [IS2_PRD_WIDTH:0] flnum,//恢复时使用的指令年龄边界，比它年轻的指令需要撤销

    input  wire i_valid,
    input  wire [IS2_RS_ENTRY_W-1:0] i_entry,
    input  wire [IS2_ISSUE_WIDTH-1:0] i_iqid,

    output reg o_valid,
    output reg [IS2_RS_ENTRY_W-1:0] o_entry,
    output reg [IS2_ISSUE_WIDTH-1:0] o_iqid);
function fifoid_gt(
    input [IS2_PRD_WIDTH:0]     a,
    input [IS2_PRD_WIDTH:0]     b
);
    fifoid_gt = ( (a[IS2_PRD_WIDTH] == b[IS2_PRD_WIDTH]) ?
                      (a[IS2_PRD_WIDTH-1:0] > b[IS2_PRD_WIDTH-1:0]) :
                      (a[IS2_PRD_WIDTH-1:0] < b[IS2_PRD_WIDTH-1:0]) );
    
endfunction

    reg reg_valid;
    reg [IS2_RS_ENTRY_W-1:0] reg_entry;
    reg [IS2_ISSUE_WIDTH-1:0] reg_iqid;

    reg kill_in;//检查正在输入的指令-不允许把它装入流水级
    reg kill_out;//已经保存在内部的指令-撤销
    
    always @(*) begin 
        kill_in  = fifoid_gt(i_entry[IS2_RS_CONTROL_ROB_IDX_LSB+IS2_RS_CONTROL_ROB_IDX_W-1:IS2_RS_CONTROL_ROB_IDX_LSB],  flnum) && ctrl_restore && i_valid;//输入有效+正在撤销+输入指令比恢复边界年轻
        
        kill_out = fifoid_gt(reg_entry[IS2_RS_CONTROL_ROB_IDX_LSB+IS2_RS_CONTROL_ROB_IDX_W-1:IS2_RS_CONTROL_ROB_IDX_LSB], flnum) && ctrl_restore && reg_valid;//存储有效+正在撤销+存储指令比恢复边界年轻
    end

    always @(*) begin 
        o_valid = reg_valid && !(fifoid_gt(reg_entry[IS2_RS_CONTROL_ROB_IDX_LSB+IS2_RS_CONTROL_ROB_IDX_W-1:IS2_RS_CONTROL_ROB_IDX_LSB], flnum) && ctrl_restore) && !ctrl_stall;
        o_entry = reg_entry;
        o_iqid  = reg_iqid;
    end
    always @(posedge clk or posedge rst) begin 
        if (rst) begin
            reg_valid <= 0;
            reg_entry <= 0;
            reg_iqid  <= 0;
        end
        else if (ctrl_clear) begin
            reg_valid <= 0;
            reg_entry <= 0;
            reg_iqid  <= 0;
        end
        else if (!ctrl_stall && !kill_in) begin
            reg_valid <= i_valid;
            reg_entry <= i_entry;
            reg_iqid  <= i_iqid;
        end else if(kill_out) begin
            reg_valid <= 0;
            reg_entry <= 0;
            reg_iqid  <= 0;
        end
    end

   

endmodule
