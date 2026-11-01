`ifndef STRUCTURE_PKG_VH
`define STRUCTURE_PKG_VH
`include "config_pkg.vh"
// Same widths as the reference; IN_WIDTH is fetch width, PORT_WIDTH dispatch width.
`define PORT_WIDTH        2
`define IN_WIDTH          8
`define FU0WB_WIDTH       (`PORT_WIDTH)
`define FU1WB_WIDTH       1
`define FU2WB_WIDTH       (`PORT_WIDTH)
`define ROB_FU0WB_WIDTH   (`FU0WB_WIDTH + 2)
`define RD_WIDTH          (2 * `ROB_FU0WB_WIDTH + 2 * `FU1WB_WIDTH + 2 * `PORT_WIDTH)
`define RT_WIDTH          (`PORT_WIDTH)
`define WK_WIDTH          (`PORT_WIDTH)
`define DECODE_WIDTH_P    (`PORT_WIDTH)
`define ERROR_CODE_WIDTH  4
`define ISSUETOTAL_WIDTH  (`FU0WB_WIDTH + `FU1WB_WIDTH + 2)
`define WBTOTAL_WIDTH     (`FU0WB_WIDTH + `FU1WB_WIDTH + `PORT_WIDTH + 1 + 2)
`define MEM_FU_IDX        (`FU0WB_WIDTH)
`define MUL_FU_IDX        (`FU0WB_WIDTH + 1)
`define DIV_FU_IDX        (`FU0WB_WIDTH + 2)
`endif
