`default_nettype none
// ---------------------------------------------------------------------------
// ext_ram_arbiter.v —— ExtRAM 单口控制器与两个主机（CPU / DVI）之间的仲裁
//
// 依据 docs/design.md 2.2.5：
//   * DVI 优先：每个像素组（4 像素）必须读到 1 个字，不能等；
//   * CPU：DVI 不占用时授予，最多被推迟一拍；
//   * 只有 CPU 和 DVI 两个主机，控制器一次只服务一个事务。
//
// 接口约定
//   * dvi_req 是**单拍**请求；dvi_next 是提前一拍的预警（dvi_req 的前一拍）。
//     vga_fb 每 4 个像素发一次请求，控制器需要 2 拍返回，所以 DVI 的请求
//     必须在 dvi_next 那一拍之前就把控制器腾出来。
//   * dvi_rdata 是"保持型"输出：DVI 响应当拍直接透传，其余时刻保持上一次
//     的字。这样 CPU 的响应即使插在像素组中间，也不会破坏正在扫描的字。
//   * CPU 侧是标准 valid/ready 单拍握手；响应只给一拍（rsp_valid）。
// ---------------------------------------------------------------------------
module ext_ram_arbiter (
    input  wire        clk,
    input  wire        rst,

    // ---- DVI 主机（实时读，不可等待）----
    input  wire        dvi_req,
    input  wire        dvi_next,
    input  wire [19:0] dvi_addr,
    output wire        dvi_ready,
    output wire [31:0] dvi_rdata,
    output wire        dvi_rsp_valid,

    // ---- CPU 主机 ----
    input  wire        cpu_req,
    input  wire [19:0] cpu_addr,
    input  wire        cpu_we,
    input  wire [3:0]  cpu_be_n,
    input  wire [31:0] cpu_wdata,
    output wire        cpu_ready,
    output wire [31:0] cpu_rsp_rdata,
    output wire        cpu_rsp_valid,

    // ---- 控制器侧 ----
    output wire        mem_req,
    output wire [19:0] mem_addr,
    output wire        mem_we,
    output wire [3:0]  mem_be_n,
    output wire [31:0] mem_wdata,
    input  wire        mem_ready,
    input  wire        mem_rsp_valid,
    input  wire [31:0] mem_rsp_rdata
);

    reg owner;   // 0 = DVI, 1 = CPU（当前在途事务的归属）

    // DVI 永远优先；CPU 只在控制器空闲、且不是 DVI 预警/请求拍时才能拿到
    wire dvi_grant = dvi_req && mem_ready;
    wire cpu_grant = cpu_req && mem_ready && !dvi_req && !dvi_next && !rst;

    assign mem_req   = dvi_grant || cpu_grant;
    assign mem_addr  = dvi_req ? dvi_addr : cpu_addr;
    assign mem_we    = dvi_req ? 1'b0     : cpu_we;
    assign mem_be_n  = dvi_req ? 4'b0000  : cpu_be_n;
    assign mem_wdata = dvi_req ? 32'd0    : cpu_wdata;

    assign dvi_ready = dvi_grant;
    assign cpu_ready = cpu_grant;

    always @(posedge clk) begin
        if (rst) begin
            owner <= 1'b0;
        end else if (dvi_grant) begin
            owner <= 1'b0;
        end else if (cpu_grant) begin
            owner <= 1'b1;
        end
    end

    wire dvi_hit = mem_rsp_valid && (owner == 1'b0);
    reg [31:0] dvi_hold;

    // 响应当拍透传，其余时刻保持，保证一个像素组内字稳定
    assign dvi_rdata     = dvi_hit ? mem_rsp_rdata : dvi_hold;
    assign dvi_rsp_valid = dvi_hit;

    always @(posedge clk) begin
        if (dvi_hit) dvi_hold <= mem_rsp_rdata;
    end

    assign cpu_rsp_valid = mem_rsp_valid && (owner == 1'b1);
    assign cpu_rsp_rdata = mem_rsp_rdata;

endmodule

`default_nettype wire
