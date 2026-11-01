// Verilog implementation reviewed against the reference; see FIX R1/R2 markers.
// Reference: D:/zz/superscalercore/vsrc/utils/rat.sv
// Keep reference ports, branch/loop order and reset behavior.
// Original control flow is retained. See docs/rename_review.md for review and validation.
// Packed multi-lane ports are flattened: lane i = bus[i*WIDTH +: WIDTH].
// Internal memories remain unpacked arrays. Lane 0 occupies the least significant bits.
`include "config_pkg.vh"
`include "rat_pkg.vh"

module rat #(
    parameter PORT_WIDTH    =   2
) (
    input wire                    clk,
    input wire                    rst,
    // Reference: rat.sv:8
    input wire[PORT_WIDTH-1:0]            have_inst, // Reference: rat.sv:9
    input wire [(PORT_WIDTH)*5-1:0] rs1,
    input wire [(PORT_WIDTH)*5-1:0] rs2,
    input wire[PORT_WIDTH-1:0]            rs1r,
    input wire[PORT_WIDTH-1:0]            rs2r,
    input wire [(PORT_WIDTH)*5-1:0] rd,
    input wire[PORT_WIDTH-1:0]            rdv,

    output reg[PORT_WIDTH-1:0]            have_inst_o,
    output reg [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] prd,
    output reg [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] pprd,
    output reg [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] prs1,
    output reg [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] prs2,
    // Reference: rat.sv:22
    output reg[PORT_WIDTH-1:0]                    freelist_consume,
    input wire[PORT_WIDTH-1:0]                    freelist_valid,
    input wire [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] freelist_prd,
    // Reference: rat.sv:26
    input wire[PORT_WIDTH-1:0]                    wk_valid,
    input wire [(PORT_WIDTH)*5-1:0] wk_rd,
    input wire [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] wk_prd,
    input wire [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] wk_pprd,
    
    //retire port -> commit RAT
    input wire[PORT_WIDTH-1:0]                    rt_grant,
    input wire[PORT_WIDTH-1:0]                    rt_regw,
    input wire [(PORT_WIDTH)*5-1:0] rt_rd,
    input wire [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] rt_prd,
    input wire[PORT_WIDTH-1:0]                    cmp_grant,
    input wire[PORT_WIDTH-1:0]                    cmp_regw,
    input wire [(PORT_WIDTH)*5-1:0] cmp_rd,
    input wire [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] cmp_prd,
    input wire[PORT_WIDTH-1:0]                    cmp_rollback_valid,
    input wire[PORT_WIDTH-1:0]                    cmp_rollback_regw,
    input wire [(PORT_WIDTH)*5-1:0] cmp_rollback_rd,
    input wire [(PORT_WIDTH)*(`PRD_WIDTH)-1:0] cmp_rollback_pprd,

    // Reference: rat.sv:46
    input wire                            restart,
    input wire                            ctrl_clear,
    input wire                            ctrl_restore,
    input wire                            ctrl_stall,
    output reg                            ctrl_stall_req,
    output reg                            ctrl_error_req
);

(* ram_style = "distribute" *) reg[`PRD_WIDTH-1:0]    rat_mem[31:0];
(* ram_style = "distribute" *) reg[`PRD_WIDTH-1:0]    commit_rat_mem[31:0];
reg                   clear;
reg                   we;
reg                   hdsignal_walk;

reg[31:0]             rat_readsrc;

reg[4:0]              rat_waddr[PORT_WIDTH-1:0];
reg[PORT_WIDTH-1:0]   rat_wr;
reg[`PRD_WIDTH-1:0]    rat_wprd[PORT_WIDTH-1:0];

reg[4:0]              rat_we_waddr[PORT_WIDTH-1:0];
reg[PORT_WIDTH-1:0]   rat_we_wr;
reg[`PRD_WIDTH-1:0]    rat_we_wprd[PORT_WIDTH-1:0];

reg[4:0]              rat_wk_waddr[PORT_WIDTH-1:0];
reg[PORT_WIDTH-1:0]   rat_wk_wr;
reg[`PRD_WIDTH-1:0]    rat_wk_wprd[PORT_WIDTH-1:0];

reg [2:0] currState;
reg [2:0] nextState;

function signal_isnotvalid;
    input [PORT_WIDTH-1:0] sig;
    reg is_valid;
    begin
        is_valid = ((sig & (sig + 1)) == 0);
        signal_isnotvalid = !is_valid;
    end
endfunction

wire signal_error;
//assign signal_error = signal_isnotvalid(have_inst) | signal_isnotvalid(wk_valid);
assign signal_error = 1'b0;

always @ ( posedge clk or posedge rst  ) begin : proc_1
    integer i;
    if(rst) begin
        currState <= `RAT_NORMAL;
    end else begin
        currState <= nextState;
    end
end

always @(*) begin : proc_2
    integer i;
    nextState = `RAT_NORMAL;
    case(currState)
        `RAT_NORMAL: begin
            if(signal_error) begin
                nextState = `RAT_ERROR;
            end else if(ctrl_clear) begin
                 nextState = `RAT_CLEAR;
            end else if(ctrl_restore) begin
                 nextState = `RAT_RESTORE;
            end else if(ctrl_stall) begin
                nextState = `RAT_STALL; 
            end else begin
                 nextState = `RAT_NORMAL;
            end
        end
        `RAT_CLEAR: begin
           nextState = `RAT_NORMAL;
        end
        `RAT_STALL: begin
            if(ctrl_clear) begin
                nextState = `RAT_CLEAR;
            end else if(ctrl_stall) begin
                 nextState = `RAT_STALL;
            end else begin
                nextState = `RAT_NORMAL;
            end
        end
        `RAT_RESTORE: begin
            if(signal_error) begin
               nextState = `RAT_ERROR;
            end if(ctrl_clear) begin
                nextState = `RAT_CLEAR;
            end else if(ctrl_restore) begin
               nextState = `RAT_RESTORE;
            end else begin
                nextState = `RAT_NORMAL;
            end
        end
        `RAT_ERROR: begin
            if(restart) begin
                nextState = `RAT_NORMAL;
            end else begin
                nextState = `RAT_ERROR;
            end
        end
        default: begin
           nextState = `RAT_NORMAL;
        end
    endcase
end

always @* begin : proc_3
    integer i;
    ctrl_stall_req  = 1'b0;
    ctrl_error_req  = 1'b0;
    clear           = 1'b0;
    we              = 1'b1;
    freelist_consume= have_inst;
    hdsignal_walk   = 1'b0;
    case(currState)
        `RAT_NORMAL: begin
            if(signal_error) begin
                 we= 1'b0;
                freelist_consume= 1'b0;
            end else if(ctrl_clear) begin
               clear           = 1'b1;
                we              = 1'b0;
                freelist_consume= 1'b0;
            end else if(ctrl_restore) begin
                hdsignal_walk   = 1'b1;
                we              = 1'b1;
                freelist_consume= 1'b0;
            end else if(ctrl_stall) begin
                we              = 1'b0;
                freelist_consume= 1'b0;
            end else if(have_inst != (freelist_valid & have_inst)) begin
              we              = 1'b0;
                freelist_consume= 1'b0;
            end
        end
        `RAT_CLEAR: begin
        end
        `RAT_STALL: begin
            if(ctrl_clear) begin
                 clear           = 1'b1;
                we              = 1'b0;
                freelist_consume= 1'b0;
            end if(ctrl_stall) begin
                we              = 1'b0;
                freelist_consume= 1'b0;
            end else if(have_inst != (freelist_valid & have_inst)) begin
            we              = 1'b0;
                freelist_consume= 1'b0;
            end
        end
        `RAT_RESTORE: begin
            if(signal_error) begin
               we              = 1'b0;
                freelist_consume= 1'b0; 
            end if(ctrl_clear) begin
              clear           = 1'b1;
                we              = 1'b0;
                freelist_consume= 1'b0; 
            end else if(ctrl_restore) begin
               hdsignal_walk   = 1'b1;
                we              = 1'b1;
                freelist_consume= 1'b0;
            end
        end
        `RAT_ERROR: begin
            if(restart) begin
            end else begin
  ctrl_error_req  = 1'b1;
                we              = 1'b0;
                freelist_consume= 1'b0;
            end
        end
        default: begin
        end
    endcase
    if(!(&freelist_valid)) begin
       ctrl_stall_req  = 1'b1;
    end
end

always @* begin : proc_4
    integer i;
    have_inst_o     = freelist_consume;
end

genvar weidx;
generate
    for(weidx = 0; weidx < PORT_WIDTH; weidx = weidx+1) begin : gen_1
        always @* begin : proc_5
            integer i;
 rat_we_wr[weidx] = rdv[weidx] & have_inst[weidx];
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            rat_we_wprd[weidx] = freelist_prd[(weidx)*`PRD_WIDTH +: `PRD_WIDTH];
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            rat_we_waddr[weidx] = rd[(weidx)*5 +: 5];
            for(i = weidx+1; i<PORT_WIDTH; i=i+1) begin
                if((rd[(weidx)*5 +: 5]==rd[(i)*5 +: 5]) && rdv[weidx] && rdv[i] && have_inst[i]) begin
                    rat_we_wr[weidx] = 1'b0;
                    // FIX R1: Read/write the entire flattened lane, not a single bit.
                    // FIX R2: Restore the reference WAW data assignment; this is not an address write.
                    rat_we_wprd[weidx] = freelist_prd[(i)*`PRD_WIDTH +: `PRD_WIDTH];
                end
            end
        end
    end
endgenerate

genvar wkidx;
generate
    for(wkidx = 0; wkidx < PORT_WIDTH; wkidx = wkidx+1) begin : gen_2
        always @* begin : proc_6
            integer i;
rat_wk_wr[wkidx] = wk_valid[wkidx];
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            rat_wk_wprd[wkidx] = wk_pprd[(wkidx)*`PRD_WIDTH +: `PRD_WIDTH];
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            rat_wk_waddr[wkidx]= wk_rd[(wkidx)*5 +: 5];
            for(i = wkidx+1; i<PORT_WIDTH; i=i+1) begin
                if(wk_rd[(wkidx)*5 +: 5]==wk_rd[(i)*5 +: 5] && wk_valid[wkidx] && wk_valid[i]) begin
                   rat_wk_wr[wkidx] = 1'b0;
                    // FIX R1: Read/write the entire flattened lane, not a single bit.
                    rat_wk_wprd[wkidx] = wk_pprd[(wkidx)*`PRD_WIDTH +: `PRD_WIDTH];
                end
            end
        end
    end
endgenerate

genvar ridx;
generate
    for(ridx = 0; ridx < PORT_WIDTH; ridx=ridx+1) begin : gen_3
        always @(*) begin : proc_7
            integer i;
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            prs1[(ridx)*`PRD_WIDTH +: `PRD_WIDTH] = rat_readsrc[rs1[(ridx)*5 +: 5]] ? rat_mem[rs1[(ridx)*5 +: 5]] : commit_rat_mem[rs1[(ridx)*5 +: 5]];
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            prs2[(ridx)*`PRD_WIDTH +: `PRD_WIDTH] = rat_readsrc[rs2[(ridx)*5 +: 5]] ? rat_mem[rs2[(ridx)*5 +: 5]] : commit_rat_mem[rs2[(ridx)*5 +: 5]];
            // FIX R1: Read/write the entire flattened lane, not a single bit.
            prd[(ridx)*`PRD_WIDTH +: `PRD_WIDTH]  = freelist_prd[(ridx)*`PRD_WIDTH +: `PRD_WIDTH];
             // FIX R1: Read/write the entire flattened lane, not a single bit.
             pprd[(ridx)*`PRD_WIDTH +: `PRD_WIDTH] = rat_readsrc[rd[(ridx)*5 +: 5]] ? rat_mem[rd[(ridx)*5 +: 5]] : commit_rat_mem[rd[(ridx)*5 +: 5]];
            for(i = 0; i<ridx; i=i+1) begin
                if(rd[(i)*5 +: 5]==rs1[(ridx)*5 +: 5] && rdv[i]) begin
                  // FIX R1: Read/write the entire flattened lane, not a single bit.
                  prs1[(ridx)*`PRD_WIDTH +: `PRD_WIDTH] = freelist_prd[(i)*`PRD_WIDTH +: `PRD_WIDTH];
                end
            end
            for(i = 0; i<ridx; i=i+1) begin
                if(rd[(i)*5 +: 5]==rs2[(ridx)*5 +: 5] && rdv[i]) begin
                   // FIX R1: Read/write the entire flattened lane, not a single bit.
                   prs2[(ridx)*`PRD_WIDTH +: `PRD_WIDTH] = freelist_prd[(i)*`PRD_WIDTH +: `PRD_WIDTH];
                end
            end
            for(i = 0; i<ridx; i=i+1) begin
                if(rd[(i)*5 +: 5]==rd[(ridx)*5 +: 5] && rdv[i]) begin
                    // FIX R1: Read/write the entire flattened lane, not a single bit.
                    pprd[(ridx)*`PRD_WIDTH +: `PRD_WIDTH] = freelist_prd[(i)*`PRD_WIDTH +: `PRD_WIDTH];
                end
            end
        end
    end
endgenerate

genvar widx;
generate
    for(widx = 0; widx<PORT_WIDTH; widx=widx+1) begin : gen_4
        always @(*) begin : proc_8
            integer i;
            if(hdsignal_walk) begin
                 rat_wr[widx]    = rat_wk_wr[widx] & we;
                rat_waddr[widx] = rat_wk_waddr[widx];
                rat_wprd[widx]  = rat_wk_wprd[widx];
            end else begin
               rat_wr[widx]    = rat_we_wr[widx] & we;
                rat_waddr[widx] = rat_we_waddr[widx];
                rat_wprd[widx]  = rat_we_wprd[widx];
            end
        end
    end
endgenerate

always @ ( posedge clk or posedge rst ) begin : proc_9
    integer i;
    if(rst) begin
        for(i=0; i<32; i=i+1) begin
            rat_mem[i] <= i;
        end
    end else if(clear) begin
        for(i=0; i<32; i=i+1) begin
            rat_mem[i] <= commit_rat_mem[i];
        end
    end else begin
        for(i=0; i<PORT_WIDTH; i=i+1) begin
            if(rat_wr[i])begin
               rat_mem[rat_waddr[i]]<=rat_wprd[i];
                
                end
        end
    end
end

always @( posedge clk or posedge rst ) begin : proc_10
    integer i;
    if(rst || clear) begin
        rat_readsrc <= 0;
    end else begin
        for(i=0; i<PORT_WIDTH; i=i+1) begin
            if(rat_wr[i])begin
               rat_readsrc[rat_waddr[i]]<=1'b1;
                end
        end
    end
end

// commit rat
reg[4:0]              commit_rat_we_waddr[PORT_WIDTH-1:0];
reg[PORT_WIDTH-1:0]   commit_rat_we_wr;
reg[`PRD_WIDTH-1:0]    commit_rat_we_wprd[PORT_WIDTH-1:0];

generate
    for(weidx = 0; weidx < PORT_WIDTH; weidx = weidx+1) begin : gen_5
        always @* begin : proc_11
            integer i;
            if(|cmp_rollback_valid) begin
             commit_rat_we_wr[weidx] =
                    cmp_rollback_valid[weidx] & cmp_rollback_regw[weidx];
                // FIX R1: Read/write the entire flattened lane, not a single bit.
                commit_rat_we_wprd[weidx] = cmp_rollback_pprd[(weidx)*`PRD_WIDTH +: `PRD_WIDTH];
                // FIX R1: Read/write the entire flattened lane, not a single bit.
                commit_rat_we_waddr[weidx] = cmp_rollback_rd[(weidx)*5 +: 5];
       for(i = weidx+1; i<PORT_WIDTH; i=i+1) begin
                    if((cmp_rollback_rd[(weidx)*5 +: 5]==cmp_rollback_rd[(i)*5 +: 5]) &&
                        cmp_rollback_valid[weidx] && cmp_rollback_valid[i] &&
                        cmp_rollback_regw[weidx] && cmp_rollback_regw[i]) begin
                       commit_rat_we_wr[weidx] = 1'b0;
                        // FIX R1: Read/write the entire flattened lane, not a single bit.
                        commit_rat_we_wprd[weidx] = cmp_rollback_pprd[(i)*`PRD_WIDTH +: `PRD_WIDTH];
                        end
                end
            end else begin
                commit_rat_we_wr[weidx] = cmp_regw[weidx] & cmp_grant[weidx];
                // FIX R1: Read/write the entire flattened lane, not a single bit.
                commit_rat_we_wprd[weidx] = cmp_prd[(weidx)*`PRD_WIDTH +: `PRD_WIDTH];
                // FIX R1: Read/write the entire flattened lane, not a single bit.
                commit_rat_we_waddr[weidx] = cmp_rd[(weidx)*5 +: 5];
                for(i = weidx+1; i<PORT_WIDTH; i=i+1) begin
                    if((cmp_rd[(weidx)*5 +: 5]==cmp_rd[(i)*5 +: 5]) && cmp_regw[weidx] && cmp_regw[i] && cmp_grant[i]) begin
                      commit_rat_we_wr[weidx] = 1'b0;
                        // FIX R1: Read/write the entire flattened lane, not a single bit.
                        commit_rat_we_wprd[weidx] = cmp_prd[(i)*`PRD_WIDTH +: `PRD_WIDTH];
                    end
                end
            end
        end
    end
endgenerate

always @( posedge clk or posedge rst ) begin : proc_12
    integer i;
    if(rst) begin
        for(i=0; i<32; i=i+1) begin
            commit_rat_mem[i] <= i;
        end
    end else begin
        for(i=0; i<PORT_WIDTH; i=i+1) begin
            if(commit_rat_we_wr[i])
                begin
                commit_rat_mem[commit_rat_we_waddr[i]] <= commit_rat_we_wprd[i];
                end
        end
    end
end

endmodule
