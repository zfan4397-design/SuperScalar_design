`ifndef CONFIG_PKG_VH
`define CONFIG_PKG_VH
// Verilog constants corresponding to lockstep-3.2/config_pkg.sv.
// Source commit: 8af31705bf8e6e6571a6361e0a0ab53e25656cb0.
`define INIT_ADDR        32'h8000_0000
`define PRD_WIDTH        6
`define LOG2_ROB_DEPTH   (`PRD_WIDTH)
`define ROB_DEPTH        (1 << `LOG2_ROB_DEPTH)
`define PC_WIDTH         32
`define DATA_WIDTH       32
`define STBF_WIDTH       5
`define ISSUE_WIDTH      3

`define BR_INFO_WIDTH    4
`define EQ               4'd0
`define NE               4'd1
`define LTU              4'd2
`define GEU              4'd3
`define LT               4'd6
`define GE               4'd7

`define BRTYPE_WIDTH     2
`define NBR              2'd0
`define MBR_DIRECT       2'd1
`define CBR_DIRECT       2'd2
`define MBR_INDIRECT     2'd3

`define REG_INFO_WIDTH   3
`define REGW_ALU         3'd0
`define REGW_PC          3'd2
`define REGW_CMP         3'd3
`define REGW_CSR         3'd4
`define REGW_EXTEND      3'd5
`define REGW_MEM_SIGNED  3'd6
`define REGW_MEM_UNSIGNED 3'd7

`define ALU_INFO_WIDTH   5
`define ALU_ADD          5'd0
`define ALU_SUB          5'd1
`define ALU_XOR          5'd2
`define ALU_OR           5'd3
`define ALU_AND          5'd4
`define ALU_SLL          5'd5
`define ALU_SRL          5'd6
`define ALU_SRA          5'd7
`define ALU_SLT          5'd8
`define ALU_SLTU         5'd9
`define ALU_MUL          5'd10
`define ALU_MULH         5'd11
`define ALU_MULHSU       5'd12
`define ALU_MULHU        5'd13
`define ALU_DIV          5'd14
`define ALU_DIVU         5'd15
`define ALU_REM          5'd16
`define ALU_REMU         5'd17

`define TYPE_WIDTH       3
`define RETIRE_NWR       3'd0
`define RETIRE_WR_ARF    3'd1
`define RETIRE_WR_MEM    3'd2

`define FU_TYPE_WIDTH    3
`define FU_NORMAL        3'd1
`define FU_MEM           3'd2
`define FU_BR            3'd3
`define FU_CSR           3'd4
`define FU_EXC           3'd5
`define FU_MUL           3'd6
`define FU_DIV           3'd7

`define ALU_SRCSEL_WIDTH 2
`define SRC1SEL_REGDATA  2'd0
`define SRC1SEL_PC       2'd1
`define SRC1SEL_ZIMM     2'd2
`define SRC2SEL_REGDATA  2'd0
`define SRC2SEL_EXTEND   2'd1

// Values 16..23 carry the upstream MMIO request encoding.
`define EXCPT_WIDTH             5
`define EXCPT_NOEX              5'd0
`define EXCPT_BRWRONG           5'd1
`define EXCPT_ILLEGAL_INST      5'd2
`define EXCPT_INVALID_CALCULATE 5'd3
`define EXCPT_INVALID_MEMR      5'd4
`define EXCPT_INVALID_MEMW      5'd5
`define EXCPT_CSR_ILLEGAL       5'd6
`define EXCPT_CSR_SIDE_EFFECT   5'd7
`define EXCPT_EBREAK            5'd8
`define EXCPT_ECALL             5'd9
`define EXCPT_MRET              5'd10
`define EXCPT_SRET              5'd11
`define EXCPT_URET              5'd12
`define EXCPT_MMIO_TRAN         5'd16

`define MEM_ERROR_WIDTH        2
`define ERROR_MEM_NERR         2'd0
`define ERROR_MEM_PAGEFAULT    2'd1
`define ERROR_MEM_INVALIDADDR  2'd2
`define ERROR_MEM_CROSSWORDVISIT 2'd3

`define WSTRB_WIDTH    4
`define WSTRB_SW       4'b1111
`define WSTRB_SB       4'b0001
`define WSTRB_SH       4'b0011
`define WSTRB_NONE     4'b0000
`define WSTRB_ALL      4'b1111

`define CSROP_WIDTH   3
`define CSROP_NCSR    3'd0
`define CSROP_CSRRW   3'd1
`define CSROP_CSRRS   3'd2
`define CSROP_CSRRC   3'd3
`define CSROP_CSRRWI  3'd4
`define CSROP_CSRRSI  3'd5
`define CSROP_CSRRCI  3'd6
`define CSROP_READ    3'd7
`define CSRADDR_WIDTH 12
`define ZIMM_WIDTH    5

`define PRIV_WIDTH    2
`define PRIV_U_MODE   2'd0
`define PRIV_S_MODE   2'd1
`define PRIV_M_MODE   2'd3

`define PRF_IDX_W     (`PRD_WIDTH)
`define AGE_W         (`PRD_WIDTH + 1)
`define XLEN          (`DATA_WIDTH)
`define CSR_ADDR_W    12
`define IQ_DEPTH      (1 << `ISSUE_WIDTH)

`define DRAM_ADDR_START  32'h8000_0000
`define DRAM_ADDR_END    32'h8013_FFFF
`define SW0_ADDR         32'h8020_0000
`define SW1_ADDR         32'h8020_0004
`define KEY_ADDR         32'h8020_0010
`define SEG_ADDR         32'h8020_0020
`define LED_ADDR         32'h8020_0040
`define CNT_ADDR         32'h8020_0050
`define INT_ADDR_START   32'h0000_0000
`define INT_ADDR_END     32'h0000_1000
`define TIMER_ADDR_START 32'h0200_0000
`define TIMER_ADDR_END   32'h0200_1000
`define LOG_ADDR_START   32'h0100_0000
`define LOG_ADDR_END     32'h0113_FFFF
`endif
