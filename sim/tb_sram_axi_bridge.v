`timescale 1ns/1ps
`default_nettype none

module tb_sram_axi_bridge;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg aresetn = 1'b0;

    reg        inst_req, inst_wr;
    reg [1:0]  inst_size;
    reg [31:0] inst_addr, inst_wdata;
    reg [3:0]  inst_wstrb;
    wire       inst_addr_ok, inst_data_ok;
    wire [31:0] inst_rdata;

    reg        data_req, data_wr;
    reg [1:0]  data_size;
    reg [31:0] data_addr, data_wdata;
    reg [3:0]  data_wstrb;
    wire       data_addr_ok, data_data_ok;
    wire [31:0] data_rdata;

    wire [3:0] arid, awid, wid;
    wire [31:0] araddr, awaddr, wdata;
    wire [7:0] arlen, awlen;
    wire [2:0] arsize, awsize, arprot, awprot;
    wire [1:0] arburst, awburst, arlock, awlock;
    wire [3:0] arcache, awcache, wstrb;
    wire arvalid, arready, rready, awvalid, awready, wlast, wvalid, wready;
    wire [3:0] rid, bid;
    wire [31:0] rdata;
    wire [1:0] rresp, bresp;
    wire rlast, rvalid, bvalid, bready;

    reg arready_r = 0, awready_r = 0, wready_r = 0;
    reg [3:0] rid_r = 0, bid_r = 0;
    reg [31:0] rdata_r = 0;
    reg [1:0] rresp_r = 0, bresp_r = 0;
    reg rlast_r = 0, rvalid_r = 0, bvalid_r = 0;
    reg aw_seen = 0, w_seen = 0;

    assign arready = arready_r;
    assign awready = awready_r;
    assign wready  = wready_r;
    assign rid     = rid_r;
    assign rdata   = rdata_r;
    assign rresp   = rresp_r;
    assign rlast   = rlast_r;
    assign rvalid  = rvalid_r;
    assign bid     = bid_r;
    assign bresp   = bresp_r;
    assign bvalid  = bvalid_r;

    sram_axi_bridge dut (
        .aclk(clk), .aresetn(aresetn),
        .inst_req(inst_req), .inst_wr(inst_wr), .inst_size(inst_size),
        .inst_addr(inst_addr), .inst_wstrb(inst_wstrb), .inst_wdata(inst_wdata),
        .inst_addr_ok(inst_addr_ok), .inst_data_ok(inst_data_ok), .inst_rdata(inst_rdata),
        .data_req(data_req), .data_wr(data_wr), .data_size(data_size),
        .data_addr(data_addr), .data_wstrb(data_wstrb), .data_wdata(data_wdata),
        .data_addr_ok(data_addr_ok), .data_data_ok(data_data_ok), .data_rdata(data_rdata),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache),
        .m_axi_arprot(arprot), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache),
        .m_axi_awprot(awprot), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wid(wid), .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    task automatic fail(input [255:0] msg);
        begin $display("FAIL: %s", msg); $fatal(1); end
    endtask

    task automatic wait_data(input integer which);
        integer n;
        begin
            for (n = 0; n < 40; n = n + 1) begin
                @(posedge clk);
                if ((which == 0 && inst_data_ok) || (which == 1 && data_data_ok)) disable wait_data;
            end
            fail("timeout waiting for data_ok");
        end
    endtask

    always @(posedge clk) begin
        // One-cycle delayed read response after an accepted AR.
        arready_r <= 1'b0;
        if (arvalid) begin
            if (arlen !== 0 || arburst !== 2'b01 || arid !== 0)
                fail("invalid AXI read attributes");
            arready_r <= 1'b1;
            if (arready_r) begin
                rdata_r  <= araddr ^ 32'h1357_9BDF;
                rid_r    <= arid;
                rlast_r  <= 1'b1;
                rvalid_r <= 1'b1;
            end
        end
        if (rvalid_r && rready)
            rvalid_r <= 1'b0;

        // Backpressure write channels independently: accept W first, then AW.
        // This catches bridges that incorrectly require the two channels to
        // handshake in the same cycle.
        awready_r <= awvalid && w_seen;
        wready_r  <= wvalid && !w_seen;
        if (awvalid && awready && (awid !== 1 || awlen !== 0 || awburst !== 2'b01))
            fail("invalid AXI write attributes");
        if (wvalid && wready && !wlast)
            fail("write must be one beat");
        if (awvalid && awready)
            aw_seen <= 1'b1;
        if (wvalid && wready)
            w_seen <= 1'b1;
        if ((aw_seen || (awvalid && awready)) && (w_seen || (wvalid && wready)))
            bvalid_r <= 1'b1;
        if (bvalid_r && bready) begin
            bvalid_r <= 1'b0;
            aw_seen <= 1'b0;
            w_seen <= 1'b0;
        end
    end

    initial begin
        inst_req=0; inst_wr=0; inst_size=2; inst_addr=0; inst_wdata=0; inst_wstrb=0;
        data_req=0; data_wr=0; data_size=2; data_addr=0; data_wdata=0; data_wstrb=0;
        repeat (3) @(posedge clk);
        aresetn = 1'b1;
        repeat (2) @(posedge clk);

        // Data has priority when both requests arrive together.
        @(negedge clk);
        inst_addr = 32'h1000;
        inst_req  = 1'b1;
        data_addr = 32'h2000;
        data_req  = 1'b1;
        @(posedge clk); #1;
        $display("t=%0t data_addr_ok=%b inst_addr_ok=%b state=%h", $time, data_addr_ok, inst_addr_ok, dut.state);
        if (!data_addr_ok || inst_addr_ok) fail("data request did not win arbitration");
        data_req = 1'b0;
        inst_req = 1'b0;
        wait_data(1);
        if (data_rdata !== (32'h2000 ^ 32'h1357_9BDF)) fail("bad data read result");

        // Instruction read after the data transaction.
        repeat (2) @(posedge clk);
        @(negedge clk);
        inst_req = 1'b1;
        @(posedge clk); #1;
        if (!inst_addr_ok) fail("instruction request not accepted");
        inst_req = 1'b0;
        wait_data(0);
        if (inst_rdata !== (32'h1000 ^ 32'h1357_9BDF)) fail("bad instruction result");

        // Partial write: AW and W are separate handshakes, B completes it.
        repeat (2) @(posedge clk);
        @(negedge clk);
        data_addr  = 32'h3000;
        data_wdata = 32'hA5A5_5A5A;
        data_wstrb = 4'b0101;
        data_wr    = 1'b1;
        data_req   = 1'b1;
        @(posedge clk); #1;
        if (!data_addr_ok) fail("write request not accepted");
        data_req = 1'b0;
        wait_data(1);

        $display("PASS: sram_axi_bridge arbitration, read, write and AXI attributes");
        $finish;
    end
endmodule

`default_nettype wire
