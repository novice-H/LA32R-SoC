`default_nettype none
// ---------------------------------------------------------------------------
// ram_model.v —— ExtRAM 行为模型（4 MB = 1M × 32 bit）
//
// 单口、同步读、1 拍延迟，与板上 SRAM 的读时序一致。
// 上电时按 INIT_FILE 用 $readmemh 预装测试数据（每行一个 32 位字）。
// 未初始化的字清零，避免仿真里出现 X 传播。
// ---------------------------------------------------------------------------
module ram_model #(
    parameter integer WORDS     = 1048576,
    parameter         INIT_FILE = "fb0.hex"
)(
    input  wire        clk,
    input  wire [19:0] addr,
    input  wire        req,
    output reg  [31:0] rdata
);

    reg [31:0] mem [0:WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'd0;
        $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if (req) rdata <= mem[addr];
    end

endmodule

`default_nettype wire
