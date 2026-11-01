// Verilog-2005 translation; original module names and boundaries retained.
// Default build: USE_XPM, PRED_TRACE_EN and PRED_STATS_EN are undefined.
module direction_exception_predictor (
	clk,
	rst,
	have_inst_i,
	pc_i,
	use_long_o,
	lp_o,
	dbg_base_hist_o,
	dbg_lookup_hist_o,
	dbg_slot_o,
	dbg_bypass_hit_o,
	dbg_bypass_addr_o,
	dbg_bypass_ctr_o,
	dbg_final_ctr_o,
	dbg_ctr_src_o,
	br_grant,
	br_pc,
	br_brtype,
	br_taken,
	rt_grant,
	rt_pc,
	rt_brtype,
	rt_brdest,
	rt_exception,
	rt_use_long_o
);
	reg _sv2v_0;
	parameter [31:0] IN_WIDTH = 4;
	parameter [31:0] PORT_WIDTH = 2;
	parameter [31:0] MODE_ENTRIES = 16;
	parameter [31:0] LONG_SLOTS = 2;
	parameter [31:0] BHR_BITS = 12;
	parameter [31:0] SAMPLE_THRESHOLD = 96;
	parameter [31:0] MISS_THRESHOLD = 64;
	parameter [1:0] PHT_INIT_STATE = 2'b10;
	input wire clk;
	input wire rst;
	input wire have_inst_i;
	localparam signed [31:0] config_pkg_PC_WIDTH = 32;
	input wire [31:0] pc_i;
	output reg [IN_WIDTH - 1:0] use_long_o;
	output reg [(IN_WIDTH * 2) - 1:0] lp_o;
	output reg [(IN_WIDTH * BHR_BITS) - 1:0] dbg_base_hist_o;
	output reg [(IN_WIDTH * BHR_BITS) - 1:0] dbg_lookup_hist_o;
	localparam [31:0] SLOT_IDX_W = (LONG_SLOTS <= 2 ? 1 : $clog2(LONG_SLOTS));
	output reg [(IN_WIDTH * SLOT_IDX_W) - 1:0] dbg_slot_o;
	output reg [IN_WIDTH - 1:0] dbg_bypass_hit_o;
	output reg [(IN_WIDTH * BHR_BITS) - 1:0] dbg_bypass_addr_o;
	output reg [(IN_WIDTH * 2) - 1:0] dbg_bypass_ctr_o;
	output reg [(IN_WIDTH * 2) - 1:0] dbg_final_ctr_o;
	output reg [(IN_WIDTH * 2) - 1:0] dbg_ctr_src_o;
	input wire [IN_WIDTH - 1:0] br_grant;
	input wire [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] br_pc;
	localparam signed [31:0] config_pkg_BRTYPE_WIDTH = 2;
	input wire [(IN_WIDTH * config_pkg_BRTYPE_WIDTH) - 1:0] br_brtype;
	input wire [IN_WIDTH - 1:0] br_taken;
	input wire [PORT_WIDTH - 1:0] rt_grant;
	input wire [(PORT_WIDTH * config_pkg_PC_WIDTH) - 1:0] rt_pc;
	input wire [(PORT_WIDTH * config_pkg_BRTYPE_WIDTH) - 1:0] rt_brtype;
	input wire [(PORT_WIDTH * config_pkg_PC_WIDTH) - 1:0] rt_brdest;
	localparam signed [31:0] config_pkg_EXCPT_WIDTH = 4;
	input wire [(PORT_WIDTH * config_pkg_EXCPT_WIDTH) - 1:0] rt_exception;
	output reg [PORT_WIDTH - 1:0] rt_use_long_o;
	localparam [31:0] MODE_IDX_BITS = $clog2(MODE_ENTRIES);
	localparam [31:0] MODE_TAG_W = 30;
	localparam [31:0] SAMPLE_W = (SAMPLE_THRESHOLD <= 1 ? 1 : $clog2(SAMPLE_THRESHOLD + 1));
	localparam [31:0] MISS_W = (SAMPLE_THRESHOLD <= 1 ? 1 : $clog2(SAMPLE_THRESHOLD + 1));
	localparam [31:0] UPD_FIFO_BITS = 2;
	localparam [31:0] UPD_FIFO_DEPTH = 4;
	localparam [31:0] BYPASS_BITS = 2;
	localparam [31:0] BYPASS_DEPTH = 4;
	localparam [1:0] UPD_IDLE = 2'd0;
	localparam [1:0] UPD_WAIT = 2'd1;
	localparam [1:0] UPD_WRITE = 2'd2;
	reg [MODE_ENTRIES - 1:0] mode_valid;
	reg [MODE_ENTRIES - 1:0] mode_upgraded;
	reg [(MODE_ENTRIES * MODE_TAG_W) - 1:0] mode_tag;
	reg [(MODE_ENTRIES * SAMPLE_W) - 1:0] mode_sample_ctr;
	reg [(MODE_ENTRIES * MISS_W) - 1:0] mode_miss_ctr;
	reg [(MODE_ENTRIES * BHR_BITS) - 1:0] mode_candidate_hist;
	reg [(MODE_ENTRIES * SLOT_IDX_W) - 1:0] mode_long_slot_id;
	reg [LONG_SLOTS - 1:0] long_slot_valid;
	reg [(LONG_SLOTS * MODE_TAG_W) - 1:0] long_slot_tag;
	reg [(LONG_SLOTS * BHR_BITS) - 1:0] active_bhr;
	reg [(LONG_SLOTS * BHR_BITS) - 1:0] commit_bhr;
	reg [(LONG_SLOTS * BHR_BITS) - 1:0] shadow_bhr;
	reg [(LONG_SLOTS * 8) - 1:0] epoch_tag;
	reg [7:0] active_epoch;
	reg have_q;
	reg [IN_WIDTH - 1:0] lane_use_long_now;
	reg [IN_WIDTH - 1:0] lane_use_long_q;
	reg [IN_WIDTH - 1:0] lane_lookup_valid_now;
	reg [IN_WIDTH - 1:0] lane_lookup_valid_q;
	reg [(IN_WIDTH * SLOT_IDX_W) - 1:0] lane_slot_now;
	reg [(IN_WIDTH * SLOT_IDX_W) - 1:0] lane_slot_q;
	reg [(IN_WIDTH * BHR_BITS) - 1:0] lane_base_hist_now;
	reg [(IN_WIDTH * BHR_BITS) - 1:0] lane_base_hist_q;
	reg [(IN_WIDTH * BHR_BITS) - 1:0] lane_lookup_hist_q;
	reg [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] lane_pc_now;
	reg [PORT_WIDTH - 1:0] rt_is_dir;
	reg [PORT_WIDTH - 1:0] rt_taken;
	reg [PORT_WIDTH - 1:0] rt_misp;
	reg [(PORT_WIDTH * MODE_IDX_BITS) - 1:0] rt_mode_idx;
	reg [(PORT_WIDTH * MODE_TAG_W) - 1:0] rt_mode_tag;
	reg [PORT_WIDTH - 1:0] rt_mode_hit;
	reg [PORT_WIDTH - 1:0] rt_mode_replace_ok;
	reg [PORT_WIDTH - 1:0] rt_mode_upgraded_hit;
	reg [(PORT_WIDTH * SLOT_IDX_W) - 1:0] rt_slot_id;
	reg mispred_any;
	reg [7:0] epoch_next;
	reg [(LONG_SLOTS * BHR_BITS) - 1:0] pht_addra_slot;
	wire [(LONG_SLOTS * 2) - 1:0] pht_douta_slot;
	reg [LONG_SLOTS - 1:0] pht_web_slot;
	reg [(LONG_SLOTS * BHR_BITS) - 1:0] pht_addrb_slot;
	reg [(LONG_SLOTS * 2) - 1:0] pht_dinb_slot;
	wire [(LONG_SLOTS * 2) - 1:0] pht_doutb_slot;
	reg [((LONG_SLOTS * UPD_FIFO_DEPTH) * BHR_BITS) - 1:0] upd_fifo_addr;
	reg [(LONG_SLOTS * UPD_FIFO_DEPTH) - 1:0] upd_fifo_taken;
	reg [(LONG_SLOTS * UPD_FIFO_DEPTH) - 1:0] upd_fifo_seed;
	reg [((LONG_SLOTS * UPD_FIFO_DEPTH) * 2) - 1:0] upd_fifo_seed_ctr;
	reg [(LONG_SLOTS * UPD_FIFO_BITS) - 1:0] upd_fifo_head;
	reg [(LONG_SLOTS * UPD_FIFO_BITS) - 1:0] upd_fifo_tail;
	reg [(LONG_SLOTS * 3) - 1:0] upd_fifo_count;
	reg [(LONG_SLOTS * 2) - 1:0] upd_state;
	reg [(LONG_SLOTS * BHR_BITS) - 1:0] pend_addr;
	reg [LONG_SLOTS - 1:0] pend_taken;
	reg [(LONG_SLOTS * 2) - 1:0] pend_new_ctr;
	reg [(LONG_SLOTS * BYPASS_DEPTH) - 1:0] bypass_valid;
	reg [((LONG_SLOTS * BYPASS_DEPTH) * BHR_BITS) - 1:0] bypass_addr;
	reg [((LONG_SLOTS * BYPASS_DEPTH) * 2) - 1:0] bypass_ctr;
	reg [(LONG_SLOTS * BYPASS_BITS) - 1:0] bypass_ptr;
	function automatic [MODE_IDX_BITS - 1:0] pc_mode_idx;
		input reg [31:0] pc;
		reg [MODE_IDX_BITS - 1:0] idx;
		integer bit_i;
		integer slot;
		begin
			idx = 1'sb0;
			for (bit_i = 2; bit_i < config_pkg_PC_WIDTH; bit_i = bit_i + 1)
				begin
					slot = (bit_i - 2) % MODE_IDX_BITS;
					idx[slot] = idx[slot] ^ pc[bit_i];
				end
			pc_mode_idx = idx;
		end
	endfunction
	function automatic [29:0] pc_mode_tag;
		input reg [31:0] pc;
		pc_mode_tag = pc[31:2];
	endfunction
	function automatic [1:0] sat2_update;
		input reg [1:0] cur;
		input reg taken;
		reg [1:0] nxt;
		begin
			nxt = cur;
			(* full_case, parallel_case *)
			case (cur)
				2'b00: nxt = (taken ? 2'b01 : 2'b00);
				2'b01: nxt = (taken ? 2'b10 : 2'b00);
				2'b10: nxt = (taken ? 2'b11 : 2'b01);
				2'b11: nxt = (taken ? 2'b11 : 2'b10);
				default: nxt = 2'b10;
			endcase
			sat2_update = nxt;
		end
	endfunction
	function automatic [BHR_BITS - 1:0] sv2v_cast_BA5C6;
		input reg [BHR_BITS - 1:0] inp;
		sv2v_cast_BA5C6 = inp;
	endfunction
	function automatic [BHR_BITS - 1:0] bhr_shift_in;
		input reg [BHR_BITS - 1:0] bhr_old;
		input reg taken;
		reg [BHR_BITS - 1:0] bhr_new;
		begin
			if (BHR_BITS == 1)
				bhr_new = sv2v_cast_BA5C6(taken);
			else
				bhr_new = {bhr_old[BHR_BITS - 2:0], taken};
			bhr_shift_in = bhr_new;
		end
	endfunction
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		lane_pc_now = 1'sb0;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				lane_pc_now[i * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = pc_i + sv2v_cast_32($unsigned(i) << 2);
		end
	end
	always @(*) begin : sv2v_autoblock_2
		reg [LONG_SLOTS - 1:0] slot_claimed;
		if (_sv2v_0)
			;
		lane_use_long_now = 1'sb0;
		lane_lookup_valid_now = 1'sb0;
		lane_slot_now = 1'sb0;
		lane_base_hist_now = 1'sb0;
		pht_addra_slot = 1'sb0;
		slot_claimed = 1'sb0;
		begin : sv2v_autoblock_3
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				begin : sv2v_autoblock_4
					reg [MODE_IDX_BITS - 1:0] idx;
					reg [29:0] tag;
					reg [SLOT_IDX_W - 1:0] slot;
					reg mode_hit;
					idx = pc_mode_idx(lane_pc_now[i * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH]);
					tag = pc_mode_tag(lane_pc_now[i * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH]);
					slot = mode_long_slot_id[idx * SLOT_IDX_W+:SLOT_IDX_W];
					mode_hit = (((mode_valid[idx] && mode_upgraded[idx]) && (mode_tag[idx * MODE_TAG_W+:MODE_TAG_W] == tag)) && long_slot_valid[slot]) && (long_slot_tag[slot * MODE_TAG_W+:MODE_TAG_W] == tag);
					if (mode_hit) begin
						lane_use_long_now[i] = 1'b1;
						lane_slot_now[i * SLOT_IDX_W+:SLOT_IDX_W] = slot;
						lane_base_hist_now[i * BHR_BITS+:BHR_BITS] = shadow_bhr[slot * BHR_BITS+:BHR_BITS];
						if (!slot_claimed[slot]) begin
							lane_lookup_valid_now[i] = 1'b1;
							pht_addra_slot[slot * BHR_BITS+:BHR_BITS] = shadow_bhr[slot * BHR_BITS+:BHR_BITS];
							slot_claimed[slot] = 1'b1;
						end
					end
				end
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		use_long_o = (have_q ? lane_use_long_q & lane_lookup_valid_q : {IN_WIDTH {1'sb0}});
		lp_o = 1'sb0;
		dbg_base_hist_o = 1'sb0;
		dbg_lookup_hist_o = 1'sb0;
		dbg_slot_o = 1'sb0;
		dbg_bypass_hit_o = 1'sb0;
		dbg_bypass_addr_o = 1'sb0;
		dbg_bypass_ctr_o = 1'sb0;
		dbg_final_ctr_o = 1'sb0;
		dbg_ctr_src_o = 1'sb0;
		begin : sv2v_autoblock_5
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				begin : sv2v_autoblock_6
					reg [1:0] ctr_sel;
					reg bypass_hit;
					reg [BHR_BITS - 1:0] matched_bypass_addr;
					reg [1:0] matched_bypass_ctr;
					ctr_sel = pht_douta_slot[lane_slot_q[i * SLOT_IDX_W+:SLOT_IDX_W] * 2+:2];
					bypass_hit = 1'b0;
					matched_bypass_addr = 1'sb0;
					matched_bypass_ctr = 1'sb0;
					if ((have_q && lane_use_long_q[i]) && lane_lookup_valid_q[i]) begin
						begin : sv2v_autoblock_7
							reg signed [31:0] b;
							for (b = 0; b < BYPASS_DEPTH; b = b + 1)
								if (bypass_valid[(lane_slot_q[i * SLOT_IDX_W+:SLOT_IDX_W] * BYPASS_DEPTH) + b] && (bypass_addr[((lane_slot_q[i * SLOT_IDX_W+:SLOT_IDX_W] * BYPASS_DEPTH) + b) * BHR_BITS+:BHR_BITS] == lane_lookup_hist_q[i * BHR_BITS+:BHR_BITS])) begin
									ctr_sel = bypass_ctr[((lane_slot_q[i * SLOT_IDX_W+:SLOT_IDX_W] * BYPASS_DEPTH) + b) * 2+:2];
									bypass_hit = 1'b1;
									matched_bypass_addr = bypass_addr[((lane_slot_q[i * SLOT_IDX_W+:SLOT_IDX_W] * BYPASS_DEPTH) + b) * BHR_BITS+:BHR_BITS];
									matched_bypass_ctr = bypass_ctr[((lane_slot_q[i * SLOT_IDX_W+:SLOT_IDX_W] * BYPASS_DEPTH) + b) * 2+:2];
								end
						end
						lp_o[i * 2+:2] = ctr_sel;
					end
					dbg_base_hist_o[i * BHR_BITS+:BHR_BITS] = lane_base_hist_q[i * BHR_BITS+:BHR_BITS];
					dbg_lookup_hist_o[i * BHR_BITS+:BHR_BITS] = lane_lookup_hist_q[i * BHR_BITS+:BHR_BITS];
					dbg_slot_o[i * SLOT_IDX_W+:SLOT_IDX_W] = lane_slot_q[i * SLOT_IDX_W+:SLOT_IDX_W];
					dbg_bypass_hit_o[i] = (have_q && lane_lookup_valid_q[i]) && bypass_hit;
					dbg_bypass_addr_o[i * BHR_BITS+:BHR_BITS] = matched_bypass_addr;
					dbg_bypass_ctr_o[i * 2+:2] = matched_bypass_ctr;
					dbg_final_ctr_o[i * 2+:2] = lp_o[i * 2+:2];
					dbg_ctr_src_o[i * 2+:2] = (have_q && lane_lookup_valid_q[i] ? (bypass_hit ? 2'd1 : 2'd0) : 2'd0);
				end
		end
	end
	function automatic [1:0] sv2v_cast_B2A15;
		input reg [1:0] inp;
		sv2v_cast_B2A15 = inp;
	endfunction
	function automatic [3:0] sv2v_cast_E0276;
		input reg [3:0] inp;
		sv2v_cast_E0276 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		rt_is_dir = 1'sb0;
		rt_taken = 1'sb0;
		rt_misp = 1'sb0;
		rt_mode_idx = 1'sb0;
		rt_mode_tag = 1'sb0;
		rt_mode_hit = 1'sb0;
		rt_mode_replace_ok = 1'sb0;
		rt_mode_upgraded_hit = 1'sb0;
		rt_slot_id = 1'sb0;
		rt_use_long_o = 1'sb0;
		mispred_any = 1'b0;
		begin : sv2v_autoblock_8
			reg signed [31:0] p;
			for (p = 0; p < PORT_WIDTH; p = p + 1)
				begin : sv2v_autoblock_9
					reg [MODE_IDX_BITS - 1:0] idx;
					reg [29:0] tag;
					reg [SLOT_IDX_W - 1:0] slot;
					idx = pc_mode_idx(rt_pc[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH]);
					tag = pc_mode_tag(rt_pc[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH]);
					slot = mode_long_slot_id[idx * SLOT_IDX_W+:SLOT_IDX_W];
					rt_is_dir[p] = rt_grant[p] && (rt_brtype[p * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] == sv2v_cast_B2A15(2));
					rt_taken[p] = rt_brdest[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] != (rt_pc[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] + 32'd4);
					rt_misp[p] = rt_exception[p * config_pkg_EXCPT_WIDTH+:config_pkg_EXCPT_WIDTH] == sv2v_cast_E0276(1);
					rt_mode_idx[p * MODE_IDX_BITS+:MODE_IDX_BITS] = idx;
					rt_mode_tag[p * MODE_TAG_W+:MODE_TAG_W] = tag;
					rt_mode_hit[p] = mode_valid[idx] && (mode_tag[idx * MODE_TAG_W+:MODE_TAG_W] == tag);
					rt_mode_replace_ok[p] = !mode_valid[idx] || !mode_upgraded[idx];
					rt_mode_upgraded_hit[p] = ((rt_mode_hit[p] && mode_upgraded[idx]) && long_slot_valid[slot]) && (long_slot_tag[slot * MODE_TAG_W+:MODE_TAG_W] == tag);
					rt_slot_id[p * SLOT_IDX_W+:SLOT_IDX_W] = slot;
					rt_use_long_o[p] = rt_is_dir[p] && rt_mode_upgraded_hit[p];
					mispred_any = mispred_any | (rt_is_dir[p] && rt_misp[p]);
				end
		end
	end
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		epoch_next = active_epoch + sv2v_cast_8((mispred_any ? 1'b1 : 1'b0));
	end
	genvar _gv_si_1;
	generate
		for (_gv_si_1 = 0; _gv_si_1 < LONG_SLOTS; _gv_si_1 = _gv_si_1 + 1) begin : gen_long_pht_bram
			localparam si = _gv_si_1;
			localparam [31:0] sv2v_uu_u_long_pht_DATA_W = 2;
			localparam [1:0] sv2v_uu_u_long_pht_ext_dina_0 = 1'sb0;
			sync_dp_bram_exc #(
				.ADDR_W(BHR_BITS),
				.DATA_W(2),
				.INIT_VALUE(PHT_INIT_STATE)
			) u_long_pht(
				.clka(clk),
				.wea(1'b0),
				.addra(pht_addra_slot[si * BHR_BITS+:BHR_BITS]),
				.dina(sv2v_uu_u_long_pht_ext_dina_0),
				.douta(pht_douta_slot[si * 2+:2]),
				.clkb(clk),
				.web(pht_web_slot[si]),
				.addrb(pht_addrb_slot[si * BHR_BITS+:BHR_BITS]),
				.dinb(pht_dinb_slot[si * 2+:2]),
				.doutb(pht_doutb_slot[si * 2+:2])
			);
		end
	endgenerate
	always @(*) begin
		if (_sv2v_0)
			;
		pht_web_slot = 1'sb0;
		pht_addrb_slot = 1'sb0;
		pht_dinb_slot = 1'sb0;
		begin : sv2v_autoblock_10
			reg signed [31:0] si;
			for (si = 0; si < LONG_SLOTS; si = si + 1)
				(* full_case, parallel_case *)
				case (upd_state[si * 2+:2])
					UPD_IDLE:
						if (upd_fifo_count[0 + (si * 3)+:3] != 0) begin
							pht_addrb_slot[si * BHR_BITS+:BHR_BITS] = upd_fifo_addr[((si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]) * BHR_BITS+:BHR_BITS];
							if (upd_fifo_seed[(si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]]) begin
								pht_web_slot[si] = 1'b1;
								pht_dinb_slot[si * 2+:2] = upd_fifo_seed_ctr[((si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]) * 2+:2];
							end
						end
					UPD_WRITE: begin
						pht_web_slot[si] = 1'b1;
						pht_addrb_slot[si * BHR_BITS+:BHR_BITS] = pend_addr[si * BHR_BITS+:BHR_BITS];
						pht_dinb_slot[si * 2+:2] = pend_new_ctr[si * 2+:2];
					end
					default: pht_addrb_slot[si * BHR_BITS+:BHR_BITS] = 1'sb0;
				endcase
		end
	end
	function automatic signed [SAMPLE_W - 1:0] sv2v_cast_80863_signed;
		input reg signed [SAMPLE_W - 1:0] inp;
		sv2v_cast_80863_signed = inp;
	endfunction
	function automatic signed [MISS_W - 1:0] sv2v_cast_EEBAF_signed;
		input reg signed [MISS_W - 1:0] inp;
		sv2v_cast_EEBAF_signed = inp;
	endfunction
	function automatic signed [SLOT_IDX_W - 1:0] sv2v_cast_9A159_signed;
		input reg signed [SLOT_IDX_W - 1:0] inp;
		sv2v_cast_9A159_signed = inp;
	endfunction
	function automatic [MISS_W - 1:0] sv2v_cast_EEBAF;
		input reg [MISS_W - 1:0] inp;
		sv2v_cast_EEBAF = inp;
	endfunction
	function automatic signed [1:0] sv2v_cast_4138B_signed;
		input reg signed [1:0] inp;
		sv2v_cast_4138B_signed = inp;
	endfunction
	always @(posedge clk)
		if (rst) begin
			have_q <= 1'b0;
			lane_use_long_q <= 1'sb0;
			lane_lookup_valid_q <= 1'sb0;
			lane_slot_q <= 1'sb0;
			lane_base_hist_q <= 1'sb0;
			lane_lookup_hist_q <= 1'sb0;
			active_epoch <= 1'sb0;
			begin : sv2v_autoblock_11
				reg signed [31:0] mi;
				for (mi = 0; mi < MODE_ENTRIES; mi = mi + 1)
					begin
						mode_valid[mi] <= 1'b0;
						mode_upgraded[mi] <= 1'b0;
						mode_tag[mi * MODE_TAG_W+:MODE_TAG_W] <= 1'sb0;
						mode_sample_ctr[mi * SAMPLE_W+:SAMPLE_W] <= 1'sb0;
						mode_miss_ctr[mi * MISS_W+:MISS_W] <= 1'sb0;
						mode_candidate_hist[mi * BHR_BITS+:BHR_BITS] <= 1'sb0;
						mode_long_slot_id[mi * SLOT_IDX_W+:SLOT_IDX_W] <= 1'sb0;
					end
			end
			begin : sv2v_autoblock_12
				reg signed [31:0] si;
				for (si = 0; si < LONG_SLOTS; si = si + 1)
					begin
						long_slot_valid[si] <= 1'b0;
						long_slot_tag[si * MODE_TAG_W+:MODE_TAG_W] <= 1'sb0;
						active_bhr[si * BHR_BITS+:BHR_BITS] <= 1'sb0;
						commit_bhr[si * BHR_BITS+:BHR_BITS] <= 1'sb0;
						shadow_bhr[si * BHR_BITS+:BHR_BITS] <= 1'sb0;
						epoch_tag[si * 8+:8] <= 1'sb0;
						upd_fifo_head[si * UPD_FIFO_BITS+:UPD_FIFO_BITS] <= 1'sb0;
						upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS] <= 1'sb0;
						upd_fifo_count[0 + (si * 3)+:3] <= 1'sb0;
						upd_state[si * 2+:2] <= UPD_IDLE;
						pend_addr[si * BHR_BITS+:BHR_BITS] <= 1'sb0;
						pend_taken[si] <= 1'b0;
						pend_new_ctr[si * 2+:2] <= PHT_INIT_STATE;
						bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS] <= 1'sb0;
						begin : sv2v_autoblock_13
							reg signed [31:0] qi;
							for (qi = 0; qi < UPD_FIFO_DEPTH; qi = qi + 1)
								begin
									upd_fifo_addr[((si * UPD_FIFO_DEPTH) + qi) * BHR_BITS+:BHR_BITS] <= 1'sb0;
									upd_fifo_taken[(si * UPD_FIFO_DEPTH) + qi] <= 1'b0;
									upd_fifo_seed[(si * UPD_FIFO_DEPTH) + qi] <= 1'b0;
									upd_fifo_seed_ctr[((si * UPD_FIFO_DEPTH) + qi) * 2+:2] <= PHT_INIT_STATE;
								end
						end
						begin : sv2v_autoblock_14
							reg signed [31:0] bi;
							for (bi = 0; bi < BYPASS_DEPTH; bi = bi + 1)
								begin
									bypass_valid[(si * BYPASS_DEPTH) + bi] <= 1'b0;
									bypass_addr[((si * BYPASS_DEPTH) + bi) * BHR_BITS+:BHR_BITS] <= 1'sb0;
									bypass_ctr[((si * BYPASS_DEPTH) + bi) * 2+:2] <= PHT_INIT_STATE;
								end
						end
					end
			end
		end
		else begin : sv2v_autoblock_15
			reg [(LONG_SLOTS * BHR_BITS) - 1:0] active_bhr_tmp;
			reg [(LONG_SLOTS * BHR_BITS) - 1:0] commit_bhr_tmp;
			reg [(LONG_SLOTS * 8) - 1:0] epoch_tag_tmp;
			reg [7:0] active_epoch_tmp;
			reg [LONG_SLOTS - 1:0] slot_busy_tmp;
			reg [LONG_SLOTS - 1:0] evt_valid;
			reg [(LONG_SLOTS * BHR_BITS) - 1:0] evt_addr;
			reg [LONG_SLOTS - 1:0] evt_taken;
			reg [LONG_SLOTS - 1:0] evt_seed;
			reg [(LONG_SLOTS * 2) - 1:0] evt_seed_ctr;
			active_epoch_tmp = (mispred_any ? epoch_next : active_epoch);
			slot_busy_tmp = long_slot_valid;
			evt_valid = 1'sb0;
			evt_addr = 1'sb0;
			evt_taken = 1'sb0;
			evt_seed = 1'sb0;
			evt_seed_ctr = 1'sb0;
			begin : sv2v_autoblock_16
				reg signed [31:0] si;
				for (si = 0; si < LONG_SLOTS; si = si + 1)
					begin
						active_bhr_tmp[si * BHR_BITS+:BHR_BITS] = active_bhr[si * BHR_BITS+:BHR_BITS];
						commit_bhr_tmp[si * BHR_BITS+:BHR_BITS] = commit_bhr[si * BHR_BITS+:BHR_BITS];
						epoch_tag_tmp[si * 8+:8] = epoch_tag[si * 8+:8];
					end
			end
			have_q <= have_inst_i;
			lane_use_long_q <= lane_use_long_now;
			lane_lookup_valid_q <= lane_lookup_valid_now;
			lane_slot_q <= lane_slot_now;
			lane_base_hist_q <= lane_base_hist_now;
			lane_lookup_hist_q <= lane_base_hist_now;
			active_epoch <= active_epoch_tmp;
			begin : sv2v_autoblock_17
				reg signed [31:0] p;
				for (p = 0; p < PORT_WIDTH; p = p + 1)
					if (rt_is_dir[p]) begin : sv2v_autoblock_18
						reg [MODE_IDX_BITS - 1:0] idx;
						reg [29:0] tag;
						idx = rt_mode_idx[p * MODE_IDX_BITS+:MODE_IDX_BITS];
						tag = rt_mode_tag[p * MODE_TAG_W+:MODE_TAG_W];
						if (rt_mode_upgraded_hit[p]) begin : sv2v_autoblock_19
							reg [SLOT_IDX_W - 1:0] slot;
							reg [BHR_BITS - 1:0] old_bhr_c;
							reg [BHR_BITS - 1:0] new_bhr_c;
							slot = rt_slot_id[p * SLOT_IDX_W+:SLOT_IDX_W];
							old_bhr_c = commit_bhr_tmp[slot * BHR_BITS+:BHR_BITS];
							new_bhr_c = bhr_shift_in(old_bhr_c, rt_taken[p]);
							commit_bhr_tmp[slot * BHR_BITS+:BHR_BITS] = new_bhr_c;
							evt_valid[slot] = 1'b1;
							evt_addr[slot * BHR_BITS+:BHR_BITS] = old_bhr_c;
							evt_taken[slot] = rt_taken[p];
							evt_seed[slot] = 1'b0;
							if (rt_misp[p]) begin
								active_bhr_tmp[slot * BHR_BITS+:BHR_BITS] = new_bhr_c;
								epoch_tag_tmp[slot * 8+:8] = epoch_next;
							end
						end
						else if (rt_mode_hit[p]) begin : sv2v_autoblock_20
							reg [SAMPLE_W - 1:0] sample_cur;
							reg [SAMPLE_W - 1:0] sample_n;
							reg [MISS_W - 1:0] miss_cur;
							reg [MISS_W - 1:0] miss_n;
							reg [BHR_BITS - 1:0] hist_cur;
							reg [BHR_BITS - 1:0] hist_n;
							sample_cur = mode_sample_ctr[idx * SAMPLE_W+:SAMPLE_W];
							miss_cur = mode_miss_ctr[idx * MISS_W+:MISS_W];
							hist_cur = mode_candidate_hist[idx * BHR_BITS+:BHR_BITS];
							hist_n = bhr_shift_in(hist_cur, rt_taken[p]);
							sample_n = sample_cur;
							miss_n = miss_cur;
							if (sample_cur < SAMPLE_THRESHOLD) begin
								sample_n = sample_cur + sv2v_cast_80863_signed(1);
								if (rt_misp[p] && (miss_cur < SAMPLE_THRESHOLD))
									miss_n = miss_cur + sv2v_cast_EEBAF_signed(1);
							end
							mode_sample_ctr[idx * SAMPLE_W+:SAMPLE_W] <= sample_n;
							mode_miss_ctr[idx * MISS_W+:MISS_W] <= miss_n;
							mode_candidate_hist[idx * BHR_BITS+:BHR_BITS] <= hist_n;
							if ((((sample_cur < SAMPLE_THRESHOLD) && (sample_n == SAMPLE_THRESHOLD)) && (miss_n >= MISS_THRESHOLD)) && !mode_upgraded[idx]) begin : sv2v_autoblock_21
								reg found_free_slot;
								reg [SLOT_IDX_W - 1:0] alloc_slot;
								found_free_slot = 1'b0;
								alloc_slot = 1'sb0;
								begin : sv2v_autoblock_22
									reg signed [31:0] s;
									for (s = 0; s < LONG_SLOTS; s = s + 1)
										if (!found_free_slot && !slot_busy_tmp[s]) begin
											found_free_slot = 1'b1;
											alloc_slot = sv2v_cast_9A159_signed(s);
										end
								end
								if (found_free_slot) begin
									slot_busy_tmp[alloc_slot] = 1'b1;
									mode_upgraded[idx] <= 1'b1;
									mode_long_slot_id[idx * SLOT_IDX_W+:SLOT_IDX_W] <= alloc_slot;
									long_slot_valid[alloc_slot] <= 1'b1;
									long_slot_tag[alloc_slot * MODE_TAG_W+:MODE_TAG_W] <= tag;
									active_bhr_tmp[alloc_slot * BHR_BITS+:BHR_BITS] = hist_n;
									commit_bhr_tmp[alloc_slot * BHR_BITS+:BHR_BITS] = hist_n;
									epoch_tag_tmp[alloc_slot * 8+:8] = active_epoch_tmp;
									evt_valid[alloc_slot] = 1'b1;
									evt_addr[alloc_slot * BHR_BITS+:BHR_BITS] = hist_cur;
									evt_taken[alloc_slot] = rt_taken[p];
									evt_seed[alloc_slot] = 1'b1;
									evt_seed_ctr[alloc_slot * 2+:2] = sat2_update(PHT_INIT_STATE, rt_taken[p]);
								end
							end
						end
						else if (rt_mode_replace_ok[p]) begin
							mode_valid[idx] <= 1'b1;
							mode_upgraded[idx] <= 1'b0;
							mode_tag[idx * MODE_TAG_W+:MODE_TAG_W] <= tag;
							mode_sample_ctr[idx * SAMPLE_W+:SAMPLE_W] <= sv2v_cast_80863_signed(1);
							mode_miss_ctr[idx * MISS_W+:MISS_W] <= sv2v_cast_EEBAF((rt_misp[p] ? 1'b1 : 1'b0));
							mode_candidate_hist[idx * BHR_BITS+:BHR_BITS] <= bhr_shift_in(1'sb0, rt_taken[p]);
							mode_long_slot_id[idx * SLOT_IDX_W+:SLOT_IDX_W] <= 1'sb0;
						end
					end
			end
			if (!mispred_any) begin : sv2v_autoblock_23
				reg signed [31:0] i;
				for (i = 0; i < IN_WIDTH; i = i + 1)
					if (((br_grant[i] && lane_use_long_q[i]) && lane_lookup_valid_q[i]) && (br_brtype[i * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] == sv2v_cast_B2A15(2))) begin : sv2v_autoblock_24
						reg [SLOT_IDX_W - 1:0] slot;
						reg [BHR_BITS - 1:0] bhr_src;
						reg [BHR_BITS - 1:0] bhr_new;
						slot = lane_slot_q[i * SLOT_IDX_W+:SLOT_IDX_W];
						if (epoch_tag_tmp[slot * 8+:8] == active_epoch_tmp)
							bhr_src = active_bhr_tmp[slot * BHR_BITS+:BHR_BITS];
						else
							bhr_src = commit_bhr_tmp[slot * BHR_BITS+:BHR_BITS];
						bhr_new = bhr_shift_in(bhr_src, br_taken[i]);
						active_bhr_tmp[slot * BHR_BITS+:BHR_BITS] = bhr_new;
						epoch_tag_tmp[slot * 8+:8] = active_epoch_tmp;
					end
			end
			begin : sv2v_autoblock_25
				reg signed [31:0] si;
				for (si = 0; si < LONG_SLOTS; si = si + 1)
					begin : sv2v_autoblock_26
						reg [1:0] head_tmp;
						reg [1:0] tail_tmp;
						reg [UPD_FIFO_BITS:0] count_tmp;
						head_tmp = upd_fifo_head[si * UPD_FIFO_BITS+:UPD_FIFO_BITS];
						tail_tmp = upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS];
						count_tmp = upd_fifo_count[0 + (si * 3)+:3];
						(* full_case, parallel_case *)
						case (upd_state[si * 2+:2])
							UPD_IDLE:
								if (upd_fifo_count[0 + (si * 3)+:3] != 0) begin
									if (upd_fifo_seed[(si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]]) begin : sv2v_autoblock_27
										reg found_bypass;
										found_bypass = 1'b0;
										begin : sv2v_autoblock_28
											reg signed [31:0] bi;
											for (bi = 0; bi < BYPASS_DEPTH; bi = bi + 1)
												if (bypass_valid[(si * BYPASS_DEPTH) + bi] && (bypass_addr[((si * BYPASS_DEPTH) + bi) * BHR_BITS+:BHR_BITS] == upd_fifo_addr[((si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]) * BHR_BITS+:BHR_BITS])) begin
													bypass_ctr[((si * BYPASS_DEPTH) + bi) * 2+:2] <= upd_fifo_seed_ctr[((si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]) * 2+:2];
													found_bypass = 1'b1;
												end
										end
										if (!found_bypass) begin
											bypass_valid[(si * BYPASS_DEPTH) + bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS]] <= 1'b1;
											bypass_addr[((si * BYPASS_DEPTH) + bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS]) * BHR_BITS+:BHR_BITS] <= upd_fifo_addr[((si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]) * BHR_BITS+:BHR_BITS];
											bypass_ctr[((si * BYPASS_DEPTH) + bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS]) * 2+:2] <= upd_fifo_seed_ctr[((si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]) * 2+:2];
											bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS] <= bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS] + sv2v_cast_4138B_signed(1);
										end
										tail_tmp = upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS] + sv2v_cast_4138B_signed(1);
										count_tmp = upd_fifo_count[0 + (si * 3)+:3] - 1'b1;
									end
									else begin
										pend_addr[si * BHR_BITS+:BHR_BITS] <= upd_fifo_addr[((si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]) * BHR_BITS+:BHR_BITS];
										pend_taken[si] <= upd_fifo_taken[(si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]];
									end
								end
							UPD_WAIT: begin : sv2v_autoblock_29
								reg [1:0] old_ctr;
								reg [1:0] new_ctr;
								reg found_bypass;
								old_ctr = pht_doutb_slot[si * 2+:2];
								found_bypass = 1'b0;
								begin : sv2v_autoblock_30
									reg signed [31:0] bi;
									for (bi = 0; bi < BYPASS_DEPTH; bi = bi + 1)
										if (bypass_valid[(si * BYPASS_DEPTH) + bi] && (bypass_addr[((si * BYPASS_DEPTH) + bi) * BHR_BITS+:BHR_BITS] == pend_addr[si * BHR_BITS+:BHR_BITS])) begin
											old_ctr = bypass_ctr[((si * BYPASS_DEPTH) + bi) * 2+:2];
											found_bypass = 1'b1;
										end
								end
								new_ctr = sat2_update(old_ctr, pend_taken[si]);
								pend_new_ctr[si * 2+:2] <= new_ctr;
								found_bypass = 1'b0;
								begin : sv2v_autoblock_31
									reg signed [31:0] bi;
									for (bi = 0; bi < BYPASS_DEPTH; bi = bi + 1)
										if (bypass_valid[(si * BYPASS_DEPTH) + bi] && (bypass_addr[((si * BYPASS_DEPTH) + bi) * BHR_BITS+:BHR_BITS] == pend_addr[si * BHR_BITS+:BHR_BITS])) begin
											bypass_ctr[((si * BYPASS_DEPTH) + bi) * 2+:2] <= new_ctr;
											found_bypass = 1'b1;
										end
								end
								if (!found_bypass) begin
									bypass_valid[(si * BYPASS_DEPTH) + bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS]] <= 1'b1;
									bypass_addr[((si * BYPASS_DEPTH) + bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS]) * BHR_BITS+:BHR_BITS] <= pend_addr[si * BHR_BITS+:BHR_BITS];
									bypass_ctr[((si * BYPASS_DEPTH) + bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS]) * 2+:2] <= new_ctr;
									bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS] <= bypass_ptr[si * BYPASS_BITS+:BYPASS_BITS] + sv2v_cast_4138B_signed(1);
								end
							end
							UPD_WRITE: begin
								tail_tmp = upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS] + sv2v_cast_4138B_signed(1);
								count_tmp = upd_fifo_count[0 + (si * 3)+:3] - 1'b1;
							end
							default:
								;
						endcase
						if (evt_valid[si]) begin
							if (count_tmp < UPD_FIFO_DEPTH) begin
								upd_fifo_addr[((si * UPD_FIFO_DEPTH) + head_tmp) * BHR_BITS+:BHR_BITS] <= evt_addr[si * BHR_BITS+:BHR_BITS];
								upd_fifo_taken[(si * UPD_FIFO_DEPTH) + head_tmp] <= evt_taken[si];
								upd_fifo_seed[(si * UPD_FIFO_DEPTH) + head_tmp] <= evt_seed[si];
								upd_fifo_seed_ctr[((si * UPD_FIFO_DEPTH) + head_tmp) * 2+:2] <= evt_seed_ctr[si * 2+:2];
								head_tmp = head_tmp + sv2v_cast_4138B_signed(1);
								count_tmp = count_tmp + 1'b1;
							end
						end
						upd_fifo_head[si * UPD_FIFO_BITS+:UPD_FIFO_BITS] <= head_tmp;
						upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS] <= tail_tmp;
						upd_fifo_count[0 + (si * 3)+:3] <= count_tmp;
						(* full_case, parallel_case *)
						case (upd_state[si * 2+:2])
							UPD_IDLE:
								if (upd_fifo_count[0 + (si * 3)+:3] != 0) begin
									if (upd_fifo_seed[(si * UPD_FIFO_DEPTH) + upd_fifo_tail[si * UPD_FIFO_BITS+:UPD_FIFO_BITS]])
										upd_state[si * 2+:2] <= UPD_IDLE;
									else
										upd_state[si * 2+:2] <= UPD_WAIT;
								end
								else
									upd_state[si * 2+:2] <= UPD_IDLE;
							UPD_WAIT: upd_state[si * 2+:2] <= UPD_WRITE;
							UPD_WRITE: upd_state[si * 2+:2] <= UPD_IDLE;
							default: upd_state[si * 2+:2] <= UPD_IDLE;
						endcase
					end
			end
			begin : sv2v_autoblock_32
				reg signed [31:0] si;
				for (si = 0; si < LONG_SLOTS; si = si + 1)
					begin
						active_bhr[si * BHR_BITS+:BHR_BITS] <= active_bhr_tmp[si * BHR_BITS+:BHR_BITS];
						commit_bhr[si * BHR_BITS+:BHR_BITS] <= commit_bhr_tmp[si * BHR_BITS+:BHR_BITS];
						epoch_tag[si * 8+:8] <= epoch_tag_tmp[si * 8+:8];
						if (epoch_tag_tmp[si * 8+:8] == active_epoch_tmp)
							shadow_bhr[si * BHR_BITS+:BHR_BITS] <= active_bhr_tmp[si * BHR_BITS+:BHR_BITS];
						else
							shadow_bhr[si * BHR_BITS+:BHR_BITS] <= commit_bhr_tmp[si * BHR_BITS+:BHR_BITS];
					end
			end
		end
	initial _sv2v_0 = 0;
endmodule
module sync_dp_bram_exc (
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
	parameter [31:0] ADDR_W = 6;
	parameter [31:0] DATA_W = 8;
	parameter [DATA_W - 1:0] INIT_VALUE = 1'sb0;
	input wire clka;
	input wire wea;
	input wire [ADDR_W - 1:0] addra;
	input wire [DATA_W - 1:0] dina;
	output wire [DATA_W - 1:0] douta;
	input wire clkb;
	input wire web;
	input wire [ADDR_W - 1:0] addrb;
	input wire [DATA_W - 1:0] dinb;
	output wire [DATA_W - 1:0] doutb;
	localparam [31:0] DEPTH = 1 << ADDR_W;
	localparam [31:0] MEM_BITS = DEPTH * DATA_W;
	(* ram_style = "block" *) reg [DATA_W - 1:0] mem [0:DEPTH - 1];
	reg [DATA_W - 1:0] douta_r;
	reg [DATA_W - 1:0] doutb_r;
	initial begin
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < DEPTH; i = i + 1)
				mem[i] = INIT_VALUE;
		end
		douta_r = INIT_VALUE;
		doutb_r = INIT_VALUE;
	end
	always @(posedge clka) begin
		if (wea)
			mem[addra] <= dina;
		douta_r <= mem[addra];
	end
	always @(posedge clka) begin
		if (web)
			mem[addrb] <= dinb;
		doutb_r <= mem[addrb];
	end
	assign douta = douta_r;
	assign doutb = doutb_r;
endmodule
