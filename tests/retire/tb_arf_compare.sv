`timescale 1ns/1ps

module arf_compare_probe #(parameter P=2)(input logic clk, output logic done);
    logic rst=0;
    logic [P-1:0] arf_v=0;
    logic [P-1:0][4:0] arf_rd='0;
    logic [P-1:0][31:0] arf_wdata='0;
    logic [31:0] expected [0:31];
    logic [31:0] rng=32'h35cd07a1+P;
    integer cycle, p, r;
    bit found;

    arf #(.PORT_WIDTH(P)) dut (
        .clk(clk), .rst(rst), .arf_v(arf_v), .arf_rd(arf_rd), .arf_wdata(arf_wdata));
    arf_reference #(.PORT_WIDTH(P)) reference (
        .clk(clk), .rst(rst), .arf_v(arf_v), .arf_rd(arf_rd), .arf_wdata(arf_wdata));

    function automatic [31:0] random_word;
        begin
            rng=rng*32'd1664525+32'd1013904223;
            random_word=rng;
        end
    endfunction

    task clear_expected;
        integer n;
        begin
            for(n=0;n<32;n=n+1) expected[n]=0;
        end
    endtask

    task check_state;
        integer n;
        begin
            for(n=0;n<32;n=n+1) begin
                if(dut.regfile[n] !== reference.regfile[n])
                    $fatal(1,"ARF reference mismatch P=%0d cycle=%0d register=%0d",P,cycle,n);
                if(dut.regfile[n] !== expected[n])
                    $fatal(1,"ARF scoreboard mismatch P=%0d cycle=%0d register=%0d got=%h expected=%h",
                        P,cycle,n,dut.regfile[n],expected[n]);
            end
        end
    endtask

    initial begin
        done=0;
        cycle=-1;
        clear_expected();
        rst=1;
        #1;
        check_state();
        @(negedge clk);
        rst=0;
        for(cycle=0;cycle<200;cycle=cycle+1) begin
            @(negedge clk);
            arf_v=random_word();
            for(p=0;p<P;p=p+1) begin
                arf_rd[p]=random_word();
                arf_wdata[p]=random_word();
            end
            case(cycle)
                0: begin // Disabled writes must preserve reset contents.
                    arf_v='0;
                    for(p=0;p<P;p=p+1) begin arf_rd[p]=5; arf_wdata[p]='1; end
                end
                1: begin // Every port attempts to write x0.
                    arf_v='1;
                    for(p=0;p<P;p=p+1) begin arf_rd[p]=0; arf_wdata[p]=32'hffff0010+p; end
                end
                2: begin // Same destination: preserve reference low-port priority.
                    arf_v='1;
                    for(p=0;p<P;p=p+1) begin arf_rd[p]=5; arf_wdata[p]=32'h12340000+p; end
                end
                3: begin // All independent lanes must write the right data slice.
                    arf_v='1;
                    for(p=0;p<P;p=p+1) begin arf_rd[p]=p+1; arf_wdata[p]=32'h56780000+p; end
                end
                4: begin // Disabled port zero must not block active later ports.
                    arf_v='1; arf_v[0]=0;
                    for(p=0;p<P;p=p+1) begin arf_rd[p]=5; arf_wdata[p]=32'h9abc0000+p; end
                end
                5: begin
                    arf_v='0; arf_v[P-1]=1;
                    arf_rd[P-1]=31; arf_wdata[P-1]=32'hdeadcafe;
                end
                default: begin
                    if(cycle%7==0) begin
                        arf_v='1;
                        for(p=0;p<P;p=p+1) arf_rd[p]=11;
                    end
                end
            endcase
            @(posedge clk);
            // Independent model: for each architectural register choose the first active writer.
            for(r=1;r<32;r=r+1) begin
                found=0;
                for(p=0;p<P;p=p+1) begin
                    if(!found && arf_v[p] && arf_rd[p]==r) begin
                        expected[r]=arf_wdata[p];
                        found=1;
                    end
                end
            end
            #1;
            check_state();
            if(cycle==80) begin // Reset between clock edges must take effect immediately.
                #1;
                arf_v='0;
                rst=1;
                clear_expected();
                #1;
                check_state();
                @(negedge clk);
                rst=0;
            end
        end
        $display("ARF_PROBE_PASS P=%0d cycles=200",P);
        done=1;
    end
endmodule

module tb_arf_compare;
    logic clk=0;
    wire done2, done4;
    always #5 clk=~clk;
    arf_compare_probe #(.P(2)) p2(.clk(clk),.done(done2));
    arf_compare_probe #(.P(4)) p4(.clk(clk),.done(done4));
    initial begin
        wait(done2 && done4);
        $display("ARF_REFERENCE_AND_MODEL_PASS");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1,"ARF test TIMEOUT");
    end
endmodule
