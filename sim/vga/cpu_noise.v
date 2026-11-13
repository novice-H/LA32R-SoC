`default_nettype none
// ---------------------------------------------------------------------------
// cpu_noise.v —— 仿真用的"CPU 噪声"主机
//
// ExtRAM 的真实使用里，CPU 会在 DVI 扫描的同时读写显存/AI 表。本模块持续向
// 高地址区（默认 300000 字，避开 FB0/FB1）写-读-校验，用来验证：
//   * 仲裁器在 DVI 优先的前提下不会饿死 CPU；
//   * CPU 的写入/读回在争用下仍然正确；
//   * DVI 画面不被 CPU 访问破坏。
// ---------------------------------------------------------------------------
module cpu_noise #(
    parameter integer BASE = 300000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        en,

    output reg         req,
    output reg  [19:0] addr,
    output reg         we,
    output reg  [3:0]  be_n,
    output reg  [31:0] wdata,
    input  wire        ready,
    input  wire        rsp_valid,
    input  wire [31:0] rsp_rdata,

    output reg  [31:0] grants,
    output reg  [31:0] errors
);

    localparam [2:0] S_IDLE   = 3'd0,
                     S_WR     = 3'd1,
                     S_WR_WAIT= 3'd2,
                     S_RD     = 3'd3,
                     S_RD_WAIT= 3'd4;

    reg [2:0]  st;
    reg [7:0]  idx;
    reg [31:0] exp_word;

    always @(posedge clk) begin
        if (rst) begin
            st     <= S_IDLE;
            req    <= 1'b0;
            addr   <= 20'd0;
            we     <= 1'b0;
            be_n   <= 4'h0;
            wdata  <= 32'd0;
            idx    <= 8'd0;
            grants <= 32'd0;
            errors <= 32'd0;
        end else if (!en) begin
            st  <= S_IDLE;
            req <= 1'b0;
        end else begin
            case (st)
                S_IDLE: begin
                    addr   <= BASE[19:0] + {12'd0, idx};
                    we     <= 1'b1;
                    be_n   <= 4'b0000;
                    wdata  <= 32'hC0DE_0000 | {24'd0, idx};
                    exp_word <= 32'hC0DE_0000 | {24'd0, idx};
                    req    <= 1'b1;
                    st     <= S_WR;
                end
                S_WR: if (ready) begin
                    grants <= grants + 32'd1;
                    req    <= 1'b0;
                    st     <= S_WR_WAIT;
                end
                S_WR_WAIT: if (rsp_valid) begin
                    addr <= BASE[19:0] + {12'd0, idx};
                    we   <= 1'b0;
                    be_n <= 4'b0000;
                    req  <= 1'b1;
                    st   <= S_RD;
                end
                S_RD: if (ready) begin
                    grants <= grants + 32'd1;
                    req    <= 1'b0;
                    st     <= S_RD_WAIT;
                end
                S_RD_WAIT: if (rsp_valid) begin
                    if (rsp_rdata !== exp_word) errors <= errors + 32'd1;
                    idx <= idx + 8'd1;
                    st  <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
