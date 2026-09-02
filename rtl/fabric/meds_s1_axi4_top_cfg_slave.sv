
`include "meds_s1_axi4_crossbar/axi4_params.svh"
`include "axi4/axi4_params.svh"

module meds_s1_axi4_top_cfg_slave #(
    parameter int SLAVE_IDX = 3, // peripheral MMIO window, per meds_s1_axi4_addr_decode.sv
    parameter logic [`AXI_DATA_W-1:0] ID_VAL = {`AXI_DATA_W{1'b0}},
    parameter logic [`AXI_DATA_W-1:0] VERSION_VAL = {{(`AXI_DATA_W-32){1'b0}}, 32'h0001_0000}
) (
    input logic clk,
    input logic rst_n,

    // Crossbar slave-port slice (index SLAVE_IDX)
    // Connect these directly to meds_s1_axi4_crossbar's s_*[SLAVE_IDX] bits at the
    // top level that instantiates both the crossbar and this module, e.g.:
    //
    // meds_s1_axi4_top_cfg_slave cfg_slave (
    //.clk (clk),
    //.rst_n (rst_n),
    //.s_awid (s_awid[3]),
    //.s_awaddr (s_awaddr[3]),
    //...
    //.s_rready (s_rready[3])
    //);
    //
    input logic [`AXI_ID_W-1:0] s_awid,
    input logic [`AXI_ADDR_W-1:0] s_awaddr,
    input logic [7:0] s_awlen,
    input logic [2:0] s_awsize,
    input logic [1:0] s_awburst,
    input logic s_awvalid,
    output logic s_awready,

    input logic [`AXI_DATA_W-1:0] s_wdata,
    input logic [`AXI_STRB_W-1:0] s_wstrb,
    input logic s_wlast,
    input logic s_wvalid,
    output logic s_wready,

    output logic [`AXI_ID_W-1:0] s_bid,
    output logic [1:0] s_bresp,
    output logic s_bvalid,
    input logic s_bready,

    input logic [`AXI_ID_W-1:0] s_arid,
    input logic [`AXI_ADDR_W-1:0] s_araddr,
    input logic [7:0] s_arlen,
    input logic [2:0] s_arsize,
    input logic [1:0] s_arburst,
    input logic s_arvalid,
    output logic s_arready,

    output logic [`AXI_ID_W-1:0] s_rid,
    output logic [`AXI_DATA_W-1:0] s_rdata,
    output logic [1:0] s_rresp,
    output logic s_rlast,
    output logic s_rvalid,
    input logic s_rready,

    // Peripheral hardware-facing boundary 
 
    output logic HwStart, // 1-cycle pulse
    output logic HwAbort, // 1-cycle pulse
    output logic HwIrqEn, // level
    input logic HwBusy, // tie 0 for a stub
    input logic HwDone, // tie 0 for a stub
    input logic HwError, // tie 0 for a stub
    input logic [3:0] HwErrcode, // tie 0 for a stub
    input logic [`AXI_DATA_W-1:0] HwCapability, // tie 0 for a stub
    input logic [`AXI_DATA_W-1:0] HwPerfCycles, // tie 0 for a stub
    input logic [`AXI_DATA_W-1:0] HwPerfStalls, // tie 0 for a stub

    output logic Irq
);

    //  backbone-address -> window-relative offset 
    
    localparam logic [`AXI_ADDR_W-1:0] CFG_SLAVE_BASE = 40'h2000_0000;

    logic [`AXI_ADDR_W-1:0] awaddr_rel, araddr_rel;
    assign awaddr_rel = s_awaddr - CFG_SLAVE_BASE;
    assign araddr_rel = s_araddr - CFG_SLAVE_BASE;

    meds_s1_axi4_slave_wrapper #(
        .ID_VAL (ID_VAL),
        .VERSION_VAL (VERSION_VAL)
    ) u_cfg_wrapper (
        .clk (clk),
        .rst_n (rst_n),

        .awid (s_awid),
        .awaddr (awaddr_rel),
        .awlen (s_awlen),
        .awsize (s_awsize),
        .awburst (s_awburst),
        .awvalid (s_awvalid),
        .awready (s_awready),

        .wdata (s_wdata),
        .wstrb (s_wstrb),
        .wlast (s_wlast),
        .wvalid (s_wvalid),
        .wready (s_wready),

        .bid (s_bid),
        .bresp (s_bresp),
        .bvalid (s_bvalid),
        .bready (s_bready),

        .arid (s_arid),
        .araddr (araddr_rel),
        .arlen (s_arlen),
        .arsize (s_arsize),
        .arburst (s_arburst),
        .arvalid (s_arvalid),
        .arready (s_arready),

        .rid (s_rid),
        .rdata (s_rdata),
        .rresp (s_rresp),
        .rlast (s_rlast),
        .rvalid (s_rvalid),
        .rready (s_rready),

        .HwStart (HwStart),
        .HwAbort (HwAbort),
        .HwIrqEn (HwIrqEn),
        .HwBusy (HwBusy),
        .HwDone (HwDone),
        .HwError (HwError),
        .HwErrcode (HwErrcode),
        .HwCapability (HwCapability),
        .HwPerfCycles (HwPerfCycles),
        .HwPerfStalls (HwPerfStalls),

        .Irq (Irq)
    );

endmodule
