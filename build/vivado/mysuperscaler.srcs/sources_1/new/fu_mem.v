`timescale 1ns / 1ps
// Exercise scaffold translated from superscalercore/vsrc/core/fu_mem.sv.
// Core assignments remain at their original TODO positions; this is not functional yet.
// Keep reference port/signal/process/instance/condition/loop/assignment ordering.
// Struct fields use payload_defs.vh; packed lane ports are flattened with lane zero low.
// The reference top is combinational; reset and pipeline storage reside in dff_fu.
`include "config_pkg.vh"
`include "payload_defs.vh"

module fu_mem #(
    parameter PORT_WIDTH    =   2
) (
    input wire                        clk,
    input wire                        rst,

    input wire                        have_inst,
    input wire [`RS_PAYLOAD_RAM_WIDTH-1:0]               payload_ram,
    input wire[`DATA_WIDTH-1:0]        src1,
    input wire[`DATA_WIDTH-1:0]        src2,
    input wire[`PRD_WIDTH-1:0]         prd,
    input wire                        prd_v,
    input wire[`PRD_WIDTH:0]           rob_fifonum,


    output reg[`DATA_WIDTH-1:0]        dcache_addr,
    output reg                        dcache_re,
    output reg                        dcache_we,
    output wire[`DATA_WIDTH-1:0]        dcache_wdata,
    output wire[3:0]                   dcache_wstrb,
    input wire[`DATA_WIDTH-1:0]        dcache_rdata,
    input wire                        dcache_rvalid,

    input wire                        dcache_done,
    input wire                        dcache_busy,

    input wire                        ctrl_restore,
    input wire                        ctrl_clear,
    input wire                        lockstep_restore_pulse,
    input wire[`PRD_WIDTH:0]           lockstep_restore_flnum,
    output reg                        ctrl_stall_req,
    input wire[`PRD_WIDTH:0]           flnum,

    input wire[PORT_WIDTH-1:0]                    rt_stbf_grant,
    input wire[PORT_WIDTH*((`STBF_WIDTH+1))-1:0]      rt_stbf_id,
    output wire[PORT_WIDTH-1:0]                    rt_sreq,
    output wire[PORT_WIDTH*(`DATA_WIDTH)-1:0]    rt_saddr,
    output wire[PORT_WIDTH*(`DATA_WIDTH)-1:0]    rt_sdata,
    input wire[PORT_WIDTH-1:0]                    cmp_stbf_grant,
    input wire[PORT_WIDTH*((`STBF_WIDTH+1))-1:0]      cmp_stbf_id,


    output reg[`PRD_WIDTH-1:0]         wb1_prd,
    output reg                        wb1_valid,
    output reg                        wb1_regw,
    output reg[`STBF_WIDTH:0]          wb1_stbfid,
    output reg[`DATA_WIDTH-1:0]        wb1_data,
    output reg[`EXCPT_WIDTH-1:0]       wb1_exception,
    output reg[`PRD_WIDTH:0]           wb1_fifonum
);

reg [`DATA_WIDTH-1:0]              oprand_src1;
reg [`DATA_WIDTH-1:0]              oprand_src2;
reg [`DATA_WIDTH-1:0]              mem_addr;
reg [`DATA_WIDTH-1:0]              mem_addr_base;
reg [1:0]                         mem_offset;
reg [`EXCPT_WIDTH-1:0]             mem_exception;
reg [7:0]                         mem_sdata[3:0];
reg [7:0]                         mem_masked_sdata[3:0];

wire                               mmio_req;

wire                        c1_have_inst;
wire[`PRD_WIDTH:0]           c1_rob_fifonum;
wire[`DATA_WIDTH-1:0]        c1_ldata;
wire[3:0]                   c1_lmask;
wire[`REG_INFO_WIDTH-1:0]    c1_reg_info;
wire[3:0]                   c1_reg_wstrb;
wire                        c1_regw;
wire[`STBF_WIDTH:0]          c1_stbf_id;
wire                        c1_we;
wire[`PRD_WIDTH-1:0]         c1_prd;
wire[1:0]                   c1_mem_offset;
wire[`DATA_WIDTH-1:0]        c1_mem_addr;
wire[`EXCPT_WIDTH-1:0]       c1_exception;

reg[`PC_WIDTH-1:0]         debug_pc;
// Verilog equivalent of the reference's one-time variable initialization.
initial begin : init_debug_pc
    debug_pc = payload_ram[`RS_PAYLOAD_RAM_PC_RANGE];
end

always @* begin : proc_1
    case(payload_ram[`RS_PAYLOAD_RAM_ALU_SRC1_RANGE])
        `SRC1SEL_REGDATA :   oprand_src1 = src1;
        `SRC1SEL_PC      :   oprand_src1 = payload_ram[`RS_PAYLOAD_RAM_PC_RANGE];
        default         :   oprand_src1 = 0;
    endcase
end

always @* begin : proc_2
    case(payload_ram[`RS_PAYLOAD_RAM_ALU_SRC2_RANGE])
        `SRC2SEL_REGDATA :   oprand_src2 = src2;
        `SRC2SEL_EXTEND  :   oprand_src2 = payload_ram[`RS_PAYLOAD_RAM_EXTEND_RANGE];
        default         :   oprand_src2 = 0;
    endcase
end

always @* begin : proc_3
    // TODO FM01 [fu_mem.sv:97] mem_addr: add the selected address operands.
    // TODO FM02 [fu_mem.sv:98] mem_addr_base: form the aligned word address.
    // TODO FM03 [fu_mem.sv:99] mem_offset: extract the byte offset within the word.
    if(mmio_req) begin
        // TODO FM04 [fu_mem.sv:101] mem_exception: encode an MMIO transfer and its write flag.
    end else begin
        mem_exception = `EXCPT_NOEX;
    end
end

// TODO FM05 [fu_mem.sv:107] mmio_req: classify valid accesses outside the ordinary DRAM and LOG ranges.

genvar memidx;
generate
    for(memidx=0; memidx<4; memidx=memidx+1) begin : gen_memidx
        always @* begin : proc_4
            mem_sdata[memidx] = src2[memidx*8+7:memidx*8];
            // TODO FM06 [fu_mem.sv:116] mem_masked_sdata[memidx]: retain only enabled store bytes.
        end
    end
endgenerate

wire           sig_dcache_we;
reg           sig_dcache_wdone;
wire[`DATA_WIDTH-1:0]   data_dcache_waddr;
wire           store_buffer_full;


reg [`DATA_WIDTH-1:0]      saddr;
reg [`DATA_WIDTH-1:0]      sdata;
reg [3:0]                 swstrb;
reg                       sreq;
wire[`STBF_WIDTH:0]         stbf_id;
wire                       svalid;

reg[`DATA_WIDTH-1:0]       laddr;
wire[`DATA_WIDTH-1:0]       ldata;
wire[3:0]                  lmask;
reg                       req_dcache_re;

always @* begin : proc_5
    saddr   =   mem_addr_base;
    sdata = {
    mem_masked_sdata[3],
    mem_masked_sdata[2],
    mem_masked_sdata[1],
    mem_masked_sdata[0]
} << {mem_offset, 3'b000};

swstrb =
    payload_ram[`RS_PAYLOAD_RAM_MEM_WSTRB_RANGE]
    << mem_offset;

sreq =
    payload_ram[`RS_PAYLOAD_RAM_MEM_W_LSB]
    && have_inst
    && !mmio_req;
    laddr   =   mem_addr_base;
    // Store Buffer未提供load需要的全部字节时，请求读取存储器。
req_dcache_re =
    (((lmask >> mem_offset)
       & payload_ram[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE])
      != payload_ram[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE])
    && payload_ram[`RS_PAYLOAD_RAM_MEM_R_LSB]
    && have_inst
    && !mmio_req;

ctrl_stall_req = store_buffer_full | dcache_busy;

sig_dcache_wdone = c1_we & dcache_done;
end

always @* begin : proc_6
    if(req_dcache_re && !dcache_busy) begin
        dcache_addr = mem_addr_base;
       dcache_re   = 1'b1;
        dcache_we   = 1'b0;
    end else begin
        dcache_addr = data_dcache_waddr;
        dcache_re   = 1'b0;
        dcache_we   = sig_dcache_we;
    end
end

store_buffer #(
    .PORT_WIDTH(PORT_WIDTH)
) store_buffer_inst(
    .clk(clk),
    .rst(rst),
    .rob_fifonum(rob_fifonum),
    .saddr(saddr),
    .sdata(sdata),
    .swstrb(swstrb),
    .sreq(sreq),
    .stbf_id(stbf_id),
    .svalid(svalid),
    .laddr(laddr),
    .lrob_fifonum(rob_fifonum),
    .ldata(ldata),
    .lmask(lmask),
    .rt_stbf_grant(rt_stbf_grant),
    .rt_stbf_id(rt_stbf_id),
    .rt_sreq(rt_sreq),
    .rt_saddr(rt_saddr),
    .rt_sdata(rt_sdata),
    .cmp_stbf_grant(cmp_stbf_grant),
    .cmp_stbf_id(cmp_stbf_id),
    .dcache_re(dcache_re),
    .dcache_busy(dcache_busy),
    .dcache_wdone(sig_dcache_wdone),
    .dcache_waddr(data_dcache_waddr),
    .dcache_we(sig_dcache_we),
    .dcache_we_resp(dcache_we),
    .dcache_wdata(dcache_wdata),
    .dcache_wstrb(dcache_wstrb),
    .ctrl_restore(ctrl_restore),
    .ctrl_clear(ctrl_clear),
    .lockstep_restore_pulse(lockstep_restore_pulse),
    .lockstep_restore_flnum(lockstep_restore_flnum),
    .flnum(flnum),
    .ctrl_stall(ctrl_stall_req),
    .full(store_buffer_full)
);

dff_fu dff_fu (
    .clk(clk),
    .rst(rst),

    .ctrl_clear(ctrl_clear),
    .ctrl_stall(ctrl_stall_req),
    .ctrl_restore(ctrl_restore),
    .flnum(flnum),

    .i_have_inst(have_inst),
    .i_rob_fifonum(rob_fifonum),
    .i_ldata(ldata),
    .i_lmask(lmask),
    .i_reg_info(payload_ram[`RS_PAYLOAD_RAM_REG_INFO_RANGE]),
    .i_reg_wstrb(payload_ram[`RS_PAYLOAD_RAM_REG_WSTRB_RANGE]),
    .i_regw(payload_ram[`RS_PAYLOAD_RAM_RDV_RANGE] && (payload_ram[`RS_PAYLOAD_RAM_RD_RANGE]!=5'b0)),
    .i_stbf_id(stbf_id),
    .i_we(dcache_we),
    .i_prd(prd),
    .i_mem_offset(mem_offset),
    .i_mem_addr(mem_addr),
    .i_exception(mem_exception),
    .o_have_inst(c1_have_inst),
    .o_rob_fifonum(c1_rob_fifonum),
    .o_ldata(c1_ldata),
    .o_lmask(c1_lmask),
    .o_reg_info(c1_reg_info),
    .o_reg_wstrb(c1_reg_wstrb),
    .o_regw(c1_regw),
    .o_stbf_id(c1_stbf_id),
    .o_we(c1_we),
    .o_prd(c1_prd),
    .o_mem_offset(c1_mem_offset),
    .o_mem_addr(c1_mem_addr),
    .o_exception(c1_exception)
);

always @* begin : proc_7
    wb1_prd = c1_prd;
    wb1_fifonum = c1_rob_fifonum; 
    wb1_stbfid = c1_stbf_id;
end

reg [`DATA_WIDTH-1:0]  merge_data;
reg [`DATA_WIDTH-1:0]  final_data;
genvar meridx;
generate
    for(meridx=0; meridx<4; meridx=meridx+1) begin : gen_meridx
        always @* begin : proc_8
            if(c1_lmask[meridx]) begin
                merge_data[8*meridx+7:8*meridx] = c1_ldata[8*meridx+7:8*meridx];
            end else begin
                merge_data[8*meridx+7:8*meridx] = dcache_rdata[8*meridx+7:8*meridx];
            end
        end
    end
endgenerate

always @* begin : proc_9
    final_data = merge_data >> {c1_mem_offset, 3'b000}; 
end



always @* begin : proc_10
    if(c1_exception==`EXCPT_NOEX) begin
        wb1_exception = c1_exception;
        wb1_regw = c1_regw;
        case(c1_reg_wstrb)
        4'b1111: begin
            wb1_data = final_data;
        end
        4'b0011: begin
            if(c1_reg_info==`REGW_MEM_SIGNED) begin
                wb1_data = {{16{final_data[15]}}, final_data[15:0]};
            end else begin
                wb1_data = {{16{1'b0}}, final_data[15:0]};
            end
        end
        4'b0001: begin
            if(c1_reg_info==`REGW_MEM_SIGNED) begin
               wb1_data = {{24{final_data[7]}}, final_data[7:0]}; 
            end else begin
                wb1_data = {{24{1'b0}}, final_data[7:0]};
            end
        end
        default: begin
            wb1_data = final_data;
        end
        endcase
    end else begin
        wb1_data = c1_mem_addr;
        wb1_regw = 1'b0;
        case(c1_reg_wstrb)
        4'b1111: begin
            wb1_exception = c1_exception | 2'b11;
        end
        4'b0011: begin
            wb1_exception = c1_exception | 2'b10;
        end
        4'b0001: begin
            wb1_exception = c1_exception | 2'b01;
        end
        default: begin
            wb1_exception = c1_exception | 2'b00;
        end
        endcase
    end
end

always @* begin : proc_11
    wb1_valid = c1_have_inst;
end

endmodule
