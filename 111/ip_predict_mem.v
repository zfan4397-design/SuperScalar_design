// 中文阅读说明：只增加注释，保留原参数、接口、表达式、状态机和读写时序。
// 术语：lane=本组第几路指令；bank=独立存储分块；slot=长预测资源槽。
// 命名：_now=当前组合查询；_q=寄存查询上下文；_tmp=本拍合并更新临时量；dbg=观察信号。
// reg/wire是声明类别，是否为时钟状态由赋值位置决定；[W-1:0]是W位，名称后的数组维度表示多项。
// Verilog-2005 translation; original module names and boundaries retained.
// Default build: USE_XPM, PRED_TRACE_EN and PRED_STATS_EN are undefined.

// ============================================================================
// 保留旧方向路径的BHT单bank：64项×4位历史，完整表由上层多实例组成。
// A口通常供前端查历史，B口供更新；真实工作时钟为clka，clkb未使用。
// 本模型显式做write-first旁路：读地址遇到本拍写入时返回新数据；与sync_dp_bram的read-first不同。
// 无复位和initial清表；未写地址的仿真初值取决于仿真器，不应假定为0。
// ============================================================================
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

    // 生成循环的 genvar 提前声明；过程循环在 for 内声明 integer。


	// RAM实际工作时钟；本实现A口与B口都由posedge clka驱动。
	input wire clka;
	// A口写使能，1时在clka上升沿写mem[addra]；预测器查询实例中通常固定接0。
	input wire wea;
	// A口查询/写入行地址，固定6位，选择64行中的一行；bank选择由上层完成。
	input wire [5:0] addra;
	// A口写数据：旧BHT为4位历史，BTB为56位{类型2,tag22,目标32}，实际位宽见声明。
	input wire [3:0] dina;
	// A口同步读出，支持写入新值旁路(write-first)；旧BHT4位，BTB56位。
	output wire [3:0] douta;
	// 保留的B口时钟接口；本文件内部不使用它，A/B实际共用clka，不能据端口名当作异步双时钟RAM。
	input wire clkb;
	// B口写使能，1时在clka上升沿写mem[addrb]；更新状态机驱动。
	input wire web;
	// B口更新/读取行地址，固定6位；上层更新FSM先读旧信息，再写新表项。
	input wire [5:0] addrb;
	// B口更新数据：旧BHT为4位新历史，BTB为56位新表项。
	input wire [3:0] dinb;
	// B口同步读出，供更新FSM检查旧表项；同边沿写入时输出新值旁路。
	output wire [3:0] doutb;
	// 旧bht_mem每项历史宽度，固定4位；每bank 64项。
	localparam signed [31:0] BITS = 4;
	// RAM逻辑行数；通用RAM为2^ADDR_W，ip_predict_mem中的旧BHT/BTB固定64行。
	localparam signed [31:0] DEPTH = 64;
	// 本模块实例独立的RAM数组；多实例不是共享同一份数据，实际映射由综合工具决定。
	reg [3:0] mem [0:63];
	// A口读数据寄存器；对外douta由连续赋值连接它。
	reg [3:0] douta_r;
	// B口读数据寄存器；对外doutb由连续赋值连接它。
	reg [3:0] doutb_r;
	always @(posedge clka) begin
		// A口允许写入；若同边沿A/B写同址，同一always中后面的B口赋值在该模型内优先。
		if (wea)
			mem[addra] <= dina;
		// B口写使能有效则写入；B读输出也优先返回本次B新数据，而不是旧mem值。
		if (web)
			mem[addrb] <= dinb;
		// A口读地址遇到B口写同址，直接返回B新数据；否则若A自己写则返回A新数据，实现write-first。
		if (web && (addrb == addra))
			douta_r <= dinb;
		else if (wea)
			douta_r <= dina;
		else
			douta_r <= mem[addra];
		// B口写使能有效则写入；B读输出也优先返回本次B新数据，而不是旧mem值。
		if (web)
			doutb_r <= dinb;
		// B口没有写，但A口写到了B所读地址，B输出旁路A新数据。
		else if (wea && (addra == addrb))
			doutb_r <= dina;
		else
			doutb_r <= mem[addrb];
	end
	// A口读结果由douta_r寄存器输出；外部连线本身不增加延迟。
	assign douta = douta_r;
	// B口读结果由doutb_r寄存器输出；数据在clka边沿后更新。
	assign doutb = doutb_r;
endmodule

// ============================================================================
// BTB单bank：64项×56位，每项{brtype[1:0],PC_tag[21:0],actual_next_PC[31:0]}。
// A口通常查询，B口训练；双口共用clka，clkb未使用；读写同址显式返回新数据(write-first)。
// 同一always中B写排在A写之后；两口写同址时该模型后面的B写优先，不应推广为所有物理RAM的保证。
// 无复位、无initial清表、无独立valid；地址路由/tag命中由上层实现，此模块只负责存取。
// ============================================================================
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

    // 生成循环的 genvar 提前声明；过程循环在 for 内声明 integer。


	// RAM实际工作时钟；本实现A口与B口都由posedge clka驱动。
	input wire clka;
	// A口写使能，1时在clka上升沿写mem[addra]；预测器查询实例中通常固定接0。
	input wire wea;
	// A口查询/写入行地址，固定6位，选择64行中的一行；bank选择由上层完成。
	input wire [5:0] addra;
	// A口写数据：旧BHT为4位历史，BTB为56位{类型2,tag22,目标32}，实际位宽见声明。
	input wire [55:0] dina;
	// A口同步读出，支持写入新值旁路(write-first)；旧BHT4位，BTB56位。
	output wire [55:0] douta;
	// 保留的B口时钟接口；本文件内部不使用它，A/B实际共用clka，不能据端口名当作异步双时钟RAM。
	input wire clkb;
	// B口写使能，1时在clka上升沿写mem[addrb]；更新状态机驱动。
	input wire web;
	// B口更新/读取行地址，固定6位；上层更新FSM先读旧信息，再写新表项。
	input wire [5:0] addrb;
	// B口更新数据：旧BHT为4位新历史，BTB为56位新表项。
	input wire [55:0] dinb;
	// B口同步读出，供更新FSM检查旧表项；同边沿写入时输出新值旁路。
	output wire [55:0] doutb;
	// RAM逻辑行数；通用RAM为2^ADDR_W，ip_predict_mem中的旧BHT/BTB固定64行。
	localparam signed [31:0] DEPTH = 64;
	// 本模块实例独立的RAM数组；多实例不是共享同一份数据，实际映射由综合工具决定。
	reg [55:0] mem [0:63];
	// A口读数据寄存器；对外douta由连续赋值连接它。
	reg [55:0] douta_r;
	// B口读数据寄存器；对外doutb由连续赋值连接它。
	reg [55:0] doutb_r;
	always @(posedge clka) begin
		// A口允许写入；若同边沿A/B写同址，同一always中后面的B口赋值在该模型内优先。
		if (wea)
			mem[addra] <= dina;
		// B口写使能有效则写入；B读输出也优先返回本次B新数据，而不是旧mem值。
		if (web)
			mem[addrb] <= dinb;
		// A口读地址遇到B口写同址，直接返回B新数据；否则若A自己写则返回A新数据，实现write-first。
		if (web && (addrb == addra))
			douta_r <= dinb;
		else if (wea)
			douta_r <= dina;
		else
			douta_r <= mem[addra];
		// B口写使能有效则写入；B读输出也优先返回本次B新数据，而不是旧mem值。
		if (web)
			doutb_r <= dinb;
		// B口没有写，但A口写到了B所读地址，B输出旁路A新数据。
		else if (wea && (addra == addrb))
			doutb_r <= dina;
		else
			doutb_r <= mem[addrb];
	end
	// A口读结果由douta_r寄存器输出；外部连线本身不增加延迟。
	assign douta = douta_r;
	// B口读结果由doutb_r寄存器输出；数据在clka边沿后更新。
	assign doutb = doutb_r;
endmodule
