module sync_dp_bram #(
    parameter ADDR_W = 6,
    parameter DATA_W = 8,
    parameter [DATA_W-1:0] INIT_VALUE = 0
)(
    input  wire clka,
    input  wire wea,
    input  wire [ADDR_W-1:0] addra,
    input  wire [DATA_W-1:0] dina,
    output wire [DATA_W-1:0] douta,

    input  wire clkb,
    input  wire web,
    input  wire [ADDR_W-1:0] addrb,
    input  wire [DATA_W-1:0] dinb,
    output wire [DATA_W-1:0] doutb
);

    localparam DEPTH = 1 << ADDR_W;

    (* ram_style = "block" *)
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    reg [DATA_W-1:0] douta_r;
    reg [DATA_W-1:0] doutb_r;

    integer i;

    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = INIT_VALUE;

        douta_r = INIT_VALUE;
        doutb_r = INIT_VALUE;
    end

    // A 端口：同步读取，read-first。
    always @(posedge clka) begin
        if (wea)
            mem[addra] <= dina;

        douta_r <= mem[addra];
    end

  
    always @(posedge clkb) begin
        if (web)
            mem[addrb] <= dinb;

        doutb_r <= mem[addrb];
    end

    assign douta = douta_r;
    assign doutb = doutb_r;

endmodule