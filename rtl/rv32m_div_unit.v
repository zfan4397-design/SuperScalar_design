module rv32m_div_unit #(
parameter integer XLEN = 32
) (
    input  wire clk,
    input  wire rst,
    input  wire flush_i,
    input  wire req_valid_i,
    output wire req_ready_o,
    input  wire [1:0] req_op_i,
    input  wire [XLEN-1:0] req_rs1_i,
    input  wire [XLEN-1:0] req_rs2_i,
    
    output wire resp_valid_o,
    input  wire resp_ready_i,
    output wire [XLEN-1:0] resp_result_o
    );

    localparam [1:0] OP_DIV  = 2'b00;
    localparam [1:0] OP_DIVU = 2'b01;
    localparam [1:0] OP_REM  = 2'b10;
    localparam [1:0] OP_REMU = 2'b11;

    localparam [1:0] ST_IDLE = 2'b00;
    localparam [1:0] ST_RUN  = 2'b01;
    localparam [1:0] ST_OUT  = 2'b10;

    localparam [XLEN-1:0] ZERO_WORD = 0;
    localparam [XLEN-1:0] ONE_WORD  = {{(XLEN-1){1'b0}}, 1'b1};
    localparam [XLEN-1:0] MIN_INT   = {1'b1, {(XLEN-1){1'b0}}};
    localparam [XLEN-1:0] ALL_ONE   = {XLEN{1'b1}};
    
    //寄存器
    reg [1:0] state_r;
    reg [1:0] op_r;
    reg quot_neg_r;//商是否取负
    reg rem_neg_r;//余数是否取负
    reg [XLEN-1:0] divisor_r;
    reg [XLEN-1:0] quot_r;//复用寄存器。它开始存被除数，运算过程中同时保存“尚未处理的被除数位”和“已经生成的商位”，最后才全部变成商。
    reg [XLEN:0] rem_r;
    reg [$clog2(XLEN+1)-1:0] iter_cnt_r;//剩余迭代次数
    reg [XLEN-1:0] result_r;

    reg req_is_signed;
    reg req_is_quot;
    wire req_div_by_zero;
    wire req_signed_overflow;
    reg [XLEN-1:0] req_dividend_abs;
    reg [XLEN-1:0] req_divisor_abs;
    wire req_quot_neg;
    wire req_rem_neg;
    reg [XLEN-1:0] req_special_result;
    wire [XLEN:0] run_rem_shift;
    wire [XLEN:0] run_divisor_ext;
    wire [XLEN+1:0] run_sub_ext;
    wire run_qbit;
    wire [XLEN:0] run_rem_next;
    wire [XLEN-1:0] run_quot_next;
    wire [XLEN-1:0] run_quot_fixed;
    wire [XLEN-1:0] run_rem_mag;
    wire [XLEN-1:0] run_rem_fixed;
    reg [XLEN-1:0] run_final_result;

    always @(*) begin
        req_is_signed = 1'b0;
        req_is_quot   = 1'b0;
        case (req_op_i)
            OP_DIV: begin
                req_is_signed = 1'b1;
                req_is_quot   = 1'b1;
            end
            OP_DIVU: begin
                req_is_signed = 1'b0;
                req_is_quot   = 1'b1;
            end
            OP_REM: begin
                req_is_signed = 1'b1;
                req_is_quot   = 1'b0;
            end
            OP_REMU: begin
                req_is_signed = 1'b0;
                req_is_quot   = 1'b0;
            end
            default: begin
                req_is_signed = 1'b0;
                req_is_quot   = 1'b1;
            end
        endcase
    end

    assign req_div_by_zero     = (req_rs2_i == ZERO_WORD);
    assign req_signed_overflow = req_is_signed && (req_rs1_i == MIN_INT) && (req_rs2_i == ALL_ONE);//溢出：最小数/-1会溢出

    always @(*) begin
        req_dividend_abs = req_rs1_i;
        req_divisor_abs  = req_rs2_i;
        if (req_is_signed && req_rs1_i[XLEN-1]) begin//有符号数+最高位为1=负数
            req_dividend_abs = ~req_rs1_i + ONE_WORD;
        end
        if (req_is_signed && req_rs2_i[XLEN-1]) begin
            req_divisor_abs = ~req_rs2_i + ONE_WORD;
        end
    end

    assign req_quot_neg = req_is_signed && (req_rs1_i[XLEN-1] ^ req_rs2_i[XLEN-1]);  // 商的符号：被除数与除数异号则为负
    assign req_rem_neg  = req_is_signed && req_rs1_i[XLEN-1];

    always @(*) begin
        req_special_result = ZERO_WORD;
        if (req_div_by_zero) begin
            if (req_is_quot) begin  // 除零：商为全 1（-1），余数为被除数
                req_special_result = ALL_ONE;
            end else begin
                req_special_result = req_rs1_i;
            end
        end else if (req_signed_overflow) begin
            if (req_is_quot) begin // MIN_INT / -1：商为 MIN_INT，余数为 0
                req_special_result = MIN_INT;
            end else begin
                req_special_result = ZERO_WORD;
            end
        end
    end
    
     // 恢复余数迭代逻辑（
    assign run_rem_shift   = {rem_r[XLEN-1:0], quot_r[XLEN-1]}; // 将下一位被除数移入余数: {当前余数, 当前quot_r的最高位};
    assign run_divisor_ext = {1'b0, divisor_r};// 除数零扩展对齐位宽
    assign run_sub_ext     = {1'b0, run_rem_shift} - {1'b0, run_divisor_ext};//试减结果 = 临时余数 - 除数
    assign run_qbit        = ~run_sub_ext[XLEN+1];//临时余数 ≥ 除数，可以减---减法最高位为0
    assign run_rem_next    = run_qbit ? run_sub_ext[XLEN:0] : run_rem_shift;//选择新余数：能减：使用减法结果; 不能减：保留试减之前的临时余数。
    assign run_quot_next   = {quot_r[XLEN-2:0], run_qbit};//把本位商填入 quot_r 的最低位:{当前quot_r剩下的位, 新商位};
    assign run_quot_fixed  = quot_neg_r ? (~run_quot_next + ONE_WORD) : run_quot_next;// 符号修正：若商/余数应为负，则对其绝对值取负
    assign run_rem_mag     = run_rem_next[XLEN-1:0];// 余数幅度（最多 XLEN 位）
    assign run_rem_fixed   = rem_neg_r ? (~run_rem_mag + ONE_WORD) : run_rem_mag;

    always @(*) begin
        case (op_r)
            OP_DIV, OP_DIVU: run_final_result = run_quot_fixed;
            OP_REM, OP_REMU: run_final_result = run_rem_fixed;
            default:         run_final_result = ZERO_WORD;
        endcase
    end

    assign req_ready_o   = (state_r == ST_IDLE);
    assign resp_valid_o  = (state_r == ST_OUT);
    assign resp_result_o = result_r;

    always @(posedge clk) begin
        if (rst) begin
            state_r     <= ST_IDLE;
            op_r        <= 0;
            quot_neg_r  <= 1'b0;
            rem_neg_r   <= 1'b0;
            divisor_r   <= 0;
            quot_r      <= 0;
            rem_r       <= 0;
            iter_cnt_r  <= 0;
            result_r    <= 0;
        end else if (flush_i) begin
            state_r     <= ST_IDLE;
            op_r        <= 0;
            quot_neg_r  <= 1'b0;
            rem_neg_r   <= 1'b0;
            divisor_r   <= 0;
            quot_r      <= 0;
            rem_r       <= 0;
            iter_cnt_r  <= 0;
            result_r    <= 0;
        end else begin
            case (state_r)
                ST_IDLE: begin
                    if (req_valid_i) begin
                        if (req_div_by_zero || req_signed_overflow) begin
                            result_r <= req_special_result;
                            state_r  <= ST_OUT;
                        end else begin
                            op_r       <= req_op_i;
                            quot_neg_r <= req_quot_neg;
                            rem_neg_r  <= req_rem_neg;
                            divisor_r  <= req_divisor_abs;
                            quot_r     <= req_dividend_abs;
                            rem_r      <= 0;
                            iter_cnt_r <= XLEN[$clog2(XLEN+1)-1:0];
                            state_r    <= ST_RUN;
                        end
                    end
                end
                ST_RUN: begin
                    quot_r     <= run_quot_next;
                    rem_r      <= run_rem_next;
                    iter_cnt_r <= iter_cnt_r - 1'b1;
                    if (iter_cnt_r == 1) begin
                        result_r <= run_final_result;
                        state_r  <= ST_OUT;
                    end
                end
                ST_OUT: begin
                    if (resp_ready_i) begin
                        state_r <= ST_IDLE;
                    end
                end
                default: begin
                    state_r <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
