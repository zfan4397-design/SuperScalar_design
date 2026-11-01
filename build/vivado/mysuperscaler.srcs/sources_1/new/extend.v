`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/13 23:31:27
// Design Name: 
// Module Name: extend
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


module extend(
     input [24:0]		imm_i
	,input [2:0]		extend_op
	,input				extend_sign
	
	,output reg [31:0]	extend
    );
    reg [12:0] debug;


always@(*) begin
   case (extend_op)
       3'b000 : //I?????????
       begin
           extend[11:0] = imm_i[24:13];
           extend[31:12] = extend_sign ? (imm_i[24] ? 20'hfffff : 20'h0) : 20'h0;
        end
       
        3'b101 ://I????????
        begin 
           extend[4:0] = imm_i[17:13];
           extend[31:5] = 27'b0;
        end
        
        3'b001 ://S??????
        begin 
           extend[4:0] = imm_i[4:0];
           extend[11:5] = imm_i[24:18];
           extend[31:12] = extend_sign ? (imm_i[24] ? 20'hfffff : 20'h0) : 20'h0;
        end
         
        3'b010 ://B??????
        begin 
           extend[0] = 0;
           extend[11] = imm_i[0];
           extend[4:1] = imm_i[4:1];
           extend[10:5] = imm_i[23:18];
           extend[12] = imm_i[24];
           extend[31:13] = extend_sign ? (imm_i[24] ? 19'b1111111111111111111 : 19'b0) : 19'b0;
        end
         
        3'b011 ://U??????
        begin 
           extend[11:0] = 12'h000;
           extend[31:12] = imm_i[24:5];
          
        end
        
        3'b100 ://J??????
        begin 
           extend[0] = 0;
           extend[19:12] = imm_i[12:5];
           extend[11] = imm_i[13];
           extend[10:1] = imm_i[23:14];
           extend[20] = imm_i[24];
           extend[31:21] = extend_sign ? (imm_i[24] ? 11'b11111111111 :11'b0) :11'b0;
         end
         3'b110:
         begin
            extend[0] = 1'b0;
            extend[12:1] = imm_i[24:13];
            extend[31:13] = 'd0;
         end

         default://?????
         begin
            extend = 32'b0;
         end
   endcase
end
endmodule
