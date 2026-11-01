module bp_btb_ram #(
    parameter BTB_RAM_DEPTH = 64,
    parameter BRTYPE_WIDTH  = 2,
    parameter TAG_WIDTH     = 22,
    parameter BRDEST_WIDTH  = 32,

    parameter ADDR_WIDTH =
        (BTB_RAM_DEPTH <= 1) ? 1 : $clog2(BTB_RAM_DEPTH)
)(
    input  wire clka,
    input  wire wea,
    input  wire [ADDR_WIDTH-1:0] addra,

    input  wire [BRTYPE_WIDTH+TAG_WIDTH+BRDEST_WIDTH-1:0] dina,
    output wire [BRTYPE_WIDTH+TAG_WIDTH+BRDEST_WIDTH-1:0] douta,

    input  wire clkb,
    input  wire web,
    input  wire [ADDR_WIDTH-1:0] addrb,

    input  wire [BRTYPE_WIDTH+TAG_WIDTH+BRDEST_WIDTH-1:0] dinb,
    output wire [BRTYPE_WIDTH+TAG_WIDTH+BRDEST_WIDTH-1:0] doutb
);

    localparam DATA_WIDTH =
        BRTYPE_WIDTH + TAG_WIDTH + BRDEST_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:BTB_RAM_DEPTH-1];

    reg [DATA_WIDTH-1:0] douta_r;
    reg [DATA_WIDTH-1:0] doutb_r;

    // 与原设计一致：两个端口都使用 clka。
    always @(posedge clka) begin

        // 两个端口可以同时写入。
        // 同地址同时写入时，B 优先。
        if (wea)
            mem[addra] <= dina;

        if (web)
            mem[addrb] <= dinb;

        // A 端口读取及写数据旁路。
        if (web && (addrb == addra))
            douta_r <= dinb;
        else if (wea)
            douta_r <= dina;
        else
            douta_r <= mem[addra];

        // B 端口读取及写数据旁路。
        if (web)
            doutb_r <= dinb;
        else if (wea && (addra == addrb))
            doutb_r <= dina;
        else
            doutb_r <= mem[addrb];

    end

    assign douta = douta_r;
    assign doutb = doutb_r;

endmodule