`default_nettype none
// ---------------------------------------------------------------------------
// soc_bus.v —— 地址译码 + 固定 2 拍应答
//
// 主设备侧（来自 AXI 桥）是简单的单拍请求：
//   m_req_valid/ready, m_addr[31:0]（字节地址）, m_we, m_be_n, m_wdata
//   -> m_rsp_valid（请求后第 2 拍）+ m_rsp_rdata
//
// 从设备：
//   BaseRAM  0x1C00_0000–0x1C3F_FFFF   别名 0x8000_0000–0x803F_FFFF
//   ExtRAM   0x1C40_0000–0x1C7F_FFFF   别名 0xA000_0000–0xA03F_FFFF
//   confreg  0xBFD0_0000–0xBFD0_00FF
//
// 为什么同时支持两套地址：
//   openLA500 复位后 PC=0x1C00_0000（DA=1 直接地址），代码与数据必须落在
//   0x1C00_0000/0x1C40_0000；而 docs/design.md 沿用 0x8000_0000/0xA000_0000
//   的 LA32R 窗口约定。译码器同时接受两套，软件可任选。
//
// 固定 2 拍应答：存储器控制器 2 拍返回、confreg 1 拍返回，这里统一成 2 拍，
// CPU 侧只看到一种等待状态（design.md 2.2.3）。
// ---------------------------------------------------------------------------
module soc_bus (
    input  wire        clk,
    input  wire        rst,

    // ---- 主设备（AXI 桥的简单总线侧）----
    input  wire        m_req_valid,
    output wire        m_req_ready,
    input  wire [31:0] m_addr,
    input  wire        m_we,
    input  wire [3:0]  m_be_n,
    input  wire [31:0] m_wdata,
    output wire        m_rsp_valid,
    output wire [31:0] m_rsp_rdata,
    output reg         m_error,       // 访问了未映射地址（单拍）

    // ---- BaseRAM ----
    output wire        b_req,
    input  wire        b_ready,
    output wire [19:0] b_addr,
    output wire        b_we,
    output wire [3:0]  b_be_n,
    output wire [31:0] b_wdata,
    input  wire        b_rsp_valid,
    input  wire [31:0] b_rsp_rdata,

    // ---- ExtRAM（仲裁器的 CPU 侧）----
    output wire        e_req,
    input  wire        e_ready,
    output wire [19:0] e_addr,
    output wire        e_we,
    output wire [3:0]  e_be_n,
    output wire [31:0] e_wdata,
    input  wire        e_rsp_valid,
    input  wire [31:0] e_rsp_rdata,

    // ---- confreg ----
    output wire        c_req,
    input  wire        c_ready,
    output wire [7:0]  c_addr,
    output wire        c_we,
    output wire [3:0]  c_be_n,
    output wire [31:0] c_wdata,
    input  wire        c_rsp_valid,
    input  wire [31:0] c_rsp_rdata
);

    // ---------------------------------------------------------------- 译码
    wire sel_base = (m_addr >= 32'h1C00_0000 && m_addr <= 32'h1C3F_FFFF) ||
                    (m_addr >= 32'h8000_0000 && m_addr <= 32'h803F_FFFF);
    wire sel_ext  = (m_addr >= 32'h1C40_0000 && m_addr <= 32'h1C7F_FFFF) ||
                    (m_addr >= 32'hA000_0000 && m_addr <= 32'hA03F_FFFF);
    wire sel_conf = (m_addr >= 32'hBFD0_0000 && m_addr <= 32'hBFD0_00FF);

    wire [1:0] sel = sel_base ? 2'd1 : sel_ext ? 2'd2 : sel_conf ? 2'd3 : 2'd0;

    // 片内偏移 -> 字地址（RAM）或字节偏移（confreg）
    wire [19:0] word_addr = m_addr[21:2];
    wire [7:0]  conf_off  = m_addr[7:0];

    // ---------------------------------------------------------------- 状态机
    localparam [1:0] S_IDLE = 2'd0, S_W1 = 2'd1, S_W2 = 2'd2;

    reg [1:0]  st;
    reg [1:0]  sel_q;
    reg [31:0] cap_data;

    wire slave_ready = (sel == 2'd1) ? b_ready :
                       (sel == 2'd2) ? e_ready :
                       (sel == 2'd3) ? c_ready : 1'b1;

    assign m_req_ready = (st == S_IDLE) && slave_ready;

    // 请求只在接收那一拍发出（组合）
    assign b_req   = (st == S_IDLE) && m_req_valid && (sel == 2'd1);
    assign b_addr  = word_addr;
    assign b_we    = m_we;
    assign b_be_n  = m_be_n;
    assign b_wdata = m_wdata;

    assign e_req   = (st == S_IDLE) && m_req_valid && (sel == 2'd2);
    assign e_addr  = word_addr;
    assign e_we    = m_we;
    assign e_be_n  = m_be_n;
    assign e_wdata = m_wdata;

    assign c_req   = (st == S_IDLE) && m_req_valid && (sel == 2'd3);
    assign c_addr  = conf_off;
    assign c_we    = m_we;
    assign c_be_n  = m_be_n;
    assign c_wdata = m_wdata;

    wire slave_rsp_valid = (sel_q == 2'd1) ? b_rsp_valid :
                           (sel_q == 2'd2) ? e_rsp_valid :
                           (sel_q == 2'd3) ? c_rsp_valid : 1'b0;
    wire [31:0] slave_rsp_data = (sel_q == 2'd1) ? b_rsp_rdata :
                                 (sel_q == 2'd2) ? e_rsp_rdata :
                                 (sel_q == 2'd3) ? c_rsp_rdata : 32'd0;

    always @(posedge clk) begin
        if (rst) begin
            st       <= S_IDLE;
            sel_q    <= 2'd0;
            cap_data <= 32'd0;
            m_error  <= 1'b0;
        end else begin
            m_error <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (m_req_valid && m_req_ready) begin
                        st    <= S_W1;
                        sel_q <= sel;
                        if (sel == 2'd0) m_error <= 1'b1;   // 未映射
                    end
                end
                S_W1: begin
                    if (slave_rsp_valid) cap_data <= slave_rsp_data;
                    st <= S_W2;
                end
                S_W2: st <= S_IDLE;
                default: st <= S_IDLE;
            endcase
        end
    end

    assign m_rsp_valid = (st == S_W2);
    assign m_rsp_rdata = slave_rsp_valid ? slave_rsp_data : cap_data;

endmodule

`default_nettype wire
