`default_nettype none
// ---------------------------------------------------------------------------
// sram_ctrl.v —— 板上异步 SRAM 控制器（从 loongsoncup2026 的 LSU/RAM 设计移植）
//
// 来源设计（参考实现）：
//   loongsoncup2026-229ms-191.7MHz/src/soc/RAM.sv
//   原工程：thinpad_top → CPU → LSU → BSE / EXT → RAM（共享的异步 SRAM 控制器）
//
// 移植时做了三件事（原因见 soc/mem/README.md）：
//   1. 去掉 IFU/XIU 双请求端口、hold buffer、cancel、响应元数据，只保留
//      物理 SRAM 协议层，对外是干净的 valid/ready 单请求接口。
//   2. 频率参数化：RAM_CYC = ceil(CLK_FREQ / RAM_FREQ)。原工程 193MHz/67MHz
//      → 3 拍；本工程 50MHz → 1 拍。
//   3. 读返回原始 32 位字（字节选择/符号扩展交给总线桥），写返回完成脉冲。
//
// 板上 SRAM 是**异步**器件：地址/CE/OE/WE/BE 由 IOB 寄存器直接驱动，
// 读数据在访问窗口末尾采样。控制引脚全部低有效。
// ---------------------------------------------------------------------------
module sram_ctrl #(
    parameter integer CLK_FREQ = 50_000_000,   // 控制器时钟
    parameter integer RAM_FREQ = 67_000_000    // SRAM 器件频率上限（薄板约 67MHz）
)(
    input  wire        clk,
    input  wire        rst,          // 同步、高有效

    // 请求通道（一次一个事务；无背压响应）
    input  wire        req_valid,
    output wire        req_ready,    // 空闲时接受；与 req_valid 同拍握手
    input  wire [19:0] req_addr,     // 字地址（4 字节对齐）
    input  wire        req_we,       // 1=写，0=读
    input  wire [3:0]  req_be_n,     // 字节使能，低有效；读可给 4'h0
    input  wire [31:0] req_wdata,    // 写数据（已对齐到 32 位通道）

    // 响应通道：读给出数据；写给出完成脉冲（数据无效）
    output reg         rsp_valid,
    output reg  [31:0] rsp_rdata,

    // 板上异步 SRAM 物理引脚
    inout  wire [31:0] ram_data,
    output wire [19:0] ram_addr,
    output wire [3:0]  ram_be_n,
    output wire        ram_ce_n,
    output wire        ram_oe_n,
    output wire        ram_we_n
);

    localparam integer RAM_CYC = (CLK_FREQ + RAM_FREQ - 1) / RAM_FREQ;
    localparam integer CYC_W   = (RAM_CYC <= 1) ? 1 : $clog2(RAM_CYC);
    localparam [CYC_W-1:0] LAST = RAM_CYC - 1;   // Verilog-2001：隐式截断到 CYC_W 位

    reg              busy;
    reg [CYC_W-1:0]  cyc;
    reg [19:0]       addr_q;
    reg [3:0]        be_n_q;
    reg              we_q;

    // 引脚寄存器尽量放进 IOB（与原设计一致）
    (* iob = "true" *) reg        ce_n_q;
    (* iob = "true" *) reg        oe_n_q;
    (* iob = "true" *) reg        we_n_q;
    (* iob = "true" *) reg [31:0] wdata_o;

    assign ram_addr = addr_q;
    assign ram_be_n = be_n_q;
    assign ram_ce_n = ce_n_q;
    assign ram_oe_n = oe_n_q;
    assign ram_we_n = we_n_q;

    // 只在写事务的访问窗口内驱动数据总线，其余时间高阻
    assign ram_data = (busy && we_q && !ce_n_q) ? wdata_o : 32'bz;

    assign req_ready = !busy;

`ifdef SIMU
    // 仿真防空写：Verilator/部分仿真器上电把寄存器初始化成 0，
    // 会让 CE_n/WE_n 在第一个时钟沿前呈现"写"电平，误写一个 0。
    // 原设计 RAM.sv 也用了同样的处理。
    initial begin
        busy      = 1'b0;
        cyc       = {CYC_W{1'b0}};
        addr_q    = 20'd0;
        be_n_q    = 4'hf;
        we_q      = 1'b0;
        ce_n_q    = 1'b1;
        oe_n_q    = 1'b1;
        we_n_q    = 1'b1;
        wdata_o   = 32'd0;
        rsp_valid = 1'b0;
        rsp_rdata = 32'd0;
    end
`endif

    always @(posedge clk) begin
        if (rst) begin
            busy      <= 1'b0;
            cyc       <= {CYC_W{1'b0}};
            addr_q    <= 20'd0;
            be_n_q    <= 4'hf;
            we_q      <= 1'b0;
            ce_n_q    <= 1'b1;
            oe_n_q    <= 1'b1;
            we_n_q    <= 1'b1;
            wdata_o   <= 32'd0;
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'd0;
        end else begin
            rsp_valid <= 1'b0;

            if (!busy) begin
                if (req_valid) begin
                    // 接受请求：当拍就拉低 CE，进入访问窗口
                    busy      <= 1'b1;
                    cyc       <= {CYC_W{1'b0}};
                    addr_q    <= req_addr;
                    be_n_q    <= req_be_n;
                    we_q      <= req_we;
                    wdata_o   <= req_wdata;
                    ce_n_q    <= 1'b0;
                    oe_n_q    <= req_we;      // 写：OE=1；读：OE=0
                    we_n_q    <= ~req_we;
                end
            end else begin
                if (cyc == LAST) begin
                    // 访问窗口结束：收 CE/OE/WE，读事务采样数据
                    busy    <= 1'b0;
                    ce_n_q  <= 1'b1;
                    oe_n_q  <= 1'b1;
                    we_n_q  <= 1'b1;
                    if (!we_q) begin
                        rsp_rdata <= ram_data;
                    end
                    rsp_valid <= 1'b1;        // 读/写都给一个完成脉冲
                end else begin
                    cyc <= cyc + 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
