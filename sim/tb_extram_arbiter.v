`timescale 1ns/1ps
`default_nettype none

module tb_extram_arbiter;
    reg clk;
    reg rst;

    reg  [31:0] cpu_addr;
    reg  [31:0] cpu_wdata;
    reg  [3:0]  cpu_wstrb;
    reg         cpu_req;
    reg         cpu_we;
    wire [31:0] cpu_rdata;
    wire        cpu_ack;

    reg  [19:0] vga_addr;
    reg         vga_req;
    wire [31:0] vga_rdata;
    wire        vga_rvalid;

    wire [19:0] ext_ram_addr;
    tri  [31:0] ext_ram_data;
    wire [3:0]  ext_ram_be_n;
    wire        ext_ram_ce_n;
    wire        ext_ram_oe_n;
    wire        ext_ram_we_n;

    reg [31:0] mem [0:255];
    integer i;

    extram_arbiter u_dut (
        .clk          (clk),
        .rst          (rst),
        .cpu_addr     (cpu_addr),
        .cpu_wdata    (cpu_wdata),
        .cpu_wstrb    (cpu_wstrb),
        .cpu_req      (cpu_req),
        .cpu_we       (cpu_we),
        .cpu_rdata    (cpu_rdata),
        .cpu_ack      (cpu_ack),
        .vga_addr     (vga_addr),
        .vga_req      (vga_req),
        .vga_rdata    (vga_rdata),
        .vga_rvalid   (vga_rvalid),
        .ext_ram_addr (ext_ram_addr),
        .ext_ram_data (ext_ram_data),
        .ext_ram_be_n (ext_ram_be_n),
        .ext_ram_ce_n (ext_ram_ce_n),
        .ext_ram_oe_n (ext_ram_oe_n),
        .ext_ram_we_n (ext_ram_we_n)
    );

    // 行为级 ExtRAM：读数据在仲裁器拉低 CE/OE 时组合输出，写入在时钟沿发生。
    assign ext_ram_data = (!ext_ram_ce_n && !ext_ram_oe_n && ext_ram_we_n)
                        ? mem[ext_ram_addr]
                        : 32'bz;

    always @(posedge clk) begin
        if (!ext_ram_ce_n && !ext_ram_we_n) begin
            for (i = 0; i < 4; i = i + 1)
                if (!ext_ram_be_n[i])
                    mem[ext_ram_addr][i*8 +: 8] <= ext_ram_data[i*8 +: 8];
        end
    end

    always #10 clk = ~clk;

    task cpu_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(negedge clk);
            cpu_addr  = addr;
            cpu_wdata = data;
            cpu_wstrb = strb;
            cpu_we    = 1'b1;
            cpu_req   = 1'b1;
            while (!cpu_ack) @(posedge clk);
            @(negedge clk);
            cpu_req   = 1'b0;
            cpu_we    = 1'b0;
        end
    endtask

    task cpu_read;
        input [31:0] addr;
        input [31:0] expected;
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_we   = 1'b0;
            cpu_req  = 1'b1;
            while (!cpu_ack) @(posedge clk);
            if (cpu_rdata !== expected) begin
                $display("FAIL CPU read: got %h expected %h", cpu_rdata, expected);
                $fatal;
            end
            @(negedge clk);
            cpu_req = 1'b0;
        end
    endtask

    initial begin
        clk       = 1'b0;
        rst       = 1'b1;
        cpu_addr  = 32'd0;
        cpu_wdata = 32'd0;
        cpu_wstrb = 4'd0;
        cpu_req   = 1'b0;
        cpu_we    = 1'b0;
        vga_addr  = 20'd0;
        vga_req   = 1'b0;
        for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;
        mem[5] = 32'hAABB_CCDD;

        repeat (2) @(posedge clk);
        rst = 1'b0;

        cpu_write(32'hA000_0000, 32'h1122_3344, 4'b1111);
        cpu_read (32'hA000_0000, 32'h1122_3344);

        // 同一拍同时提出 VGA 和 CPU 请求，检查 VGA 优先。
        @(negedge clk);
        vga_addr = 20'd5;
        vga_req  = 1'b1;
        cpu_addr = 32'hA000_0018;
        cpu_req  = 1'b1;
        cpu_we   = 1'b0;
        @(posedge clk);
        @(negedge clk);
        vga_req  = 1'b0;
        @(posedge clk);
        #1;
        if (!vga_rvalid || vga_rdata !== 32'hAABB_CCDD) begin
            $display("FAIL VGA priority/read: valid=%b data=%h", vga_rvalid, vga_rdata);
            $fatal;
        end
        while (!cpu_ack) @(posedge clk);
        @(negedge clk);
        cpu_req = 1'b0;

        // 检查部分字节写：只更新最低字节。
        cpu_write(32'hA000_0000, 32'h0000_00AA, 4'b0001);
        cpu_read (32'hA000_0000, 32'h1122_33AA);

        $display("PASS: ExtRAM arbiter CPU read/write, VGA priority and byte strobes");
        $finish;
    end
endmodule

`default_nettype wire
