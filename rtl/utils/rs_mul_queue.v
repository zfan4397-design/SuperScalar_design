// Verilog-2001 translation of superscalercore/vsrc/utils/rs_mul_queue.sv.
// Parameter, port, signal, function, process, branch and assignment order follow the reference.
// Packed structs/buses are flattened exactly as in the existing LSU translation.
// Shared age_matrix_arbiter is instantiated below, not duplicated in this file.
`include "config_pkg.vh"
`include "issue_pkg.vh"
`include "payload_defs.vh"

module rs_mul_queue #(
    parameter ENTRY_NUM      = `IQ_DEPTH,
    parameter WAKE_DELAY     = 3,
    parameter WB_PORT_NUM    = 4,
    parameter FU_NUM         = 5,
    parameter PRF_IDX_W      = `PRF_IDX_W,
    parameter AGE_W          = `AGE_W,
    parameter PORT_WIDTH     = 2,
    parameter ISSUE_W        = (ENTRY_NUM <= 1) ? 1 : $clog2(ENTRY_NUM),
    parameter LSU_FU_IDX     = 2,
    parameter MUL_FU_IDX     = 3,
    parameter DIV_FU_IDX     = 4
) (
    input wire                                    clk,
    input wire                                    rst_n,
    input wire                                    flush_i,
    input wire                                    walk_i,
    input wire [AGE_W-1:0]                        restore_age_bound_i,
    input wire                                    rob_stall_i,
    input wire [PORT_WIDTH-1:0]                   disp_valid_i,
    input wire [PORT_WIDTH-1:0]                   disp_valid_raw_i,
    input wire [PORT_WIDTH*`RS_ENTRY_WIDTH-1:0] disp_entry_i,
    input wire [PORT_WIDTH-1:0]                   disp_prs1_rdy_i,
    input wire [PORT_WIDTH-1:0]                   disp_prs2_rdy_i,
    output reg                                    rs_full_o,
    input wire [WB_PORT_NUM*PRF_IDX_W-1:0] wb_prd_i,
    input wire [WB_PORT_NUM-1:0]                 wb_valid_i,
    input wire [FU_NUM*PRF_IDX_W-1:0] is_prd_i,
    input wire [FU_NUM-1:0]                      is_valid_i,
    input wire                                    fu_ready_i,
    output reg                                    issue_valid_o,
    output reg [`RS_ENTRY_WIDTH-1:0] issue_entry_o,
    output reg [ISSUE_W-1:0]                      is_iqid_o,
    input wire [ISSUE_W-1:0]                      resp_isid_i,
    input wire                                    resp_valid_i,
    input wire                                    resp_issued_i
);

    localparam ENTRY_IDX_W = (ENTRY_NUM <= 1) ? 1 : $clog2(ENTRY_NUM);
    localparam COUNT_W     = $clog2(ENTRY_NUM + 1);

    // Packed rs_entry_t field offsets; syntax adaptation only.
    localparam RS_AGE_LSB = `RS_ENTRY_CONTROL_LSB + `RS_CONTROL_ROB_IDX_LSB;
    localparam RS_PRS1_LSB = `RS_ENTRY_CONTROL_LSB + `RS_CONTROL_PRS1_LSB;
    localparam RS_PRS1_V_BIT = `RS_ENTRY_CONTROL_LSB + `RS_CONTROL_PRS1_V_LSB;
    localparam RS_PRS2_LSB = `RS_ENTRY_CONTROL_LSB + `RS_CONTROL_PRS2_LSB;
    localparam RS_PRS2_V_BIT = `RS_ENTRY_CONTROL_LSB + `RS_CONTROL_PRS2_V_LSB;
    localparam RS_FUTYPE_LSB = `RS_ENTRY_PAYLOAD_RAM_LSB + `RS_PAYLOAD_RAM_FUTYPE_LSB;

    reg [2:0]                             state_q;
    reg [2:0]                             state_d;
    reg [ENTRY_NUM-1:0]                   free_q;
    reg [ENTRY_NUM-1:0]                   issued_q;
    reg [ENTRY_NUM-1:0]                   rdy_q;
    reg [ENTRY_NUM*AGE_W-1:0] age_vec;
    reg [ENTRY_NUM-1:0]                   valid_vec;
    reg [ENTRY_NUM-1:0]                   issue_elig_vec;
    wire [ENTRY_IDX_W-1:0]                 arb_issue_idx;
    wire                                   arb_issue_valid;
    reg [PORT_WIDTH-1:0]                  disp_match;
    reg [PORT_WIDTH-1:0]                  disp_need_match;
    reg [PORT_WIDTH-1:0]                  alloc_fire;
    reg [ENTRY_IDX_W-1:0] alloc_idx [PORT_WIDTH-1:0];
    reg                                   issue_fire;
    wire [ENTRY_IDX_W-1:0]                 issue_idx;
    reg                                   can_issue;
    wire                                   issue_kill;
    wire [ENTRY_IDX_W-1:0]                 resp_idx;
    reg [WAKE_DELAY-1:0]                  prs1_ready_q [0:ENTRY_NUM-1];
    reg [WAKE_DELAY-1:0]                  prs2_ready_q [0:ENTRY_NUM-1];
    reg [WAKE_DELAY-1:0]                  next_prs1;
    reg [WAKE_DELAY-1:0]                  next_prs2;
    reg [COUNT_W-1:0]                     free_cnt;
    reg [COUNT_W-1:0]                     disp_match_cnt;

    reg [`RS_ENTRY_WIDTH-1:0] entry_q [0:ENTRY_NUM-1];

    `include "fifoid_functions.vh"

    function automatic [WAKE_DELAY-1:0] shift_ready;
        input [WAKE_DELAY-1:0] ready_vec;
        reg [WAKE_DELAY-1:0] next_vec;
        integer t;
        begin
            next_vec = ready_vec;
            for (t = 0; t < WAKE_DELAY-1; t = t + 1) begin
                next_vec[t] = ready_vec[t+1];
            end
            next_vec[WAKE_DELAY-1] = ready_vec[WAKE_DELAY-1];
            shift_ready = next_vec;
        end
    endfunction

    function automatic [WAKE_DELAY-1:0] fu_wake_mask;
        input integer fu_idx;
        reg [WAKE_DELAY-1:0] mask;
        begin
            mask = {WAKE_DELAY{1'b1}};
            if (fu_idx == DIV_FU_IDX) begin
                mask = {WAKE_DELAY{1'b0}};
            end else if (fu_idx == MUL_FU_IDX) begin
                mask = 0;
                mask[WAKE_DELAY-1] = 1'b1;
            end else if (fu_idx == LSU_FU_IDX) begin
                mask = {WAKE_DELAY{1'b1}};
                mask[0] = 1'b0;
            end
            fu_wake_mask = mask;
        end
    endfunction

    assign issue_kill = resp_valid_i && !resp_issued_i;
    assign resp_idx   = resp_isid_i[ENTRY_IDX_W-1:0];
    assign issue_idx  = arb_issue_idx;

    always @(posedge clk or negedge rst_n) begin : proc_1
        if (!rst_n) begin
            state_q <= `ISSUE_CLEAR;
        end else begin
            state_q <= state_d;
        end
    end

    always @* begin : proc_2
        state_d = state_q;
        case (state_q)
            `ISSUE_NORMAL: begin
                if (flush_i) begin
                    state_d = `ISSUE_CLEAR;
                end else if (walk_i) begin
                    state_d = `ISSUE_RESTORE;
                end else if (rob_stall_i) begin
                    state_d = `ISSUE_STALL;
                end
            end
            `ISSUE_RESTORE: begin
                if (!walk_i) begin
                    state_d = `ISSUE_NORMAL;
                end
            end
            `ISSUE_STALL: begin
                if (flush_i) begin
                    state_d = `ISSUE_CLEAR;
                end else if (!rob_stall_i) begin
                    state_d = `ISSUE_NORMAL;
                end
            end
            `ISSUE_CLEAR: begin
                if (walk_i) begin
                    state_d = `ISSUE_RESTORE;
                end else begin
                    state_d = `ISSUE_NORMAL;
                end
            end
            default: begin
                state_d = `ISSUE_ERROR;
            end
        endcase
    end

    always @* begin : proc_3
        integer i;
        for (i = 0; i < PORT_WIDTH; i = i + 1) begin
            disp_match[i] = disp_valid_i[i]
                         && (disp_entry_i[i*`RS_ENTRY_WIDTH + RS_FUTYPE_LSB +: `FU_TYPE_WIDTH] == `FU_MUL)
                         && !walk_i
                         && !rob_stall_i;
            disp_need_match[i] = disp_valid_raw_i[i]
                              && (disp_entry_i[i*`RS_ENTRY_WIDTH + RS_FUTYPE_LSB +: `FU_TYPE_WIDTH] == `FU_MUL)
                              && !walk_i
                              && !rob_stall_i;
        end
    end

    always @* begin : proc_4
        integer i;
        free_cnt = 0;
        for (i = 0; i < ENTRY_NUM; i = i + 1) begin
            if (free_q[i]) begin
                free_cnt = free_cnt + 1'b1;
            end
        end
    end

    always @* begin : proc_5
        integer i;
        disp_match_cnt = 0;
        for (i = 0; i < PORT_WIDTH; i = i + 1) begin
            if (disp_need_match[i]) begin
                disp_match_cnt = disp_match_cnt + 1'b1;
            end
        end
        // Reference comment discusses demand-based backpressure; retain the comparison below.
        rs_full_o = (free_cnt < PORT_WIDTH);
    end

    always @* begin : proc_6
        integer i;
        integer j;
        reg [ENTRY_NUM-1:0] free_tmp;
        free_tmp = free_q;
        for (i = 0; i < PORT_WIDTH; i = i + 1) begin
            alloc_fire[i] = 1'b0;
            alloc_idx[i]  = 0;
            if (disp_match[i] && !rs_full_o) begin
                for (j = 0; j < ENTRY_NUM; j = j + 1) begin
                    if (!alloc_fire[i] && free_tmp[j]) begin
                        alloc_fire[i] = 1'b1;
                        alloc_idx[i]  = j;
                        free_tmp[j]   = 1'b0;
                    end
                end
            end
        end
    end

    always @* begin : proc_7
        integer i;
        for (i = 0; i < ENTRY_NUM; i = i + 1) begin
            rdy_q[i] = ((!entry_q[i][RS_PRS1_V_BIT]) || prs1_ready_q[i][0])
                    && ((!entry_q[i][RS_PRS2_V_BIT]) || prs2_ready_q[i][0]);
        end
    end

    always @* begin : proc_8
        integer i;
        for (i = 0; i < ENTRY_NUM; i = i + 1) begin
            age_vec[i*AGE_W +: AGE_W]        = entry_q[i][RS_AGE_LSB +: `AGE_W];
            valid_vec[i]      = entry_q[i][`RS_ENTRY_V_LSB];
            issue_elig_vec[i] = valid_vec[i]
                             && !issued_q[i]
                             && ((state_q == `ISSUE_NORMAL) || (state_q == `ISSUE_STALL))
                             && rdy_q[i];
        end
    end

    always @* begin : proc_9
        issue_fire    = 1'b0;
        issue_valid_o = 1'b0;
        issue_entry_o = 0;
        can_issue     = 1'b0;
        is_iqid_o     = {{(ISSUE_W-ENTRY_IDX_W){1'b0}}, issue_idx};
        if (arb_issue_valid && fu_ready_i) begin
            can_issue = issue_elig_vec[arb_issue_idx] && !issue_kill && !walk_i && !flush_i;
            if (can_issue) begin
                issue_fire    = 1'b1;
                issue_valid_o = 1'b1;
                issue_entry_o = entry_q[arb_issue_idx];
            end
        end
    end

    age_matrix_arbiter #(
        .ENTRY_NUM (ENTRY_NUM),
        .AGE_W     (AGE_W)
    ) u_age_matrix_arbiter (
        .valid_i   (issue_elig_vec),
        .age_i     (age_vec),
        .index_o   (arb_issue_idx),
        .valid_o   (arb_issue_valid)
    );

    integer i;
    always @(posedge clk or negedge rst_n) begin : proc_10
        if (!rst_n) begin
            free_q   <= {ENTRY_NUM{1'b1}};
            issued_q <= 0;
            for (i = 0; i < ENTRY_NUM; i = i + 1) begin
                entry_q[i] <= 0;
            end
        end else if (flush_i) begin
            free_q   <= {ENTRY_NUM{1'b1}};
            issued_q <= 0;
            for (i = 0; i < ENTRY_NUM; i = i + 1) begin
                entry_q[i][`RS_ENTRY_V_LSB] <= 1'b0;
            end
        end else if (walk_i) begin
            if (resp_valid_i) begin
                if (resp_issued_i) begin
                    entry_q[resp_idx][`RS_ENTRY_V_LSB] <= 1'b0;
                    free_q[resp_idx]    <= 1'b1;
                end else begin
                    issued_q[resp_idx]  <= 1'b0;
                end
            end
            for (i = 0; i < ENTRY_NUM; i = i + 1) begin
                if (entry_q[i][`RS_ENTRY_V_LSB] && fifoid_gt(entry_q[i][RS_AGE_LSB +: `AGE_W], restore_age_bound_i)) begin
                    entry_q[i][`RS_ENTRY_V_LSB] <= 1'b0;
                    free_q[i]    <= 1'b1;
                    issued_q[i]  <= 1'b0;
                end
            end
        end else begin
            if (resp_valid_i) begin
                if (resp_issued_i) begin
                    entry_q[resp_idx][`RS_ENTRY_V_LSB] <= 1'b0;
                    free_q[resp_idx]    <= 1'b1;
                end else begin
                    issued_q[resp_idx]  <= 1'b0;
                end
            end
            for (i = 0; i < PORT_WIDTH; i = i + 1) begin
                if (alloc_fire[i]) begin
                    free_q[alloc_idx[i]]    <= 1'b0;
                    entry_q[alloc_idx[i]]   <= disp_entry_i[i*`RS_ENTRY_WIDTH +: `RS_ENTRY_WIDTH];
                    entry_q[alloc_idx[i]][`RS_ENTRY_V_LSB] <= 1'b1;
                    issued_q[alloc_idx[i]]  <= 1'b0;
                end
            end
            if (issue_fire) begin
                issued_q[issue_idx] <= 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin : proc_11
        integer j;
        integer k;
        integer p;
        if (!rst_n || flush_i) begin
            for (j = 0; j < ENTRY_NUM; j = j + 1) begin
                prs1_ready_q[j] <= 0;
                prs2_ready_q[j] <= 0;
            end
        end else begin
            for (j = 0; j < ENTRY_NUM; j = j + 1) begin
                next_prs1 = shift_ready(prs1_ready_q[j]);
                next_prs2 = shift_ready(prs2_ready_q[j]);
                if (!entry_q[j][`RS_ENTRY_V_LSB]) begin
                    next_prs1 = 0;
                    next_prs2 = 0;
                end
                for (k = 0; k < PORT_WIDTH; k = k + 1) begin
                    if (alloc_fire[k] && (j == alloc_idx[k])) begin
                        next_prs1 = disp_prs1_rdy_i[k] ? {WAKE_DELAY{1'b1}} : {WAKE_DELAY{1'b0}};
                        next_prs2 = disp_prs2_rdy_i[k] ? {WAKE_DELAY{1'b1}} : {WAKE_DELAY{1'b0}};
                    end
                end
                if (entry_q[j][`RS_ENTRY_V_LSB]) begin
                    for (p = 0; p < WB_PORT_NUM; p = p + 1) begin
                        if (wb_valid_i[p]) begin
                            if (entry_q[j][RS_PRS1_V_BIT] && (wb_prd_i[p*PRF_IDX_W +: PRF_IDX_W] == entry_q[j][RS_PRS1_LSB +: `PRF_IDX_W])) begin
                                next_prs1 = {WAKE_DELAY{1'b1}};
                            end
                            if (entry_q[j][RS_PRS2_V_BIT] && (wb_prd_i[p*PRF_IDX_W +: PRF_IDX_W] == entry_q[j][RS_PRS2_LSB +: `PRF_IDX_W])) begin
                                next_prs2 = {WAKE_DELAY{1'b1}};
                            end
                        end
                    end
                end
                if (entry_q[j][`RS_ENTRY_V_LSB]) begin
                    for (p = 0; p < FU_NUM; p = p + 1) begin
                        if (is_valid_i[p]) begin
                            if (entry_q[j][RS_PRS1_V_BIT] && (is_prd_i[p*PRF_IDX_W +: PRF_IDX_W] == entry_q[j][RS_PRS1_LSB +: `PRF_IDX_W])) begin
                                next_prs1 = fu_wake_mask(p);
                            end
                            if (entry_q[j][RS_PRS2_V_BIT] && (is_prd_i[p*PRF_IDX_W +: PRF_IDX_W] == entry_q[j][RS_PRS2_LSB +: `PRF_IDX_W])) begin
                                next_prs2 = fu_wake_mask(p);
                            end
                        end
                    end
                end
                prs1_ready_q[j] <= next_prs1;
                prs2_ready_q[j] <= next_prs2;
            end
        end
    end

endmodule
