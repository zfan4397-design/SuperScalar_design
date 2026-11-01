`timescale 1ns / 1ps
// Verilog exercise scaffold; core TODOs are intentionally unfinished.
// Reference: D:/zz/superscalercore/vsrc/utils/clint.sv
// Keep reference constants, ports, helpers, processes, branches and statement order.
// CL01..CL30 replace only selected core assignments at their original locations.
// No fallback implementation is inserted for missing core assignments.
`include "config_pkg.vh"

module clint (
    input wire                    clk,
    input wire                    rst,  

    // external: [0]=timer, [1]=ext, [2]=soft
    input wire [2:0]              ext_int_flag_i,

    // from retire_ctrl
    input wire                    ctrl_exception_req,
    input wire [`EXCPT_WIDTH-1:0]   ctrl_exception_code,
    input wire [`PC_WIDTH-1:0]      retire_ctrl_pc,
    input wire [`PC_WIDTH-1:0]      retire_ctrl_nxtpc,

    // from/to csr
    input wire [`PRIV_WIDTH-1:0]    priv_level_i,
    
    output reg                     csr_clint_rd_en,
    output reg [`CSRADDR_WIDTH-1:0] csr_clint_rd_addr,
    input wire [`DATA_WIDTH-1:0]    csr_clint_rd_data,

    output reg                     csr_clint_wr_en,
    output reg [`CSRADDR_WIDTH-1:0] csr_clint_wr_addr,
    output reg [`DATA_WIDTH-1:0]    csr_clint_wr_data,

    output reg                     csr_clint_priv_set_en,
    output reg [`PRIV_WIDTH-1:0]    csr_clint_priv_set_val,

    // to
    output reg                     ctrl_exceptend,
    output reg                     ctrl_except_resp,
    output reg [`PC_WIDTH-1:0]      nxtpc_interrupt,

    input                            async_en
);

    // ---------------- CSR addrs ----------------
    localparam [11:0] CSR_MSTATUS = 12'h300;
    localparam [11:0] CSR_MIE     = 12'h304;
    localparam [11:0] CSR_MTVEC   = 12'h305;
    localparam [11:0] CSR_MEPC    = 12'h341;
    localparam [11:0] CSR_MCAUSE  = 12'h342;

    localparam [11:0] CSR_SEPC    = 12'h141;
    localparam [11:0] CSR_UEPC    = 12'h041;

    // mie
    localparam integer MSIE_BIT = 3;
    localparam integer MTIE_BIT = 7;
    localparam integer MEIE_BIT = 11;

    // mstatus
    localparam integer TSR_BIT  = 22;   // TSR
    localparam HAS_URET = 1'b1; // Reference comment at the same source position.

    //  mcause
    localparam [31:0] MCAUSE_MSOFT  = 32'h8000_0003;
    localparam [31:0] MCAUSE_MTIMER = 32'h8000_0007;
    localparam [31:0] MCAUSE_MEXT   = 32'h8000_000B;

    localparam [31:0] MCAUSE_ILLEGAL = 32'd2;
    localparam [31:0] MCAUSE_BREAK   = 32'd3;
    localparam [31:0] MCAUSE_ECALL_U = 32'd8;
    localparam [31:0] MCAUSE_ECALL_S = 32'd9;
    localparam [31:0] MCAUSE_ECALL_M = 32'd11;
    
    localparam [31:0] MCAUSE_LAF  = 32'd5;
    localparam [31:0] MCAUSE_SAF  = 32'd7;

    // interrupt source
    localparam [2:0] INT_TIMER = 3'b001;
    localparam [2:0] INT_EXT   = 3'b010;
    localparam [2:0] INT_SOFT  = 3'b100;

    // functions
    function automatic [31:0] excpt_to_mcause;
        input [`EXCPT_WIDTH-1:0] code;
        input [`PRIV_WIDTH-1:0] cur_priv;
        reg [31:0] v;
        begin
            v = MCAUSE_ILLEGAL;
            case (code)
                `EXCPT_CSR_ILLEGAL, `EXCPT_ILLEGAL_INST, `EXCPT_INVALID_CALCULATE: v = MCAUSE_ILLEGAL;
                `EXCPT_EBREAK:                          v = MCAUSE_BREAK;
                `EXCPT_ECALL: begin
                    if (cur_priv == `PRIV_M_MODE)      v = MCAUSE_ECALL_M;
                    else if (cur_priv == `PRIV_S_MODE) v = MCAUSE_ECALL_S;
                    else                              v = MCAUSE_ECALL_U;
                end
                `EXCPT_INVALID_MEMR: v = MCAUSE_LAF;
                `EXCPT_INVALID_MEMW: v = MCAUSE_SAF;
                default: v = MCAUSE_ILLEGAL;
            endcase
            excpt_to_mcause = v;
        end
    endfunction

    function automatic [31:0] intsrc_to_mcause;
        input [2:0] src;
        reg [31:0] v;
        begin
            if (src[0] & INT_TIMER[0])      v = MCAUSE_MTIMER;
            else if (src[1] & INT_EXT[1])   v = MCAUSE_MEXT;
            else                      v = MCAUSE_MSOFT;
            intsrc_to_mcause = v;
        end
    endfunction

    function automatic int_enabled;
        input [31:0] mstatus;
        input [31:0] mie;
        input [2:0] src;
        reg global_en, per_en;
        begin
            global_en = mstatus[3]; // MIE
            per_en = 1'b0;
            if (src[0] & INT_TIMER[0])      per_en = mie[MTIE_BIT];
            else if (src[1] & INT_EXT[1])   per_en = mie[MEIE_BIT];
            else if (src[2] & INT_SOFT[2])  per_en = mie[MSIE_BIT];
            return (global_en && per_en);
        end
    endfunction

    function automatic [31:0] mtvec_target;
        input [31:0] mtvec;
        input [31:0] mcause;
        reg [31:0] base;
        reg [31:0] cause_code;
        begin
            base = {mtvec[31:2], 2'b00};
            if ((mtvec[1:0] == 2'b01) && (mcause[31] == 1'b1)) begin // Reference comment at the same source position.
                cause_code = {28'd0, mcause[3:0]};
                mtvec_target = base + (cause_code << 2);
            end else begin
                mtvec_target = base ;
            end
        end
    endfunction

    function automatic is_ret_event;
        input [`EXCPT_WIDTH-1:0] code;
        is_ret_event = (code == `EXCPT_MRET) || (code == `EXCPT_SRET) || (code == `EXCPT_URET);
    endfunction

    function automatic [11:0] ret_epc_csr;
        input [`EXCPT_WIDTH-1:0] code;
        if (code == `EXCPT_MRET) ret_epc_csr = CSR_MEPC;
        else if (code == `EXCPT_SRET) ret_epc_csr = CSR_SEPC;
        else ret_epc_csr = CSR_UEPC;
    endfunction

    // return
    task automatic compute_ret_update;
        input [`EXCPT_WIDTH-1:0] code;
        input [31:0] mstatus_in;
        output reg [31:0] mstatus_out;
        output reg [`PRIV_WIDTH-1:0] priv_out;
        begin
            mstatus_out = mstatus_in;
            priv_out    = priv_level_i;

            if (code == `EXCPT_MRET) begin
                priv_out              = mstatus_in[12:11]; // MPP
                mstatus_out[3]        = mstatus_in[7];     // MIE<=MPIE
                mstatus_out[7]        = 1'b1;              // MPIE<=1
                mstatus_out[12:11]    = 2'b00;       
            end
            else if (code == `EXCPT_SRET) begin
                // SPP=bit8, SIE=bit1, SPIE=bit5
                priv_out              = (mstatus_in[8] ? `PRIV_S_MODE : `PRIV_U_MODE);
                mstatus_out[1]        = mstatus_in[5];
                mstatus_out[5]        = 1'b1;
                mstatus_out[8]        = 1'b0;
            end
            else begin // URET
                // UIE=bit0, UPIE=bit4
                priv_out              = `PRIV_U_MODE;
                mstatus_out[0]        = mstatus_in[4];
                mstatus_out[4]        = 1'b1;
            end
        end
    endtask

    // ---------------- return legality check ----------------
    function automatic ret_legal_fast;
        input [`EXCPT_WIDTH-1:0] code;
        input [`PRIV_WIDTH-1:0] priv;
        reg ok;
        begin
            ok = 1'b1;
            case (code)
                `EXCPT_MRET: ok = (priv == `PRIV_M_MODE);
                `EXCPT_SRET: ok = (priv != `PRIV_U_MODE);                 
                `EXCPT_URET: ok = (HAS_URET && (priv == `PRIV_U_MODE));
                default:   ok = 1'b0;
            endcase
            ret_legal_fast = ok;
        end
    endfunction

    function automatic sret_illegal_by_tsr;
        input [`PRIV_WIDTH-1:0] priv;
        input [31:0] mstatus;
        // Reference comment at the same source position.
        sret_illegal_by_tsr = ((priv == `PRIV_S_MODE) && (mstatus[TSR_BIT] == 1'b1));
    endfunction

    // ---------------- FSM ----------------
    // State encodings preserved from the reference enum.
        localparam [4:0] ST_IDLE = 5'd0;

        localparam [4:0] ST_FAST_FLUSH = 5'd1;

        // entry
        localparam [4:0] ST_RD_MSTATUS = 5'd2;
        localparam [4:0] ST_RD_MIE = 5'd3;
        localparam [4:0] ST_RD_MTVEC = 5'd4;
        localparam [4:0] ST_WR_MEPC = 5'd5;
        localparam [4:0] ST_WR_MCAUSE = 5'd6;
        localparam [4:0] ST_WR_MSTATUS = 5'd7;
        localparam [4:0] ST_DONE_TRAP = 5'd8;

        // return
        localparam [4:0] ST_RET_RD_MSTATUS = 5'd9;
        localparam [4:0] ST_RET_RD_EPC = 5'd10;
        localparam [4:0] ST_RET_WR_MSTATUS = 5'd11;
        localparam [4:0] ST_RET_DONE = 5'd12;

    reg [4:0] st_q, st_d;

    // request latch
    reg                      req_valid_q;
    reg                      req_is_async_q;
    reg [`EXCPT_WIDTH-1:0]     req_code_q;
    reg [2:0]                req_int_src_q;
    reg [`PC_WIDTH-1:0]        req_pc_q;
    reg [`PC_WIDTH-1:0]        req_nxtpc_q;
    reg [2:0]                pending_async_q;
    // csr 
    reg [31:0] mstatus_q, mie_q, mtvec_q, epc_q;  
    reg [31:0] mepc_w, mcause_w, mstatus_w;
    reg [31:0] mstatus_ret_w;
    reg [`PRIV_WIDTH-1:0] priv_ret_w;
    // Reference comment at the same source position.
    reg                      allow_retire_q;
    // sret TSR illegal
    reg   sret_tsr_illegal_now;

    // ext interrupt pick
    reg [2:0] ext_pick;
    reg [2:0] async_req_vec;
    reg       async_req_any;
    always @* begin : proc_1
       async_req_vec = pending_async_q | ext_int_flag_i;
        async_req_any = (async_req_vec != 3'b000); 

        ext_pick = 3'b000;
        // Avoid timer hogging other async sources when timer line keeps high.
        if (async_req_vec[1] & INT_EXT[1]) begin
            ext_pick = INT_EXT;
        end
        else if (async_req_vec[2] & INT_SOFT[2]) begin
            ext_pick = INT_SOFT;
        end
        else if (async_req_vec[0] & INT_TIMER[0]) begin
            ext_pick = INT_TIMER;// TODO CL11 [clint.sv:263]: select the timer-interrupt source in this branch.
        end
    end

    
    always @* begin : proc_2
        ctrl_except_resp = 1'b0;
        ctrl_exceptend   = 1'b0;
        case (st_q)
            ST_FAST_FLUSH: begin
                ctrl_except_resp = allow_retire_q; // 1
                ctrl_exceptend   = 1'b1;
            end
            ST_DONE_TRAP: begin
                ctrl_except_resp = allow_retire_q; // ?????=0?????§Ø?=1
                ctrl_exceptend   = 1'b1;
            end
            ST_RET_DONE: begin
                ctrl_except_resp = allow_retire_q; 
                ctrl_exceptend   = 1'b1;
            end
            default: begin
                ctrl_except_resp = 1'b0;
                ctrl_exceptend   = 1'b0;
            end
        endcase
    end
    
    always @* begin : proc_3
        // defaults
        st_d = st_q;

        csr_clint_rd_en        = 1'b0;
        csr_clint_rd_addr      = 0;
        csr_clint_wr_en        = 1'b0;
        csr_clint_wr_addr      = 0;
        csr_clint_wr_data      = 0;

        csr_clint_priv_set_en  = 1'b0;
        csr_clint_priv_set_val = `PRIV_M_MODE;

        //ctrl_exceptend   = 1'b0;
        
        nxtpc_interrupt  = 0;
        
        mstatus_ret_w = mstatus_q;
        priv_ret_w    = priv_level_i;
        
        // csr
        mepc_w   = req_is_async_q ? req_nxtpc_q : req_pc_q;
        mcause_w = req_is_async_q ? intsrc_to_mcause(req_int_src_q) : excpt_to_mcause(req_code_q, priv_level_i);
        mstatus_w = mstatus_q;
        mstatus_w[12:11] = priv_level_i;
        mstatus_w[7]     = mstatus_q[3];
        mstatus_w[3]     = 1'b0;
        
        // TSR check
        sret_tsr_illegal_now = (req_code_q == `EXCPT_SRET) && sret_illegal_by_tsr(priv_level_i, mstatus_q);

        case (st_q)
            ST_IDLE: begin
                // 1) control request
                if (ctrl_exception_req) begin
                    if (ctrl_exception_code == `EXCPT_CSR_SIDE_EFFECT) begin
                        st_d = ST_FAST_FLUSH;
                    end
                    else if (is_ret_event(ctrl_exception_code)) begin
                        // return
                        if (!ret_legal_fast(ctrl_exception_code, priv_level_i)) begin
                            st_d = ST_RD_MSTATUS;       // illegal
                        end else begin
                            st_d = ST_RET_RD_MSTATUS;   // legal 
                        end
                    end
                    else begin
                        st_d = ST_RD_MSTATUS; // sync
                    end
                end
                // 2) async interrupts
                else if ((ext_int_flag_i != 3'b000) && (async_en == 1'b1)) begin
                    st_d = ST_RD_MSTATUS;
                end
            end

            ST_FAST_FLUSH: begin
                //ctrl_exceptend   = 1'b1;
                //ctrl_except_resp = allow_retire_q; // 1
               nxtpc_interrupt  = retire_ctrl_nxtpc; 
                st_d             = ST_IDLE;
            end

            // ----- trap entry -----
            ST_RD_MSTATUS: begin
                csr_clint_rd_en   = 1'b1;
                csr_clint_rd_addr = CSR_MSTATUS;
                st_d              = ST_RD_MIE;
            end

            ST_RD_MIE: begin
                csr_clint_rd_en   = 1'b1;
                csr_clint_rd_addr = CSR_MIE;
                st_d              = ST_RD_MTVEC;
            end

            ST_RD_MTVEC: begin
                csr_clint_rd_en   = 1'b1;
                csr_clint_rd_addr = CSR_MTVEC;
                if (req_is_async_q) begin
                    if (int_enabled(mstatus_q, mie_q, req_int_src_q)) st_d = ST_WR_MEPC;
                    else st_d = ST_IDLE; 
                end else begin
                    st_d = ST_WR_MEPC; 
                end
            end

            ST_WR_MEPC: begin
                csr_clint_wr_en   = req_is_async_q ? 1'b0 : 1'b1;
                csr_clint_wr_addr = CSR_MEPC;
                csr_clint_wr_data = mepc_w;
                st_d              = ST_WR_MCAUSE;
            end

            ST_WR_MCAUSE: begin
                csr_clint_wr_en   = 1'b1;
                csr_clint_wr_addr = CSR_MCAUSE;
                csr_clint_wr_data = mcause_w;
                st_d              = ST_WR_MSTATUS;
            end

            ST_WR_MSTATUS: begin
                csr_clint_priv_set_en  = 1'b1;
                csr_clint_priv_set_val = `PRIV_M_MODE;

                csr_clint_wr_en   = 1'b1;
                csr_clint_wr_addr = CSR_MSTATUS;
                csr_clint_wr_data = mstatus_w;

                st_d = ST_DONE_TRAP;
            end

            ST_DONE_TRAP: begin
                //ctrl_exceptend   = 1'b1;
               // Reference comment at the same source position.
                csr_clint_wr_en   = req_is_async_q ? 1'b1 : 1'b0;
                csr_clint_wr_addr = CSR_MEPC;
                csr_clint_wr_data = retire_ctrl_nxtpc;
                nxtpc_interrupt  = mtvec_target(mtvec_q, mcause_w);
                st_d             = ST_IDLE;
            end

            // ----- return -----
            ST_RET_RD_MSTATUS: begin
                csr_clint_rd_en   = 1'b1;
                csr_clint_rd_addr = CSR_MSTATUS;
                st_d              = ST_RET_RD_EPC;
            end

            ST_RET_RD_EPC: begin
                csr_clint_rd_en   = 1'b1;
                csr_clint_rd_addr = ret_epc_csr(req_code_q);
                // TSR illegal
                if (sret_tsr_illegal_now) begin
                    st_d = ST_RD_MIE;
                end else begin
                    st_d = ST_RET_WR_MSTATUS;
                end
            end

            ST_RET_WR_MSTATUS: begin
                compute_ret_update(req_code_q, mstatus_q, mstatus_ret_w, priv_ret_w);
                
                csr_clint_priv_set_en  = 1'b1;
                csr_clint_priv_set_val = priv_ret_w;

                csr_clint_wr_en   = 1'b1;
                csr_clint_wr_addr = CSR_MSTATUS;
                csr_clint_wr_data = mstatus_ret_w;

                st_d = ST_RET_DONE;
            end

            ST_RET_DONE: begin
                //ctrl_exceptend   = 1'b1;
                //ctrl_except_resp = allow_retire_q; 
                nxtpc_interrupt  = epc_q;
                st_d             = ST_IDLE;
            end

            default: st_d = ST_IDLE;
        endcase
    end

    // -------------------------------------------------
    always @(posedge clk or posedge rst) begin : proc_4
        reg [2:0] pending_async_nxt; // Verilog: declaration moved before statements.
        if (rst) begin
            st_q           <= ST_IDLE;
            req_valid_q    <= 1'b0;
            req_is_async_q <= 1'b0;
            req_code_q     <= `EXCPT_NOEX;
            req_int_src_q  <= 3'b000;
            req_pc_q       <= 0;
            req_nxtpc_q    <= 0;
            pending_async_q <= 3'b000;

            allow_retire_q <= 1'b0;

            mstatus_q      <= 32'h0;
            mie_q          <= 32'h0;
            mtvec_q        <= 32'h0;
            epc_q          <= 32'h0;
        end else begin
            // pending_async_nxt is declared at the start of proc_4.
            st_q <= st_d;

            pending_async_nxt = pending_async_q | ext_int_flag_i;
            if ((st_q == ST_RD_MTVEC) && req_is_async_q
                && int_enabled(mstatus_q, mie_q, req_int_src_q)) begin
                pending_async_nxt = pending_async_nxt & ~req_int_src_q;
            end
            pending_async_q <= pending_async_nxt;

            if (st_q == ST_IDLE) begin
                if (ctrl_exception_req) begin
                    req_valid_q    <= 1'b1;
                    req_is_async_q <= 1'b0;
                    req_pc_q       <= retire_ctrl_pc;
                    req_nxtpc_q    <= retire_ctrl_nxtpc;
                    // 1) side-effect
                    if (ctrl_exception_code == `EXCPT_CSR_SIDE_EFFECT) begin
                        req_code_q     <= `EXCPT_CSR_SIDE_EFFECT;
                        allow_retire_q <= 1'b1;
                    end
                    // 2) return
                    else if (is_ret_event(ctrl_exception_code)) begin
                        if (!ret_legal_fast(ctrl_exception_code, priv_level_i)) begin
                            req_code_q     <= `EXCPT_CSR_ILLEGAL; // mcause=2
                            allow_retire_q <= 1'b0;  
                        end else begin
                            req_code_q     <= ctrl_exception_code;
                            allow_retire_q <= 1'b1;  
                        end
                    end
                    else begin
                        req_code_q     <= ctrl_exception_code;
                       allow_retire_q <= 1'b0; 
                    end
                end
                else if (async_req_any) begin
                    req_valid_q    <= 1'b1;
                    req_is_async_q <= 1'b1;
                    req_code_q     <= `EXCPT_NOEX; 
                    req_int_src_q  <= ext_pick;
                    req_pc_q       <= retire_ctrl_pc;
                    req_nxtpc_q    <= retire_ctrl_nxtpc;
                    allow_retire_q <= 1'b1;
                end
                else begin
                    req_valid_q <= 1'b0;
                end
            end

            // SRET 
            if (st_q == ST_RET_RD_EPC) begin
                if ((req_code_q == `EXCPT_SRET) && sret_illegal_by_tsr(priv_level_i, mstatus_q)) begin
                    req_code_q     <= `EXCPT_CSR_ILLEGAL; 
                    req_is_async_q <= 1'b0;
                    allow_retire_q <= 1'b0;   
                end
            end

            // CSR reads
            if (st_q == ST_RD_MSTATUS || st_q == ST_RET_RD_MSTATUS) begin
                mstatus_q <= csr_clint_rd_data;
            end
            if (st_q == ST_RD_MIE) begin
                mie_q <= csr_clint_rd_data;
            end
            if (st_q == ST_RD_MTVEC) begin
                mtvec_q <= csr_clint_rd_data;
            end
            if (st_q == ST_RET_RD_EPC) begin
                epc_q <= csr_clint_rd_data;
            end
        end
    end

endmodule
