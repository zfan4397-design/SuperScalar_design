`timescale 1ns / 1ps
// Exercise scaffold; core logic is intentionally unfinished.
// Reference: D:/zz/superscalercore/vsrc/utils/store_buffer.sv
// Preserve reference ports, signal/process/branch/assignment order and reset behavior.
// Packed lane ports are flattened; lane i occupies bus[i*WIDTH +: WIDTH].
// Resets, payload storage, direct wiring, conditions, loops and helper functions are supplied.
// Complete only the marked TODOs at their original positions.
`include "config_pkg.vh"


module store_buffer #(
    parameter PORT_WIDTH = 2
) (
    input wire                    clk,
    input wire                    rst,

    input wire[`PRD_WIDTH:0]       rob_fifonum,
    input wire[`DATA_WIDTH-1:0]    saddr,
    input wire[`DATA_WIDTH-1:0]    sdata,
    input wire[3:0]               swstrb,
    input wire                    sreq,
    output reg[`STBF_WIDTH:0]      stbf_id,
    output reg                    svalid,

    input wire[`DATA_WIDTH-1:0]    laddr,
    input wire[`PRD_WIDTH:0]       lrob_fifonum,
    output reg[`DATA_WIDTH-1:0]    ldata,
    output reg[3:0]               lmask,

    input wire[PORT_WIDTH-1:0]                    rt_stbf_grant,
    input wire[PORT_WIDTH*((`STBF_WIDTH+1))-1:0]      rt_stbf_id,
    output reg[PORT_WIDTH-1:0]                    rt_sreq,
    output reg[PORT_WIDTH*(`DATA_WIDTH)-1:0]    rt_saddr,
    output reg[PORT_WIDTH*(`DATA_WIDTH)-1:0]    rt_sdata,

    input wire[PORT_WIDTH-1:0]                    cmp_stbf_grant,
    input wire[PORT_WIDTH*((`STBF_WIDTH+1))-1:0]      cmp_stbf_id,

    input wire                    dcache_re,
    input wire                    dcache_busy,
    input wire                    dcache_wdone,
    output reg[`DATA_WIDTH-1:0]    dcache_waddr,
    output reg                    dcache_we,
    input wire                    dcache_we_resp,
    output reg[`DATA_WIDTH-1:0]    dcache_wdata,
    output reg[3:0]               dcache_wstrb,

    input wire                    ctrl_restore,
    input wire                    ctrl_clear,
    input wire                    lockstep_restore_pulse,
    input wire[`PRD_WIDTH:0]       lockstep_restore_flnum,
    input wire                    ctrl_stall,
    input wire[`PRD_WIDTH:0]       flnum,
    output wire                    full
);

localparam DEPTH = 1 << `STBF_WIDTH;

// Imported ROB-age helpers become module-local Verilog functions.
`include "fifoid_functions.vh"

function stbfid_gt;
    input [`STBF_WIDTH:0] a;
    input [`STBF_WIDTH:0] b;
    begin
    stbfid_gt = ( (a[`STBF_WIDTH] == b[`STBF_WIDTH]) ?
                      (a[`STBF_WIDTH-1:0] > b[`STBF_WIDTH-1:0]) :
                      (a[`STBF_WIDTH-1:0] < b[`STBF_WIDTH-1:0]) );
    
    end
endfunction

reg [`STBF_WIDTH:0]    head_ptr;
reg [`STBF_WIDTH:0]    tail_ptr;
reg [`STBF_WIDTH:0]    retire_ptr;
// FIX V1: plain Verilog requires entry_valid to be declared before its first use.
reg [DEPTH-1:0]        entry_valid;
wire                   raw_full;
wire                   tail_skip;
assign raw_full = entry_valid[head_ptr[`STBF_WIDTH-1:0]];
assign full = raw_full;
assign tail_skip = (tail_ptr != head_ptr) && !entry_valid[tail_ptr[`STBF_WIDTH-1:0]];

reg [`DATA_WIDTH-1:0]   entry_data   [DEPTH-1:0];
reg [`DATA_WIDTH-1:0]   entry_addr   [DEPTH-1:0];
reg [3:0]              entry_wstrb  [DEPTH-1:0];
reg [`STBF_WIDTH:0]     entry_sid    [DEPTH-1:0];
reg [DEPTH-1:0]        entry_complete;
reg [DEPTH-1:0]        entry_valid_nxt_ncl;
reg [DEPTH-1:0]        entry_valid_nxt;
reg [DEPTH-1:0]        entry_complete_nxt;
reg [`PRD_WIDTH:0]      entry_fnum   [DEPTH-1:0];

wire [DEPTH-1:0]        valid_vec;
wire [DEPTH-1:0]        valid_nxt_vec;
wire [`STBF_WIDTH:0]     idx_vec[DEPTH-1:0];
wire [`PRD_WIDTH:0]      restore_flnum;

assign restore_flnum = lockstep_restore_pulse ? lockstep_restore_flnum : flnum;

always @ ( posedge clk or posedge rst ) begin : proc_1
    if(rst) begin
        head_ptr <= 0;
    end else if(sreq && ~full && ~ctrl_stall) begin
        head_ptr <= head_ptr + 1;
    end
end
always @ ( posedge clk or posedge rst ) begin : proc_2
    if(rst) begin
        tail_ptr <= 0;
    end else if(dcache_we_resp || tail_skip) begin
        tail_ptr <= tail_ptr+1;
    end
end

always @ ( posedge clk or posedge rst ) begin : proc_3
    if(rst) begin
        retire_ptr <= 0;
    end else if(dcache_we_resp || tail_skip) begin
        retire_ptr <= retire_ptr + 1;
    end
end

always @* begin : proc_4
    integer i;
    entry_valid_nxt_ncl = entry_valid;
    entry_complete_nxt = entry_complete;
    if(dcache_we_resp) begin
       entry_valid_nxt_ncl[tail_ptr[`STBF_WIDTH-1:0]] = 1'b0;
    end
    if(ctrl_restore || lockstep_restore_pulse) begin
        for(i=0; i<DEPTH; i=i+1) begin
            if(fifoid_gt(entry_fnum[i], restore_flnum)) begin
                entry_valid_nxt_ncl[i] = 1'b0;
            end
        end
    end
    if(sreq && ~full && ~ctrl_stall) begin
        entry_valid_nxt_ncl[head_ptr[`STBF_WIDTH-1:0]] = 1'b1;
        entry_complete_nxt[head_ptr[`STBF_WIDTH-1:0]] = 1'b0;
    end
    for(i=0; i<PORT_WIDTH; i=i+1) begin
        if(cmp_stbf_grant[i]) begin
            if(entry_valid[cmp_stbf_id[i*(`STBF_WIDTH+1) +: `STBF_WIDTH]]
                && (entry_sid[cmp_stbf_id[i*(`STBF_WIDTH+1) +: `STBF_WIDTH]] == cmp_stbf_id[i*(`STBF_WIDTH+1) +: (`STBF_WIDTH+1)])) begin
                entry_complete_nxt[cmp_stbf_id[i*(`STBF_WIDTH+1) +: `STBF_WIDTH]] = 1'b1;
            end
        end
    end
end

always @* begin : proc_5
    if(ctrl_clear) begin
        entry_valid_nxt = entry_valid_nxt_ncl & entry_complete_nxt;
    end else begin
        entry_valid_nxt = entry_valid_nxt_ncl;
    end
end


genvar nidx;
generate
    for(nidx=0; nidx < DEPTH; nidx = nidx+1) begin : gen_nidx
        assign idx_vec[nidx] = (tail_ptr + nidx);
        assign valid_nxt_vec[nidx] = entry_valid_nxt[idx_vec[nidx][`STBF_WIDTH-1:0]];
        assign valid_vec[nidx]  =   entry_valid[idx_vec[nidx][`STBF_WIDTH-1:0]];
    end
endgenerate

always @ ( posedge clk) begin : proc_6
    if(sreq && ~full && ~ctrl_stall) begin
        entry_data [head_ptr[`STBF_WIDTH-1:0]] <= sdata;
        entry_addr [head_ptr[`STBF_WIDTH-1:0]] <= saddr;
        entry_wstrb[head_ptr[`STBF_WIDTH-1:0]] <= swstrb;
        entry_sid  [head_ptr[`STBF_WIDTH-1:0]] <= head_ptr;
        entry_fnum [head_ptr[`STBF_WIDTH-1:0]] <= rob_fifonum;
    end
end

always @ ( posedge clk or posedge rst ) begin : proc_7
    if(rst) begin
        entry_valid <= 0;
        entry_complete <= 0;
    end else if(~ctrl_stall || ctrl_restore || ctrl_clear || lockstep_restore_pulse) begin
        entry_valid <= entry_valid_nxt;
        entry_complete <= entry_complete_nxt;
    end
end


always @* begin : proc_8
    stbf_id = head_ptr;
   svalid  = sreq && !full && !ctrl_stall; 
end


reg [7:0]     merge_byte  [3:0];
genvar midx;
generate
    for(midx = 0; midx < 4; midx=midx+1) begin : gen_midx
        always @* begin : proc_9
            integer i;
            merge_byte[midx] = 0;
            lmask[midx]      = 1'b0;
            for(i=0; i<DEPTH; i=i+1) begin
                if(valid_vec[i]
                    && fifoid_lt(entry_fnum[idx_vec[i][`STBF_WIDTH-1:0]], lrob_fifonum)
                    && (laddr == entry_addr[idx_vec[i][`STBF_WIDTH-1:0]])
                    && entry_wstrb[idx_vec[i][`STBF_WIDTH-1:0]][midx]) begin
                    merge_byte[midx] = entry_data[idx_vec[i][`STBF_WIDTH-1:0]][midx*8+7:midx*8];
                    lmask[midx] = 1'b1;
                end
            end
        end
    end
endgenerate

always @* begin : proc_10
    ldata = {merge_byte[3], merge_byte[2], merge_byte[1], merge_byte[0]};
end


genvar ridx;
generate
    for(ridx=0; ridx<PORT_WIDTH; ridx=ridx+1) begin : gen_ridx
        always @* begin : proc_11
            rt_sreq[ridx]  = rt_stbf_grant[ridx];
            rt_saddr[ridx*`DATA_WIDTH +: `DATA_WIDTH] = entry_addr[rt_stbf_id[ridx*(`STBF_WIDTH+1) +: `STBF_WIDTH]];
            rt_sdata[ridx*`DATA_WIDTH +: `DATA_WIDTH] = entry_data[rt_stbf_id[ridx*(`STBF_WIDTH+1) +: `STBF_WIDTH]];
        end
    end
endgenerate


always @* begin : proc_12
    dcache_waddr = entry_addr[retire_ptr[`STBF_WIDTH-1:0]];
    dcache_wdata = entry_data[retire_ptr[`STBF_WIDTH-1:0]];
    dcache_we    = entry_valid[retire_ptr[`STBF_WIDTH-1:0]] & entry_complete[retire_ptr[`STBF_WIDTH-1:0]];
    dcache_wstrb = entry_wstrb[retire_ptr[`STBF_WIDTH-1:0]];
end

endmodule
