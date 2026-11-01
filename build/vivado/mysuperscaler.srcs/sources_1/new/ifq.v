`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/13 20:00:21
// Design Name: 
// Module Name: ifq
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

`include "cpu_defs.vh"

module ifq #(
    parameter IFQ_BITS   = 6,
    parameter IN_WIDTH   = 4,
    parameter PORT_WIDTH = 2,
    parameter PC_WIDTH   = `PC_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH
) (
    input  clk,
    input  rst,

    input  [IN_WIDTH-1:0] have_inst_i,
    input  [IN_WIDTH*PC_WIDTH-1:0] pc_i,
    input  [IN_WIDTH*PC_WIDTH-1:0] pc_next_i,
    input  [IN_WIDTH*DATA_WIDTH-1:0] inst_i,

    output reg [PORT_WIDTH-1:0] have_inst,
    output reg [PORT_WIDTH*PC_WIDTH-1:0] pc,
    output reg [PORT_WIDTH*PC_WIDTH-1:0] pc_next,
    output reg [PORT_WIDTH*DATA_WIDTH-1:0] inst,

    input  ctrl_clear,
    input  ctrl_restore_pulse,
    input  ctrl_stall,

    output  ifq_full
);

localparam IFQ_DEPTH       = (1 << IFQ_BITS);
localparam LOG2_IN_WIDTH   = $clog2(IN_WIDTH);
localparam LOG2_PORT_WIDTH = $clog2(PORT_WIDTH);

reg  [IFQ_BITS:0] head_ptr;
reg  [IFQ_BITS:0] tail_ptr;
wire [IFQ_BITS:0] diff;

wire [IFQ_BITS:0] head_addr [0:IN_WIDTH-1];
wire [IFQ_BITS:0] tail_addr [0:PORT_WIDTH-1];

wire [IN_WIDTH-1:0]   fifo_in;
wire [PORT_WIDTH-1:0] fifo_out;
wire [IN_WIDTH-1:0]   direct_out;

wire [LOG2_IN_WIDTH-1:0] fout_pos [0:PORT_WIDTH-1];

reg [IFQ_DEPTH-1:0] entry_valid;
reg [IFQ_DEPTH-1:0] entry_valid_nxt;

reg [PC_WIDTH-1:0]   entry_pc      [0:IFQ_DEPTH-1];
reg [PC_WIDTH-1:0]   entry_pc_next [0:IFQ_DEPTH-1];
reg [DATA_WIDTH-1:0] entry_inst    [0:IFQ_DEPTH-1];

assign diff = head_ptr - tail_ptr;
assign ifq_full = diff >= (IFQ_DEPTH - 2*IN_WIDTH);

localparam COUNT_WIDTH =
    (IN_WIDTH > PORT_WIDTH) ? IN_WIDTH : PORT_WIDTH;

// 统计向量中有多少个1
function integer countones;
    input [COUNT_WIDTH-1:0] value;
    integer bit_idx;
    begin
        countones = 0;
        for (bit_idx = 0; bit_idx < COUNT_WIDTH;
             bit_idx = bit_idx + 1) begin
            if (value[bit_idx] == 1'b1)
                countones = countones + 1;
        end
    end
endfunction

genvar nidx;

generate
    for (nidx = 0; nidx < PORT_WIDTH;
         nidx = nidx + 1) begin : gen_direct_out

        assign direct_out[nidx] =
            (~(fifo_out[PORT_WIDTH-1-nidx] | ctrl_stall))
            & have_inst_i[nidx];
    end

    for (nidx = PORT_WIDTH; nidx < IN_WIDTH;
         nidx = nidx + 1) begin : gen_direct_zero

        assign direct_out[nidx] = 1'b0;
    end
endgenerate

generate
    for (nidx = 0; nidx < IN_WIDTH;
         nidx = nidx + 1) begin : gen_fifo_in

        assign fifo_in[nidx] =
            (~direct_out[nidx]) & have_inst_i[nidx];

        assign head_addr[nidx] =
            countones(fifo_in[nidx:0]) + head_ptr - 1;
    end
endgenerate

generate
    for (nidx = 0; nidx < PORT_WIDTH;
         nidx = nidx + 1) begin : gen_fifo_out

        assign tail_addr[nidx] = tail_ptr + nidx;

        assign fifo_out[nidx] =
            entry_valid[tail_addr[nidx][IFQ_BITS-1:0]]
            & (~ctrl_stall);

        assign fout_pos[nidx] =
            fifo_out[nidx]
            ? {LOG2_IN_WIDTH{1'b0}}
            : (nidx - countones(fifo_out[nidx:0]));
    end
endgenerate

    always @( posedge clk or posedge rst ) begin
    if(rst) begin
        head_ptr <= 0;
    end else begin
        if(ctrl_restore_pulse || ctrl_clear) begin
            head_ptr <= 0;
        end else begin
            head_ptr <= head_ptr + countones(fifo_in);
        end
    end
end

    always @( posedge clk or posedge rst ) begin
    if(rst) begin
        tail_ptr <= 0;
    end else begin
        if(ctrl_restore_pulse || ctrl_clear) begin
            tail_ptr <= 0;
        end else if(!ctrl_stall) begin
            tail_ptr <= tail_ptr + countones(fifo_out);
        end
    end
end

    always @ ( posedge clk or posedge rst ) begin
    if(rst) begin
        entry_valid <= 0;
    end else begin
        entry_valid <= entry_valid_nxt;
    end
end

     // FIX I1: use a block-local loop variable, as in the reference.
     always@ (*) begin : proc_entry_valid
     integer i;
     if (ctrl_restore_pulse||ctrl_clear) begin
     entry_valid_nxt = 0;
     end else begin
     // FIX: preserve valid bits not changed by dequeue/enqueue.
     entry_valid_nxt = entry_valid;
     if (!ctrl_stall) begin
        for (i = 0; i < PORT_WIDTH; i = i + 1) begin
            entry_valid_nxt[tail_addr[i][IFQ_BITS-1:0]] = 1'b0;
        end
    end
    for (i = 0; i < IN_WIDTH; i = i + 1) begin
        if (fifo_in[i]) begin
            entry_valid_nxt[head_addr[i][IFQ_BITS-1:0]] = 1'b1;
        end
    end
end
end


    // FIX I1: keep this loop variable independent of the valid-state logic.
    always @(posedge clk or posedge rst)begin : proc_entry_data
    integer i;
        if(rst) begin
        for(i=0; i<IFQ_DEPTH; i=i+1) begin
            entry_pc     [i]    <=  0;
            entry_pc_next[i]    <=  0;
            entry_inst   [i]    <=  0;
        end
    end else begin
        if(ctrl_restore_pulse || ctrl_clear) begin
            for(i=0; i<IFQ_DEPTH; i=i+1) begin
                entry_pc     [i]    <=  0;
                entry_pc_next[i]    <=  0;
                entry_inst   [i]    <=  0;
            end
        end else begin
            // FIX I2: enumerate input lanes; IFQ_DEPTH would index past fifo_in/head_addr.
            for(i=0; i<IN_WIDTH; i=i+1) begin
            if(fifo_in[i]) begin
                    // FIX I3: copy the entire flattened input lane, not a single bit.
                    entry_pc     [head_addr[i][IFQ_BITS-1:0]]    <=  pc_i[i*PC_WIDTH +: PC_WIDTH];
                    entry_pc_next[head_addr[i][IFQ_BITS-1:0]]    <=  pc_next_i[i*PC_WIDTH +: PC_WIDTH];
                    entry_inst   [head_addr[i][IFQ_BITS-1:0]]    <=  inst_i[i*DATA_WIDTH +: DATA_WIDTH];
                end  
            end
        end
    end
end

    // FIX I4: every output lane is a full PC/instruction-width slice.
    generate
    for(nidx = 0; nidx < PORT_WIDTH; nidx = nidx+1) begin
        always@(*) begin
            if(ctrl_stall || ctrl_clear || ctrl_restore_pulse) begin
                have_inst[nidx] =   1'b0;
                pc[nidx*PC_WIDTH +: PC_WIDTH]        =   0;
                pc_next[nidx*PC_WIDTH +: PC_WIDTH]   =   0;
                inst[nidx*DATA_WIDTH +: DATA_WIDTH]      =   0;
            end else begin
                if(fifo_out[nidx]) begin
                    have_inst[nidx] =   1'b1;
                    pc[nidx*PC_WIDTH +: PC_WIDTH]        =   entry_pc[tail_addr[nidx][IFQ_BITS-1:0]];
                    pc_next[nidx*PC_WIDTH +: PC_WIDTH]   =   entry_pc_next[tail_addr[nidx][IFQ_BITS-1:0]];
                    inst[nidx*DATA_WIDTH +: DATA_WIDTH]      =   entry_inst[tail_addr[nidx][IFQ_BITS-1:0]];
                end else begin
                    have_inst[nidx] =   have_inst_i[fout_pos[nidx]];
                    pc[nidx*PC_WIDTH +: PC_WIDTH]        =   pc_i[fout_pos[nidx]*PC_WIDTH +: PC_WIDTH];
                    pc_next[nidx*PC_WIDTH +: PC_WIDTH]   =   pc_next_i[fout_pos[nidx]*PC_WIDTH +: PC_WIDTH];
                    inst[nidx*DATA_WIDTH +: DATA_WIDTH]      =   inst_i[fout_pos[nidx]*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end
    end
endgenerate

endmodule


