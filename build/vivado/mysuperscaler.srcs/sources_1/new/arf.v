`timescale 1ns / 1ps
// Complete Verilog translation of vsrc/utils/arf.sv.
// Reference port/process/condition/write ordering and low-port priority are retained.
// Lane p uses arf_rd[p*5 +: 5] and arf_wdata[p*DATA_WIDTH +: DATA_WIDTH].
`include "config_pkg.vh"
`include "retire_pkg.vh"

module arf #(
    parameter PORT_WIDTH    =   2
) (
    input wire                            clk,
    input wire                            rst,

    // retire_ctrl -> ARF
    input wire[PORT_WIDTH-1:0]                        arf_v,
    input wire[PORT_WIDTH*((4+1))-1:0]                   arf_rd,
    input wire[PORT_WIDTH*(`DATA_WIDTH)-1:0]        arf_wdata
);

    // 32 x 32-bit architectural registers
    reg [`DATA_WIDTH-1:0] regfile [0:31];

    // 写冲突掩码
    reg [PORT_WIDTH-1:0] write_ok;

    // ---------- 写冲突检测 ----------
    always @* begin : proc_1
        integer p;
        integer q;
        for(p = 0; p < PORT_WIDTH; p=p+1) begin
            write_ok[p] = arf_v[p];

            // 不能写 x0
            if (arf_rd[p*5 +: 5] == 5'd0)
                write_ok[p] = 1'b0;

            // 检查冲突（低端口优先）
            for (q = 0; q < p; q=q+1) begin
                if (arf_v[q] && (arf_rd[q*5 +: 5] == arf_rd[p*5 +: 5])) begin
                    write_ok[p] = 1'b0;   // 与更高优先级端口冲突，禁写
                end
            end
        end
    end

    // ---------- 寄存器写入 ----------
    integer i;
    always @(posedge clk or posedge rst) begin : proc_2
        integer p;
        if (rst) begin
            for (i=0; i<32; i=i+1)
                regfile[i] <= 0;
        end else begin
            for(p = 0; p < PORT_WIDTH; p=p+1) begin
                if (write_ok[p]) begin
                    regfile[ arf_rd[p*5 +: 5] ] <= arf_wdata[p*`DATA_WIDTH +: `DATA_WIDTH];
                end
            end
        end
    end

endmodule
