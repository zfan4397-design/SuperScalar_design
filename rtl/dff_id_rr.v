`include "config_pkg.vh"
`include "structure_pkg.vh"
`include "payload_defs.vh"

module dff_id_rr (
    input wire clk,
    input wire rst,

    input wire ctrl_clear,
    input wire ctrl_stall,
    input wire ctrl_restore,
    input wire [`PRD_WIDTH:0] flnum,

    input wire [`DECODE_WIDTH_P-1:0] i_have_inst,
    input wire
        [`DECODE_WIDTH_P*`RS_PAYLOAD_RAM_WIDTH-1:0] i_payload,

    input wire [`DECODE_WIDTH_P*5-1:0] i_rs1_addr,
    input wire [`DECODE_WIDTH_P*5-1:0] i_rs2_addr,
    input wire [`DECODE_WIDTH_P*5-1:0] i_rd_addr,
    input wire [`DECODE_WIDTH_P*12-1:0] i_csr_addr,

    output reg [`DECODE_WIDTH_P-1:0] o_have_inst,
    output reg
        [`DECODE_WIDTH_P*`RS_PAYLOAD_RAM_WIDTH-1:0] o_payload,

    output reg [`DECODE_WIDTH_P*5-1:0] o_rs1_addr,
    output reg [`DECODE_WIDTH_P*5-1:0] o_rs2_addr,
    output reg [`DECODE_WIDTH_P*5-1:0] o_rd_addr,
    output reg [`DECODE_WIDTH_P*12-1:0] o_csr_addr
);

    reg [`DECODE_WIDTH_P-1:0] reg_have_inst;
    reg [`DECODE_WIDTH_P*`RS_PAYLOAD_RAM_WIDTH-1:0]
        reg_payload;

    reg [`DECODE_WIDTH_P*5-1:0] reg_rs1_addr;
    reg [`DECODE_WIDTH_P*5-1:0] reg_rs2_addr;
    reg [`DECODE_WIDTH_P*5-1:0] reg_rd_addr;
    reg [`DECODE_WIDTH_P*12-1:0] reg_csr_addr;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_have_inst <= {`DECODE_WIDTH_P{1'b0}};
            reg_payload   <=
                {(`DECODE_WIDTH_P*`RS_PAYLOAD_RAM_WIDTH){1'b0}};
            reg_rs1_addr  <= {(`DECODE_WIDTH_P*5){1'b0}};
            reg_rs2_addr  <= {(`DECODE_WIDTH_P*5){1'b0}};
            reg_rd_addr   <= {(`DECODE_WIDTH_P*5){1'b0}};
            reg_csr_addr  <= {(`DECODE_WIDTH_P*12){1'b0}};
        end
        else if (ctrl_clear || ctrl_restore) begin
            reg_have_inst <= {`DECODE_WIDTH_P{1'b0}};
            reg_payload   <=
                {(`DECODE_WIDTH_P*`RS_PAYLOAD_RAM_WIDTH){1'b0}};
            reg_rs1_addr  <= {(`DECODE_WIDTH_P*5){1'b0}};
            reg_rs2_addr  <= {(`DECODE_WIDTH_P*5){1'b0}};
            reg_rd_addr   <= {(`DECODE_WIDTH_P*5){1'b0}};
            reg_csr_addr  <= {(`DECODE_WIDTH_P*12){1'b0}};
        end
        else if (!ctrl_stall) begin
            reg_have_inst <= i_have_inst;
            reg_payload   <= i_payload;
            reg_rs1_addr  <= i_rs1_addr;
            reg_rs2_addr  <= i_rs2_addr;
            reg_rd_addr   <= i_rd_addr;
            reg_csr_addr  <= i_csr_addr;
        end
    end

    always @(*) begin
        o_have_inst =
            reg_have_inst & {`DECODE_WIDTH_P{~ctrl_stall}};
        o_payload   = reg_payload;
        o_rs1_addr  = reg_rs1_addr;
        o_rs2_addr  = reg_rs2_addr;
        o_rd_addr   = reg_rd_addr;
        o_csr_addr  = reg_csr_addr;
    end

endmodule