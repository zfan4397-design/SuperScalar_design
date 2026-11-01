module bp_bundle_control(
    input wire ctrl_clear;
	input wire ctrl_restore_pulse;
	input wire have_inst_reg;
	input wire icache_busy;
	input wire icache_rvalid;
	input wire [31:0] nxtpc_interrupt;
	input wire [31:0] nxtpc_flush;
	input wire [IN_WIDTH - 1:0] pre_taken;
	input wire [(IN_WIDTH * 32) - 1:0] pre_brdest;
	output reg [IN_WIDTH - 1:0] have_inst;
	output reg redirect;
	output reg [31:0] redirect_pc;
	output reg [31:0] dbg_bundle_cut_inst
);

reg sv2v_0;
parameter IN_WIDTH = 4;
always @(*) begin
		if (_sv2v_0)
			;
		dbg_bundle_cut_inst = 1'sb0;
		if (ctrl_clear) begin
			have_inst = 1'sb0;
			redirect = 1'b1;
			redirect_pc = nxtpc_interrupt;
		end
		else if (ctrl_restore_pulse) begin
			have_inst = 1'sb0;
			redirect = 1'b1;
			redirect_pc = nxtpc_flush;
		end
		else if (!have_inst_reg) begin
			have_inst = 1'sb0;
			redirect = 1'b0;
			redirect_pc = 1'sb0;
		end
		else begin
			have_inst[0] = 1'b1;
			redirect = 1'b0;
			redirect_pc = 1'sb0;
			begin : sv2v_autoblock_1
				reg signed [31:0] i;
				for (i = 1; i < IN_WIDTH; i = i + 1)
					have_inst[i] = (pre_taken[i - 1] ? 1'b0 : have_inst[i - 1]);
			end
			begin : sv2v_autoblock_2
				reg signed [31:0] i;
				for (i = IN_WIDTH - 1; i >= 0; i = i - 1)
					if (pre_taken[i]) begin
						redirect = 1'b1;
						redirect_pc = pre_brdest[i * 32+:32];
					end
			end
			if (!icache_busy && icache_rvalid)
				dbg_bundle_cut_inst = IN_WIDTH - bp_count_ones(have_inst);
		end
	end
	initial _sv2v_0 = 0;

function integer bp_count_ones;
    input [(IN_WIDTH)-1:0] value;
    integer bit_index;
    begin
        bp_count_ones=0;
        for(bit_index=0;bit_index<(IN_WIDTH);bit_index=bit_index+1)
            if(value[bit_index] === 1'b1) bp_count_ones=bp_count_ones+1;
    end
endfunction

endmodule