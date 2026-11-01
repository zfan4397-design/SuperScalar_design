// Verilog-2005 translation; original module names and boundaries retained.
// Default build: USE_XPM, PRED_TRACE_EN and PRED_STATS_EN are undefined.
module branch_predict (
	clk,
	rst,
	rt_grant,
	rt_rd,
	rt_pc,
	rt_brtype,
	rt_brdest,
	rt_is_ret,
	rt_exception,
	icache_rvalid,
	icache_busy,
	have_inst_i,
	pc_i,
	inst_i,
	have_inst_o,
	pc,
	pc_next,
	inst,
	dbg_bundle_cut_inst,
	ctrl_restore_pulse,
	ctrl_clear,
	nxtpc_flush,
	nxtpc_interrupt,
	redirect,
	redirect_pc
);
	reg _sv2v_0;
	parameter BUF_BITS = 3;
	parameter PORT_WIDTH = 2;
	parameter IN_WIDTH = 4;
	parameter [31:0] RAS_DEPTH = 16;
	input clk;
	input rst;
	input wire [PORT_WIDTH - 1:0] rt_grant;
	input wire [(PORT_WIDTH * 5) - 1:0] rt_rd;
	localparam signed [31:0] config_pkg_PC_WIDTH = 32;
	input wire [(PORT_WIDTH * config_pkg_PC_WIDTH) - 1:0] rt_pc;
	localparam signed [31:0] config_pkg_BRTYPE_WIDTH = 2;
	input wire [(PORT_WIDTH * config_pkg_BRTYPE_WIDTH) - 1:0] rt_brtype;
	input wire [(PORT_WIDTH * config_pkg_PC_WIDTH) - 1:0] rt_brdest;
	input wire [PORT_WIDTH - 1:0] rt_is_ret;
	localparam signed [31:0] config_pkg_EXCPT_WIDTH = 4;
	input wire [(PORT_WIDTH * config_pkg_EXCPT_WIDTH) - 1:0] rt_exception;
	input wire icache_rvalid;
	input wire icache_busy;
	input wire have_inst_i;
	input wire [31:0] pc_i;
	localparam signed [31:0] config_pkg_DATA_WIDTH = 32;
	input wire [(IN_WIDTH * config_pkg_DATA_WIDTH) - 1:0] inst_i;
	output wire [IN_WIDTH - 1:0] have_inst_o;
	output wire [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] pc;
	output wire [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] pc_next;
	output wire [(IN_WIDTH * config_pkg_DATA_WIDTH) - 1:0] inst;
	output reg [31:0] dbg_bundle_cut_inst;
	input wire ctrl_restore_pulse;
	input wire ctrl_clear;
	input wire [31:0] nxtpc_flush;
	input wire [31:0] nxtpc_interrupt;
	output reg redirect;
	output reg [31:0] redirect_pc;
	localparam BUF_DEPTH = 1 << BUF_BITS;
	localparam STATE_GET_TAG = 1'b0;
	localparam STATE_WR_DATA = 1'b1;
	localparam signed [31:0] PC_SPLICE_BITS = 10;
	localparam signed [31:0] BHR_BITS = 4;
	localparam signed [31:0] PHT_BITS = BHR_BITS + PC_SPLICE_BITS;
	localparam signed [31:0] PHT_DEPTH = 1 << PHT_BITS;
	localparam signed [31:0] PHT_BANK_BITS = 2;
	localparam signed [31:0] PHT_BANK_ADDR_BITS = PHT_BITS - PHT_BANK_BITS;
	localparam signed [31:0] LEGACY_PHT_BUF_BITS = 2;
	localparam signed [31:0] LEGACY_PHT_BUF_DEPTH = 4;
	localparam [0:0] LEGACY_PHT_RD_OLD = 1'b0;
	localparam [0:0] LEGACY_PHT_WR_NEW = 1'b1;
	localparam signed [31:0] FETCH_BANK_W = (IN_WIDTH <= 2 ? 1 : $clog2(IN_WIDTH));
	localparam signed [31:0] SHORT_BHR_BITS = 8;
	localparam signed [31:0] SHORT_LOCAL_BHT_BITS = 2;
	localparam signed [31:0] SHORT_LOCAL_ROW_BITS = 3;
	localparam signed [31:0] SHORT_BHT_IDX_BITS = $clog2(IN_WIDTH) + SHORT_LOCAL_BHT_BITS;
	localparam signed [31:0] SHORT_PC_SPLICE_BITS = $clog2(IN_WIDTH) + SHORT_LOCAL_ROW_BITS;
	localparam signed [31:0] LONG_BHR_BITS = 16;
	localparam signed [31:0] LONG_SLOT_COUNT = 4;
	localparam signed [31:0] UPGRADE_SAMPLE_WINDOW = 96;
	localparam signed [31:0] UPGRADE_MISS_THRESHOLD = 20;
	localparam [31:0] RAS_PTR_W = (RAS_DEPTH <= 2 ? 1 : $clog2(RAS_DEPTH));
	reg [31:0] active_ras_stack [0:RAS_DEPTH - 1];
	reg [31:0] commit_ras_stack [0:RAS_DEPTH - 1];
	reg [31:0] active_ras_stack_n [0:RAS_DEPTH - 1];
	reg [31:0] commit_ras_stack_n [0:RAS_DEPTH - 1];
	reg [RAS_PTR_W - 1:0] active_ras_sp;
	reg [RAS_PTR_W - 1:0] commit_ras_sp;
	reg [RAS_PTR_W - 1:0] active_ras_sp_n;
	reg [RAS_PTR_W - 1:0] commit_ras_sp_n;
	reg [RAS_PTR_W:0] active_ras_cnt;
	reg [RAS_PTR_W:0] commit_ras_cnt;
	reg [RAS_PTR_W:0] active_ras_cnt_n;
	reg [RAS_PTR_W:0] commit_ras_cnt_n;
	reg active_ras_empty;
	reg [31:0] active_ras_top;
	reg [RAS_PTR_W - 1:0] active_ras_sp_top;
	reg [IN_WIDTH - 1:0] slot_is_call;
	reg [IN_WIDTH - 1:0] slot_is_ret;
	reg [PORT_WIDTH - 1:0] rt_is_call;
	wire [(IN_WIDTH * 2) - 1:0] lp;
	reg [IN_WIDTH - 1:0] pre_taken;
	reg [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] pre_brdest;
	reg [IN_WIDTH - 1:0] have_inst;
	wire [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] pc_table;
	localparam [31:0] RAS_SP_LAST_32 = RAS_DEPTH - 1;
	localparam [31:0] RAS_CNT_MAX_32 = RAS_DEPTH;
	localparam [RAS_PTR_W - 1:0] RAS_SP_LAST = RAS_SP_LAST_32[RAS_PTR_W - 1:0];
	localparam [RAS_PTR_W:0] RAS_CNT_MAX = RAS_CNT_MAX_32[RAS_PTR_W:0];
	always @(*) begin
		if (_sv2v_0)
			;
		active_ras_empty = active_ras_cnt == 0;
		active_ras_sp_top = 1'sb0;
		active_ras_top = 1'sb0;
		if (!active_ras_empty) begin
			if (active_ras_sp == 0)
				active_ras_sp_top = RAS_SP_LAST;
			else
				active_ras_sp_top = active_ras_sp - 1'b1;
			active_ras_top = active_ras_stack[active_ras_sp_top];
		end
	end
	wire [(IN_WIDTH * PHT_BANK_ADDR_BITS) - 1:0] pht_addra_bank;
	wire [(IN_WIDTH * 2) - 1:0] pht_douta_bank;
	reg [IN_WIDTH - 1:0] pht_web_bank;
	reg [(IN_WIDTH * PHT_BANK_ADDR_BITS) - 1:0] pht_addrb_bank;
	reg [(IN_WIDTH * 2) - 1:0] pht_dinb_bank;
	wire [(IN_WIDTH * 2) - 1:0] pht_doutb_bank;
	wire [(PORT_WIDTH * 63) - 1:0] buf_wdata;
	wire [(IN_WIDTH * 6) - 1:0] raddr;
	wire [(IN_WIDTH * 32) - 1:0] r_brdest;
	wire [(IN_WIDTH * 22) - 1:0] r_tag;
	wire [(IN_WIDTH * 2) - 1:0] r_brtype;
	wire [(IN_WIDTH * BHR_BITS) - 1:0] r_bhr;
	reg [(IN_WIDTH * 6) - 1:0] bank_raddr;
	wire [(IN_WIDTH * 32) - 1:0] bank_r_brdest;
	wire [(IN_WIDTH * 22) - 1:0] bank_r_tag;
	wire [(IN_WIDTH * 2) - 1:0] bank_r_brtype;
	wire [(IN_WIDTH * BHR_BITS) - 1:0] bank_r_bhr;
	wire [(IN_WIDTH * PORT_WIDTH) - 1:0] buf_we;
	reg [IN_WIDTH - 1:0] we;
	reg [(IN_WIDTH * BHR_BITS) - 1:0] w_bhr;
	reg [IN_WIDTH - 1:0] w_taken;
	reg [(IN_WIDTH * BHR_BITS) - 1:0] w_bhr_old;
	reg [(IN_WIDTH * PHT_BANK_ADDR_BITS) - 1:0] w_pht_bank_addr;
	wire [(IN_WIDTH * PHT_BANK_ADDR_BITS) - 1:0] r_pht_bank_addr;
	reg [IN_WIDTH - 1:0] w_pht;
	function automatic [1:0] sv2v_cast_B2A15;
		input reg [1:0] inp;
		sv2v_cast_B2A15 = inp;
	endfunction
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < PORT_WIDTH; i = i + 1)
				rt_is_call[i] = (rt_grant[i] && ((rt_brtype[i * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] == sv2v_cast_B2A15(1)) || (rt_brtype[i * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] == sv2v_cast_B2A15(3)))) && (rt_rd[i * 5+:5] == 5'd1);
		end
	end
	wire [IN_WIDTH - 1:0] br_grant;
	wire [(IN_WIDTH * config_pkg_PC_WIDTH) - 1:0] br_pc;
	reg [(IN_WIDTH * config_pkg_BRTYPE_WIDTH) - 1:0] br_brtype;
	wire [IN_WIDTH - 1:0] br_taken;
	genvar _gv_nidx_1;
	generate
		for (_gv_nidx_1 = 0; _gv_nidx_1 < IN_WIDTH; _gv_nidx_1 = _gv_nidx_1 + 1) begin : gen_br_lane
			localparam nidx = _gv_nidx_1;
			assign br_grant[nidx] = have_inst_o[nidx];
			assign br_pc[nidx * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = pc[nidx * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH];
			assign br_taken[nidx] = pre_taken[nidx];
		end
	endgenerate
	wire [(IN_WIDTH * 2) - 1:0] lp_n4;
	wire [(IN_WIDTH * 2) - 1:0] lp_long;
	wire [IN_WIDTH - 1:0] use_long_pred;
	wire [(IN_WIDTH * SHORT_BHR_BITS) - 1:0] short_base_hist_dbg;
	wire [(IN_WIDTH * SHORT_BHR_BITS) - 1:0] short_prefix_hist_dbg;
	wire [(IN_WIDTH * SHORT_BHR_BITS) - 1:0] short_effective_hist_dbg;
	wire [(IN_WIDTH * (SHORT_PC_SPLICE_BITS - $clog2(IN_WIDTH))) - 1:0] short_pht_row_dbg;
	wire [(IN_WIDTH * 6) - 1:0] short_ctr_idx_dbg;
	wire [IN_WIDTH - 1:0] short_bypass_hit_dbg;
	wire [(IN_WIDTH * 2) - 1:0] short_ctr_src_dbg;
	wire [(IN_WIDTH * LONG_BHR_BITS) - 1:0] long_base_hist_dbg;
	wire [(IN_WIDTH * LONG_BHR_BITS) - 1:0] long_lookup_hist_dbg;
	wire [(IN_WIDTH * 2) - 1:0] long_slot_dbg;
	wire [IN_WIDTH - 1:0] long_bypass_hit_dbg;
	wire [(IN_WIDTH * LONG_BHR_BITS) - 1:0] long_bypass_addr_dbg;
	wire [(IN_WIDTH * 2) - 1:0] long_bypass_ctr_dbg;
	wire [(IN_WIDTH * 2) - 1:0] long_ctr_src_dbg;
	reg [IN_WIDTH - 1:0] br_short_dir_enable;
	reg [PORT_WIDTH - 1:0] rt_short_dir_enable;
	wire [PORT_WIDTH - 1:0] rt_use_long;
	direction_exception_predictor #(
		.IN_WIDTH(IN_WIDTH),
		.PORT_WIDTH(PORT_WIDTH),
		.MODE_ENTRIES(32),
		.LONG_SLOTS(LONG_SLOT_COUNT),
		.BHR_BITS(LONG_BHR_BITS),
		.SAMPLE_THRESHOLD(UPGRADE_SAMPLE_WINDOW),
		.MISS_THRESHOLD(UPGRADE_MISS_THRESHOLD),
		.PHT_INIT_STATE(2'b10)
	) direction_exception_predictor(
		.clk(clk),
		.rst(rst),
		.have_inst_i(have_inst_i),
		.pc_i(pc_i),
		.use_long_o(use_long_pred),
		.lp_o(lp_long),
		.dbg_base_hist_o(long_base_hist_dbg),
		.dbg_lookup_hist_o(long_lookup_hist_dbg),
		.dbg_slot_o(long_slot_dbg),
		.dbg_bypass_hit_o(long_bypass_hit_dbg),
		.dbg_bypass_addr_o(long_bypass_addr_dbg),
		.dbg_bypass_ctr_o(long_bypass_ctr_dbg),
		.dbg_final_ctr_o(),
		.dbg_ctr_src_o(long_ctr_src_dbg),
		.br_grant(br_grant),
		.br_pc(br_pc),
		.br_brtype(br_brtype),
		.br_taken(br_taken),
		.rt_grant(rt_grant),
		.rt_pc(rt_pc),
		.rt_brtype(rt_brtype),
		.rt_brdest(rt_brdest),
		.rt_exception(rt_exception),
		.rt_use_long_o(rt_use_long)
	);
	direction_predict_v4 #(
		.IN_WIDTH(IN_WIDTH),
		.PORT_WIDTH(PORT_WIDTH),
		.BHT_IDX_BITS(SHORT_BHT_IDX_BITS),
		.BHR_BITS(SHORT_BHR_BITS),
		.PC_SPLICE_BITS(SHORT_PC_SPLICE_BITS),
		.PHT_BANK_BITS(3),
		.BUF_BITS(3),
		.PHT_INIT_STATE(2'b10)
	) direction_predict_v4(
		.clk(clk),
		.rst(rst),
		.have_inst_i(have_inst_i),
		.pc_i(pc_i),
		.lp(lp_n4),
		.dbg_base_hist_o(short_base_hist_dbg),
		.dbg_prefix_hist_o(short_prefix_hist_dbg),
		.dbg_effective_hist_o(short_effective_hist_dbg),
		.dbg_pht_row_o(short_pht_row_dbg),
		.dbg_ctr_idx_o(short_ctr_idx_dbg),
		.dbg_bypass_hit_o(short_bypass_hit_dbg),
		.dbg_final_ctr_o(),
		.dbg_ctr_src_o(short_ctr_src_dbg),
		.br_grant(br_grant),
		.br_pc(br_pc),
		.br_brtype(br_brtype),
		.br_taken(br_taken),
		.br_dir_enable_i(br_short_dir_enable),
		.rt_grant(rt_grant),
		.rt_pc(rt_pc),
		.rt_brtype(rt_brtype),
		.rt_brdest(rt_brdest),
		.rt_exception(rt_exception),
		.rt_dir_enable_i(rt_short_dir_enable)
	);
	genvar _gv_pb_1;
	generate
		for (_gv_pb_1 = 0; _gv_pb_1 < IN_WIDTH; _gv_pb_1 = _gv_pb_1 + 1) begin : gen_legacy_pht_mem
			localparam pb = _gv_pb_1;
			localparam [31:0] sv2v_uu_u_legacy_pht_mem_DATA_W = 2;
			localparam [1:0] sv2v_uu_u_legacy_pht_mem_ext_dina_0 = 1'sb0;
			sync_dp_bram_bp_pht #(
				.ADDR_W(PHT_BANK_ADDR_BITS),
				.DATA_W(2),
				.INIT_VALUE(2'b11)
			) u_legacy_pht_mem(
				.clka(clk),
				.wea(1'b0),
				.addra(pht_addra_bank[pb * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS]),
				.dina(sv2v_uu_u_legacy_pht_mem_ext_dina_0),
				.douta(pht_douta_bank[pb * 2+:2]),
				.clkb(clk),
				.web(pht_web_bank[pb]),
				.addrb(pht_addrb_bank[pb * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS]),
				.dinb(pht_dinb_bank[pb * 2+:2]),
				.doutb(pht_doutb_bank[pb * 2+:2])
			);
		end
	endgenerate
	genvar _gv_idx_1;
	generate
		for (_gv_idx_1 = 0; _gv_idx_1 < IN_WIDTH; _gv_idx_1 = _gv_idx_1 + 1) begin : br_bank
			localparam idx = _gv_idx_1;
			wire [PORT_WIDTH - 1:0] buf_in;
			wire [(PORT_WIDTH * BUF_BITS) - 1:0] head_addr;
			reg [(BUF_DEPTH * 63) - 1:0] buf_entry;
			reg [BUF_DEPTH - 1:0] buf_v;
			reg buf_consume;
			reg [BUF_BITS - 1:0] buf_head;
			reg [BUF_BITS - 1:0] buf_tail;
			reg curr_state;
			reg next_state;
			reg [5:0] waddr;
			reg [31:0] w_brdest;
			wire [31:0] origin_brdest;
			reg [21:0] w_tag;
			wire [21:0] origin_tag;
			reg [1:0] w_brtype;
			wire [1:0] origin_brtype;
			wire [3:0] origin_bhr;
			genvar _gv_pn_1;
			for (_gv_pn_1 = 0; _gv_pn_1 < PORT_WIDTH; _gv_pn_1 = _gv_pn_1 + 1) begin : gen_buf_in
				localparam pn = _gv_pn_1;
				assign head_addr[pn * BUF_BITS+:BUF_BITS] = (buf_head + bp_count_ones(buf_we[(idx * PORT_WIDTH) + (pn >= 0 ? pn : (pn + (pn >= 0 ? pn + 1 : 1 - pn)) - 1)-:(pn >= 0 ? pn + 1 : 1 - pn)])) - 1;
				assign buf_in[pn] = ~buf_v[head_addr[pn * BUF_BITS+:BUF_BITS]] & buf_we[(idx * PORT_WIDTH) + pn];
			end
			always @(posedge clk or posedge rst)
				if (rst) begin : sv2v_autoblock_2
					reg signed [31:0] i;
					for (i = 0; i < BUF_DEPTH; i = i + 1)
						buf_entry[i * 63+:63] <= 1'sb0;
				end
				else begin : sv2v_autoblock_3
					reg signed [31:0] i;
					for (i = 0; i < PORT_WIDTH; i = i + 1)
						if (buf_in[i])
							buf_entry[head_addr[i * BUF_BITS+:BUF_BITS] * 63+:63] <= buf_wdata[i * 63+:63];
				end
			always @(posedge clk or posedge rst)
				if (rst) begin
					buf_head <= 1'sb0;
					buf_tail <= 1'sb0;
				end
				else begin
					buf_head <= buf_head + bp_count_ones(buf_in);
					if (buf_consume)
						buf_tail <= buf_tail + 1'b1;
				end
			always @(posedge clk or posedge rst)
				if (rst)
					buf_v <= 1'sb0;
				else begin
					begin : sv2v_autoblock_4
						reg signed [31:0] i;
						for (i = 0; i < PORT_WIDTH; i = i + 1)
							if (buf_in[i])
								buf_v[head_addr[i * BUF_BITS+:BUF_BITS]] <= 1'b1;
					end
					if (buf_v[buf_tail] && buf_consume)
						buf_v[buf_tail] <= 1'b0;
				end
			always @(posedge clk or posedge rst)
				if (rst)
					curr_state <= STATE_GET_TAG;
				else
					curr_state <= next_state;
			always @(*) begin
				if (_sv2v_0)
					;
				case (curr_state)
					STATE_GET_TAG: next_state = (buf_v[buf_tail] ? STATE_WR_DATA : STATE_GET_TAG);
					STATE_WR_DATA: next_state = STATE_GET_TAG;
					default: next_state = STATE_GET_TAG;
				endcase
			end
			always @(*) begin
				if (_sv2v_0)
					;
				case (curr_state)
					STATE_GET_TAG: begin
						waddr = buf_entry[(buf_tail * 63) + 61-:6];
						w_bhr[idx * BHR_BITS+:BHR_BITS] = 1'sb0;
						w_bhr_old[idx * BHR_BITS+:BHR_BITS] = 1'sb0;
						w_taken[idx] = 1'b0;
						we[idx] = 1'b0;
						buf_consume = 1'b0;
					end
					STATE_WR_DATA: begin
						waddr = buf_entry[(buf_tail * 63) + 61-:6];
						w_bhr[idx * BHR_BITS+:BHR_BITS] = (origin_tag == w_tag ? {origin_bhr[2:0], buf_entry[(buf_tail * 63) + 62]} : {{3 {1'b0}}, buf_entry[(buf_tail * 63) + 62]});
						w_bhr_old[idx * BHR_BITS+:BHR_BITS] = (origin_tag == w_tag ? origin_bhr : {4 {1'sb0}});
						w_taken[idx] = buf_entry[(buf_tail * 63) + 62];
						we[idx] = 1'b1;
						buf_consume = 1'b1;
					end
					default: begin
						waddr = buf_entry[(buf_tail * 63) + 61-:6];
						w_bhr[idx * BHR_BITS+:BHR_BITS] = 1'sb0;
						w_bhr_old[idx * BHR_BITS+:BHR_BITS] = 1'sb0;
						w_taken[idx] = 1'b0;
						we[idx] = 1'b0;
						buf_consume = 1'b0;
					end
				endcase
			end
			always @(*) begin
				if (_sv2v_0)
					;
				{w_brtype, w_tag, w_brdest} = buf_entry[(buf_tail * 63) + 55-:56];
				w_pht_bank_addr[idx * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS] = {buf_entry[(buf_tail * 63) + 33-:2], buf_entry[(buf_tail * 63) + 61-:6], w_bhr_old[idx * BHR_BITS+:BHR_BITS]};
				w_pht[idx] = we[idx] && (w_brtype == sv2v_cast_B2A15(2));
			end
			bht_mem bht_mem(
				.clka(clk),
				.wea(1'b0),
				.addra(bank_raddr[idx * 6+:6]),
				.dina(1'sb0),
				.douta(bank_r_bhr[idx * BHR_BITS+:BHR_BITS]),
				.clkb(clk),
				.web(we[idx]),
				.addrb(waddr),
				.dinb(w_bhr[idx * BHR_BITS+:BHR_BITS]),
				.doutb(origin_bhr)
			);
			btb_mem btb_mem(
				.clka(clk),
				.wea(1'b0),
				.addra(bank_raddr[idx * 6+:6]),
				.dina(1'sb0),
				.douta({bank_r_brtype[idx * 2+:2], bank_r_tag[idx * 22+:22], bank_r_brdest[idx * 32+:32]}),
				.clkb(clk),
				.web(we[idx]),
				.addrb(waddr),
				.dinb({w_brtype, w_tag, w_brdest}),
				.doutb({origin_brtype, origin_tag, origin_brdest})
			);
		end
	endgenerate
	genvar _gv_pb_2;
	function automatic signed [2:0] sv2v_cast_3_signed;
		input reg signed [2:0] inp;
		sv2v_cast_3_signed = inp;
	endfunction
	generate
		for (_gv_pb_2 = 0; _gv_pb_2 < IN_WIDTH; _gv_pb_2 = _gv_pb_2 + 1) begin : gen_legacy_pht_queue
			localparam pb = _gv_pb_2;
			reg [(LEGACY_PHT_BUF_DEPTH * PHT_BANK_ADDR_BITS) - 1:0] fifo_addr;
			reg [3:0] fifo_taken;
			reg [1:0] fifo_head;
			reg [1:0] fifo_tail;
			reg [LEGACY_PHT_BUF_BITS:0] fifo_count;
			reg curr_state;
			reg [PHT_BANK_ADDR_BITS - 1:0] pend_addr;
			reg pend_taken;
			reg [1:0] old_ctr;
			reg [1:0] new_ctr;
			always @(*) begin
				if (_sv2v_0)
					;
				old_ctr = pht_doutb_bank[pb * 2+:2];
				if (pend_taken)
					new_ctr = (old_ctr == 2'b11 ? 2'b11 : old_ctr + 2'b01);
				else
					new_ctr = (old_ctr == 2'b00 ? 2'b00 : old_ctr - 2'b01);
			end
			always @(*) begin
				if (_sv2v_0)
					;
				pht_web_bank[pb] = 1'b0;
				pht_addrb_bank[pb * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS] = 1'sb0;
				pht_dinb_bank[pb * 2+:2] = 1'sb0;
				if (curr_state == LEGACY_PHT_RD_OLD) begin
					if (fifo_count != 0)
						pht_addrb_bank[pb * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS] = fifo_addr[fifo_tail * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS];
				end
				else begin
					pht_web_bank[pb] = 1'b1;
					pht_addrb_bank[pb * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS] = pend_addr;
					pht_dinb_bank[pb * 2+:2] = new_ctr;
				end
			end
			always @(posedge clk or posedge rst)
				if (rst) begin
					fifo_head <= 1'sb0;
					fifo_tail <= 1'sb0;
					fifo_count <= 1'sb0;
					curr_state <= LEGACY_PHT_RD_OLD;
					pend_addr <= 1'sb0;
					pend_taken <= 1'b0;
				end
				else begin : sv2v_autoblock_5
					reg [1:0] head_tmp;
					reg [1:0] tail_tmp;
					reg [LEGACY_PHT_BUF_BITS:0] count_tmp;
					head_tmp = fifo_head;
					tail_tmp = fifo_tail;
					count_tmp = fifo_count;
					if ((curr_state == LEGACY_PHT_WR_NEW) && (fifo_count != 0)) begin
						tail_tmp = fifo_tail + 2'sd1;
						count_tmp = fifo_count - 1'b1;
					end
					if (w_pht[pb] && (count_tmp < sv2v_cast_3_signed(LEGACY_PHT_BUF_DEPTH))) begin
						fifo_addr[head_tmp * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS] <= w_pht_bank_addr[pb * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS];
						fifo_taken[head_tmp] <= w_taken[pb];
						head_tmp = head_tmp + 2'sd1;
						count_tmp = count_tmp + 1'b1;
					end
					fifo_head <= head_tmp;
					fifo_tail <= tail_tmp;
					fifo_count <= count_tmp;
					if ((curr_state == LEGACY_PHT_RD_OLD) && (fifo_count != 0)) begin
						pend_addr <= fifo_addr[fifo_tail * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS];
						pend_taken <= fifo_taken[fifo_tail];
					end
					if (curr_state == LEGACY_PHT_RD_OLD) begin
						if (fifo_count != 0)
							curr_state <= LEGACY_PHT_WR_NEW;
					end
					else
						curr_state <= LEGACY_PHT_RD_OLD;
				end
		end
	endgenerate
	reg [31:0] pc_reg;
	reg have_inst_reg;
	wire [IN_WIDTH - 1:0] have_inst_table;
	reg [63:0] bundle_issue_seq;
	reg [63:0] bundle_seq_reg;
	always @(posedge clk or posedge rst)
		if (rst) begin
			pc_reg <= 1'sb0;
			have_inst_reg <= 1'b0;
			bundle_issue_seq <= 1'sb0;
			bundle_seq_reg <= 1'sb0;
		end
		else if (!icache_busy) begin
			pc_reg <= pc_i;
			have_inst_reg <= have_inst_i;
			bundle_seq_reg <= bundle_issue_seq;
			if (have_inst_i)
				bundle_issue_seq <= bundle_issue_seq + 64'd1;
		end
	genvar _gv_s_1;
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	function automatic [FETCH_BANK_W - 1:0] sv2v_cast_EA7F4;
		input reg [FETCH_BANK_W - 1:0] inp;
		sv2v_cast_EA7F4 = inp;
	endfunction
	generate
		for (_gv_s_1 = 0; _gv_s_1 < IN_WIDTH; _gv_s_1 = _gv_s_1 + 1) begin : gen_out
			localparam s = _gv_s_1;
			assign pc[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = pc_reg + sv2v_cast_32($unsigned(s) << 2);
			assign pc_table[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = pc_i + sv2v_cast_32($unsigned(s) << 2);
			assign inst[s * config_pkg_DATA_WIDTH+:config_pkg_DATA_WIDTH] = inst_i[s * config_pkg_DATA_WIDTH+:config_pkg_DATA_WIDTH];
			assign pc_next[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = (pre_taken[s] ? pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] : pc[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] + 32'd4);
			assign have_inst_table[s] = (have_inst_reg & ~icache_busy) & icache_rvalid;
			assign raddr[s * 6+:6] = pc_table[(s * config_pkg_PC_WIDTH) + 9-:6];
			genvar _gv_rp_1;
			for (_gv_rp_1 = 0; _gv_rp_1 < PORT_WIDTH; _gv_rp_1 = _gv_rp_1 + 1) begin : gen_buf_we
				localparam rp = _gv_rp_1;
				assign buf_we[(s * PORT_WIDTH) + rp] = ((rt_pc[(rp * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W] == sv2v_cast_EA7F4($unsigned(s))) && rt_grant[rp]) && (rt_brtype[rp * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] != sv2v_cast_B2A15(0));
			end
			assign r_pht_bank_addr[s * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS] = {pc[(s * config_pkg_PC_WIDTH) + 11-:8], r_bhr[s * BHR_BITS+:BHR_BITS]};
			assign pht_addra_bank[s * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS] = r_pht_bank_addr[s * PHT_BANK_ADDR_BITS+:PHT_BANK_ADDR_BITS];
			assign lp[s * 2+:2] = pht_douta_bank[s * 2+:2];
			assign have_inst_o[s] = have_inst_table[s] & have_inst[s];
		end
	endgenerate
	always @(*) begin
		if (_sv2v_0)
			;
		begin : sv2v_autoblock_6
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				bank_raddr[i * 6+:6] = 1'sb0;
		end
		begin : sv2v_autoblock_7
			reg signed [31:0] i;
			for (i = 0; i < IN_WIDTH; i = i + 1)
				bank_raddr[pc_table[(i * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W] * 6+:6] = raddr[i * 6+:6];
		end
	end
	genvar _gv_s_2;
	generate
		for (_gv_s_2 = 0; _gv_s_2 < IN_WIDTH; _gv_s_2 = _gv_s_2 + 1) begin : gen_bank_out
			localparam s = _gv_s_2;
			assign r_brdest[s * 32+:32] = bank_r_brdest[pc[(s * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W] * 32+:32];
			assign r_tag[s * 22+:22] = bank_r_tag[pc[(s * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W] * 22+:22];
			assign r_brtype[s * 2+:2] = bank_r_brtype[pc[(s * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W] * 2+:2];
			assign r_bhr[s * BHR_BITS+:BHR_BITS] = bank_r_bhr[pc[(s * config_pkg_PC_WIDTH) + 2+:FETCH_BANK_W] * BHR_BITS+:BHR_BITS];
		end
	endgenerate
	genvar _gv_rp_2;
	generate
		for (_gv_rp_2 = 0; _gv_rp_2 < PORT_WIDTH; _gv_rp_2 = _gv_rp_2 + 1) begin : gen_buf_wdata
			localparam rp = _gv_rp_2;
			assign buf_wdata[rp * 63+:63] = {rt_brdest[rp * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] != (rt_pc[rp * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] + 32'd4), rt_pc[(rp * config_pkg_PC_WIDTH) + 9-:6], rt_brtype[rp * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH], rt_pc[(rp * config_pkg_PC_WIDTH) + 31-:22], rt_brdest[rp * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH]};
		end
	endgenerate
	genvar _gv_s_3;
	generate
		for (_gv_s_3 = 0; _gv_s_3 < IN_WIDTH; _gv_s_3 = _gv_s_3 + 1) begin : gen_decode
			localparam s = _gv_s_3;
			reg [6:0] opcode;
			reg [4:0] rd;
			reg [4:0] rs1;
			reg [31:0] imm;
			always @(*) begin
				if (_sv2v_0)
					;
				opcode = inst_i[(s * config_pkg_DATA_WIDTH) + 6-:7];
				rd = inst_i[(s * config_pkg_DATA_WIDTH) + 11-:5];
				rs1 = inst_i[(s * config_pkg_DATA_WIDTH) + 19-:5];
				imm = 32'b00000000000000000000000000000000;
				slot_is_call[s] = 1'b0;
				slot_is_ret[s] = 1'b0;
				case (opcode)
					7'b1101111: begin
						imm[0] = 1'b0;
						imm[19:12] = inst_i[(s * config_pkg_DATA_WIDTH) + 19-:8];
						imm[11] = inst_i[(s * config_pkg_DATA_WIDTH) + 20];
						imm[10:1] = inst_i[(s * config_pkg_DATA_WIDTH) + 30-:10];
						imm[31:20] = {12 {inst_i[(s * config_pkg_DATA_WIDTH) + 31]}};
						pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = pc[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] + imm;
						pre_taken[s] = 1'b1;
						br_brtype[s * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] = sv2v_cast_B2A15(1);
						if (rd == 5'd1)
							slot_is_call[s] = 1'b1;
					end
					7'b1100111: begin
						imm[11:0] = inst_i[(s * config_pkg_DATA_WIDTH) + 31-:12];
						imm[31:12] = {20 {inst_i[(s * config_pkg_DATA_WIDTH) + 31]}};
						br_brtype[s * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] = sv2v_cast_B2A15(3);
						if (((rd == 5'd0) && (rs1 == 5'd1)) && (imm[11:0] == 12'b000000000000)) begin
							slot_is_ret[s] = 1'b1;
							if (!active_ras_empty) begin
								pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = active_ras_top;
								pre_taken[s] = 1'b1;
							end
							else if (r_tag[s * 22+:22] != pc[(s * config_pkg_PC_WIDTH) + 31-:22]) begin
								pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = 1'sb0;
								pre_taken[s] = 1'b0;
							end
							else begin
								pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = r_brdest[s * 32+:32];
								pre_taken[s] = 1'b1;
							end
						end
						else begin
							if (rd == 5'd1)
								slot_is_call[s] = 1'b1;
							if (r_tag[s * 22+:22] != pc[(s * config_pkg_PC_WIDTH) + 31-:22]) begin
								pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = 1'sb0;
								pre_taken[s] = 1'b0;
							end
							else begin
								pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = r_brdest[s * 32+:32];
								pre_taken[s] = 1'b1;
							end
						end
					end
					7'b1100011: begin
						imm[4:1] = inst_i[(s * config_pkg_DATA_WIDTH) + 11-:4];
						imm[11] = inst_i[(s * config_pkg_DATA_WIDTH) + 7];
						imm[10:5] = inst_i[(s * config_pkg_DATA_WIDTH) + 30-:6];
						imm[12] = inst_i[(s * config_pkg_DATA_WIDTH) + 31];
						imm[0] = 1'b0;
						imm[31:13] = {19 {inst_i[(s * config_pkg_DATA_WIDTH) + 31]}};
						pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = pc[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] + imm;
						pre_taken[s] = (use_long_pred[s] ? lp_long[(s * 2) + 1] : lp_n4[(s * 2) + 1]);
						br_brtype[s * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] = sv2v_cast_B2A15(2);
					end
					default: begin
						pre_brdest[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] = 1'sb0;
						pre_taken[s] = 1'b0;
						br_brtype[s * config_pkg_BRTYPE_WIDTH+:config_pkg_BRTYPE_WIDTH] = sv2v_cast_B2A15(0);
					end
				endcase
			end
		end
	endgenerate
	always @(*) begin
		if (_sv2v_0)
			;
		br_short_dir_enable = 1'sb1;
		rt_short_dir_enable = 1'sb1;
	end
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
			begin : sv2v_autoblock_8
				reg signed [31:0] i;
				for (i = 1; i < IN_WIDTH; i = i + 1)
					have_inst[i] = (pre_taken[i - 1] ? 1'b0 : have_inst[i - 1]);
			end
			begin : sv2v_autoblock_9
				reg signed [31:0] i;
				for (i = IN_WIDTH - 1; i >= 0; i = i - 1)
					if (pre_taken[i]) begin
						redirect = 1'b1;
						redirect_pc = pre_brdest[i * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH];
					end
			end
			if (!icache_busy && icache_rvalid)
				dbg_bundle_cut_inst = IN_WIDTH - bp_count_ones(have_inst);
		end
	end
	always @(*) begin : sv2v_autoblock_10
		reg do_push;
		reg do_pop;
		reg found;
		reg [31:0] push_addr;
		if (_sv2v_0)
			;
		do_push = 1'b0;
		do_pop = 1'b0;
		found = 1'b0;
		push_addr = 1'sb0;
		begin : sv2v_autoblock_11
			reg signed [31:0] i;
			for (i = 0; i < RAS_DEPTH; i = i + 1)
				begin
					commit_ras_stack_n[i] = commit_ras_stack[i];
					active_ras_stack_n[i] = active_ras_stack[i];
				end
		end
		commit_ras_sp_n = commit_ras_sp;
		commit_ras_cnt_n = commit_ras_cnt;
		active_ras_sp_n = active_ras_sp;
		active_ras_cnt_n = active_ras_cnt;
		begin : sv2v_autoblock_12
			reg signed [31:0] p;
			for (p = 0; p < PORT_WIDTH; p = p + 1)
				if (rt_is_call[p]) begin
					commit_ras_stack_n[commit_ras_sp_n] = rt_pc[p * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] + 32'd4;
					if (commit_ras_sp_n == RAS_SP_LAST)
						commit_ras_sp_n = 1'sb0;
					else
						commit_ras_sp_n = commit_ras_sp_n + 1'b1;
					if (commit_ras_cnt_n != RAS_CNT_MAX)
						commit_ras_cnt_n = commit_ras_cnt_n + 1'b1;
				end
				else if (rt_is_ret[p] && (commit_ras_cnt_n != {(RAS_PTR_W >= 0 ? RAS_PTR_W + 1 : 1 - RAS_PTR_W) {1'sb0}})) begin
					if (commit_ras_sp_n == 0)
						commit_ras_sp_n = RAS_SP_LAST;
					else
						commit_ras_sp_n = commit_ras_sp_n - 1'b1;
					commit_ras_cnt_n = commit_ras_cnt_n - 1'b1;
				end
		end
		if (ctrl_clear) begin
			begin : sv2v_autoblock_13
				reg signed [31:0] i;
				for (i = 0; i < RAS_DEPTH; i = i + 1)
					begin
						commit_ras_stack_n[i] = 1'sb0;
						active_ras_stack_n[i] = 1'sb0;
					end
			end
			commit_ras_sp_n = 1'sb0;
			commit_ras_cnt_n = 1'sb0;
			active_ras_sp_n = 1'sb0;
			active_ras_cnt_n = 1'sb0;
		end
		else if (ctrl_restore_pulse) begin
			begin : sv2v_autoblock_14
				reg signed [31:0] i;
				for (i = 0; i < RAS_DEPTH; i = i + 1)
					active_ras_stack_n[i] = commit_ras_stack_n[i];
			end
			active_ras_sp_n = commit_ras_sp_n;
			active_ras_cnt_n = commit_ras_cnt_n;
		end
		else begin
			begin : sv2v_autoblock_15
				reg signed [31:0] s;
				for (s = 0; s < IN_WIDTH; s = s + 1)
					if (!found && have_inst_o[s]) begin
						if (slot_is_call[s]) begin
							do_push = 1'b1;
							push_addr = pc[s * config_pkg_PC_WIDTH+:config_pkg_PC_WIDTH] + 32'd4;
							found = 1'b1;
						end
						else if (slot_is_ret[s]) begin
							do_pop = 1'b1;
							found = 1'b1;
						end
						if (pre_taken[s])
							found = 1'b1;
					end
			end
			if (do_push) begin
				active_ras_stack_n[active_ras_sp] = push_addr;
				if (active_ras_sp == RAS_SP_LAST)
					active_ras_sp_n = 1'sb0;
				else
					active_ras_sp_n = active_ras_sp + 1'b1;
				if (active_ras_cnt != RAS_CNT_MAX)
					active_ras_cnt_n = active_ras_cnt + 1'b1;
			end
			else if (do_pop && !active_ras_empty) begin
				if (active_ras_sp == 0)
					active_ras_sp_n = RAS_SP_LAST;
				else
					active_ras_sp_n = active_ras_sp - 1'b1;
				active_ras_cnt_n = active_ras_cnt - 1'b1;
			end
		end
	end
	always @(posedge clk or posedge rst)
		if (rst) begin
			active_ras_sp <= 1'sb0;
			active_ras_cnt <= 1'sb0;
			commit_ras_sp <= 1'sb0;
			commit_ras_cnt <= 1'sb0;
			begin : sv2v_autoblock_16
				reg signed [31:0] i;
				for (i = 0; i < RAS_DEPTH; i = i + 1)
					begin
						active_ras_stack[i] <= 1'sb0;
						commit_ras_stack[i] <= 1'sb0;
					end
			end
		end
		else begin
			active_ras_sp <= active_ras_sp_n;
			active_ras_cnt <= active_ras_cnt_n;
			commit_ras_sp <= commit_ras_sp_n;
			commit_ras_cnt <= commit_ras_cnt_n;
			begin : sv2v_autoblock_17
				reg signed [31:0] i;
				for (i = 0; i < RAS_DEPTH; i = i + 1)
					begin
						active_ras_stack[i] <= active_ras_stack_n[i];
						commit_ras_stack[i] <= commit_ras_stack_n[i];
					end
			end
		end
	initial _sv2v_0 = 0;

function integer bp_count_ones;
    input [(IN_WIDTH + PORT_WIDTH)-1:0] value;
    integer bit_index;
    begin
        bp_count_ones = 0;
        for (bit_index=0; bit_index<(IN_WIDTH + PORT_WIDTH); bit_index=bit_index+1)
            if (value[bit_index] === 1'b1)
                bp_count_ones = bp_count_ones + 1;
    end
endfunction

endmodule
module sync_dp_bram_bp_pht (
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
