
`include "axi4_params.svh"

module meds_s1_axi4_reg_protocol #(
    parameter int ID_W = `AXI_ID_W // widened to AXI_SID_W when instantiated behind meds_s1_axi4_crossbar
) (
    input logic clk_i,
    input logic rst_ni,

    // Write address channel
    input logic [ID_W-1:0] awid,
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
    output logic [ID_W-1:0] bid,
    output logic [1:0] bresp,
    output logic bvalid,
    input logic bready,

    // Read address channel
    input logic [ID_W-1:0] arid,
    input logic [`AXI_ADDR_W-1:0] araddr,
    input logic [7:0] arlen,
    input logic [2:0] arsize,
    input logic [1:0] arburst,
    input logic arvalid,
    output logic arready,

    // Read data channel
    output logic [ID_W-1:0] rid,
    output logic [`AXI_DATA_W-1:0] rdata,
    output logic [1:0] rresp,
    output logic rlast,
    output logic rvalid,
    input logic rready,

    // ---------------- Generic register-content boundary ----------------
    // One WrEn pulse per write beat, one RdAddr lookup per read beat.
    output logic [`AXI_ADDR_W-1:0] WrAddr,
    output logic [`AXI_DATA_W-1:0] WrData,
    output logic [`AXI_STRB_W-1:0] WrStrb,
    output logic WrEn,
    input logic WrAddrValid,

    output logic [`AXI_ADDR_W-1:0] RdAddr,
    input logic [`AXI_DATA_W-1:0] RdData,
    input logic RdAddrValid
);

    // ---- aw / w buffers <-> b commit logic ----
    wire [ID_W-1:0] aw_captured_id;
    wire [`AXI_ADDR_W-1:0] aw_captured_addr;
    wire [7:0] aw_captured_len;
    wire [2:0] aw_captured_size;
    wire [1:0] aw_captured_burst;
    wire aw_captured;
    wire aw_consume;

    wire [`AXI_DATA_W-1:0] w_captured_data;
    wire [`AXI_STRB_W-1:0] w_captured_strb;
    wire w_captured_last;
    wire w_captured;
    wire w_consume;

    // ---- ar buffer <-> r response logic ----
    wire [ID_W-1:0] ar_captured_id;
    wire [`AXI_ADDR_W-1:0] ar_captured_addr;
    wire [7:0] ar_captured_len;
    wire [2:0] ar_captured_size;
    wire [1:0] ar_captured_burst;
    wire ar_captured;
    wire ar_consume;

    meds_s1_axi4_aw_ch #(
        .ID_W (ID_W)
    ) aw_ch_inst (
        .clk_i (clk_i),
        .rst_ni (rst_ni),

        .awid (awid),
        .awaddr (awaddr),
        .awlen (awlen),
        .awsize (awsize),
        .awburst (awburst),
        .awvalid (awvalid),
        .awready (awready),

        .AwCapturedId (aw_captured_id),
        .AwCapturedAddr (aw_captured_addr),
        .AwCapturedLen (aw_captured_len),
        .AwCapturedSize (aw_captured_size),
        .AwCapturedBurst (aw_captured_burst),
        .AwCaptured (aw_captured),
        .AwConsume (aw_consume)
    );

    meds_s1_axi4_w_ch w_ch_inst (
        .clk_i (clk_i),
        .rst_ni (rst_ni),

        .wdata (wdata),
        .wstrb (wstrb),
        .wlast (wlast),
        .wvalid (wvalid),
        .wready (wready),

        .WCapturedData (w_captured_data),
        .WCapturedStrb (w_captured_strb),
        .WCapturedLast (w_captured_last),
        .WCaptured (w_captured),
        .WConsume (w_consume)
    );

    meds_s1_axi4_b_ch #(
        .ID_W (ID_W)
    ) b_ch_inst (
        .clk_i (clk_i),
        .rst_ni (rst_ni),

        .AwCapturedId (aw_captured_id),
        .AwCapturedAddr (aw_captured_addr),
        .AwCapturedLen (aw_captured_len),
        .AwCapturedSize (aw_captured_size),
        .AwCapturedBurst (aw_captured_burst),
        .AwCaptured (aw_captured),
        .AwConsume (aw_consume),

        .WCapturedData (w_captured_data),
        .WCapturedStrb (w_captured_strb),
        .WCapturedLast (w_captured_last),
        .WCaptured (w_captured),
        .WConsume (w_consume),

        .bid (bid),
        .bresp (bresp),
        .bvalid (bvalid),
        .bready (bready),

        .WrAddr (WrAddr),
        .WrData (WrData),
        .WrStrb (WrStrb),
        .WrEn (WrEn),
        .WrAddrValid (WrAddrValid)
    );

    meds_s1_axi4_ar_ch #(
        .ID_W (ID_W)
    ) ar_ch_inst (
        .clk_i (clk_i),
        .rst_ni (rst_ni),

        .arid (arid),
        .araddr (araddr),
        .arlen (arlen),
        .arsize (arsize),
        .arburst (arburst),
        .arvalid (arvalid),
        .arready (arready),

        .ArCapturedId (ar_captured_id),
        .ArCapturedAddr (ar_captured_addr),
        .ArCapturedLen (ar_captured_len),
        .ArCapturedSize (ar_captured_size),
        .ArCapturedBurst (ar_captured_burst),
        .ArCaptured (ar_captured),
        .ArConsume (ar_consume)
    );

    meds_s1_axi4_r_ch #(
        .ID_W (ID_W)
    ) r_ch_inst (
        .clk_i (clk_i),
        .rst_ni (rst_ni),

        .ArCapturedId (ar_captured_id),
        .ArCapturedAddr (ar_captured_addr),
        .ArCapturedLen (ar_captured_len),
        .ArCapturedSize (ar_captured_size),
        .ArCapturedBurst (ar_captured_burst),
        .ArCaptured (ar_captured),
        .ArConsume (ar_consume),

        .rid (rid),
        .rdata (rdata),
        .rresp (rresp),
        .rlast (rlast),
        .rvalid (rvalid),
        .rready (rready),

        .RdAddr (RdAddr),
        .RdData (RdData),
        .RdAddrValid (RdAddrValid)
    );

endmodule
