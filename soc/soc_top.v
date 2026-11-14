`default_nettype none
// ---------------------------------------------------------------------------
// soc_top.v —— 2048 SoC 顶层（CPU + AXI 桥 + 总线 + 存储器 + confreg + VGA）
//
//   core_top (AXI3) ──► axi_slave_wrap ──► soc_bus ──┬─► base_ram_ctrl
//                                                    ├─► ext_ram_arbiter ─► ext_ram_ctrl
//                                                    └─► confreg
//   vga_fb ──DVI──► ext_ram_arbiter
//   confreg.fb_sel ↔ vga_fb.fb_sel, vga_fb.vsync_start → confreg
//
// 板级引脚命名与 thinpad_top.v 一致；后续把 thinpad_top 改成对本模块的封装即可。
// 地址映射见 soc/bus/soc_bus.v（同时接受 0x1C00_0000 与 0x8000_0000 两套）。
// ---------------------------------------------------------------------------
module soc_top (
    input  wire        clk_50M,
    input  wire        reset_btn,

    // BaseRAM
    inout  wire [31:0] base_ram_data,
    output wire [19:0] base_ram_addr,
    output wire [3:0]  base_ram_be_n,
    output wire        base_ram_ce_n,
    output wire        base_ram_oe_n,
    output wire        base_ram_we_n,

    // ExtRAM
    inout  wire [31:0] ext_ram_data,
    output wire [19:0] ext_ram_addr,
    output wire [3:0]  ext_ram_be_n,
    output wire        ext_ram_ce_n,
    output wire        ext_ram_oe_n,
    output wire        ext_ram_we_n,

    // 视频
    output wire [2:0]  video_red,
    output wire [2:0]  video_green,
    output wire [1:0]  video_blue,
    output wire        video_hsync,
    output wire        video_vsync,
    output wire        video_clk,
    output wire        video_de,

    // 板载 I/O
    input  wire [3:0]  touch_btn,
    input  wire [31:0] dip_sw,
    output wire [15:0] leds,
    output wire [7:0]  dpy0,
    output wire [7:0]  dpy1,

    // 仿真观测用：写回级 PC
    output wire [31:0] dbg_wb_pc
);

    // ---------------------------------------------------------------- 复位
    reg [1:0] rst_sync;
    always @(posedge clk_50M) rst_sync <= {rst_sync[0], reset_btn};
    wire rst    = rst_sync[1];
    wire aresetn = ~rst;

    // ---------------------------------------------------------------- CPU
    wire [3:0]  arid, awid, wid;
    wire [31:0] araddr, awaddr, wdata;
    wire [7:0]  arlen, awlen;
    wire [2:0]  arsize, awsize;
    wire [1:0]  arburst, awburst, arlock, awlock;
    wire [3:0]  arcache, awcache;
    wire [2:0]  arprot, awprot;
    wire        arvalid, awvalid, wvalid;
    wire        arready, awready, wready;
    wire [3:0]  rid, bid;
    wire [31:0] rdata;
    wire [1:0]  rresp, bresp;
    wire        rlast, rvalid, bvalid;
    wire        rready, bready;
    wire [3:0]  wstrb;
    wire        wlast;

    core_top u_cpu (
        .aclk      (clk_50M),
        .aresetn   (aresetn),
        .intrpt    (8'd0),
        .arid      (arid),
        .araddr    (araddr),
        .arlen     (arlen),
        .arsize    (arsize),
        .arburst   (arburst),
        .arlock    (arlock),
        .arcache   (arcache),
        .arprot    (arprot),
        .arvalid   (arvalid),
        .arready   (arready),
        .rid       (rid),
        .rdata     (rdata),
        .rresp     (rresp),
        .rlast     (rlast),
        .rvalid    (rvalid),
        .rready    (rready),
        .awid      (awid),
        .awaddr    (awaddr),
        .awlen     (awlen),
        .awsize    (awsize),
        .awburst   (awburst),
        .awlock    (awlock),
        .awcache   (awcache),
        .awprot    (awprot),
        .awvalid   (awvalid),
        .awready   (awready),
        .wid       (wid),
        .wdata     (wdata),
        .wstrb     (wstrb),
        .wlast     (wlast),
        .wvalid    (wvalid),
        .wready    (wready),
        .bid       (bid),
        .bresp     (bresp),
        .bvalid    (bvalid),
        .bready    (bready),
        .break_point(1'b0),
        .infor_flag (1'b0),
        .reg_num    (5'd0),
        .ws_valid   (),
        .rf_rdata   (),
        .debug0_wb_pc     (dbg_wb_pc),
        .debug0_wb_rf_wen (),
        .debug0_wb_rf_wnum(),
        .debug0_wb_rf_wdata(),
        .debug0_wb_inst   ()
    );

    // ---------------------------------------------------------------- AXI 桥
    wire        bus_req_valid, bus_req_ready;
    wire [31:0] bus_addr, bus_wdata, bus_rsp_rdata;
    wire        bus_we;
    wire [3:0]  bus_be_n;
    wire        bus_rsp_valid;

    axi_slave_wrap u_bridge (
        .aclk(clk_50M), .aresetn(aresetn),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast),
        .rvalid(rvalid), .rready(rready),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awvalid(awvalid), .awready(awready),
        .wid(wid), .wdata_in(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .m_addr(bus_addr), .m_req_valid(bus_req_valid), .m_req_ready(bus_req_ready),
        .m_we(bus_we), .m_be_n(bus_be_n), .m_wdata(bus_wdata),
        .m_rsp_valid(bus_rsp_valid), .m_rsp_rdata(bus_rsp_rdata)
    );

    // ---------------------------------------------------------------- 总线
    wire        b_req, b_ready, b_we, b_rsp_valid;
    wire [19:0] b_addr;
    wire [3:0]  b_be_n;
    wire [31:0] b_wdata, b_rsp_rdata;

    wire        e_req, e_ready, e_we, e_rsp_valid;
    wire [19:0] e_addr;
    wire [3:0]  e_be_n;
    wire [31:0] e_wdata, e_rsp_rdata;

    wire        c_req, c_ready, c_we, c_rsp_valid;
    wire [7:0]  c_addr;
    wire [3:0]  c_be_n;
    wire [31:0] c_wdata, c_rsp_rdata;

    soc_bus u_bus (
        .clk(clk_50M), .rst(rst),
        .m_req_valid(bus_req_valid), .m_req_ready(bus_req_ready),
        .m_addr(bus_addr), .m_we(bus_we), .m_be_n(bus_be_n), .m_wdata(bus_wdata),
        .m_rsp_valid(bus_rsp_valid), .m_rsp_rdata(bus_rsp_rdata), .m_error(),
        .b_req(b_req), .b_ready(b_ready), .b_addr(b_addr), .b_we(b_we),
        .b_be_n(b_be_n), .b_wdata(b_wdata),
        .b_rsp_valid(b_rsp_valid), .b_rsp_rdata(b_rsp_rdata),
        .e_req(e_req), .e_ready(e_ready), .e_addr(e_addr), .e_we(e_we),
        .e_be_n(e_be_n), .e_wdata(e_wdata),
        .e_rsp_valid(e_rsp_valid), .e_rsp_rdata(e_rsp_rdata),
        .c_req(c_req), .c_ready(c_ready), .c_addr(c_addr), .c_we(c_we),
        .c_be_n(c_be_n), .c_wdata(c_wdata),
        .c_rsp_valid(c_rsp_valid), .c_rsp_rdata(c_rsp_rdata)
    );

    // ---------------------------------------------------------------- BaseRAM
    base_ram_ctrl #(.CLK_FREQ(50_000_000), .RAM_FREQ(67_000_000)) u_base_ram (
        .clk(clk_50M), .rst(rst),
        .req_valid(b_req), .req_ready(b_ready),
        .req_addr(b_addr), .req_we(b_we), .req_be_n(b_be_n), .req_wdata(b_wdata),
        .rsp_valid(b_rsp_valid), .rsp_rdata(b_rsp_rdata),
        .base_ram_data(base_ram_data), .base_ram_addr(base_ram_addr),
        .base_ram_be_n(base_ram_be_n), .base_ram_ce_n(base_ram_ce_n),
        .base_ram_oe_n(base_ram_oe_n), .base_ram_we_n(base_ram_we_n)
    );

    // ---------------------------------------------------------------- ExtRAM
    wire        dvi_req, dvi_next, dvi_ready, dvi_rsp_valid;
    wire [19:0] dvi_addr;
    wire [31:0] dvi_rdata;

    wire        m_req, m_ready, m_we, m_rsp_valid;
    wire [19:0] m_addr;
    wire [3:0]  m_be_n;
    wire [31:0] m_wdata, m_rsp_rdata;

    ext_ram_arbiter u_arb (
        .clk(clk_50M), .rst(rst),
        .dvi_req(dvi_req), .dvi_next(dvi_next), .dvi_addr(dvi_addr),
        .dvi_ready(dvi_ready), .dvi_rdata(dvi_rdata), .dvi_rsp_valid(dvi_rsp_valid),
        .cpu_req(e_req), .cpu_addr(e_addr), .cpu_we(e_we),
        .cpu_be_n(e_be_n), .cpu_wdata(e_wdata),
        .cpu_ready(e_ready), .cpu_rsp_rdata(e_rsp_rdata), .cpu_rsp_valid(e_rsp_valid),
        .mem_req(m_req), .mem_addr(m_addr), .mem_we(m_we),
        .mem_be_n(m_be_n), .mem_wdata(m_wdata),
        .mem_ready(m_ready), .mem_rsp_valid(m_rsp_valid), .mem_rsp_rdata(m_rsp_rdata)
    );

    ext_ram_ctrl #(.CLK_FREQ(50_000_000), .RAM_FREQ(67_000_000)) u_ext_ram (
        .clk(clk_50M), .rst(rst),
        .req_valid(m_req), .req_ready(m_ready),
        .req_addr(m_addr), .req_we(m_we), .req_be_n(m_be_n), .req_wdata(m_wdata),
        .rsp_valid(m_rsp_valid), .rsp_rdata(m_rsp_rdata),
        .ext_ram_data(ext_ram_data), .ext_ram_addr(ext_ram_addr),
        .ext_ram_be_n(ext_ram_be_n), .ext_ram_ce_n(ext_ram_ce_n),
        .ext_ram_oe_n(ext_ram_oe_n), .ext_ram_we_n(ext_ram_we_n)
    );

    // ---------------------------------------------------------------- VGA
    wire        fb_sel;
    wire        vsync_start;

    vga_fb u_vga (
        .clk(clk_50M), .rst(rst), .fb_sel(fb_sel),
        .ram_addr(dvi_addr), .ram_req(dvi_req), .ram_rdata(dvi_rdata),
        .vga_red(video_red), .vga_green(video_green), .vga_blue(video_blue),
        .vga_hsync(video_hsync), .vga_vsync(video_vsync), .vga_de(video_de),
        .vsync_start(vsync_start), .dvi_next(dvi_next)
    );

    assign video_clk = clk_50M;

    // ---------------------------------------------------------------- confreg
    confreg u_conf (
        .clk(clk_50M), .rst(rst),
        .req_valid(c_req), .req_ready(c_ready),
        .req_addr(c_addr), .req_we(c_we), .req_be_n(c_be_n), .req_wdata(c_wdata),
        .rsp_valid(c_rsp_valid), .rsp_rdata(c_rsp_rdata),
        .touch_btn(touch_btn), .dip_sw(dip_sw),
        .vsync_start(vsync_start), .fb_sel(fb_sel),
        .leds(leds), .dpy1(dpy1), .dpy0(dpy0)
    );

endmodule

`default_nettype wire
