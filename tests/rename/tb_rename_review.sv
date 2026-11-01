// Reference-comparison regression. Run scripts/check_rename.ps1.
// DUT files are compiled as Verilog; only this testbench and the reference use SV.
import config_pkg::*;

module rat_review_probe #(parameter P=2) (input logic clk, output logic done);
    localparam PORT_WIDTH=P, RT_WIDTH=P, WK_WIDTH=P;
    logic rst;
    integer cycle, lane;
    reg [31:0] rng = 32'hf08b39c1 + P;
    function automatic [31:0] next_rand;
        begin rng = rng * 32'd1664525 + 32'd1013904223; next_rand=rng; end
    endfunction
    logic [PORT_WIDTH-1:0] have_inst;
    logic [PORT_WIDTH-1:0][4:0] rs1;
    logic [PORT_WIDTH-1:0][4:0] rs2;
    logic [PORT_WIDTH-1:0] rs1r;
    logic [PORT_WIDTH-1:0] rs2r;
    logic [PORT_WIDTH-1:0][4:0] rd;
    logic [PORT_WIDTH-1:0] rdv;
    logic [PORT_WIDTH-1:0] freelist_valid;
    logic [PORT_WIDTH-1:0][PRD_WIDTH-1:0] freelist_prd;
    logic [PORT_WIDTH-1:0] wk_valid;
    logic [PORT_WIDTH-1:0][4:0] wk_rd;
    logic [PORT_WIDTH-1:0][PRD_WIDTH-1:0] wk_prd;
    logic [PORT_WIDTH-1:0][PRD_WIDTH-1:0] wk_pprd;
    logic [PORT_WIDTH-1:0] rt_grant;
    logic [PORT_WIDTH-1:0] rt_regw;
    logic [PORT_WIDTH-1:0][4:0] rt_rd;
    logic [PORT_WIDTH-1:0][PRD_WIDTH-1:0] rt_prd;
    logic [PORT_WIDTH-1:0] cmp_grant;
    logic [PORT_WIDTH-1:0] cmp_regw;
    logic [PORT_WIDTH-1:0][4:0] cmp_rd;
    logic [PORT_WIDTH-1:0][PRD_WIDTH-1:0] cmp_prd;
    logic [PORT_WIDTH-1:0] cmp_rollback_valid;
    logic [PORT_WIDTH-1:0] cmp_rollback_regw;
    logic [PORT_WIDTH-1:0][4:0] cmp_rollback_rd;
    logic [PORT_WIDTH-1:0][PRD_WIDTH-1:0] cmp_rollback_pprd;
    logic  restart;
    logic  ctrl_clear;
    logic  ctrl_restore;
    logic  ctrl_stall;
    wire [PORT_WIDTH-1:0] have_inst_o_dut;
    wire [PORT_WIDTH-1:0] have_inst_o_ref;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] prd_dut;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] prd_ref;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] pprd_dut;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] pprd_ref;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] prs1_dut;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] prs1_ref;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] prs2_dut;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] prs2_ref;
    wire [PORT_WIDTH-1:0] freelist_consume_dut;
    wire [PORT_WIDTH-1:0] freelist_consume_ref;
    wire  ctrl_stall_req_dut;
    wire  ctrl_stall_req_ref;
    wire  ctrl_error_req_dut;
    wire  ctrl_error_req_ref;
    rat #(.PORT_WIDTH(P)) dut (
        .clk(clk),
        .rst(rst),
        .have_inst(have_inst),
        .rs1(rs1),
        .rs2(rs2),
        .rs1r(rs1r),
        .rs2r(rs2r),
        .rd(rd),
        .rdv(rdv),
        .have_inst_o(have_inst_o_dut),
        .prd(prd_dut),
        .pprd(pprd_dut),
        .prs1(prs1_dut),
        .prs2(prs2_dut),
        .freelist_consume(freelist_consume_dut),
        .freelist_valid(freelist_valid),
        .freelist_prd(freelist_prd),
        .wk_valid(wk_valid),
        .wk_rd(wk_rd),
        .wk_prd(wk_prd),
        .wk_pprd(wk_pprd),
        .rt_grant(rt_grant),
        .rt_regw(rt_regw),
        .rt_rd(rt_rd),
        .rt_prd(rt_prd),
        .cmp_grant(cmp_grant),
        .cmp_regw(cmp_regw),
        .cmp_rd(cmp_rd),
        .cmp_prd(cmp_prd),
        .cmp_rollback_valid(cmp_rollback_valid),
        .cmp_rollback_regw(cmp_rollback_regw),
        .cmp_rollback_rd(cmp_rollback_rd),
        .cmp_rollback_pprd(cmp_rollback_pprd),
        .restart(restart),
        .ctrl_clear(ctrl_clear),
        .ctrl_restore(ctrl_restore),
        .ctrl_stall(ctrl_stall),
        .ctrl_stall_req(ctrl_stall_req_dut),
        .ctrl_error_req(ctrl_error_req_dut)
    );
    rat_reference #(.PORT_WIDTH(P)) golden (
        .clk(clk),
        .rst(rst),
        .have_inst(have_inst),
        .rs1(rs1),
        .rs2(rs2),
        .rs1r(rs1r),
        .rs2r(rs2r),
        .rd(rd),
        .rdv(rdv),
        .have_inst_o(have_inst_o_ref),
        .prd(prd_ref),
        .pprd(pprd_ref),
        .prs1(prs1_ref),
        .prs2(prs2_ref),
        .freelist_consume(freelist_consume_ref),
        .freelist_valid(freelist_valid),
        .freelist_prd(freelist_prd),
        .wk_valid(wk_valid),
        .wk_rd(wk_rd),
        .wk_prd(wk_prd),
        .wk_pprd(wk_pprd),
        .rt_grant(rt_grant),
        .rt_regw(rt_regw),
        .rt_rd(rt_rd),
        .rt_prd(rt_prd),
        .cmp_grant(cmp_grant),
        .cmp_regw(cmp_regw),
        .cmp_rd(cmp_rd),
        .cmp_prd(cmp_prd),
        .cmp_rollback_valid(cmp_rollback_valid),
        .cmp_rollback_regw(cmp_rollback_regw),
        .cmp_rollback_rd(cmp_rollback_rd),
        .cmp_rollback_pprd(cmp_rollback_pprd),
        .restart(restart),
        .ctrl_clear(ctrl_clear),
        .ctrl_restore(ctrl_restore),
        .ctrl_stall(ctrl_stall),
        .ctrl_stall_req(ctrl_stall_req_ref),
        .ctrl_error_req(ctrl_error_req_ref)
    );
    task automatic check_outputs;
        begin
            if (have_inst_o_dut !== have_inst_o_ref)
                $fatal(1, "rat P=%0d cycle=%0d have_inst_o: DUT=%h REF=%h", P, cycle, have_inst_o_dut, have_inst_o_ref);
            if (prd_dut !== prd_ref)
                $fatal(1, "rat P=%0d cycle=%0d prd: DUT=%h REF=%h", P, cycle, prd_dut, prd_ref);
            if (pprd_dut !== pprd_ref)
                $fatal(1, "rat P=%0d cycle=%0d pprd: DUT=%h REF=%h", P, cycle, pprd_dut, pprd_ref);
            if (prs1_dut !== prs1_ref)
                $fatal(1, "rat P=%0d cycle=%0d prs1: DUT=%h REF=%h", P, cycle, prs1_dut, prs1_ref);
            if (prs2_dut !== prs2_ref)
                $fatal(1, "rat P=%0d cycle=%0d prs2: DUT=%h REF=%h", P, cycle, prs2_dut, prs2_ref);
            if (freelist_consume_dut !== freelist_consume_ref)
                $fatal(1, "rat P=%0d cycle=%0d freelist_consume: DUT=%h REF=%h", P, cycle, freelist_consume_dut, freelist_consume_ref);
            if (ctrl_stall_req_dut !== ctrl_stall_req_ref)
                $fatal(1, "rat P=%0d cycle=%0d ctrl_stall_req: DUT=%h REF=%h", P, cycle, ctrl_stall_req_dut, ctrl_stall_req_ref);
            if (ctrl_error_req_dut !== ctrl_error_req_ref)
                $fatal(1, "rat P=%0d cycle=%0d ctrl_error_req: DUT=%h REF=%h", P, cycle, ctrl_error_req_dut, ctrl_error_req_ref);
        end
    endtask
    task automatic check_storage;
        integer j;
        begin
            if (dut.currState !== golden.currState) $fatal(1, "rat P=%0d cycle=%0d storage currState", P, cycle);
            if (dut.rat_readsrc !== golden.rat_readsrc) $fatal(1, "rat P=%0d cycle=%0d storage rat_readsrc", P, cycle);
            for (j=0; j<32; j=j+1) begin
                if (dut.rat_mem[j] !== golden.rat_mem[j]) $fatal(1, "rat P=%0d cycle=%0d rat_mem[%0d] DUT=%h REF=%h", P, cycle, j, dut.rat_mem[j], golden.rat_mem[j]);
                if (dut.commit_rat_mem[j] !== golden.commit_rat_mem[j]) $fatal(1, "rat P=%0d cycle=%0d commit_rat_mem[%0d] DUT=%h REF=%h", P, cycle, j, dut.commit_rat_mem[j], golden.commit_rat_mem[j]);
            end
        end
    endtask
    initial begin
        done=0; rst=1;
        have_inst='0;
        rs1='0;
        rs2='0;
        rs1r='0;
        rs2r='0;
        rd='0;
        rdv='0;
        freelist_valid='0;
        freelist_prd='0;
        wk_valid='0;
        wk_rd='0;
        wk_prd='0;
        wk_pprd='0;
        rt_grant='0;
        rt_regw='0;
        rt_rd='0;
        rt_prd='0;
        cmp_grant='0;
        cmp_regw='0;
        cmp_rd='0;
        cmp_prd='0;
        cmp_rollback_valid='0;
        cmp_rollback_regw='0;
        cmp_rollback_rd='0;
        cmp_rollback_pprd='0;
        restart='0;
        ctrl_clear='0;
        ctrl_restore='0;
        ctrl_stall='0;
        for (cycle=0; cycle<600; cycle=cycle+1) begin
            @(negedge clk);
            rst = (cycle==0) || ((cycle % 89)==0);
            have_inst=next_rand();
            rs1=next_rand();
            rs2=next_rand();
            rs1r=next_rand();
            rs2r=next_rand();
            rd=next_rand();
            rdv=next_rand();
            freelist_valid=next_rand();
            freelist_prd=next_rand();
            wk_valid=next_rand();
            wk_rd=next_rand();
            wk_prd=next_rand();
            wk_pprd=next_rand();
            rt_grant=next_rand();
            rt_regw=next_rand();
            rt_rd=next_rand();
            rt_prd=next_rand();
            cmp_grant=next_rand();
            cmp_regw=next_rand();
            cmp_rd=next_rand();
            cmp_prd=next_rand();
            cmp_rollback_valid=next_rand();
            cmp_rollback_regw=next_rand();
            cmp_rollback_rd=next_rand();
            cmp_rollback_pprd=next_rand();
            restart=next_rand();
            ctrl_clear=next_rand();
            ctrl_restore=next_rand();
            ctrl_stall=next_rand();
            have_inst=(1 << (next_rand() % (P+1))) - 1;
            wk_valid=(1 << (next_rand() % (P+1))) - 1;
            rt_grant=(1 << (next_rand() % (P+1))) - 1;
            cmp_grant=(1 << (next_rand() % (P+1))) - 1;
            cmp_rollback_valid=(1 << (next_rand() % (P+1))) - 1;
            freelist_valid = ((cycle%5)==0) ? ((1 << (next_rand()%(P+1)))-1) : '1;
            ctrl_clear=(next_rand()%23)==0;
            ctrl_restore=(cycle%17)<3;
            ctrl_stall=(cycle%19)<3;
            restart=(next_rand()%7)==0;
            if (cycle==1 || cycle==2) begin
                have_inst='1; rdv='1; freelist_valid='1;
                ctrl_clear=0; ctrl_restore=0; ctrl_stall=0; cmp_grant=0; cmp_rollback_valid=0;
                for (lane=0; lane<P; lane=lane+1) begin
                    rd[lane]=(cycle==2) ? 5 : (5+lane);
                    rs1[lane]=5; rs2[lane]=6;
                    freelist_prd[lane]=32+lane+P*(cycle-1);
                end
            end
            if (cycle==3) begin
                ctrl_clear=0; ctrl_restore=1; wk_valid='1;
                for (lane=0; lane<P; lane=lane+1) begin
                    wk_rd[lane]=5; wk_pprd[lane]=(lane==P-1) ? 5 : (40+lane);
                end
            end
            if (cycle==4) begin
                ctrl_clear=1; ctrl_restore=0; cmp_grant='1; cmp_regw='1; cmp_rollback_valid=0;
                for (lane=0; lane<P; lane=lane+1) begin cmp_rd[lane]=7; cmp_prd[lane]=48+lane; end
            end
            if (cycle==5) begin
                ctrl_clear=0; ctrl_restore=0; ctrl_stall=0; have_inst='1; rdv='1; freelist_valid='1; cmp_grant=0; cmp_rollback_valid=0;
                for (lane=0; lane<P; lane=lane+1) begin rd[lane]=7; rs1[lane]=7; rs2[lane]=7; freelist_prd[lane]=56+lane; end
            end
            #1; check_outputs();
            @(posedge clk); #1;
            check_storage(); check_outputs();
        end
        $display("PROBE_PASS rat P=%0d cycles=600", P);
        done=1;
    end
endmodule

module freelist_review_probe #(parameter P=2) (input logic clk, output logic done);
    localparam PORT_WIDTH=P, RT_WIDTH=P, WK_WIDTH=P;
    logic rst;
    integer cycle, lane;
    reg [31:0] rng = 32'hf08b39c1 + P;
    function automatic [31:0] next_rand;
        begin rng = rng * 32'd1664525 + 32'd1013904223; next_rand=rng; end
    endfunction
    logic [RT_WIDTH-1:0] rt_grant;
    logic [RT_WIDTH-1:0][PRD_WIDTH-1:0] rt_pprd;
    logic [RT_WIDTH-1:0] arch_grant;
    logic  hdsignal_walk;
    logic [WK_WIDTH-1:0] wk_valid;
    logic [WK_WIDTH-1:0][PRD_WIDTH-1:0] wk_prd;
    logic [PORT_WIDTH-1:0] freelist_consume;
    logic [RT_WIDTH-1:0] cmp_grant;
    logic [WK_WIDTH-1:0] cmp_rollback_valid;
    logic [WK_WIDTH-1:0][PRD_WIDTH-1:0] cmp_rollback_prd;
    logic  cmp_rollback_commit_valid;
    logic [PRD_WIDTH-1:0] cmp_rollback_commit_prd;
    logic  cmp_rollback_active;
    logic  ctrl_clear;
    wire [PORT_WIDTH-1:0] freelist_valid_dut;
    wire [PORT_WIDTH-1:0] freelist_valid_ref;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] freelist_prd_dut;
    wire [PORT_WIDTH-1:0][PRD_WIDTH-1:0] freelist_prd_ref;
    freelist #(.PORT_WIDTH(P), .RT_WIDTH(P), .WK_WIDTH(P)) dut (
        .clk(clk),
        .rst(rst),
        .rt_grant(rt_grant),
        .rt_pprd(rt_pprd),
        .arch_grant(arch_grant),
        .hdsignal_walk(hdsignal_walk),
        .wk_valid(wk_valid),
        .wk_prd(wk_prd),
        .freelist_consume(freelist_consume),
        .freelist_valid(freelist_valid_dut),
        .freelist_prd(freelist_prd_dut),
        .cmp_grant(cmp_grant),
        .cmp_rollback_valid(cmp_rollback_valid),
        .cmp_rollback_prd(cmp_rollback_prd),
        .cmp_rollback_commit_valid(cmp_rollback_commit_valid),
        .cmp_rollback_commit_prd(cmp_rollback_commit_prd),
        .cmp_rollback_active(cmp_rollback_active),
        .ctrl_clear(ctrl_clear)
    );
    freelist_reference #(.PORT_WIDTH(P), .RT_WIDTH(P), .WK_WIDTH(P)) golden (
        .clk(clk),
        .rst(rst),
        .rt_grant(rt_grant),
        .rt_pprd(rt_pprd),
        .arch_grant(arch_grant),
        .hdsignal_walk(hdsignal_walk),
        .wk_valid(wk_valid),
        .wk_prd(wk_prd),
        .freelist_consume(freelist_consume),
        .freelist_valid(freelist_valid_ref),
        .freelist_prd(freelist_prd_ref),
        .cmp_grant(cmp_grant),
        .cmp_rollback_valid(cmp_rollback_valid),
        .cmp_rollback_prd(cmp_rollback_prd),
        .cmp_rollback_commit_valid(cmp_rollback_commit_valid),
        .cmp_rollback_commit_prd(cmp_rollback_commit_prd),
        .cmp_rollback_active(cmp_rollback_active),
        .ctrl_clear(ctrl_clear)
    );
    task automatic check_outputs;
        begin
            if (freelist_valid_dut !== freelist_valid_ref)
                $fatal(1, "freelist P=%0d cycle=%0d freelist_valid: DUT=%h REF=%h", P, cycle, freelist_valid_dut, freelist_valid_ref);
            if (freelist_prd_dut !== freelist_prd_ref)
                $fatal(1, "freelist P=%0d cycle=%0d freelist_prd: DUT=%h REF=%h", P, cycle, freelist_prd_dut, freelist_prd_ref);
        end
    endtask
    task automatic check_storage;
        integer j;
        begin
            if (dut.head_ptr !== golden.head_ptr) $fatal(1, "freelist P=%0d cycle=%0d storage head_ptr", P, cycle);
            if (dut.tail_ptr !== golden.tail_ptr) $fatal(1, "freelist P=%0d cycle=%0d storage tail_ptr", P, cycle);
            if (dut.commit_ptr !== golden.commit_ptr) $fatal(1, "freelist P=%0d cycle=%0d storage commit_ptr", P, cycle);
            if (dut.arch_ptr !== golden.arch_ptr) $fatal(1, "freelist P=%0d cycle=%0d storage arch_ptr", P, cycle);
            if (dut.freelistv_mem !== golden.freelistv_mem) $fatal(1, "freelist P=%0d cycle=%0d storage freelistv_mem", P, cycle);
            if (dut.freelistv_commit_mem !== golden.freelistv_commit_mem) $fatal(1, "freelist P=%0d cycle=%0d storage freelistv_commit_mem", P, cycle);
            if (dut.freelistv_arch_mem !== golden.freelistv_arch_mem) $fatal(1, "freelist P=%0d cycle=%0d storage freelistv_arch_mem", P, cycle);
            if (dut.num_in !== golden.num_in) $fatal(1, "freelist P=%0d cycle=%0d storage num_in", P, cycle);
            if (dut.num_out !== golden.num_out) $fatal(1, "freelist P=%0d cycle=%0d storage num_out", P, cycle);
            for (j=0; j<ROB_DEPTH; j=j+1) begin
                if (dut.freelist_mem[j] !== golden.freelist_mem[j]) $fatal(1, "freelist P=%0d cycle=%0d freelist_mem[%0d] DUT=%h REF=%h", P, cycle, j, dut.freelist_mem[j], golden.freelist_mem[j]);
            end
        end
    endtask
    initial begin
        done=0; rst=1;
        rt_grant='0;
        rt_pprd='0;
        arch_grant='0;
        hdsignal_walk='0;
        wk_valid='0;
        wk_prd='0;
        freelist_consume='0;
        cmp_grant='0;
        cmp_rollback_valid='0;
        cmp_rollback_prd='0;
        cmp_rollback_commit_valid='0;
        cmp_rollback_commit_prd='0;
        cmp_rollback_active='0;
        ctrl_clear='0;
        for (cycle=0; cycle<600; cycle=cycle+1) begin
            @(negedge clk);
            rst = (cycle==0) || ((cycle % 89)==0);
            rt_grant=next_rand();
            rt_pprd=next_rand();
            arch_grant=next_rand();
            hdsignal_walk=next_rand();
            wk_valid=next_rand();
            wk_prd=next_rand();
            freelist_consume=next_rand();
            cmp_grant=next_rand();
            cmp_rollback_valid=next_rand();
            cmp_rollback_prd=next_rand();
            cmp_rollback_commit_valid=next_rand();
            cmp_rollback_commit_prd=next_rand();
            cmp_rollback_active=next_rand();
            ctrl_clear=next_rand();
            rt_grant=(1 << (next_rand() % (P+1))) - 1;
            arch_grant=(1 << (next_rand() % (P+1))) - 1;
            wk_valid=(1 << (next_rand() % (P+1))) - 1;
            freelist_consume=(1 << (next_rand() % (P+1))) - 1;
            cmp_grant=(1 << (next_rand() % (P+1))) - 1;
            cmp_rollback_valid=(1 << (next_rand() % (P+1))) - 1;
            if (ctrl_clear || hdsignal_walk) freelist_consume=0;
            ctrl_clear=(next_rand()%23)==0;
            hdsignal_walk=(cycle%17)<3;
            cmp_rollback_active=(cycle%37)<3;
            cmp_rollback_commit_valid=(cycle%37)==1;
            if (cycle==1) begin
                ctrl_clear=0; hdsignal_walk=0; freelist_consume='1; rt_grant=0; arch_grant=0; cmp_rollback_active=0;
            end
            if (cycle==2) begin
                ctrl_clear=0; hdsignal_walk=0; freelist_consume=0; rt_grant='1; arch_grant='1;
                for (lane=0; lane<P; lane=lane+1) rt_pprd[lane]=17+lane;
            end
            if (cycle==3) begin
                ctrl_clear=0; hdsignal_walk=1; freelist_consume=0; wk_valid='1; rt_grant=1;
                for (lane=0; lane<P; lane=lane+1) wk_prd[lane]=40+lane;
            end
            if (cycle==4) begin ctrl_clear=1; cmp_rollback_active=0; end
            if (cycle==5) begin ctrl_clear=1; cmp_rollback_active=1; cmp_rollback_commit_valid=1; end
            #1; check_outputs();
            @(posedge clk); #1;
            check_storage(); check_outputs();
        end
        $display("PROBE_PASS freelist P=%0d cycles=600", P);
        done=1;
    end
endmodule

module tb_rename_review;
    logic clk=0;
    wire [3:0] done;
    always #5 clk=~clk;
    rat_review_probe #(2) r2(clk,done[0]);
    rat_review_probe #(4) r4(clk,done[1]);
    freelist_review_probe #(2) f2(clk,done[2]);
    freelist_review_probe #(4) f4(clk,done[3]);
    initial begin wait (&done); $display("RENAME_REVIEW_PASS probes=4 cycles_per_probe=600"); $finish; end
    initial begin #100000; $fatal(1,"TIMEOUT"); end
endmodule
