// Verilog implementation reviewed against the reference; see FIX R1/R2 markers.
// Reference: D:/zz/superscalercore/vsrc/utils/freelist.sv
// Keep reference ports, branch/loop order and reset behavior.
// Original control flow is retained. See docs/rename_review.md for review and validation.
// Packed multi-lane ports are flattened: lane i = bus[i*WIDTH +: WIDTH].
// Internal memories remain unpacked arrays. Lane 0 occupies the least significant bits.
`include "config_pkg.vh"
`include "rob_pkg.vh"

module freelist #(
    parameter   PORT_WIDTH  =   2,
    parameter   RT_WIDTH    =   2,
    parameter   WK_WIDTH    =   2
) (
    input           clk,
    input           rst,
    // Reference: freelist.sv:10
    input wire[RT_WIDTH-1:0]                  rt_grant,
    input wire [(RT_WIDTH)*(`PRD_WIDTH)-1:0] rt_pprd,
    // Core retirement advances the ordinary-flush boundary; comparison permits reclamation.
    input wire[RT_WIDTH-1:0]                  arch_grant,
    // Reference: freelist.sv:15
    input wire                                hdsignal_walk,
    input wire[WK_WIDTH-1:0]                  wk_valid,
    input wire [(WK_WIDTH)*(`PRD_WIDTH)-1:0] wk_prd,
    //to RAT
    input wire[PORT_WIDTH-1:0]                freelist_consume,
    output reg[PORT_WIDTH-1:0]                freelist_valid,
    output reg [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] freelist_prd,
    input wire[RT_WIDTH-1:0]                  cmp_grant,
    input wire[WK_WIDTH-1:0]                  cmp_rollback_valid,
    input wire [(WK_WIDTH)*(`PRD_WIDTH)-1:0] cmp_rollback_prd,
    input wire                                cmp_rollback_commit_valid,
    input wire[`PRD_WIDTH-1:0]                 cmp_rollback_commit_prd,
    input wire                                cmp_rollback_active,

    input wire                                ctrl_clear
);

reg [`LOG2_ROB_DEPTH-1:0]  head_ptr;
reg [`LOG2_ROB_DEPTH-1:0]  tail_ptr;
reg [`LOG2_ROB_DEPTH-1:0]  commit_ptr;
reg [`LOG2_ROB_DEPTH-1:0]  arch_ptr;

reg [`LOG2_ROB_DEPTH-1:0]  freelist_head_waddr[PORT_WIDTH-1:0];
reg [PORT_WIDTH-1:0]      freelist_head_wr;
reg [`PRD_WIDTH-1:0]       freelist_head_wprd[PORT_WIDTH-1:0];
reg [`LOG2_ROB_DEPTH-1:0]  freelist_tail_waddr[PORT_WIDTH-1:0];
reg [PORT_WIDTH-1:0]      freelist_tail_wr;
reg [`PRD_WIDTH-1:0]       freelist_tail_wprd[PORT_WIDTH-1:0];

reg [`LOG2_ROB_DEPTH-1:0]  head_addr[PORT_WIDTH-1:0];
reg [`LOG2_ROB_DEPTH-1:0]  tail_addr[PORT_WIDTH-1:0];
reg [`LOG2_ROB_DEPTH-1:0]  commit_addr[PORT_WIDTH-1:0];
reg [`LOG2_ROB_DEPTH-1:0]  arch_addr[PORT_WIDTH-1:0];
wire [`LOG2_ROB_DEPTH-1:0]  commit_rollback_head_addr;
wire [`LOG2_ROB_DEPTH-1:0]  commit_rollback_tail_addr;

wire [$clog2(RT_WIDTH):0]   rt_cnt;
wire [$clog2(RT_WIDTH):0]   arch_cnt;
wire [$clog2(PORT_WIDTH):0] wk_cnt;
wire [$clog2(PORT_WIDTH):0] cm_cnt;
wire [`LOG2_ROB_DEPTH-1:0]  commit_rollback_cnt;

reg [`PRD_WIDTH-1:0]   freelist_mem [`ROB_DEPTH-1:0];
reg [`ROB_DEPTH-1:0]   freelistv_mem;
reg [`ROB_DEPTH-1:0]   freelistv_commit_mem;
reg [`ROB_DEPTH-1:0]   freelistv_commit_mem_nxt;
reg [`ROB_DEPTH-1:0]   freelistv_lockstep_mem_nxt;
reg [`ROB_DEPTH-1:0]   freelistv_arch_mem;
reg [`ROB_DEPTH-1:0]   freelistv_arch_mem_nxt;

// Verilog replacement for $countones; widths match the original parameters.
localparam COUNT_WIDTH = (PORT_WIDTH > RT_WIDTH)
                      ? ((PORT_WIDTH > WK_WIDTH) ? PORT_WIDTH : WK_WIDTH)
                      : ((RT_WIDTH > WK_WIDTH) ? RT_WIDTH : WK_WIDTH);
function integer countones;
    input [COUNT_WIDTH-1:0] value;
    integer bit_index;
    begin
        countones = 0;
        for (bit_index = 0; bit_index < COUNT_WIDTH; bit_index = bit_index + 1)
            if (value[bit_index] === 1'b1)
                countones = countones + 1;
    end
endfunction

assign rt_cnt = countones(rt_grant);
assign arch_cnt = countones(arch_grant);
assign wk_cnt = countones(wk_valid);
assign cm_cnt = countones(freelist_consume);
assign commit_rollback_cnt =
    cmp_rollback_commit_valid ? 1'b1 : 1'b0;

assign commit_rollback_head_addr = head_ptr - 1'b1;

assign commit_rollback_tail_addr = commit_ptr - 1'b1;

always @ ( posedge clk or posedge rst ) begin : proc_1
    integer i;
    if(rst) begin
        head_ptr <= `ROB_DEPTH-32;
    end else if(ctrl_clear && cmp_rollback_active) begin
       head_ptr <= head_ptr - commit_rollback_cnt; 
    end else if(!(ctrl_clear && cmp_rollback_active)) begin
        head_ptr <= head_ptr + rt_cnt;
    end
end

always @ ( posedge clk or posedge rst ) begin : proc_2
    integer i;
    if(rst) begin
        tail_ptr <= 0;
    end else begin
        if(ctrl_clear) begin
            if(cmp_rollback_active) begin
                tail_ptr <= commit_ptr - commit_rollback_cnt;
            end else begin
                tail_ptr <= arch_ptr + arch_cnt;
            end
        end else if(hdsignal_walk) begin
            tail_ptr <= tail_ptr - wk_cnt;
        end else begin
           tail_ptr <= tail_ptr + cm_cnt;
        end
    end
end

always @( posedge clk or posedge rst ) begin : proc_3
    integer i;
    if(rst) begin
        commit_ptr <= 0;
    end else if(ctrl_clear && cmp_rollback_active) begin
        commit_ptr <= commit_ptr - commit_rollback_cnt;
    end else if(!(ctrl_clear && cmp_rollback_active)) begin
        commit_ptr <= commit_ptr + rt_cnt;
    end
end

always @( posedge clk or posedge rst ) begin : proc_4
    integer i;
    if(rst) begin
        arch_ptr <= 0;
    end else if(ctrl_clear && cmp_rollback_active) begin
       arch_ptr <= commit_ptr - commit_rollback_cnt; 
    end else begin
       arch_ptr <= arch_ptr + arch_cnt;
    end
end

genvar fidx;
generate
    for(fidx = 0; fidx<PORT_WIDTH; fidx = fidx+1) begin : gen_1
        always @* begin : proc_5
            integer i;
            freelist_head_wr[fidx]    = 1'b0;
            freelist_head_waddr[fidx] = head_addr[fidx];
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            freelist_head_wprd[fidx]  = rt_pprd[(fidx)*`PRD_WIDTH +: `PRD_WIDTH];
            freelist_tail_wr[fidx]    = 1'b0;
            freelist_tail_waddr[fidx] = tail_addr[fidx];
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            freelist_tail_wprd[fidx]  = wk_prd[(fidx)*`PRD_WIDTH +: `PRD_WIDTH];

            
            freelist_head_wr[fidx] = rt_grant[fidx];
            if(hdsignal_walk) begin
                freelist_tail_wr[fidx] = wk_valid[fidx];
            end
        end
    end
endgenerate

genvar hidx;
generate
    for(hidx=0; hidx<PORT_WIDTH; hidx=hidx+1) begin : gen_2
        always @* begin : proc_6
            integer i;
          head_addr[hidx] =
    head_ptr + countones(rt_grant[hidx:0]) - 1;
            commit_addr[hidx] = commit_ptr + hidx;
            arch_addr[hidx] = arch_ptr + hidx;
        end
    end
endgenerate

genvar tidx;
generate
    for(tidx=0; tidx<PORT_WIDTH; tidx=tidx+1) begin : gen_3
        always @* begin : proc_7
            integer i;
            if(!hdsignal_walk) begin
                tail_addr[tidx] = tail_ptr + tidx;
            end else begin
                tail_addr[tidx] = tail_ptr - tidx - 1;
            end
        end
    end
endgenerate

genvar ridx;
generate
    for(ridx=0; ridx<PORT_WIDTH; ridx=ridx+1) begin : gen_4
        always @* begin : proc_8
            integer i;
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            freelist_prd[(ridx)*`PRD_WIDTH +: `PRD_WIDTH] = freelist_mem[tail_addr[ridx]];
            freelist_valid[ridx] = freelistv_mem[tail_addr[ridx]];
        end
    end
endgenerate

always @ ( posedge clk or posedge rst ) begin : proc_9
    integer i;
    if(rst) begin
        for(i=0; i<`ROB_DEPTH-32; i=i+1) begin
            freelist_mem[i] <= i + 32;
            freelistv_mem[i] <= 1'b1;
        end
        for(i=`ROB_DEPTH-32; i<`ROB_DEPTH; i=i+1) begin
            freelist_mem[i] <= 0;
            freelistv_mem[i]<= 1'b0;
        end
    end
    else if(ctrl_clear) begin
        if(cmp_rollback_active) begin
            freelistv_mem <= freelistv_lockstep_mem_nxt;
        end else begin
             freelistv_mem <= freelistv_arch_mem_nxt;
        end
        if(cmp_rollback_active && cmp_rollback_commit_valid) begin
            freelist_mem[commit_rollback_tail_addr] <= cmp_rollback_commit_prd;
        end
        for(i=0; i<PORT_WIDTH; i=i+1) begin
            if(freelist_head_wr[i]) begin
                freelist_mem[freelist_head_waddr[i]] <= freelist_head_wprd[i];
            end
            if(freelist_tail_wr[i]) begin
                 freelist_mem[freelist_tail_waddr[i]] <= freelist_tail_wprd[i];
            end
        end
    end
    else begin
        for(i=0; i<PORT_WIDTH; i=i+1) begin
            if(freelist_head_wr[i]) begin
              freelist_mem[freelist_head_waddr[i]] <= freelist_head_wprd[i];
                freelistv_mem[freelist_head_waddr[i]]<= 1'b1;
            end
            if(freelist_tail_wr[i]) begin
                freelist_mem[freelist_tail_waddr[i]] <= freelist_tail_wprd[i];
                freelistv_mem[freelist_tail_waddr[i]]<= 1'b1;
            end
        end
        for(i=0; i<PORT_WIDTH; i=i+1) begin
            if(freelist_consume[i]) begin
               freelistv_mem[tail_addr[i]]<= 1'b0;
            end
        end
    end
end

always @( posedge clk or posedge rst ) begin : blockName
    integer i;
    if(rst) begin
        for(i=0; i<`ROB_DEPTH-32; i=i+1) begin
            freelistv_commit_mem[i] <= 1'b1;
            freelistv_arch_mem[i] <= 1'b1;
        end
        for(i=`ROB_DEPTH-32; i<`ROB_DEPTH; i=i+1) begin
            freelistv_commit_mem[i] <= 1'b0;
            freelistv_arch_mem[i] <= 1'b0;
        end
    end else if(ctrl_clear && cmp_rollback_active) begin
       freelistv_commit_mem <= freelistv_lockstep_mem_nxt;
        freelistv_arch_mem   <= freelistv_lockstep_mem_nxt;
    end else begin
        freelistv_commit_mem <= freelistv_commit_mem_nxt;
        freelistv_arch_mem   <= freelistv_arch_mem_nxt;
    end
end

always @* begin : proc_11
    integer i;
    freelistv_commit_mem_nxt = freelistv_commit_mem;
    for(i=0; i<PORT_WIDTH; i=i+1) begin
        if(rt_grant[i]) begin
             freelistv_commit_mem_nxt[head_addr[i]] = 1'b1;
        end
    end
    for(i=0; i<PORT_WIDTH; i=i+1) begin
        if(rt_grant[i]) begin
            freelistv_commit_mem_nxt[commit_addr[i]] = 1'b0;
        end
    end
end

always @(*) begin : proc_12
    integer i;
    freelistv_lockstep_mem_nxt = freelistv_commit_mem_nxt;
    if(cmp_rollback_commit_valid) begin
       freelistv_lockstep_mem_nxt[commit_rollback_head_addr] = 1'b0;
        freelistv_lockstep_mem_nxt[commit_rollback_tail_addr] = 1'b1;
    end
end

always @(*) begin : proc_13
    integer i;
    freelistv_arch_mem_nxt = freelistv_arch_mem;
    for(i=0; i<PORT_WIDTH; i=i+1) begin
        if(rt_grant[i]) begin
             freelistv_arch_mem_nxt[head_addr[i]] = 1'b1;
        end
    end
    for(i=0; i<PORT_WIDTH; i=i+1) begin
        if(arch_grant[i]) begin
            freelistv_arch_mem_nxt[arch_addr[i]] = 1'b0;
        end
    end
end

/* verilator lint_off WIDTHEXPAND */
reg [31:0] num_in;
reg [31:0] num_out;
always @ ( posedge clk or posedge rst ) begin : proc_14
    integer i;
    if(rst) begin
        num_in <= 0;
    end else begin
        if(hdsignal_walk) begin
            num_in <= num_in + wk_cnt + rt_cnt;
        end else begin
            num_in <= num_in + rt_cnt;
        end
    end
end

always @ ( posedge clk or posedge rst ) begin : proc_15
    integer i;
    if(rst) begin
        num_out <= 0;
    end else begin
        num_out <= num_out + cm_cnt;
    end
end
/* verilator lint_on WIDTHEXPAND */

endmodule
