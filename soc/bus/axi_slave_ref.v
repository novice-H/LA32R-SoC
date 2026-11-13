`default_nettype none
// ---------------------------------------------------------------------------
// axi_slave_ref.v —— 【参考实现，可替换】AXI3 从设备 → 简单总线
//
// 这是为了让全系统仿真在队友的正式 AXI 桥到位前就能跑起来的占位桥。
// 正式桥请按同一接口替换本文件（模块名保持 axi_slave_wrap，或改顶层例化）。
//
// 支持范围（覆盖 openLA500 的 cache 行填充与单字访问）：
//   * 读：INCR 突发，最多 4 拍，每拍 32 位（arsize=2）
//   * 写：INCR 突发，最多 4 拍，带 wstrb
//   * 同一时刻只处理一个事务（读优先），CPU 的 axi_bridge 本身也不会读写在途重叠
//   * rready/bready 默认常 1（openLA500 的实现即如此）
//
// 限制：只按 32 位字访问；arsize/awsize < 2 的窄传输未做字节对齐处理。
// ---------------------------------------------------------------------------
module axi_slave_wrap (
    input  wire        aclk,
    input  wire        aresetn,

    // ---- AXI3 从设备 ----
    input  wire [3:0]  arid,
    input  wire [31:0] araddr,
    input  wire [7:0]  arlen,
    input  wire [2:0]  arsize,
    input  wire [1:0]  arburst,
    input  wire        arvalid,
    output wire        arready,

    output reg  [3:0]  rid,
    output reg  [31:0] rdata,
    output reg  [1:0]  rresp,
    output reg         rlast,
    output reg         rvalid,
    input  wire        rready,

    input  wire [3:0]  awid,
    input  wire [31:0] awaddr,
    input  wire [7:0]  awlen,
    input  wire [2:0]  awsize,
    input  wire [1:0]  awburst,
    input  wire        awvalid,
    output wire        awready,

    input  wire [3:0]  wid,
    input  wire [31:0] wdata_in,
    input  wire [3:0]  wstrb,
    input  wire        wlast,
    input  wire        wvalid,
    output wire        wready,

    output reg  [3:0]  bid,
    output reg  [1:0]  bresp,
    output reg         bvalid,
    input  wire        bready,

    // ---- 简单总线（到 soc_bus）----
    output reg  [31:0] m_addr,
    output reg         m_req_valid,
    input  wire        m_req_ready,
    output reg         m_we,
    output reg  [3:0]  m_be_n,
    output reg  [31:0] m_wdata,
    input  wire        m_rsp_valid,
    input  wire [31:0] m_rsp_rdata
);

    localparam [3:0] S_IDLE   = 4'd0,
                     S_RD_REQ = 4'd1,
                     S_RD_ACK = 4'd2,   // 已发请求，等总线接收
                     S_RD_WAIT= 4'd3,
                     S_WR_AW  = 4'd4,   // 已收 AW，等 W 拍
                     S_WR_REQ = 4'd5,
                     S_WR_ACK = 4'd6,
                     S_WR_WAIT= 4'd7,
                     S_B_RESP = 4'd8;

    reg [3:0]  st;

    reg [3:0]  r_id;
    reg [31:0] r_base;
    reg [7:0]  r_len;
    reg [3:0]  r_beat;

    reg [3:0]  w_id;
    reg [31:0] w_base;
    reg [7:0]  w_len;
    reg [3:0]  w_beat;
    reg [3:0]  w_cnt;

    reg [31:0] w_buf_data [0:3];
    reg [3:0]  w_buf_strb [0:3];

    // 读优先；只有空闲时接受 AR/AW
    assign arready = (st == S_IDLE);
    assign awready = (st == S_IDLE) && !arvalid;
    assign wready  = (st == S_WR_AW);

    always @(posedge aclk) begin
        if (!aresetn) begin
            st         <= S_IDLE;
            m_req_valid<= 1'b0;
            m_we       <= 1'b0;
            m_be_n     <= 4'h0;
            m_addr     <= 32'd0;
            m_wdata    <= 32'd0;
            rvalid     <= 1'b0;
            rlast      <= 1'b0;
            rdata      <= 32'd0;
            rresp      <= 2'b0;
            rid        <= 4'd0;
            bvalid     <= 1'b0;
            bresp      <= 2'b0;
            bid        <= 4'd0;
            r_beat     <= 4'd0;
            w_beat     <= 4'd0;
            w_cnt      <= 4'd0;
        end else begin
            rvalid <= 1'b0;
            bvalid <= 1'b0;

            case (st)
                S_IDLE: begin
                    m_req_valid <= 1'b0;
                    if (arvalid) begin
                        r_id   <= arid;
                        r_base <= {araddr[31:2], 2'b00};
                        r_len  <= arlen;
                        r_beat <= 4'd0;
                        st     <= S_RD_REQ;
                    end else if (awvalid) begin
                        w_id   <= awid;
                        w_base <= {awaddr[31:2], 2'b00};
                        w_len  <= awlen;
                        w_cnt  <= 4'd0;
                        st     <= S_WR_AW;
                    end
                end

                // ---------------- 读 ----------------
                S_RD_REQ: begin
                    m_addr      <= r_base + {r_beat, 2'b00};
                    m_we        <= 1'b0;
                    m_be_n      <= 4'h0;
                    m_wdata     <= 32'd0;
                    m_req_valid <= 1'b1;
                    st          <= S_RD_ACK;
                end
                S_RD_ACK: begin
                    if (m_req_ready) begin
                        m_req_valid <= 1'b0;
                        st <= S_RD_WAIT;
                    end
                end
                S_RD_WAIT: begin
                    if (m_rsp_valid) begin
                        rdata  <= m_rsp_rdata;
                        rid    <= r_id;
                        rresp  <= 2'b00;
                        rlast  <= (r_beat == r_len);
                        rvalid <= 1'b1;
                        if (r_beat == r_len) begin
                            st <= S_IDLE;
                        end else begin
                            r_beat <= r_beat + 4'd1;
                            st     <= S_RD_REQ;
                        end
                    end
                end

                // ---------------- 写 ----------------
                S_WR_AW: begin
                    if (wvalid) begin
                        w_buf_data[w_cnt[1:0]] <= wdata_in;
                        w_buf_strb[w_cnt[1:0]] <= wstrb;
                        if (wlast) begin
                            w_beat <= 4'd0;
                            st     <= S_WR_REQ;
                        end else begin
                            w_cnt <= w_cnt + 4'd1;
                        end
                    end
                end
                S_WR_REQ: begin
                    m_addr      <= w_base + {w_beat, 2'b00};
                    m_we        <= 1'b1;
                    m_be_n      <= ~w_buf_strb[w_beat[1:0]];
                    m_wdata     <= w_buf_data[w_beat[1:0]];
                    m_req_valid <= 1'b1;
                    st          <= S_WR_ACK;
                end
                S_WR_ACK: begin
                    if (m_req_ready) begin
                        m_req_valid <= 1'b0;
                        st <= S_WR_WAIT;
                    end
                end
                S_WR_WAIT: begin
                    if (m_rsp_valid) begin
                        if (w_beat == w_len) begin
                            bid    <= w_id;
                            bresp  <= 2'b00;
                            bvalid <= 1'b1;
                            st     <= S_B_RESP;
                        end else begin
                            w_beat <= w_beat + 4'd1;
                            st     <= S_WR_REQ;
                        end
                    end
                end
                S_B_RESP: begin
                    bvalid <= 1'b1;
                    if (bready) begin
                        bvalid <= 1'b0;
                        st     <= S_IDLE;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
