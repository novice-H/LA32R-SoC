`default_nettype none
/* verilator lint_off UNUSEDSIGNAL */
// ---------------------------------------------------------------------------
// async_sram_model.v —— 板级异步 SRAM 行为模型（仅仿真用）
//
// 对应板上 IS61 系列异步 SRAM：
//   * CE_n / OE_n / WE_n 全低有效
//   * 读：CE_n=0 && OE_n=0 && WE_n=1 时，data 组合输出 mem[a]
//   * 写：CE_n=0 && WE_n=0 时，在时钟沿按 be_n 写入对应字节
//   * data 为双向总线，非读窗口时输出高阻
// ---------------------------------------------------------------------------
module async_sram_model #(
    parameter integer WORDS     = 1024,
    parameter         LOAD_INIT = 1'b0,        // 1: 用 INIT_FILE 预装；0: 填 FILL_WORD
    parameter         INIT_FILE = "fb0.hex",
    parameter [31:0]  FILL_WORD = 32'hdead_beef
)(
    input  wire        clk,
    input  wire [19:0] addr,
    input  wire [3:0]  be_n,
    input  wire        ce_n,
    input  wire        oe_n,
    input  wire        we_n,
    inout  wire [31:0] data
);

    localparam integer ADDR_W = (WORDS <= 1) ? 1 : $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];
    integer i;

    wire [ADDR_W-1:0] a = addr[ADDR_W-1:0];

    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = FILL_WORD;
        if (LOAD_INIT) $readmemh(INIT_FILE, mem);
    end

    assign data = (!ce_n && !oe_n && we_n) ? mem[a] : 32'bz;

    always @(posedge clk) begin
        if (!ce_n && !we_n) begin
            if (!be_n[0]) mem[a][7:0]   <= data[7:0];
            if (!be_n[1]) mem[a][15:8]  <= data[15:8];
            if (!be_n[2]) mem[a][23:16] <= data[23:16];
            if (!be_n[3]) mem[a][31:24] <= data[31:24];
        end
    end

endmodule

`default_nettype wire
