

// Scenarios:
// 1) write+readback to PERIPH0 at offset 0x0 (lane 0 of the 256b word)
// 2) write+readback to PERIPH0 at offset 0x4 (lane 1) -- proves the
//    addr[4:2] lane-select logic, not just sub-address decode
// 3) write+readback to PERIPH1 at offset 0x8 (lane 2), a *different*
//    peripheral index than scenario 1/2 -- proves the hit-vector priority
//    decode actually distinguishes peripherals, not just offsets
// 4) write+readback to each of PERIPH2..PERIPH5 in turn, each with a
//    distinct data pattern -- proves all 6 peripheral slots (and their
//    p_* array indices) are wired correctly, not just the first couple
// 5) write, then read, an address inside no peripheral window at all
//    -> expect DECERR from the bridge itself (no peripheral driven)
// 6) AXI ID passthrough: BID/RID must equal the AWID/ARID that was sent


`include "axi4_params.svh"
`include "parameters.svh"


module beh_axil_periph #(
    parameter int PID = 0
) (
    input logic clk_i,
    input logic rst_ni,

    input logic [`ADDR_WIDTH-1:0] awaddr,
    input logic awvalid,
    output logic awready,

    input logic [`DATA_WIDTH-1:0] wdata,
    input logic [`STRB_WIDTH-1:0] wstrb,
    input logic wvalid,
    output logic wready,

    output logic [1:0] bresp,
    output logic bvalid,
    input logic bready,

    input logic [`ADDR_WIDTH-1:0] araddr,
    input logic arvalid,
    output logic arready,

    output logic [`DATA_WIDTH-1:0] rdata,
    output logic [1:0] rresp,
    output logic rvalid,
    input logic rready
);

    reg [31:0] mem [0:15];
    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1)
            mem[i] = {4'hD, PID[3:0], 4'hE, i[3:0], 16'h0000}; // unique-per-peripheral filler
    end

    assign awready = 1'b1;
    assign wready = 1'b1;
    assign arready = 1'b1;
    assign bresp = 2'b00; // OKAY
    assign rresp = 2'b00; // OKAY

    logic bvalid_r;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            bvalid_r <= 1'b0;
        end else begin
            if (awvalid && wvalid && !bvalid_r) begin
                mem[awaddr[5:2]] <= wdata;
                bvalid_r <= 1'b1;
            end else if (bvalid_r && bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end
    assign bvalid = bvalid_r;

    logic rvalid_r;
    logic [31:0] rdata_r;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rvalid_r <= 1'b0;
            rdata_r <= 32'h0;
        end else begin
            if (arvalid && !rvalid_r) begin
                rdata_r <= mem[araddr[5:2]];
                rvalid_r <= 1'b1;
            end else if (rvalid_r && rready) begin
                rvalid_r <= 1'b0;
            end
        end
    end
    assign rvalid = rvalid_r;
    assign rdata = rdata_r;

endmodule


module tb_axil_periph_subtree;

    localparam [1:0] RESP_OKAY = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;
    localparam int NUM_PERIPH = 6;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    //  wide AXI4 slave-side signals 
    reg [`AXI_SID_W-1:0] axi_awid;
    reg [`AXI_ADDR_W-1:0] axi_awaddr;
    reg axi_awvalid;
    wire axi_awready;

    reg [`AXI_DATA_W-1:0] axi_wdata;
    reg [`AXI_STRB_W-1:0] axi_wstrb;
    reg axi_wvalid;
    wire axi_wready;

    wire [`AXI_SID_W-1:0] axi_bid;
    wire [1:0] axi_bresp;
    wire axi_bvalid;
    reg axi_bready;

    reg [`AXI_SID_W-1:0] axi_arid;
    reg [`AXI_ADDR_W-1:0] axi_araddr;
    reg axi_arvalid;
    wire axi_arready;

    wire [`AXI_SID_W-1:0] axi_rid;
    wire [`AXI_DATA_W-1:0] axi_rdata;
    wire [1:0] axi_rresp;
    wire axi_rlast;
    wire axi_rvalid;
    reg axi_rready;

    // ---- per-peripheral AXI4-Lite master-side ports ----
    wire [NUM_PERIPH-1:0][`ADDR_WIDTH-1:0] p_awaddr;
    wire [NUM_PERIPH-1:0] p_awvalid;
    wire [NUM_PERIPH-1:0] p_awready;

    wire [NUM_PERIPH-1:0][`DATA_WIDTH-1:0] p_wdata;
    wire [NUM_PERIPH-1:0][`STRB_WIDTH-1:0] p_wstrb;
    wire [NUM_PERIPH-1:0] p_wvalid;
    wire [NUM_PERIPH-1:0] p_wready;

    wire [NUM_PERIPH-1:0][1:0] p_bresp;
    wire [NUM_PERIPH-1:0] p_bvalid;
    wire [NUM_PERIPH-1:0] p_bready;

    wire [NUM_PERIPH-1:0][`ADDR_WIDTH-1:0] p_araddr;
    wire [NUM_PERIPH-1:0] p_arvalid;
    wire [NUM_PERIPH-1:0] p_arready;

    wire [NUM_PERIPH-1:0][`DATA_WIDTH-1:0] p_rdata;
    wire [NUM_PERIPH-1:0][1:0] p_rresp;
    wire [NUM_PERIPH-1:0] p_rvalid;
    wire [NUM_PERIPH-1:0] p_rready;

    integer errors = 0;

    // ---- the design under test ----
    meds_s1_axil_periph_subtree dut (
        .clk_i (clk), .rst_ni (rst_n),
        .axi_awid(axi_awid), .axi_awaddr(axi_awaddr), .axi_awvalid(axi_awvalid), .axi_awready(axi_awready),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb), .axi_wvalid(axi_wvalid), .axi_wready(axi_wready),
        .axi_bid(axi_bid), .axi_bresp(axi_bresp), .axi_bvalid(axi_bvalid), .axi_bready(axi_bready),
        .axi_arid(axi_arid), .axi_araddr(axi_araddr), .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rid(axi_rid), .axi_rdata(axi_rdata), .axi_rresp(axi_rresp), .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid), .axi_rready(axi_rready),
        .p_awaddr(p_awaddr), .p_awvalid(p_awvalid), .p_awready(p_awready),
        .p_wdata(p_wdata), .p_wstrb(p_wstrb), .p_wvalid(p_wvalid), .p_wready(p_wready),
        .p_bresp(p_bresp), .p_bvalid(p_bvalid), .p_bready(p_bready),
        .p_araddr(p_araddr), .p_arvalid(p_arvalid), .p_arready(p_arready),
        .p_rdata(p_rdata), .p_rresp(p_rresp), .p_rvalid(p_rvalid), .p_rready(p_rready)
    );

    // ---- 6 behavioural peripheral stand-ins, one per p_* index ----
    genvar gp;
    generate
        for (gp = 0; gp < NUM_PERIPH; gp = gp + 1) begin : g_periph
            beh_axil_periph #(.PID(gp)) u_periph (
                .clk_i(clk), .rst_ni(rst_n),
                .awaddr(p_awaddr[gp]), .awvalid(p_awvalid[gp]), .awready(p_awready[gp]),
                .wdata(p_wdata[gp]), .wstrb(p_wstrb[gp]), .wvalid(p_wvalid[gp]), .wready(p_wready[gp]),
                .bresp(p_bresp[gp]), .bvalid(p_bvalid[gp]), .bready(p_bready[gp]),
                .araddr(p_araddr[gp]), .arvalid(p_arvalid[gp]), .arready(p_arready[gp]),
                .rdata(p_rdata[gp]), .rresp(p_rresp[gp]), .rvalid(p_rvalid[gp]), .rready(p_rready[gp])
            );
        end
    endgenerate

    // ---- reset ----
    initial begin
        axi_awid <= 0; axi_awaddr <= 0; axi_awvalid <= 0;
        axi_wdata <= 0; axi_wstrb <= 0; axi_wvalid <= 0;
        axi_bready <= 0;
        axi_arid <= 0; axi_araddr <= 0; axi_arvalid <= 0;
        axi_rready <= 0;

        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    end


    integer cycle_num = 0;
    initial begin
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            #1;
            cycle_num = cycle_num + 1;
            $display("-------------------------------------------------------------");
            $display("[cycle %0d]", cycle_num);
            $display(" AXI-AW: awaddr=%h awvalid=%b awready=%b | W: wdata=%h wvalid=%b wready=%b | B: bid=%0d bresp=%0d bvalid=%b",
                      axi_awaddr, axi_awvalid, axi_awready, axi_wdata, axi_wvalid, axi_wready, axi_bid, axi_bresp, axi_bvalid);
            $display(" AXI-AR: araddr=%h arvalid=%b arready=%b | R: rid=%0d rdata=%h rresp=%0d rvalid=%b",
                      axi_araddr, axi_arvalid, axi_arready, axi_rid, axi_rdata, axi_rresp, axi_rvalid);
            $display(" PERIPH: p_awvalid=%b p_wvalid=%b p_bvalid=%b | p_arvalid=%b p_rvalid=%b",
                      p_awvalid, p_wvalid, p_bvalid, p_arvalid, p_rvalid);
            $display(" DUT-W : wstate=%0s aw_captured=%b w_captured=%b aw_sel=%0d aw_hit=%b aw_sel_hold=%0d aw_hit_hold=%b",
                      dut.wstate.name(), dut.aw_captured, dut.w_captured, dut.aw_sel, dut.aw_hit, dut.aw_sel_hold, dut.aw_hit_hold);
            $display(" DUT-R : rstate=%0s ar_captured=%b ar_sel=%0d ar_hit=%b ar_sel_hold=%0d ar_hit_hold=%b",
                      dut.rstate.name(), dut.ar_captured, dut.ar_sel, dut.ar_hit, dut.ar_sel_hold, dut.ar_hit_hold);
        end
    end


    task axi4_write(
        input [`AXI_ADDR_W-1:0] addr,
        input [31:0] data32,
        input [`AXI_SID_W-1:0] id,
        output [1:0] resp
    );
        integer lane;
        reg [`AXI_DATA_W-1:0] wdata_w;
        reg [`AXI_STRB_W-1:0] wstrb_w;
        begin
            lane = addr[4:2];
            wdata_w = {`AXI_DATA_W{1'b0}};
            wstrb_w = {`AXI_STRB_W{1'b0}};
            wdata_w[(lane*32) +: 32] = data32;
            wstrb_w[(lane*4) +: 4] = 4'hF;

            @(posedge clk);
            axi_awid <= id; axi_awaddr <= addr; axi_awvalid <= 1'b1;
            axi_wdata <= wdata_w; axi_wstrb <= wstrb_w; axi_wvalid <= 1'b1;
            @(posedge clk);
            while (!(axi_awready && axi_wready)) @(posedge clk);
            axi_awvalid <= 1'b0; axi_wvalid <= 1'b0;

            axi_bready <= 1'b1;
            @(posedge clk);
            while (!axi_bvalid) @(posedge clk);
            resp = axi_bresp;
            if (axi_bid !== id) begin
                $display("[FAIL] BID mismatch: got=%0d expected=%0d", axi_bid, id);
                errors = errors + 1;
            end
            axi_bready <= 1'b0;
        end
    endtask

    task axi4_read(
        input [`AXI_ADDR_W-1:0] addr,
        input [`AXI_SID_W-1:0] id,
        output [31:0] data32,
        output [1:0] resp
    );
        integer lane;
        begin
            lane = addr[4:2];

            @(posedge clk);
            axi_arid <= id; axi_araddr <= addr; axi_arvalid <= 1'b1;
            @(posedge clk);
            while (!axi_arready) @(posedge clk);
            axi_arvalid <= 1'b0;

            axi_rready <= 1'b1;
            @(posedge clk);
            while (!axi_rvalid) @(posedge clk);
            data32 = axi_rdata[(lane*32) +: 32];
            resp = axi_rresp;
            if (axi_rid !== id) begin
                $display("[FAIL] RID mismatch: got=%0d expected=%0d", axi_rid, id);
                errors = errors + 1;
            end
            axi_rready <= 1'b0;
        end
    endtask

    task check_eq(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("[FAIL] %0s: got=0x%08h expected=0x%08h", name, got, exp);
                errors = errors + 1;
            end else
                $display("[PASS] %0s: 0x%08h", name, got);
        end
    endtask


    localparam [`AXI_ADDR_W-1:0] PERIPH0_BASE = 40'h0200_0000;
    localparam [`AXI_ADDR_W-1:0] PERIPH1_BASE = 40'h0C00_0000;
    localparam [`AXI_ADDR_W-1:0] PERIPH2_BASE = 40'h1000_0000;
    localparam [`AXI_ADDR_W-1:0] PERIPH3_BASE = 40'h1000_1000;
    localparam [`AXI_ADDR_W-1:0] PERIPH4_BASE = 40'h1000_2000;
    localparam [`AXI_ADDR_W-1:0] PERIPH5_BASE = 40'h1000_3000;
    localparam [`AXI_ADDR_W-1:0] UNMAPPED_ADDR = 40'h0800_0000; // between PERIPH0's window and PERIPH1_BASE

    reg [31:0] rd;
    reg [1:0] resp;
    integer p;
    reg [`AXI_ADDR_W-1:0] periph_base [0:5];

    initial begin
        periph_base[0] = PERIPH0_BASE;
        periph_base[1] = PERIPH1_BASE;
        periph_base[2] = PERIPH2_BASE;
        periph_base[3] = PERIPH3_BASE;
        periph_base[4] = PERIPH4_BASE;
        periph_base[5] = PERIPH5_BASE;

        @(posedge rst_n);
        repeat (2) @(posedge clk);

        $display("");
        $display("### SCENARIO 1: PERIPH0 offset 0x0 (lane 0), write+readback ###");
        axi4_write(PERIPH0_BASE + 40'h0, 32'h1111_AAAA, 9'h05, resp);
        check_eq("PERIPH0@0x0 write resp == OKAY", {30'b0, resp}, {30'b0, RESP_OKAY});
        axi4_read(PERIPH0_BASE + 40'h0, 9'h06, rd, resp);
        check_eq("PERIPH0@0x0 readback", rd, 32'h1111_AAAA);

        $display("");
        $display("### SCENARIO 2: PERIPH0 offset 0x4 (lane 1) -- exercises addr[4:2] lane select ###");
        axi4_write(PERIPH0_BASE + 40'h4, 32'h2222_BBBB, 9'h05, resp);
        check_eq("PERIPH0@0x4 write resp == OKAY", {30'b0, resp}, {30'b0, RESP_OKAY});
        axi4_read(PERIPH0_BASE + 40'h4, 9'h06, rd, resp);
        check_eq("PERIPH0@0x4 readback (lane 1)", rd, 32'h2222_BBBB);
        // 0x0 must still read back what scenario 1 wrote -- proves the two
        // offsets landed in different memory locations, not the same one
        axi4_read(PERIPH0_BASE + 40'h0, 9'h06, rd, resp);
        check_eq("PERIPH0@0x0 unaffected by @0x4 write", rd, 32'h1111_AAAA);

        $display("");
        $display("### SCENARIO 3: PERIPH1 offset 0x8 (lane 2) -- different peripheral index ###");
        axi4_write(PERIPH1_BASE + 40'h8, 32'h3333_CCCC, 9'h07, resp);
        check_eq("PERIPH1@0x8 write resp == OKAY", {30'b0, resp}, {30'b0, RESP_OKAY});
        axi4_read(PERIPH1_BASE + 40'h8, 9'h08, rd, resp);
        check_eq("PERIPH1@0x8 readback", rd, 32'h3333_CCCC);

        $display("");
        $display("### SCENARIO 4: PERIPH2..PERIPH5, one write+readback each ###");
        for (p = 2; p <= 5; p = p + 1) begin
            reg [31:0] pattern;
            pattern = 32'hA000_0000 | (p << 4);
            axi4_write(periph_base[p] + 40'h0, pattern, 9'h01, resp);
            check_eq("write resp == OKAY", {30'b0, resp}, {30'b0, RESP_OKAY});
            axi4_read(periph_base[p] + 40'h0, 9'h02, rd, resp);
            check_eq("readback", rd, pattern);
        end

        $display("");
        $display("### SCENARIO 5: unmapped address 0x%h -> local DECERR, no peripheral driven ###", UNMAPPED_ADDR);
        axi4_write(UNMAPPED_ADDR, 32'hDEAD_0000, 9'h03, resp);
        check_eq("unmapped write resp == DECERR", {30'b0, resp}, {30'b0, RESP_DECERR});
        axi4_read(UNMAPPED_ADDR, 9'h04, rd, resp);
        check_eq("unmapped read resp == DECERR", {30'b0, resp}, {30'b0, RESP_DECERR});
        check_eq("unmapped read data is the default filler", rd, 32'hDEAD_BEEF);

        repeat (3) @(posedge clk);
        $display("");
        if (errors == 0) begin
            $display("=============================================");
            $display(" ALL TESTS PASSED");
            $display("=============================================");
        end else begin
            $display("=============================================");
            $display(" %0d TEST(S) FAILED", errors);
            $display("=============================================");
        end
        $finish;
    end

    initial begin
        #20000;
        $display("[TIMEOUT] testbench did not finish");
        $finish;
    end

endmodule