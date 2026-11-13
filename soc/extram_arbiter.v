`timescale 1ns/1ps
`default_nettype none

// ---------------------------------------------------------------------------
// extram_arbiter.v
//
// CPU/DVI 双主机 ExtRAM 仲裁器。
//
// CPU 接口：仓库 docs/design.md 定义的统一主机接口。
//   cpu_req 保持为 1，直到 cpu_ack 返回；写操作由 cpu_we=1 表示。
//   cpu_addr 是 LA32R 字节地址，模块将 0xA000_0000 段转换为 ExtRAM 字地址。
//
// DVI 接口：与 soc/vga_fb.v 的 ram_* 接口配套。
//   vga_req 是单拍请求；本仲裁器保证请求被接受，并在下一拍更新 vga_rdata。
//   vga_rvalid 额外提供返回脉冲，现有 vga_fb 可以不使用它。
//
// 仲裁规则：
//   1. 空闲时 DVI 优先，保证视频读请求不会被 CPU 抢占；
//   2. CPU 事务完成的同一拍可以接收新的 DVI 请求；
//   3. CPU 事务只进行单个字读写，读写应答在接收后的下一拍产生；
//   4. ExtRAM 数据总线只在写周期由 FPGA 驱动，其余时间保持高阻。
// ---------------------------------------------------------------------------
module extram_arbiter #(
    parameter [31:0] CPU_EXT_BASE = 32'hA000_0000
)(
    input  wire        clk,
    input  wire        rst,

    // CPU 主机接口
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_wstrb,
    input  wire        cpu_req,
    input  wire        cpu_we,
    output reg  [31:0] cpu_rdata,
    output reg         cpu_ack,

    // VGA/DVI 读接口
    input  wire [19:0] vga_addr,
    input  wire        vga_req,
    output reg  [31:0] vga_rdata,
    output reg         vga_rvalid,

    // 板级 ExtRAM 接口
    output wire [19:0] ext_ram_addr,
    inout  wire [31:0] ext_ram_data,
    output wire [3:0]  ext_ram_be_n,
    output wire        ext_ram_ce_n,
    output wire        ext_ram_oe_n,
    output wire        ext_ram_we_n
);

    localparam [1:0] OWNER_NONE = 2'd0;
    localparam [1:0] OWNER_CPU  = 2'd1;
    localparam [1:0] OWNER_VGA  = 2'd2;

    reg [1:0]  owner;
    reg        active_we;
    reg [19:0] active_addr;
    reg [31:0] active_wdata;
    reg [3:0]  active_wstrb;

    // CPU 请求保持到 ack 的过程中，禁止在 ack 后重复接受同一请求。
    reg cpu_req_blocked;

    // CPU 是字节地址，ExtRAM 是 32 位字地址。
    // 0xA000_0000 对应 ExtRAM 字地址 0，故减去基址后右移 2 位。
    wire [31:0] cpu_ext_offset = cpu_addr - CPU_EXT_BASE;
    wire [19:0] cpu_word_addr = cpu_ext_offset[21:2];

    wire [31:0] ext_ram_read_data = ext_ram_data;

    // ------------------------------------------------------------------ 物理 RAM 控制
    assign ext_ram_addr = active_addr;
    assign ext_ram_ce_n = (owner == OWNER_NONE) ? 1'b1 : 1'b0;
    assign ext_ram_oe_n = (owner != OWNER_NONE && !active_we) ? 1'b0 : 1'b1;
    assign ext_ram_we_n = (owner == OWNER_CPU && active_we) ? 1'b0 : 1'b1;

    // ExtRAM 字节使能低有效。
    // 读周期和空闲周期保持全字节使能/无效状态，写周期按 cpu_wstrb 取反。
    assign ext_ram_be_n = (owner == OWNER_CPU && active_we)
                        ? ~active_wstrb
                        : 4'b0000;

    // 只有写周期驱动双向数据总线，读周期必须高阻。
    assign ext_ram_data = (owner == OWNER_CPU && active_we)
                        ? active_wdata
                        : 32'bz;

    // ------------------------------------------------------------------ 仲裁和响应
    always @(posedge clk) begin
        if (rst) begin
            owner          <= OWNER_NONE;
            active_we      <= 1'b0;
            active_addr    <= 20'd0;
            active_wdata   <= 32'd0;
            active_wstrb   <= 4'd0;
            cpu_req_blocked <= 1'b0;
            cpu_rdata      <= 32'd0;
            cpu_ack        <= 1'b0;
            vga_rdata      <= 32'd0;
            vga_rvalid     <= 1'b0;
        end else begin
            // 应答和 VGA 返回信号都是单拍脉冲。
            cpu_ack    <= 1'b0;
            vga_rvalid <= 1'b0;

            // CPU 放弃请求后，允许下一次请求进入。
            if (!cpu_req)
                cpu_req_blocked <= 1'b0;

            if (owner != OWNER_NONE) begin
                // 当前事务在这一拍完成：读出 SRAM 数据，或结束写周期。
                if (owner == OWNER_VGA) begin
                    vga_rdata  <= ext_ram_read_data;
                    vga_rvalid <= 1'b1;
                end else begin
                    if (!active_we)
                        cpu_rdata <= ext_ram_read_data;
                    cpu_ack <= 1'b1;
                end

                // 完成当前事务的同时选择下一事务，避免额外空拍。
                // DVI 优先，保证它的单拍请求不会被 CPU 丢掉。
                if (vga_req) begin
                    owner       <= OWNER_VGA;
                    active_we   <= 1'b0;
                    active_addr <= vga_addr;
                end else if (cpu_req && !cpu_req_blocked) begin
                    owner        <= OWNER_CPU;
                    active_we    <= cpu_we;
                    active_addr  <= cpu_word_addr;
                    active_wdata <= cpu_wdata;
                    active_wstrb <= cpu_wstrb;
                    cpu_req_blocked <= 1'b1;
                end else begin
                    owner <= OWNER_NONE;
                end
            end else if (vga_req) begin
                // 空闲时优先接收 VGA 读请求。
                owner       <= OWNER_VGA;
                active_we   <= 1'b0;
                active_addr <= vga_addr;
            end else if (cpu_req && !cpu_req_blocked) begin
                owner        <= OWNER_CPU;
                active_we    <= cpu_we;
                active_addr  <= cpu_word_addr;
                active_wdata <= cpu_wdata;
                active_wstrb <= cpu_wstrb;
                cpu_req_blocked <= 1'b1;
            end else begin
                owner <= OWNER_NONE;
            end
        end
    end

endmodule

`default_nettype wire
