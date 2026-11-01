`timescale 1ns / 1ps
`include "cpu_defs.vh"
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/13 19:37:09
// Design Name: 
// Module Name: pc_reg
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


module pc_reg(
    input clk,
    input rst,
    
    input redirect,
    input [`PC_WIDTH - 1:0] redirect_pc,
    
    input icache_busy,
    input ifq_full,
    input ctrl_stall,
    
    output reg [`PC_WIDTH - 1 : 0] pc,
    output reg have_inst
    );
    
    reg [`PC_WIDTH - 1 : 0] reg_pc;
    wire base_stall;

    assign base_stall = icache_busy | ifq_full | ctrl_stall;
    
    always@(posedge clk or posedge rst)begin
    if (rst) begin
        reg_pc <= `INIT_ADDR;
        end
     else if (redirect) begin
         reg_pc <= redirect_pc;
         end
      else if(!base_stall) begin
          reg_pc <= reg_pc + 4*`IN_WIDTH;
          end
    end
    
    always @(*) begin
    pc = reg_pc;
    have_inst = !(base_stall || redirect);
end

endmodule
