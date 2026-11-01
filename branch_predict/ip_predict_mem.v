// Verilog-2005 translation; original module names and boundaries retained.
// Default build: USE_XPM, PRED_TRACE_EN and PRED_STATS_EN are undefined.
module bht_mem (
	clka,
	wea,
	addra,
	dina,
	douta,
	clkb,
	web,
	addrb,
	dinb,
	doutb
);
	input wire clka;
	input wire wea;
	input wire [5:0] addra;
	input wire [3:0] dina;
	output wire [3:0] douta;
	input wire clkb;
	input wire web;
	input wire [5:0] addrb;
	input wire [3:0] dinb;
	output wire [3:0] doutb;
	localparam signed [31:0] BITS = 4;
	localparam signed [31:0] DEPTH = 64;
	reg [3:0] mem [0:63];
	reg [3:0] douta_r;
	reg [3:0] doutb_r;
	always @(posedge clka) begin
		if (wea)
			mem[addra] <= dina;
		if (web)
			mem[addrb] <= dinb;
		if (web && (addrb == addra))
			douta_r <= dinb;
		else if (wea)
			douta_r <= dina;
		else
			douta_r <= mem[addra];
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
module btb_mem (
	clka,
	wea,
	addra,
	dina,
	douta,
	clkb,
	web,
	addrb,
	dinb,
	doutb
);
	input wire clka;
	input wire wea;
	input wire [5:0] addra;
	input wire [55:0] dina;
	output wire [55:0] douta;
	input wire clkb;
	input wire web;
	input wire [5:0] addrb;
	input wire [55:0] dinb;
	output wire [55:0] doutb;
	localparam signed [31:0] DEPTH = 64;
	reg [55:0] mem [0:63];
	reg [55:0] douta_r;
	reg [55:0] doutb_r;
	always @(posedge clka) begin
		if (wea)
			mem[addra] <= dina;
		if (web)
			mem[addrb] <= dinb;
		if (web && (addrb == addra))
			douta_r <= dinb;
		else if (wea)
			douta_r <= dina;
		else
			douta_r <= mem[addra];
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
