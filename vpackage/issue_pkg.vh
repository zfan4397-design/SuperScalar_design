`ifndef ISSUE_PKG_VH
`define ISSUE_PKG_VH
// Prefix replaces the original package scope (issue_pkg::STATE).
`define ISSUE_NORMAL 3'd0
`define ISSUE_RESTORE 3'd1
`define ISSUE_STALL 3'd2
`define ISSUE_CLEAR 3'd3
`define ISSUE_ERROR 3'd4
`define FU_ALU0 2'd0
`define FU_ALU1 2'd1
`define FU_LSU  2'd2
`endif
