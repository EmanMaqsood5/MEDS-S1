
`include "axi4_params.svh"

module meds_s1_axi4_slave_wrapper #(
    parameter logic [`AXI_DATA_W-1:0] ID_VAL = {`AXI_DATA_W{1'b0}},
    parameter logic [`AXI_DATA_W-1:0] VERSION_VAL = {{(`AXI_DATA_W-32){1'b0}}, 32'h0001_0000} // v1.0
) (
    input logic clk,
    input logic rst_n,

    // Write address channel
    input logic [`AXI_ID_W-1:0] awid,
    input logic [`AXI_ADDR_W-1:0] awaddr,
    input logic [7:0] awlen,
    input logic [2:0] awsize,
    input logic [1:0] awburst,
    input logic awvalid,
    output logic awready,

    // Write data channel
    input logic [`AXI_DATA_W-1:0] wdata,
    input logic [`AXI_STRB_W-1:0] wstrb,
    input logic wlast,
    input logic wvalid,
    output logic wready,

    // Write response channel
    output logic [`AXI_ID_W-1:0] bid,
    output logic [1:0] bresp,
    output logic bvalid,
    input logic bready,

    // Read address channel
    input logic [`AXI_ID_W-1:0] arid,
    input logic [`AXI_ADDR_W-1:0] araddr,
    input logic [7:0] arlen,
    input logic [2:0] arsize,
    input logic [1:0] arburst,
    input logic arvalid,
    output logic arready,

    // Read data channel
    output logic [`AXI_ID_W-1:0] rid,
    output logic [`AXI_DATA_W-1:0] rdata,
    output logic [1:0] rresp,
    output logic rlast,
    output logic rvalid,
    input logic rready,

    // Hardware-facing boundary ( periph_subtree) 
    output logic HwStart, // 1-cycle pulse
    output logic HwAbort, // 1-cycle pulse
    output logic HwIrqEn, // level
    input logic HwBusy,
    input logic HwDone, // 1-cycle pulse expected
    input logic HwError, // 1-cycle pulse expected
    input logic [3:0] HwErrcode,
    input logic [`AXI_DATA_W-1:0] HwCapability,
    input logic [`AXI_DATA_W-1:0] HwPerfCycles,
    input logic [`AXI_DATA_W-1:0] HwPerfStalls,

    output logic Irq
);

    //  register offsets 
    localparam logic [`AXI_ADDR_W-1:0] OFF_ID = 'h000;
    localparam logic [`AXI_ADDR_W-1:0] OFF_VERSION = 'h004;
    localparam logic [`AXI_ADDR_W-1:0] OFF_CTRL = 'h008;
    localparam logic [`AXI_ADDR_W-1:0] OFF_STATUS = 'h00C;
    localparam logic [`AXI_ADDR_W-1:0] OFF_IRQ_STATUS = 'h010;
    localparam logic [`AXI_ADDR_W-1:0] OFF_CAPABILITY = 'h014;
    localparam logic [`AXI_ADDR_W-1:0] OFF_PERF_CYCLES = 'h018;
    localparam logic [`AXI_ADDR_W-1:0] OFF_PERF_STALLS = 'h01C;

    //  Wr*/Rd* boundary exposed by meds_s1_axi4_reg_protocol
    wire [`AXI_ADDR_W-1:0] WrAddr;
    wire [`AXI_DATA_W-1:0] WrData;
    wire [`AXI_STRB_W-1:0] WrStrb;
    wire WrEn;
    logic WrAddrValid;

    wire [`AXI_ADDR_W-1:0] RdAddr;
    logic [`AXI_DATA_W-1:0] RdData;
    logic RdAddrValid;

    meds_s1_axi4_reg_protocol reg_protocol_inst (
        .clk_i (clk),
        .rst_ni (rst_n),

        .awid (awid),
        .awaddr (awaddr),
        .awlen (awlen),
        .awsize (awsize),
        .awburst (awburst),
        .awvalid (awvalid),
        .awready (awready),

        .wdata (wdata),
        .wstrb (wstrb),
        .wlast (wlast),
        .wvalid (wvalid),
        .wready (wready),

        .bid (bid),
        .bresp (bresp),
        .bvalid (bvalid),
        .bready (bready),

        .arid (arid),
        .araddr (araddr),
        .arlen (arlen),
        .arsize (arsize),
        .arburst (arburst),
        .arvalid (arvalid),
        .arready (arready),

        .rid (rid),
        .rdata (rdata),
        .rresp (rresp),
        .rlast (rlast),
        .rvalid (rvalid),
        .rready (rready),

        .WrAddr (WrAddr),
        .WrData (WrData),
        .WrStrb (WrStrb),
        .WrEn (WrEn),
        .WrAddrValid (WrAddrValid),

        .RdAddr (RdAddr),
        .RdData (RdData),
        .RdAddrValid (RdAddrValid)
    );

    // ---- CTRL / IRQ_STATUS storage ----
    logic ctrl_irq_en_reg;
    logic [3:0] irq_status_reg; // bit0: done, bit1: error (room for more later)

    assign HwIrqEn = ctrl_irq_en_reg;
    assign Irq = ctrl_irq_en_reg && (|irq_status_reg);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_irq_en_reg <= 1'b0;
            irq_status_reg <= '0;
            HwStart <= 1'b0;
            HwAbort <= 1'b0;
        end else begin
            // default: pulses are one cycle only
            HwStart <= 1'b0;
            HwAbort <= 1'b0;

            if (WrEn && (WrAddr == OFF_CTRL)) begin
                if (WrStrb[0]) begin
                    HwStart <= WrData[0];
                    HwAbort <= WrData[1];
                    ctrl_irq_en_reg <= WrData[2];
                end
            end

            if (WrEn && (WrAddr == OFF_IRQ_STATUS)) begin
                // write-1-to-clear
                irq_status_reg <= irq_status_reg & ~WrData[3:0];
            end

            if (HwDone) irq_status_reg[0] <= 1'b1;
            if (HwError) irq_status_reg[1] <= 1'b1;
        end
    end

    // ---- read mux ----
    always_comb begin
        RdAddrValid = 1'b1;
        case (RdAddr)
            OFF_ID: RdData = ID_VAL;
            OFF_VERSION: RdData = VERSION_VAL;
            OFF_CTRL: RdData = {{(`AXI_DATA_W-3){1'b0}}, ctrl_irq_en_reg, 2'b00}; // start/abort self-clear, not readable back
            OFF_STATUS: RdData = {{(`AXI_DATA_W-8){1'b0}}, HwErrcode, 1'b0, HwError, HwDone, HwBusy};
            OFF_IRQ_STATUS: RdData = {{(`AXI_DATA_W-4){1'b0}}, irq_status_reg};
            OFF_CAPABILITY: RdData = HwCapability;
            OFF_PERF_CYCLES: RdData = HwPerfCycles;
            OFF_PERF_STALLS: RdData = HwPerfStalls;
            default: begin
                RdData = {`AXI_DATA_W{1'b0}};
                RdAddrValid = 1'b0; // -> DECERR, per meds_s1_axi4_b_ch / meds_s1_axi4_r_ch
            end
        endcase
    end

    // write-address range check -> WrAddrValid (DECERR outside the mapped block)
    always_comb begin
        case (WrAddr)
            OFF_CTRL, OFF_IRQ_STATUS: WrAddrValid = 1'b1;
            default: WrAddrValid = 1'b0;
        endcase
    end

endmodule
