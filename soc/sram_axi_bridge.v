`default_nettype none

// -----------------------------------------------------------------------------
// sram_axi_bridge
//
// Convert the two class-SRAM request ports used by the LA32R CPU (instruction
// and data) into one 32-bit AXI master port.  This is the 2x1 bridge described
// by the AXI interface design document:
//
//   * data requests have priority over instruction fetches;
//   * one class-SRAM transaction maps to exactly one AXI transaction;
//   * only one AXI transaction is outstanding at a time;
//   * reads are held off until a previous write response has arrived;
//   * AXI valid/data/address outputs are registered and held until ready;
//   * ARID is 0 for instruction/data reads and AWID/WID is 1 for writes;
//   * all transactions are single-beat, 32-bit maximum (ARLEN/AWLEN = 0).
//
// The bridge intentionally exposes the class-SRAM protocol instead of guessing
// a vendor CPU wrapper.  The CPU-specific wrapper can connect its real ports to
// these signals without changing the AXI state machine.
// -----------------------------------------------------------------------------
module sram_axi_bridge #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                    aclk,
    input  wire                    aresetn,

    // Instruction class-SRAM master -> bridge slave (read-only in practice).
    input  wire                    inst_req,
    input  wire                    inst_wr,
    input  wire [1:0]              inst_size,
    input  wire [ADDR_WIDTH-1:0]   inst_addr,
    input  wire [STRB_WIDTH-1:0]   inst_wstrb,
    input  wire [DATA_WIDTH-1:0]   inst_wdata,
    output reg                     inst_addr_ok,
    output reg                     inst_data_ok,
    output reg  [DATA_WIDTH-1:0]   inst_rdata,

    // Data class-SRAM master -> bridge slave.
    input  wire                    data_req,
    input  wire                    data_wr,
    input  wire [1:0]              data_size,
    input  wire [ADDR_WIDTH-1:0]   data_addr,
    input  wire [STRB_WIDTH-1:0]   data_wstrb,
    input  wire [DATA_WIDTH-1:0]   data_wdata,
    output reg                     data_addr_ok,
    output reg                     data_data_ok,
    output reg  [DATA_WIDTH-1:0]   data_rdata,

    // AXI read-address channel.
    output reg  [3:0]              m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]   m_axi_araddr,
    output wire [7:0]              m_axi_arlen,
    output wire [2:0]              m_axi_arsize,
    output wire [1:0]              m_axi_arburst,
    output wire [1:0]              m_axi_arlock,
    output wire [3:0]              m_axi_arcache,
    output wire [2:0]              m_axi_arprot,
    output reg                     m_axi_arvalid,
    input  wire                    m_axi_arready,

    // AXI read-data channel.
    input  wire [3:0]              m_axi_rid,
    input  wire [DATA_WIDTH-1:0]   m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output reg                     m_axi_rready,

    // AXI write-address channel.
    output reg  [3:0]              m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output wire [7:0]              m_axi_awlen,
    output wire [2:0]              m_axi_awsize,
    output wire [1:0]              m_axi_awburst,
    output wire [1:0]              m_axi_awlock,
    output wire [3:0]              m_axi_awcache,
    output wire [2:0]              m_axi_awprot,
    output reg                     m_axi_awvalid,
    input  wire                    m_axi_awready,

    // AXI write-data channel.
    output reg  [3:0]              m_axi_wid,
    output reg  [DATA_WIDTH-1:0]   m_axi_wdata,
    output reg  [STRB_WIDTH-1:0]   m_axi_wstrb,
    output wire                    m_axi_wlast,
    output reg                     m_axi_wvalid,
    input  wire                    m_axi_wready,

    // AXI write-response channel.
    input  wire [3:0]              m_axi_bid,
    input  wire [1:0]              m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output reg                     m_axi_bready
);

    localparam [3:0] READ_ID  = 4'd0;
    localparam [3:0] WRITE_ID = 4'd1;

    localparam [3:0] ST_IDLE   = 4'd0;
    localparam [3:0] ST_AR     = 4'd1;
    localparam [3:0] ST_R      = 4'd2;
    localparam [3:0] ST_AW_W   = 4'd3;
    localparam [3:0] ST_B      = 4'd4;

    reg [3:0] state;
    reg       active_is_data;
    reg       active_is_write;
    reg [1:0] active_size;
    reg [ADDR_WIDTH-1:0] active_addr;
    reg [STRB_WIDTH-1:0] active_wstrb;
    reg [DATA_WIDTH-1:0] active_wdata;
    reg       aw_done;
    reg       w_done;
    reg       inst_blocked;
    reg       data_blocked;

    wire ar_fire = m_axi_arvalid && m_axi_arready;
    wire r_fire  = m_axi_rvalid  && m_axi_rready;
    wire aw_fire = m_axi_awvalid && m_axi_awready;
    wire w_fire  = m_axi_wvalid  && m_axi_wready;
    wire b_fire  = m_axi_bvalid  && m_axi_bready;

    // Fixed attributes required by the supplied AXI design specification.
    assign m_axi_arlen   = 8'd0;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_arsize  = {1'b0, active_size};
    assign m_axi_awsize  = {1'b0, active_size};
    assign m_axi_arburst = 2'b01; // INCR
    assign m_axi_awburst = 2'b01; // INCR
    assign m_axi_arlock  = 2'b00;
    assign m_axi_awlock  = 2'b00;
    assign m_axi_arcache = 4'b0000;
    assign m_axi_awcache = 4'b0000;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_wlast   = 1'b1;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state          <= ST_IDLE;
            active_is_data <= 1'b0;
            active_is_write<= 1'b0;
            active_size    <= 2'd2;
            active_addr    <= {ADDR_WIDTH{1'b0}};
            active_wstrb   <= {STRB_WIDTH{1'b0}};
            active_wdata   <= {DATA_WIDTH{1'b0}};
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            inst_blocked   <= 1'b0;
            data_blocked   <= 1'b0;

            inst_addr_ok   <= 1'b0;
            inst_data_ok   <= 1'b0;
            inst_rdata     <= {DATA_WIDTH{1'b0}};
            data_addr_ok   <= 1'b0;
            data_data_ok   <= 1'b0;
            data_rdata     <= {DATA_WIDTH{1'b0}};

            m_axi_arid    <= READ_ID;
            m_axi_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b0;
            m_axi_awid    <= WRITE_ID;
            m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axi_awvalid <= 1'b0;
            m_axi_wid     <= WRITE_ID;
            m_axi_wdata   <= {DATA_WIDTH{1'b0}};
            m_axi_wstrb   <= {STRB_WIDTH{1'b0}};
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
        end else begin
            // All completion/acceptance indications are one-cycle pulses.
            inst_addr_ok <= 1'b0;
            inst_data_ok <= 1'b0;
            data_addr_ok <= 1'b0;
            data_data_ok <= 1'b0;

            // A class-SRAM master is allowed to keep req asserted until the
            // address handshake.  Block re-acceptance until req is released.
            if (!inst_req)
                inst_blocked <= 1'b0;
            if (!data_req)
                data_blocked <= 1'b0;

            case (state)
                ST_IDLE: begin
                    // Data has priority over instruction fetches, as required
                    // by the AXI bridge design specification.
                    if (data_req && !data_blocked) begin
                        active_is_data  <= 1'b1;
                        active_is_write <= data_wr;
                        active_size     <= data_size;
                        active_addr     <= data_addr;
                        active_wstrb    <= data_wstrb;
                        active_wdata    <= data_wdata;
                        data_addr_ok    <= 1'b1;
                        data_blocked    <= 1'b1;

                        if (data_wr) begin
                            m_axi_awid    <= WRITE_ID;
                            m_axi_awaddr  <= data_addr;
                            m_axi_awvalid <= 1'b1;
                            m_axi_wid     <= WRITE_ID;
                            m_axi_wdata   <= data_wdata;
                            m_axi_wstrb   <= data_wstrb;
                            m_axi_wvalid  <= 1'b1;
                            aw_done       <= 1'b0;
                            w_done        <= 1'b0;
                            state         <= ST_AW_W;
                        end else begin
                            m_axi_arid    <= READ_ID;
                            m_axi_araddr  <= data_addr;
                            m_axi_arvalid <= 1'b1;
                            state         <= ST_AR;
                        end
                    end else if (inst_req && !inst_blocked) begin
                        active_is_data  <= 1'b0;
                        active_is_write <= inst_wr;
                        active_size     <= inst_size;
                        active_addr     <= inst_addr;
                        active_wstrb    <= inst_wstrb;
                        active_wdata    <= inst_wdata;
                        inst_addr_ok    <= 1'b1;
                        inst_blocked    <= 1'b1;

                        // Instruction fetches are reads in the LA32R design.
                        // Keep inst_wr legal for diagnostics, but preserve the
                        // same AXI mapping if a testbench drives it high.
                        if (inst_wr) begin
                            m_axi_awid    <= WRITE_ID;
                            m_axi_awaddr  <= inst_addr;
                            m_axi_awvalid <= 1'b1;
                            m_axi_wid     <= WRITE_ID;
                            m_axi_wdata   <= inst_wdata;
                            m_axi_wstrb   <= inst_wstrb;
                            m_axi_wvalid  <= 1'b1;
                            aw_done       <= 1'b0;
                            w_done        <= 1'b0;
                            state         <= ST_AW_W;
                        end else begin
                            m_axi_arid    <= READ_ID;
                            m_axi_araddr  <= inst_addr;
                            m_axi_arvalid <= 1'b1;
                            state         <= ST_AR;
                        end
                    end
                end

                ST_AR: begin
                    if (ar_fire) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        state         <= ST_R;
                    end
                end

                ST_R: begin
                    if (r_fire) begin
                        if (active_is_data) begin
                            data_rdata   <= m_axi_rdata;
                            data_data_ok <= 1'b1;
                        end else begin
                            inst_rdata   <= m_axi_rdata;
                            inst_data_ok <= 1'b1;
                        end
                        m_axi_rready <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end

                ST_AW_W: begin
                    // Each channel is independent.  Both payloads remain
                    // stable while their respective valid is waiting.
                    if (aw_fire) begin
                        m_axi_awvalid <= 1'b0;
                        aw_done       <= 1'b1;
                    end
                    if (w_fire) begin
                        m_axi_wvalid <= 1'b0;
                        w_done       <= 1'b1;
                    end

                    // Include handshakes occurring on this edge when deciding
                    // whether both write request channels have completed.
                    if ((aw_done || aw_fire) && (w_done || w_fire)) begin
                        m_axi_bready <= 1'b1;
                        state        <= ST_B;
                    end
                end

                ST_B: begin
                    if (b_fire) begin
                        if (active_is_data)
                            data_data_ok <= 1'b1;
                        else
                            inst_data_ok <= 1'b1;
                        m_axi_bready <= 1'b0;
                        state        <= ST_IDLE;
                    end
                end

                default: begin
                    state         <= ST_IDLE;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
