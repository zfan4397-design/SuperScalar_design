// Verilog-2005 translation; original module names and boundaries retained.
// Default build: USE_XPM, PRED_TRACE_EN and PRED_STATS_EN are undefined.
module direction_predict_v4 (
	clk,
	rst,
	have_inst_i,
	pc_i,
	lp,
	dbg_base_hist_o,
	dbg_prefix_hist_o,
	dbg_effective_hist_o,
	dbg_pht_row_o,
	dbg_ctr_idx_o,
	dbg_bypass_hit_o,
	dbg_final_ctr_o,
	dbg_ctr_src_o,
	br_grant,
	br_pc,
	br_brtype,
	br_taken,
	br_dir_enable_i,
	rt_grant,
	rt_pc,
	rt_brtype,
	rt_brdest,
	rt_exception,
	rt_dir_enable_i
);
	reg _sv2v_0;
	parameter [31:0] IN_WIDTH = 4;
	parameter [31:0] PORT_WIDTH = 2;
	parameter [31:0] BHT_IDX_BITS = 4;
	parameter [31:0] BHR_BITS = 9;
	parameter [31:0] PC_SPLICE_BITS = 5;
	parameter [31:0] PHT_BANK_BITS = 3;
	parameter [31:0] BUF_BITS = 2;
	parameter [1:0] PHT_INIT_STATE = 2'b11;
	input wire clk;
	input wire rst;
	input wire have_inst_i;
	localparam signed [31:0] config_pkg_PC_WIDTH = 32;
	input wire [31:0] pc_i;
	output reg [(IN_WIDTH * 2) - 1:0] lp;
	output reg [(IN_WIDTH * BHR_BITS) - 1:0] dbg_base_hist_o;
	output reg [(IN_WIDTH * BHR_BITS) - 1:0] dbg_prefix_hist_o;
	output reg [(IN_WIDTH * BHR_BITS) - 1:0] dbg_effective_hist_o;
	localparam [31:0] FETCH_BANK_W = $clog2(IN_WIDTH);
	localparam [31:0] PHT_PC_ADDR_W = PC_SPLICE_BITS - FETCH_BANK_W;
	output reg [(IN_WIDTH * PHT_PC_ADDR_W) - 1:0] dbg_pht_row_o;
	localparam [31:0] PHT_SUBIDX_W = BHR_BITS - PHT_BANK_BITS;
	output reg [(PHT_SUBIDX_W >= 0 ? (IN_WIDTH * (PHT_SUBIDX_W + 1)) - 1 : (IN_WIDTH * (1 - PHT_SUBIDX_W)) + (PHT_SUBIDX_W - 1)):(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W + 0)] dbg_ctr_idx_o;
	output reg [IN_WIDTH - 1:0] dbg_bypass_hit_o;
	output reg [(IN_WIDTH * 2) - 1:0] dbg_final_ctr_o;
	output reg [(IN_WIDTH * 2) - 1:0] dbg_ctr_src_o;
	input wire [IN_WIDTH - 1:0] br_grant;
	input wire [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] br_pc;
	localparam signed [31:0] config_pkg_BRTYPE_WIDTH = 2;
	input wire [(IN_WIDTH * config_pkg_BRTYPE_WIDTH) - 1:0] br_brtype;
	input wire [IN_WIDTH - 1:0] br_taken;
	input wire [IN_WIDTH - 1:0] br_dir_enable_i;
	input wire [PORT_WIDTH - 1:0] rt_grant;
	input wire [(PORT_WIDTH * config_pkg_PC_WIDTH) - 1:0] rt_pc;
	input wire [(PORT_WIDTH * config_pkg_BRTYPE_WIDTH) - 1:0] rt_brtype;
	input wire [(PORT_WIDTH * config_pkg_PC_WIDTH) - 1:0] rt_brdest;
	localparam signed [31:0] config_pkg_EXCPT_WIDTH = 4;
	input wire [(PORT_WIDTH * config_pkg_EXCPT_WIDTH) - 1:0] rt_exception;
	input wire [PORT_WIDTH - 1:0] rt_dir_enable_i;
	localparam [31:0] EPOCH_BITS = 8;
	localparam [31:0] BHT_ADDR_W = BHT_IDX_BITS - FETCH_BANK_W;
	localparam [31:0] BHT_ENTRIES = 1 << BHT_IDX_BITS;
	localparam [31:0] BUF_DEPTH = 1 << BUF_BITS;
	localparam [31:0] PHT_BANKS = 1 << PHT_BANK_BITS;
	localparam [31:0] PHT_SUBLINE_W = (1 << PHT_SUBIDX_W) * 2;
	localparam [31:0] BYPASS_BITS = 2;
	localparam [31:0] BYPASS_DEPTH = 4;
	localparam [PHT_SUBLINE_W - 1:0] PHT_INIT_SUBLINE = {1 << PHT_SUBIDX_W {PHT_INIT_STATE}};
	localparam [0:0] STATE_RD_OLD = 1'b0;
	localparam [0:0] STATE_WR_NEW = 1'b1;
	reg [BHR_BITS - 1:0] active_bht [0:BHT_ENTRIES - 1];
	reg [BHR_BITS - 1:0] commit_bht [0:BHT_ENTRIES - 1];
	reg [7:0] epoch_tag [0:BHT_ENTRIES - 1];
	reg [BHR_BITS - 1:0] shadow_bht [0:BHT_ENTRIES - 1];
	reg have_q;
	reg [7:0] active_epoch;
	reg [7:0] epoch_next;
	reg [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] lane_pc_now;
	reg [(IN_WIDTH * FETCH_BANK_W) - 1:0] lane_fetch_bank_now;
	reg [(IN_WIDTH * BHT_IDX_BITS) - 1:0] lane_bht_idx_now;
	reg [(IN_WIDTH * PHT_PC_ADDR_W) - 1:0] lane_pht_pc_addr_now;
	reg [(IN_WIDTH * FETCH_BANK_W) - 1:0] lane_fetch_bank_q;
	reg [(IN_WIDTH * BHT_IDX_BITS) - 1:0] lane_bht_idx_q;
	reg [(IN_WIDTH * PHT_PC_ADDR_W) - 1:0] lane_pht_pc_addr_q;
	reg [(IN_WIDTH * BHR_BITS) - 1:0] lane_base_hist_live;
	reg [(IN_WIDTH * BHR_BITS) - 1:0] lane_prefix_hist_comb;
	reg [(IN_WIDTH * BHR_BITS) - 1:0] lane_hist_eff_comb;
	reg [(PHT_SUBIDX_W >= 0 ? (IN_WIDTH * (PHT_SUBIDX_W + 1)) - 1 : (IN_WIDTH * (1 - PHT_SUBIDX_W)) + (PHT_SUBIDX_W - 1)):(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W + 0)] lane_ctr_idx_comb;
	reg [(IN_WIDTH * 2) - 1:0] lane_ctr_final_comb;
	reg [(IN_WIDTH * 2) - 1:0] lane_ctr_src_comb;
	reg [IN_WIDTH - 1:0] lane_bypass_hit_comb;
	reg [IN_WIDTH - 1:0] lane_pred_taken_comb;
	reg [(IN_WIDTH * FETCH_BANK_W) - 1:0] br_fetch_bank;
	reg [(IN_WIDTH * BHT_IDX_BITS) - 1:0] br_bht_idx;
	reg [PORT_WIDTH - 1:0] rt_is_dir;
	reg [PORT_WIDTH - 1:0] rt_valid_dir;
	reg [(PORT_WIDTH * FETCH_BANK_W) - 1:0] rt_fetch_bank;
	reg [(PORT_WIDTH * BHT_IDX_BITS) - 1:0] rt_bht_idx;
	reg [(PORT_WIDTH * PHT_PC_ADDR_W) - 1:0] rt_pht_pc_addr;
	reg [PORT_WIDTH - 1:0] rt_taken;
	reg [PORT_WIDTH - 1:0] rt_misp;
	reg [(PORT_WIDTH * BHR_BITS) - 1:0] rt_old_bhr;
	reg [(PORT_WIDTH * PHT_BANK_BITS) - 1:0] rt_pht_bank_sel;
	reg [(PHT_SUBIDX_W >= 0 ? (PORT_WIDTH * (PHT_SUBIDX_W + 1)) - 1 : (PORT_WIDTH * (1 - PHT_SUBIDX_W)) + (PHT_SUBIDX_W - 1)):(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W + 0)] rt_pht_ctr_idx;
	reg mispred_any;
	reg [((IN_WIDTH * PHT_BANKS) * PHT_PC_ADDR_W) - 1:0] pht_addra_bank;
	wire [((IN_WIDTH * PHT_BANKS) * PHT_SUBLINE_W) - 1:0] pht_douta_bank;
	reg [(IN_WIDTH * PHT_BANKS) - 1:0] pht_web_bank;
	reg [((IN_WIDTH * PHT_BANKS) * PHT_PC_ADDR_W) - 1:0] pht_addrb_bank;
	reg [((IN_WIDTH * PHT_BANKS) * PHT_SUBLINE_W) - 1:0] pht_dinb_bank;
	wire [((IN_WIDTH * PHT_BANKS) * PHT_SUBLINE_W) - 1:0] pht_doutb_bank;
	reg [((IN_WIDTH * PHT_BANKS) * 32) - 1:0] fifo_push_count_dbg;
	reg [((IN_WIDTH * PHT_BANKS) * 32) - 1:0] fifo_drop_count_dbg;
	reg [(BUF_BITS >= 0 ? ((IN_WIDTH * PHT_BANKS) * (BUF_BITS + 1)) - 1 : ((IN_WIDTH * PHT_BANKS) * (1 - BUF_BITS)) + (BUF_BITS - 1)):(BUF_BITS >= 0 ? 0 : BUF_BITS + 0)] fifo_peak_depth_dbg;
	reg [((IN_WIDTH * PHT_BANKS) * 4) - 1:0] bypass_valid;
	reg [(((IN_WIDTH * PHT_BANKS) * 4) * PHT_PC_ADDR_W) - 1:0] bypass_row;
	reg [(PHT_SUBIDX_W >= 0 ? (((IN_WIDTH * PHT_BANKS) * 4) * (PHT_SUBIDX_W + 1)) - 1 : (((IN_WIDTH * PHT_BANKS) * 4) * (1 - PHT_SUBIDX_W)) + (PHT_SUBIDX_W - 1)):(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W + 0)] bypass_ctr_idx;
	reg [(((IN_WIDTH * PHT_BANKS) * 4) * 2) - 1:0] bypass_ctr;
	reg [((IN_WIDTH * PHT_BANKS) * 2) - 1:0] bypass_ptr;
	reg [31:0] dbg_bp_fifo_push_count;
	reg [31:0] dbg_bp_fifo_drop_count;
	reg [31:0] dbg_bp_fifo_peak_depth;
	reg [31:0] dbg_bp_repair_count;
	genvar _gv_g_1;
	initial begin
		if ((IN_WIDTH == 0) || ((IN_WIDTH & (IN_WIDTH - 1)) != 0)) begin
			$display("direction_predict_v4 requires IN_WIDTH to be a non-zero power of two");
			$finish;
		end
		if (BHT_IDX_BITS <= FETCH_BANK_W) begin
			$display("direction_predict_v4 requires BHT_IDX_BITS > $clog2(IN_WIDTH)");
			$finish;
		end
		if (PC_SPLICE_BITS <= FETCH_BANK_W) begin
			$display("direction_predict_v4 requires PC_SPLICE_BITS > $clog2(IN_WIDTH)");
			$finish;
		end
		if (BHR_BITS < PHT_BANK_BITS) begin
			$display("direction_predict_v4 requires BHR_BITS >= PHT_BANK_BITS");
			$finish;
		end
	end
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
	function automatic [BHT_ADDR_W - 1:0] pc_fold_bht_local_idx;
		input reg [31:0] pc;
		reg [BHT_ADDR_W - 1:0] idx;
		integer bit_i;
		integer slot;
		begin
			idx = 1'sb0;
			for (bit_i = FETCH_BANK_W + 2; bit_i < config_pkg_PC_WIDTH; bit_i = bit_i + 1)
				begin
					slot = (bit_i - (FETCH_BANK_W + 2)) % BHT_ADDR_W;
					idx[slot] = idx[slot] ^ pc[bit_i];
				end
			pc_fold_bht_local_idx = idx;
		end
	endfunction
	function automatic [PHT_PC_ADDR_W - 1:0] pc_fold_pht_row_idx;
		input reg [31:0] pc;
		reg [PHT_PC_ADDR_W - 1:0] idx;
		integer bit_i;
		integer slot;
		begin
			idx = 1'sb0;
			for (bit_i = FETCH_BANK_W + 2; bit_i < config_pkg_PC_WIDTH; bit_i = bit_i + 1)
				begin
					slot = (bit_i - (FETCH_BANK_W + 2)) % PHT_PC_ADDR_W;
					idx[slot] = idx[slot] ^ pc[bit_i];
				end
			pc_fold_pht_row_idx = idx;
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
		lane_fetch_bank_now = 1'sb0;
		lane_bht_idx_now = 1'sb0;
		lane_pht_pc_addr_now = 1'sb0;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				begin
					lane_pc_now[i * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = pc_i + sv2v_cast_32($unsigned(i) << 2);
					lane_fetch_bank_now[i * FETCH_BANK_W+:FETCH_BANK_W] = lane_pc_now[(i * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W];
					lane_bht_idx_now[i * BHT_IDX_BITS+:BHT_IDX_BITS] = {lane_fetch_bank_now[i * FETCH_BANK_W+:FETCH_BANK_W], pc_fold_bht_local_idx(lane_pc_now[i * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH])};
					lane_pht_pc_addr_now[i * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] = pc_fold_pht_row_idx(lane_pc_now[i * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH]);
				end
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		lane_base_hist_live = 1'sb0;
		begin : sv2v_autoblock_2
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				lane_base_hist_live[i * BHR_BITS+:BHR_BITS] = shadow_bht[lane_bht_idx_q[i * BHT_IDX_BITS+:BHT_IDX_BITS]];
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		pht_addra_bank = 1'sb0;
		begin : sv2v_autoblock_3
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				begin : sv2v_autoblock_4
					reg signed [31:0] sb;
					for (sb = 0; sb < PHT_BANKS; sb = sb + 1)
						pht_addra_bank[((lane_fetch_bank_now[i * FETCH_BANK_W+:FETCH_BANK_W] * PHT_BANKS) + sb) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] = lane_pht_pc_addr_now[i * PHT_PC_ADDR_W+:PHT_PC_ADDR_W];
				end
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		br_fetch_bank = 1'sb0;
		br_bht_idx = 1'sb0;
		begin : sv2v_autoblock_5
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				begin
					br_fetch_bank[i * FETCH_BANK_W+:FETCH_BANK_W] = br_pc[(i * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W];
					br_bht_idx[i * BHT_IDX_BITS+:BHT_IDX_BITS] = {br_fetch_bank[i * FETCH_BANK_W+:FETCH_BANK_W], pc_fold_bht_local_idx(br_pc[i * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH])};
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
		mispred_any = 1'b0;
		rt_is_dir = 1'sb0;
		rt_valid_dir = 1'sb0;
		rt_fetch_bank = 1'sb0;
		rt_bht_idx = 1'sb0;
		rt_pht_pc_addr = 1'sb0;
		rt_taken = 1'sb0;
		rt_misp = 1'sb0;
		rt_old_bhr = 1'sb0;
		rt_pht_bank_sel = 1'sb0;
		rt_pht_ctr_idx = 1'sb0;
		begin : sv2v_autoblock_6
			reg signed [31:0] p;
			for (p = 0; p < PORT_WIDTH; p = p + 1)
				begin
					rt_is_dir[p] = rt_grant[p] && (rt_brtype[p * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] == sv2v_cast_B2A15(2));
					rt_valid_dir[p] = rt_is_dir[p] && rt_dir_enable_i[p];
					rt_fetch_bank[p * FETCH_BANK_W+:FETCH_BANK_W] = rt_pc[(p * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W];
					rt_bht_idx[p * BHT_IDX_BITS+:BHT_IDX_BITS] = {rt_fetch_bank[p * FETCH_BANK_W+:FETCH_BANK_W], pc_fold_bht_local_idx(rt_pc[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH])};
					rt_pht_pc_addr[p * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] = pc_fold_pht_row_idx(rt_pc[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH]);
					rt_taken[p] = rt_brdest[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] != (rt_pc[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] + $unsigned(32'd4));
					rt_misp[p] = rt_exception[p * config_pkg_EXCPT_WIDTH+:config_pkg_EXCPT_WIDTH] == sv2v_cast_E0276(1);
					rt_old_bhr[p * BHR_BITS+:BHR_BITS] = commit_bht[rt_bht_idx[p * BHT_IDX_BITS+:BHT_IDX_BITS]];
					rt_pht_bank_sel[p * PHT_BANK_BITS+:PHT_BANK_BITS] = rt_old_bhr[(p * BHR_BITS) + (PHT_BANK_BITS - 1)-:PHT_BANK_BITS];
					rt_pht_ctr_idx[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (p * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)] = {rt_old_bhr[(p * BHR_BITS) + ((BHR_BITS - 1) >= PHT_BANK_BITS ? BHR_BITS - 1 : ((BHR_BITS - 1) + ((BHR_BITS - 1) >= PHT_BANK_BITS ? ((BHR_BITS - 1) - PHT_BANK_BITS) + 1 : (PHT_BANK_BITS - (BHR_BITS - 1)) + 1)) - 1)-:((BHR_BITS - 1) >= PHT_BANK_BITS ? ((BHR_BITS - 1) - PHT_BANK_BITS) + 1 : (PHT_BANK_BITS - (BHR_BITS - 1)) + 1)], 1'b0};
					mispred_any = mispred_any | (rt_is_dir[p] && rt_misp[p]);
				end
		end
	end
	function automatic [7:0] sv2v_cast_4E301;
		input reg [7:0] inp;
		sv2v_cast_4E301 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		epoch_next = active_epoch + sv2v_cast_4E301((mispred_any ? 1'b1 : 1'b0));
	end
	always @(*) begin
		if (_sv2v_0)
			;
		lp = 1'sb0;
		lane_prefix_hist_comb = 1'sb0;
		lane_hist_eff_comb = 1'sb0;
		lane_ctr_idx_comb = 1'sb0;
		lane_ctr_final_comb = 1'sb0;
		lane_ctr_src_comb = 1'sb0;
		lane_bypass_hit_comb = 1'sb0;
		lane_pred_taken_comb = 1'sb0;
		dbg_base_hist_o = 1'sb0;
		dbg_prefix_hist_o = 1'sb0;
		dbg_effective_hist_o = 1'sb0;
		dbg_pht_row_o = 1'sb0;
		dbg_ctr_idx_o = 1'sb0;
		dbg_bypass_hit_o = 1'sb0;
		dbg_final_ctr_o = 1'sb0;
		dbg_ctr_src_o = 1'sb0;
		begin : sv2v_autoblock_7
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				begin : sv2v_autoblock_8
					reg [PHT_BANK_BITS - 1:0] pht_bank_sel;
					reg [PHT_SUBIDX_W:0] ctr_idx;
					reg [1:0] ctr_sel;
					reg bypass_hit;
					pht_bank_sel = lane_base_hist_live[(i * BHR_BITS) + (PHT_BANK_BITS - 1)-:PHT_BANK_BITS];
					ctr_idx = {lane_base_hist_live[(i * BHR_BITS) + ((BHR_BITS - 1) >= PHT_BANK_BITS ? BHR_BITS - 1 : ((BHR_BITS - 1) + ((BHR_BITS - 1) >= PHT_BANK_BITS ? ((BHR_BITS - 1) - PHT_BANK_BITS) + 1 : (PHT_BANK_BITS - (BHR_BITS - 1)) + 1)) - 1)-:((BHR_BITS - 1) >= PHT_BANK_BITS ? ((BHR_BITS - 1) - PHT_BANK_BITS) + 1 : (PHT_BANK_BITS - (BHR_BITS - 1)) + 1)], 1'b0};
					ctr_sel = pht_douta_bank[(((lane_fetch_bank_q[i * FETCH_BANK_W+:FETCH_BANK_W] * PHT_BANKS) + pht_bank_sel) * PHT_SUBLINE_W) + ctr_idx+:2];
					bypass_hit = 1'b0;
					begin : sv2v_autoblock_9
						reg signed [31:0] b;
						for (b = 0; b < BYPASS_DEPTH; b = b + 1)
							if ((bypass_valid[(((lane_fetch_bank_q[i * FETCH_BANK_W+:FETCH_BANK_W] * PHT_BANKS) + pht_bank_sel) * 4) + b] && (bypass_row[((((lane_fetch_bank_q[i * FETCH_BANK_W+:FETCH_BANK_W] * PHT_BANKS) + pht_bank_sel) * 4) + b) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] == lane_pht_pc_addr_q[i * PHT_PC_ADDR_W+:PHT_PC_ADDR_W])) && (bypass_ctr_idx[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (((((lane_fetch_bank_q[i * FETCH_BANK_W+:FETCH_BANK_W] * PHT_BANKS) + pht_bank_sel) * 4) + b) * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)] == ctr_idx)) begin
								ctr_sel = bypass_ctr[((((lane_fetch_bank_q[i * FETCH_BANK_W+:FETCH_BANK_W] * PHT_BANKS) + pht_bank_sel) * 4) + b) * 2+:2];
								bypass_hit = 1'b1;
							end
					end
					lane_prefix_hist_comb[i * BHR_BITS+:BHR_BITS] = lane_base_hist_live[i * BHR_BITS+:BHR_BITS];
					lane_hist_eff_comb[i * BHR_BITS+:BHR_BITS] = lane_base_hist_live[i * BHR_BITS+:BHR_BITS];
					lane_ctr_idx_comb[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (i * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)] = ctr_idx;
					lane_bypass_hit_comb[i] = have_q && bypass_hit;
					lane_ctr_final_comb[i * 2+:2] = (have_q ? ctr_sel : 2'b00);
					lane_ctr_src_comb[i * 2+:2] = (have_q ? (bypass_hit ? 2'd1 : 2'd0) : 2'd0);
					lane_pred_taken_comb[i] = (have_q ? ctr_sel[1] : 1'b0);
					lp[i * 2+:2] = lane_ctr_final_comb[i * 2+:2];
					dbg_base_hist_o[i * BHR_BITS+:BHR_BITS] = lane_base_hist_live[i * BHR_BITS+:BHR_BITS];
					dbg_prefix_hist_o[i * BHR_BITS+:BHR_BITS] = lane_prefix_hist_comb[i * BHR_BITS+:BHR_BITS];
					dbg_effective_hist_o[i * BHR_BITS+:BHR_BITS] = lane_hist_eff_comb[i * BHR_BITS+:BHR_BITS];
					dbg_pht_row_o[i * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] = lane_pht_pc_addr_q[i * PHT_PC_ADDR_W+:PHT_PC_ADDR_W];
					dbg_ctr_idx_o[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (i * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)] = lane_ctr_idx_comb[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (i * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)];
					dbg_bypass_hit_o[i] = lane_bypass_hit_comb[i];
					dbg_final_ctr_o[i * 2+:2] = lane_ctr_final_comb[i * 2+:2];
					dbg_ctr_src_o[i * 2+:2] = lane_ctr_src_comb[i * 2+:2];
				end
		end
	end
	always @(*) begin
		if (_sv2v_0)
			;
		dbg_bp_fifo_push_count = 1'sb0;
		dbg_bp_fifo_drop_count = 1'sb0;
		dbg_bp_fifo_peak_depth = 1'sb0;
		begin : sv2v_autoblock_10
			reg signed [31:0] bank;
			for (bank = 0; bank < IN_WIDTH; bank = bank + 1)
				begin : sv2v_autoblock_11
					reg signed [31:0] sb;
					for (sb = 0; sb < PHT_BANKS; sb = sb + 1)
						begin
							dbg_bp_fifo_push_count = dbg_bp_fifo_push_count + fifo_push_count_dbg[((bank * PHT_BANKS) + sb) * 32+:32];
							dbg_bp_fifo_drop_count = dbg_bp_fifo_drop_count + fifo_drop_count_dbg[((bank * PHT_BANKS) + sb) * 32+:32];
							if (fifo_peak_depth_dbg[(BUF_BITS >= 0 ? 0 : BUF_BITS) + (((bank * PHT_BANKS) + sb) * (BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS))+:(BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS)] > dbg_bp_fifo_peak_depth[BUF_BITS:0])
								dbg_bp_fifo_peak_depth = fifo_peak_depth_dbg[(BUF_BITS >= 0 ? 0 : BUF_BITS) + (((bank * PHT_BANKS) + sb) * (BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS))+:(BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS)];
						end
				end
		end
	end
	generate
		for (_gv_g_1 = 0; _gv_g_1 < IN_WIDTH; _gv_g_1 = _gv_g_1 + 1) begin : gen_pht_mem
			localparam g = _gv_g_1;
			genvar _gv_sb_1;
			for (_gv_sb_1 = 0; _gv_sb_1 < PHT_BANKS; _gv_sb_1 = _gv_sb_1 + 1) begin : gen_pht_subbank
				localparam sb = _gv_sb_1;
				localparam [31:0] sv2v_uu_u_pht_mem_DATA_W = PHT_SUBLINE_W;
				localparam [PHT_SUBLINE_W - 1:0] sv2v_uu_u_pht_mem_ext_dina_0 = 1'sb0;
				sync_dp_bram #(
					.ADDR_W(PHT_PC_ADDR_W),
					.DATA_W(PHT_SUBLINE_W),
					.INIT_VALUE(PHT_INIT_SUBLINE)
				) u_pht_mem(
					.clka(clk),
					.wea(1'b0),
					.addra(pht_addra_bank[((g * PHT_BANKS) + sb) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W]),
					.dina(sv2v_uu_u_pht_mem_ext_dina_0),
					.douta(pht_douta_bank[((g * PHT_BANKS) + sb) * PHT_SUBLINE_W+:PHT_SUBLINE_W]),
					.clkb(clk),
					.web(pht_web_bank[(g * PHT_BANKS) + sb]),
					.addrb(pht_addrb_bank[((g * PHT_BANKS) + sb) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W]),
					.dinb(pht_dinb_bank[((g * PHT_BANKS) + sb) * PHT_SUBLINE_W+:PHT_SUBLINE_W]),
					.doutb(pht_doutb_bank[((g * PHT_BANKS) + sb) * PHT_SUBLINE_W+:PHT_SUBLINE_W])
				);
			end
		end
	endgenerate
	always @(posedge clk)
		if (rst) begin
			have_q <= 1'b0;
			lane_fetch_bank_q <= 1'sb0;
			lane_bht_idx_q <= 1'sb0;
			lane_pht_pc_addr_q <= 1'sb0;
			active_epoch <= 1'sb0;
			dbg_bp_repair_count <= 1'sb0;
			begin : sv2v_autoblock_12
				reg signed [31:0] bi;
				for (bi = 0; bi < BHT_ENTRIES; bi = bi + 1)
					begin
						active_bht[bi] <= 1'sb0;
						commit_bht[bi] <= 1'sb0;
						epoch_tag[bi] <= 1'sb0;
						shadow_bht[bi] <= 1'sb0;
					end
			end
		end
		else begin : sv2v_autoblock_13
			reg [BHR_BITS - 1:0] active_bht_tmp [0:BHT_ENTRIES - 1];
			reg [BHR_BITS - 1:0] commit_bht_tmp [0:BHT_ENTRIES - 1];
			reg [7:0] epoch_tag_tmp [0:BHT_ENTRIES - 1];
			reg [7:0] active_epoch_tmp;
			reg [31:0] repair_inc;
			repair_inc = 1'sb0;
			active_epoch_tmp = (mispred_any ? epoch_next : active_epoch);
			begin : sv2v_autoblock_14
				reg signed [31:0] bi;
				for (bi = 0; bi < BHT_ENTRIES; bi = bi + 1)
					begin
						active_bht_tmp[bi] = active_bht[bi];
						commit_bht_tmp[bi] = commit_bht[bi];
						epoch_tag_tmp[bi] = epoch_tag[bi];
					end
			end
			have_q <= have_inst_i;
			lane_fetch_bank_q <= lane_fetch_bank_now;
			lane_bht_idx_q <= lane_bht_idx_now;
			lane_pht_pc_addr_q <= lane_pht_pc_addr_now;
			active_epoch <= active_epoch_tmp;
			begin : sv2v_autoblock_15
				reg signed [31:0] p;
				for (p = 0; p < PORT_WIDTH; p = p + 1)
					if (rt_valid_dir[p]) begin : sv2v_autoblock_16
						reg [BHT_IDX_BITS - 1:0] idx_u;
						reg [BHR_BITS - 1:0] old_bhr_c;
						reg [BHR_BITS - 1:0] new_bhr_c;
						idx_u = rt_bht_idx[p * BHT_IDX_BITS+:BHT_IDX_BITS];
						old_bhr_c = commit_bht_tmp[idx_u];
						new_bhr_c = bhr_shift_in(old_bhr_c, rt_taken[p]);
						commit_bht_tmp[idx_u] = new_bhr_c;
						if (rt_misp[p]) begin
							active_bht_tmp[idx_u] = new_bhr_c;
							epoch_tag_tmp[idx_u] = epoch_next;
							repair_inc = repair_inc + 32'd1;
						end
					end
			end
			if (!mispred_any) begin : sv2v_autoblock_17
				reg signed [31:0] i;
				for (i = 0; i < IN_WIDTH; i = i + 1)
					if ((br_grant[i] && br_dir_enable_i[i]) && (br_brtype[i * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] == sv2v_cast_B2A15(2))) begin : sv2v_autoblock_18
						reg [BHT_IDX_BITS - 1:0] idx_s;
						reg [BHR_BITS - 1:0] bhr_src;
						reg [BHR_BITS - 1:0] bhr_new;
						idx_s = br_bht_idx[i * BHT_IDX_BITS+:BHT_IDX_BITS];
						if (epoch_tag_tmp[idx_s] == active_epoch_tmp)
							bhr_src = active_bht_tmp[idx_s];
						else
							bhr_src = commit_bht_tmp[idx_s];
						bhr_new = bhr_shift_in(bhr_src, br_taken[i]);
						active_bht_tmp[idx_s] = bhr_new;
						epoch_tag_tmp[idx_s] = active_epoch_tmp;
					end
			end
			begin : sv2v_autoblock_19
				reg signed [31:0] bi;
				for (bi = 0; bi < BHT_ENTRIES; bi = bi + 1)
					begin
						active_bht[bi] <= active_bht_tmp[bi];
						commit_bht[bi] <= commit_bht_tmp[bi];
						epoch_tag[bi] <= epoch_tag_tmp[bi];
						if (epoch_tag_tmp[bi] == active_epoch_tmp)
							shadow_bht[bi] <= active_bht_tmp[bi];
						else
							shadow_bht[bi] <= commit_bht_tmp[bi];
					end
			end
			dbg_bp_repair_count <= dbg_bp_repair_count + repair_inc;
		end
	function automatic signed [1:0] sv2v_cast_4138B_signed;
		input reg signed [1:0] inp;
		sv2v_cast_4138B_signed = inp;
	endfunction
	function automatic signed [BUF_BITS - 1:0] sv2v_cast_8A43F_signed;
		input reg signed [BUF_BITS - 1:0] inp;
		sv2v_cast_8A43F_signed = inp;
	endfunction
	function automatic signed [FETCH_BANK_W - 1:0] sv2v_cast_EA7F4_signed;
		input reg signed [FETCH_BANK_W - 1:0] inp;
		sv2v_cast_EA7F4_signed = inp;
	endfunction
	function automatic signed [PHT_BANK_BITS - 1:0] sv2v_cast_5B3BE_signed;
		input reg signed [PHT_BANK_BITS - 1:0] inp;
		sv2v_cast_5B3BE_signed = inp;
	endfunction
	generate
		for (_gv_g_1 = 0; _gv_g_1 < IN_WIDTH; _gv_g_1 = _gv_g_1 + 1) begin : gen_pht_queue_bank
			localparam g = _gv_g_1;
			genvar _gv_sb_2;
			for (_gv_sb_2 = 0; _gv_sb_2 < PHT_BANKS; _gv_sb_2 = _gv_sb_2 + 1) begin : gen_pht_queue
				localparam sb = _gv_sb_2;
				reg [PHT_PC_ADDR_W - 1:0] fifo_pht_addr [0:BUF_DEPTH - 1];
				reg [PHT_SUBIDX_W:0] fifo_ctr_idx [0:BUF_DEPTH - 1];
				reg fifo_taken [0:BUF_DEPTH - 1];
				reg [BUF_BITS - 1:0] fifo_head;
				reg [BUF_BITS - 1:0] fifo_tail;
				reg [BUF_BITS:0] fifo_count;
				reg curr_state;
				reg next_state;
				reg [PHT_PC_ADDR_W - 1:0] pend_pht_addr;
				reg [PHT_SUBIDX_W:0] pend_ctr_idx;
				reg pend_taken;
				reg [PHT_SUBLINE_W - 1:0] old_pht_subline;
				reg [PHT_SUBLINE_W - 1:0] new_pht_subline;
				reg [1:0] old_ctr;
				reg [1:0] new_ctr;
				always @(*) begin
					if (_sv2v_0)
						;
					next_state = curr_state;
					(* full_case, parallel_case *)
					case (curr_state)
						STATE_RD_OLD:
							if (fifo_count != 0)
								next_state = STATE_WR_NEW;
						STATE_WR_NEW: next_state = STATE_RD_OLD;
						default: next_state = STATE_RD_OLD;
					endcase
				end
				always @(*) begin
					if (_sv2v_0)
						;
					old_pht_subline = pht_doutb_bank[((g * PHT_BANKS) + sb) * PHT_SUBLINE_W+:PHT_SUBLINE_W];
					old_ctr = old_pht_subline[pend_ctr_idx+:2];
					begin : sv2v_autoblock_20
						reg signed [31:0] bi;
						for (bi = 0; bi < BYPASS_DEPTH; bi = bi + 1)
							if ((bypass_valid[(((g * PHT_BANKS) + sb) * 4) + bi] && (bypass_row[((((g * PHT_BANKS) + sb) * 4) + bi) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] == pend_pht_addr)) && (bypass_ctr_idx[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (((((g * PHT_BANKS) + sb) * 4) + bi) * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)] == pend_ctr_idx))
								old_ctr = bypass_ctr[((((g * PHT_BANKS) + sb) * 4) + bi) * 2+:2];
					end
					new_ctr = sat2_update(old_ctr, pend_taken);
					new_pht_subline = old_pht_subline;
					new_pht_subline[pend_ctr_idx+:2] = new_ctr;
				end
				always @(*) begin
					if (_sv2v_0)
						;
					pht_web_bank[(g * PHT_BANKS) + sb] = 1'b0;
					pht_addrb_bank[((g * PHT_BANKS) + sb) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] = 1'sb0;
					pht_dinb_bank[((g * PHT_BANKS) + sb) * PHT_SUBLINE_W+:PHT_SUBLINE_W] = 1'sb0;
					if (curr_state == STATE_RD_OLD) begin
						if (fifo_count != 0)
							pht_addrb_bank[((g * PHT_BANKS) + sb) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] = fifo_pht_addr[fifo_tail];
					end
					else begin
						pht_web_bank[(g * PHT_BANKS) + sb] = 1'b1;
						pht_addrb_bank[((g * PHT_BANKS) + sb) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] = pend_pht_addr;
						pht_dinb_bank[((g * PHT_BANKS) + sb) * PHT_SUBLINE_W+:PHT_SUBLINE_W] = new_pht_subline;
					end
				end
				always @(posedge clk)
					if (rst) begin
						fifo_head <= 1'sb0;
						fifo_tail <= 1'sb0;
						fifo_count <= 1'sb0;
						curr_state <= STATE_RD_OLD;
						pend_pht_addr <= 1'sb0;
						pend_ctr_idx <= 1'sb0;
						pend_taken <= 1'b0;
						fifo_push_count_dbg[((g * PHT_BANKS) + sb) * 32+:32] <= 1'sb0;
						fifo_drop_count_dbg[((g * PHT_BANKS) + sb) * 32+:32] <= 1'sb0;
						fifo_peak_depth_dbg[(BUF_BITS >= 0 ? 0 : BUF_BITS) + (((g * PHT_BANKS) + sb) * (BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS))+:(BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS)] <= 1'sb0;
						bypass_ptr[((g * PHT_BANKS) + sb) * 2+:2] <= 1'sb0;
						begin : sv2v_autoblock_21
							reg signed [31:0] bi;
							for (bi = 0; bi < BYPASS_DEPTH; bi = bi + 1)
								begin
									bypass_valid[(((g * PHT_BANKS) + sb) * 4) + bi] <= 1'b0;
									bypass_row[((((g * PHT_BANKS) + sb) * 4) + bi) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] <= 1'sb0;
									bypass_ctr_idx[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (((((g * PHT_BANKS) + sb) * 4) + bi) * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)] <= 1'sb0;
									bypass_ctr[((((g * PHT_BANKS) + sb) * 4) + bi) * 2+:2] <= PHT_INIT_STATE;
								end
						end
					end
					else begin : sv2v_autoblock_22
						reg [BUF_BITS - 1:0] head_tmp;
						reg [BUF_BITS - 1:0] tail_tmp;
						reg [BUF_BITS:0] count_tmp;
						reg [31:0] push_count_tmp;
						reg [31:0] drop_count_tmp;
						head_tmp = fifo_head;
						tail_tmp = fifo_tail;
						count_tmp = fifo_count;
						push_count_tmp = fifo_push_count_dbg[((g * PHT_BANKS) + sb) * 32+:32];
						drop_count_tmp = fifo_drop_count_dbg[((g * PHT_BANKS) + sb) * 32+:32];
						if ((curr_state == STATE_WR_NEW) && (fifo_count != 0)) begin : sv2v_autoblock_23
							reg found_bypass;
							found_bypass = 1'b0;
							begin : sv2v_autoblock_24
								reg signed [31:0] bi;
								for (bi = 0; bi < BYPASS_DEPTH; bi = bi + 1)
									if ((bypass_valid[(((g * PHT_BANKS) + sb) * 4) + bi] && (bypass_row[((((g * PHT_BANKS) + sb) * 4) + bi) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] == pend_pht_addr)) && (bypass_ctr_idx[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (((((g * PHT_BANKS) + sb) * 4) + bi) * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)] == pend_ctr_idx)) begin
										bypass_ctr[((((g * PHT_BANKS) + sb) * 4) + bi) * 2+:2] <= new_ctr;
										found_bypass = 1'b1;
									end
							end
							if (!found_bypass) begin
								bypass_valid[(((g * PHT_BANKS) + sb) * 4) + bypass_ptr[((g * PHT_BANKS) + sb) * 2+:2]] <= 1'b1;
								bypass_row[((((g * PHT_BANKS) + sb) * 4) + bypass_ptr[((g * PHT_BANKS) + sb) * 2+:2]) * PHT_PC_ADDR_W+:PHT_PC_ADDR_W] <= pend_pht_addr;
								bypass_ctr_idx[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (((((g * PHT_BANKS) + sb) * 4) + bypass_ptr[((g * PHT_BANKS) + sb) * 2+:2]) * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)] <= pend_ctr_idx;
								bypass_ctr[((((g * PHT_BANKS) + sb) * 4) + bypass_ptr[((g * PHT_BANKS) + sb) * 2+:2]) * 2+:2] <= new_ctr;
								bypass_ptr[((g * PHT_BANKS) + sb) * 2+:2] <= bypass_ptr[((g * PHT_BANKS) + sb) * 2+:2] + sv2v_cast_4138B_signed(1);
							end
							tail_tmp = fifo_tail + sv2v_cast_8A43F_signed(1);
							count_tmp = fifo_count - 1'b1;
						end
						begin : sv2v_autoblock_25
							reg signed [31:0] p;
							for (p = 0; p < PORT_WIDTH; p = p + 1)
								if ((rt_valid_dir[p] && (rt_fetch_bank[p * FETCH_BANK_W+:FETCH_BANK_W] == sv2v_cast_EA7F4_signed(g))) && (rt_pht_bank_sel[p * PHT_BANK_BITS+:PHT_BANK_BITS] == sv2v_cast_5B3BE_signed(sb))) begin
									if (count_tmp < BUF_DEPTH) begin
										fifo_pht_addr[head_tmp] <= rt_pht_pc_addr[p * PHT_PC_ADDR_W+:PHT_PC_ADDR_W];
										fifo_ctr_idx[head_tmp] <= rt_pht_ctr_idx[(PHT_SUBIDX_W >= 0 ? 0 : PHT_SUBIDX_W) + (p * (PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W))+:(PHT_SUBIDX_W >= 0 ? PHT_SUBIDX_W + 1 : 1 - PHT_SUBIDX_W)];
										fifo_taken[head_tmp] <= rt_taken[p];
										head_tmp = head_tmp + sv2v_cast_8A43F_signed(1);
										count_tmp = count_tmp + 1'b1;
										push_count_tmp = push_count_tmp + 1'b1;
									end
									else
										drop_count_tmp = drop_count_tmp + 1'b1;
								end
						end
						fifo_head <= head_tmp;
						fifo_tail <= tail_tmp;
						fifo_count <= count_tmp;
						curr_state <= next_state;
						fifo_push_count_dbg[((g * PHT_BANKS) + sb) * 32+:32] <= push_count_tmp;
						fifo_drop_count_dbg[((g * PHT_BANKS) + sb) * 32+:32] <= drop_count_tmp;
						if (count_tmp > fifo_peak_depth_dbg[(BUF_BITS >= 0 ? 0 : BUF_BITS) + (((g * PHT_BANKS) + sb) * (BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS))+:(BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS)])
							fifo_peak_depth_dbg[(BUF_BITS >= 0 ? 0 : BUF_BITS) + (((g * PHT_BANKS) + sb) * (BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS))+:(BUF_BITS >= 0 ? BUF_BITS + 1 : 1 - BUF_BITS)] <= count_tmp;
						if ((curr_state == STATE_RD_OLD) && (fifo_count != 0)) begin
							pend_pht_addr <= fifo_pht_addr[fifo_tail];
							pend_ctr_idx <= fifo_ctr_idx[fifo_tail];
							pend_taken <= fifo_taken[fifo_tail];
						end
					end
			end
		end
	endgenerate
	initial _sv2v_0 = 0;
endmodule
module sync_dp_bram (
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
