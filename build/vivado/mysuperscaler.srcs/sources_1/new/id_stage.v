`include "config_pkg.vh"
`include "payload_defs.vh"

module id_stage #(
    parameter DECODE_WIDTH_P = 4
) (
    input wire clk,
    input wire rst,

    input wire [DECODE_WIDTH_P*`PC_WIDTH-1:0] pc_i,
    input wire [DECODE_WIDTH_P-1:0] have_inst_i,
    input wire [DECODE_WIDTH_P*`PC_WIDTH-1:0] predictpc_i,
    input wire [DECODE_WIDTH_P*32-1:0] inst_i,

    output wire [DECODE_WIDTH_P-1:0] have_inst_o,
    output wire
        [DECODE_WIDTH_P*`RS_PAYLOAD_RAM_WIDTH-1:0] payload_o,

    output wire [DECODE_WIDTH_P*5-1:0] rs1_addr_o,
    output wire [DECODE_WIDTH_P*5-1:0] rs2_addr_o,
    output wire [DECODE_WIDTH_P*5-1:0] rd_addr_o,
    output wire [DECODE_WIDTH_P*12-1:0] csr_addr_o
);

    wire [DECODE_WIDTH_P*32-1:0] inst;

    genvar dcidx;
    genvar dk;

    generate
        for (dcidx = 0;
             dcidx < DECODE_WIDTH_P;
             dcidx = dcidx + 1) begin

            assign have_inst_o[dcidx] = have_inst_i[dcidx];

            assign inst[dcidx*32 +: 32] =
                inst_i[dcidx*32 +: 32];
        end
    endgenerate

    generate
        for (dk = 0; dk < DECODE_WIDTH_P; dk = dk + 1)
        begin : g_decoder

            decoder u_decoder (
                .instr_i (
                    inst[dk*32 +: 32]
                ),
                .pc_i (
                    pc_i[dk*`PC_WIDTH +: `PC_WIDTH]
                ),
                .next_pc_i (
                    predictpc_i[dk*`PC_WIDTH +: `PC_WIDTH]
                ),
                .payload_o (
                    payload_o[
                        dk*`RS_PAYLOAD_RAM_WIDTH
                        +: `RS_PAYLOAD_RAM_WIDTH
                    ]
                ),
                .rs1_addr_o (
                    rs1_addr_o[dk*5 +: 5]
                ),
                .rs2_addr_o (
                    rs2_addr_o[dk*5 +: 5]
                ),
                .csr_addr_o (
                    csr_addr_o[dk*12 +: 12]
                )
            );

            assign rd_addr_o[dk*5 +: 5] =
                payload_o[
                    dk*`RS_PAYLOAD_RAM_WIDTH
                    + `RS_PAYLOAD_RAM_RD_LSB
                    +: 5
                ];
        end
    endgenerate

endmodule