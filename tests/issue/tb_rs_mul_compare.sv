import config_pkg::*;

// Compare the translated Verilog against independent, unmodified reference logic.
module rs_mul_compare_probe #(
    parameter P=2, E=8, D=3
) (input logic clk, output logic done);
    localparam W=$clog2(E), WB=4, FU=5;
    logic rst_n=0, flush_i=0, walk_i=0, rob_stall_i=0;
    logic [AGE_W-1:0] restore_age_bound_i=0;
    logic [P-1:0] disp_valid_i=0, disp_valid_raw_i=0;
    rs_entry_t [P-1:0] disp_entry_i;
    logic [P-1:0] disp_prs1_rdy_i=0, disp_prs2_rdy_i=0;
    logic [WB-1:0][PRF_IDX_W-1:0] wb_prd_i=0;
    logic [WB-1:0] wb_valid_i=0;
    logic [FU-1:0][PRF_IDX_W-1:0] is_prd_i=0;
    logic [FU-1:0] is_valid_i=0;
    logic fu_ready_i=0;
    logic [W-1:0] resp_isid_i=0;
    logic resp_valid_i=0, resp_issued_i=0;
    wire full_dut, full_ref, valid_dut, valid_ref;
    wire [$bits(rs_entry_t)-1:0] entry_dut;
    rs_entry_t entry_ref;
    wire [W-1:0] index_dut, index_ref;
    integer cycle, lane, p, q, serial=60;
    integer alloc_seen=0, issue_seen=0, fail_seen=0, wb_seen=0, early_seen=0;
    integer empty_alloc_seen=0;
    logic pending=0;
    logic [W-1:0] pending_idx=0;
    reg [31:0] rng=32'h913bc071 + P*17 + E*3 + D;
    function automatic [31:0] random_word;
        begin
            rng=rng*32'd1664525+32'd1013904223;
            random_word=rng;
        end
    endfunction

    rs_mul_queue #(.ENTRY_NUM(E), .PORT_WIDTH(P), .WAKE_DELAY(D),
        .WB_PORT_NUM(WB), .FU_NUM(FU)) dut (
        .clk(clk), .rst_n(rst_n), .flush_i(flush_i), .walk_i(walk_i),
        .restore_age_bound_i(restore_age_bound_i), .rob_stall_i(rob_stall_i),
        .disp_valid_i(disp_valid_i), .disp_valid_raw_i(disp_valid_raw_i),
        .disp_entry_i(disp_entry_i), .disp_prs1_rdy_i(disp_prs1_rdy_i),
        .disp_prs2_rdy_i(disp_prs2_rdy_i), .rs_full_o(full_dut),
        .wb_prd_i(wb_prd_i), .wb_valid_i(wb_valid_i),
        .is_prd_i(is_prd_i), .is_valid_i(is_valid_i), .fu_ready_i(fu_ready_i),
        .issue_valid_o(valid_dut), .issue_entry_o(entry_dut), .is_iqid_o(index_dut),
        .resp_isid_i(resp_isid_i), .resp_valid_i(resp_valid_i), .resp_issued_i(resp_issued_i));
    rs_mul_queue_reference #(.ENTRY_NUM(E), .PORT_WIDTH(P), .WAKE_DELAY(D),
        .WB_PORT_NUM(WB), .FU_NUM(FU)) ref_dut (
        .clk(clk), .rst_n(rst_n), .flush_i(flush_i), .walk_i(walk_i),
        .restore_age_bound_i(restore_age_bound_i), .rob_stall_i(rob_stall_i),
        .disp_valid_i(disp_valid_i), .disp_valid_raw_i(disp_valid_raw_i),
        .disp_entry_i(disp_entry_i), .disp_prs1_rdy_i(disp_prs1_rdy_i),
        .disp_prs2_rdy_i(disp_prs2_rdy_i), .rs_full_o(full_ref),
        .wb_prd_i(wb_prd_i), .wb_valid_i(wb_valid_i),
        .is_prd_i(is_prd_i), .is_valid_i(is_valid_i), .fu_ready_i(fu_ready_i),
        .issue_valid_o(valid_ref), .issue_entry_o(entry_ref), .is_iqid_o(index_ref),
        .resp_isid_i(resp_isid_i), .resp_valid_i(resp_valid_i), .resp_issued_i(resp_issued_i));

    task check_equal;
        integer n;
        begin
            if ({full_dut,valid_dut,entry_dut,index_dut} !==
                {full_ref,valid_ref,entry_ref,index_ref})
                $fatal(1,"MUL output mismatch P=%0d E=%0d D=%0d cycle=%0d",P,E,D,cycle);
            if ({dut.state_q,dut.state_d,dut.free_q,dut.issued_q,dut.rdy_q,
                 dut.issue_elig_vec,dut.alloc_fire,dut.free_cnt,dut.disp_match_cnt} !==
                {ref_dut.state_q,ref_dut.state_d,ref_dut.free_q,ref_dut.issued_q,ref_dut.rdy_q,
                 ref_dut.issue_elig_vec,ref_dut.alloc_fire,ref_dut.free_cnt,ref_dut.disp_match_cnt})
                $fatal(1,"MUL state mismatch P=%0d E=%0d D=%0d cycle=%0d",P,E,D,cycle);
            for (n=0;n<E;n=n+1) begin
                if (dut.entry_q[n] !== ref_dut.entry_q[n] ||
                    dut.prs1_ready_q[n] !== ref_dut.prs1_ready_q[n] ||
                    dut.prs2_ready_q[n] !== ref_dut.prs2_ready_q[n])
                    $fatal(1,"MUL entry mismatch P=%0d E=%0d D=%0d cycle=%0d slot=%0d",P,E,D,cycle,n);
            end
            for (n=0;n<P;n=n+1)
                if (dut.alloc_idx[n] !== ref_dut.alloc_idx[n])
                    $fatal(1,"MUL allocation mismatch cycle=%0d lane=%0d",cycle,n);
        end
    endtask

    initial begin
        done=0;
        disp_entry_i='0;
        repeat (2) @(negedge clk);
        rst_n=1;
        for (cycle=0;cycle<600;cycle=cycle+1) begin
            @(negedge clk);
            // Periodic flush keeps live ages inside the valid ring comparison window.
            flush_i=(cycle%12==11);
            walk_i=(cycle%12==8 || cycle%12==9);
            rob_stall_i=(cycle%12==7);
            restore_age_bound_i=AGE_W'(serial-2);
            fu_ready_i=(cycle%12>1);
            resp_valid_i=pending && !flush_i;
            resp_isid_i=pending_idx;
            resp_issued_i=(cycle%7!=4);
            disp_valid_i=0;
            disp_valid_raw_i=0;
            disp_prs1_rdy_i=0;
            disp_prs2_rdy_i=0;
            for (lane=0;lane<P;lane=lane+1) begin
                disp_entry_i[lane]='0;
                disp_entry_i[lane].v=1;
                disp_entry_i[lane].control.rob_idx=AGE_W'(serial);
                serial=serial+1;
                disp_entry_i[lane].control.prs1=PRF_IDX_W'(random_word());
                disp_entry_i[lane].control.prs2=PRF_IDX_W'(random_word());
                disp_entry_i[lane].control.prs1_v=1;
                disp_entry_i[lane].control.prs2_v=(lane%2==0);
                disp_entry_i[lane].control.prd=PRF_IDX_W'(serial+11);
                disp_entry_i[lane].control.prd_v=1;
                disp_entry_i[lane].payload_ram.futype=(cycle%5==4 && lane==0) ? FU_MEM : FU_MUL;
                disp_entry_i[lane].payload_ram.pc=32'h80000000+serial*4;
                disp_valid_raw_i[lane]=(cycle%12<6);
                disp_valid_i[lane]=disp_valid_raw_i[lane] && !walk_i && !rob_stall_i;
                disp_prs1_rdy_i[lane]=(cycle%3==0);
                disp_prs2_rdy_i[lane]=(cycle%2==0);
            end
            wb_valid_i=0;
            is_valid_i=0;
            for (p=0;p<WB;p=p+1) wb_prd_i[p]=PRF_IDX_W'(random_word());
            for (p=0;p<FU;p=p+1) is_prd_i[p]=PRF_IDX_W'(random_word());
            // Aim broadcasts at actual waiting operands, rotating through every bus lane.
            for (q=0;q<E;q=q+1) begin
                if (ref_dut.entry_q[q].v && (q+cycle)%3==0) begin
                    p=(q+cycle)%FU;
                    is_valid_i[p]=1;
                    is_prd_i[p]=ref_dut.entry_q[q].control.prs1;
                    early_seen=early_seen+1;
                end
                if (ref_dut.entry_q[q].v && (q+cycle)%4==0) begin
                    p=(q+cycle)%WB;
                    wb_valid_i[p]=1;
                    wb_prd_i[p]=(cycle%2) ? ref_dut.entry_q[q].control.prs1 : ref_dut.entry_q[q].control.prs2;
                    wb_seen=wb_seen+1;
                end
            end
            #1;
            check_equal();
            for (lane=0;lane<P;lane=lane+1) begin
                if (ref_dut.alloc_fire[lane]) begin
                    alloc_seen=alloc_seen+1;
                    if (!disp_prs1_rdy_i[lane]) empty_alloc_seen=empty_alloc_seen+1;
                end
            end
            if (valid_ref) issue_seen=issue_seen+1;
            if (resp_valid_i && !resp_issued_i) fail_seen=fail_seen+1;
            pending=valid_ref;
            pending_idx=index_ref;
            @(posedge clk);
            #1;
            check_equal();
        end
        if (!alloc_seen || !issue_seen || !fail_seen || !wb_seen || !early_seen || !empty_alloc_seen)
            $fatal(1,"Insufficient scenario coverage P=%0d E=%0d D=%0d",P,E,D);
        $display("MUL_PROBE_PASS P=%0d E=%0d D=%0d cycles=600 alloc=%0d issue=%0d retry=%0d wb=%0d early=%0d notready_alloc=%0d",
                 P,E,D,alloc_seen,issue_seen,fail_seen,wb_seen,early_seen,empty_alloc_seen);
        done=1;
    end
endmodule

module tb_rs_mul_compare;
    logic clk=0;
    always #5 clk=~clk;
    wire done0,done1,done2;
    rs_mul_compare_probe #(.P(2),.E(8),.D(3)) p0(clk,done0);
    rs_mul_compare_probe #(.P(4),.E(8),.D(3)) p1(clk,done1);
    rs_mul_compare_probe #(.P(2),.E(4),.D(1)) p2(clk,done2);
    initial begin
        wait(done0 && done1 && done2);
        $display("RS_MUL_REFERENCE_COMPARE_PASS");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1,"MUL comparison timeout");
    end
endmodule
