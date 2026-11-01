module rv32m_mul_unit #(
    parameter integer XLEN = 32
) (
    input  wire clk,
    input  wire rst,
    input  wire flush_i,
    input  wire req_valid_i,//上游当前提供了一组有效的乘法请求
    output wire req_ready_o,//本模块是否能接收
    input  wire [1:0] req_op_i,//执行哪种乘法
    input  wire [XLEN-1:0] req_rs1_i,
    input  wire [XLEN-1:0] req_rs2_i,
    output wire resp_valid_o,//当前输出结果是否有效
    input  wire resp_ready_i,//下游能否接收结果
    output wire [XLEN-1:0] resp_result_o//结果
    );

    localparam [1:0] OP_MUL    = 2'b00;
    localparam [1:0] OP_MULH   = 2'b01;
    localparam [1:0] OP_MULHSU = 2'b10;
    localparam [1:0] OP_MULHU  = 2'b11;
    
    localparam integer EXT_W  = XLEN + 1;
    localparam integer PROD_W = EXT_W * 2;

    reg s0_valid_r;
    reg [1:0] s0_op_r;
    reg [EXT_W-1:0] s0_a_ext_r;
    reg [EXT_W-1:0] s0_b_ext_r;
    reg s1_valid_r;
    reg [1:0] s1_op_r;
    reg [PROD_W-1:0] s1_product_r;
    reg s2_valid_r;
    reg [XLEN-1:0] s2_result_r;

    reg req_rs1_signed;
    reg req_rs2_signed;
    wire [EXT_W-1:0] req_a_ext;
    wire [EXT_W-1:0] req_b_ext;
    
    always @(*) begin
        req_rs1_signed = 1'b0;
        req_rs2_signed = 1'b0;
        case (req_op_i)
            OP_MULH: begin
                req_rs1_signed = 1'b1;
                req_rs2_signed = 1'b1;
            end
            OP_MULHSU: begin
                req_rs1_signed = 1'b1;
                req_rs2_signed = 1'b0;
            end
            default: begin
                req_rs1_signed = 1'b0;
                req_rs2_signed = 1'b0;
            end
        endcase
    end

    assign req_a_ext = {req_rs1_signed & req_rs1_i[XLEN-1], req_rs1_i};
    assign req_b_ext = {req_rs2_signed & req_rs2_i[XLEN-1], req_rs2_i};//乘数扩展一位

    wire s2_ready;
    wire s1_ready;
    wire s0_ready;

    assign s2_ready    = ~s2_valid_r | resp_ready_i;
    assign s1_ready    = ~s1_valid_r | s2_ready;
    assign s0_ready    = ~s0_valid_r | s1_ready;
    assign req_ready_o = s0_ready;

    wire signed [EXT_W-1:0] s0_a_ext_signed;
    wire signed [EXT_W-1:0] s0_b_ext_signed;
    wire signed [PROD_W-1:0] s0_product_signed;
    reg [XLEN-1:0] s1_selected_result;

    assign s0_a_ext_signed = $signed(s0_a_ext_r);
    assign s0_b_ext_signed = $signed(s0_b_ext_r);
    assign s0_product_signed = s0_a_ext_signed * s0_b_ext_signed;

    always @(*) begin
        case (s1_op_r)
            OP_MUL:    s1_selected_result = s1_product_r[31:0];
            OP_MULH:   s1_selected_result = s1_product_r[63:32];
            OP_MULHSU: s1_selected_result = s1_product_r[63:32];
            OP_MULHU:  s1_selected_result = s1_product_r[63:32];
            default:   s1_selected_result = 0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            s0_valid_r   <= 1'b0;
            s1_valid_r   <= 1'b0;
            s2_valid_r   <= 1'b0;
            s0_op_r      <= 0;
            s0_a_ext_r   <= 0;
            s0_b_ext_r   <= 0;
            s1_op_r      <= 0;
            s1_product_r <= 0;
            s2_result_r  <= 0;
        end else if (flush_i) begin
            s0_valid_r <= 1'b0;
            s1_valid_r <= 1'b0;
            s2_valid_r <= 1'b0;
        end else begin
            if (s2_ready) begin
                s2_valid_r <= s1_valid_r;
                if (s1_valid_r) begin
                    s2_result_r <= s1_selected_result;
                end
            end
            if (s1_ready) begin
                s1_valid_r <= s0_valid_r;
                if (s0_valid_r) begin
                    s1_op_r      <= s0_op_r;
                    s1_product_r <= $unsigned(s0_product_signed);
                end
            end
            if (s0_ready) begin
                s0_valid_r <= req_valid_i;
                if (req_valid_i) begin
                    s0_op_r    <= req_op_i;
                    s0_a_ext_r <= req_a_ext;
                    s0_b_ext_r <= req_b_ext;
                end
            end
        end
    end

    assign resp_valid_o  = s2_valid_r;
    assign resp_result_o = s2_result_r;

endmodule
