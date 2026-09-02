
`include "axi4_params.svh"

module tb_axi4_simple;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic [`AXI_ID_W-1:0] awid, arid;
    logic [`AXI_ADDR_W-1:0] awaddr, araddr;
    logic [7:0] awlen, arlen;
    logic [2:0] awsize, arsize;
    logic [1:0] awburst, arburst;
    logic awvalid, arvalid;
    logic awready, arready;

    logic [`AXI_DATA_W-1:0] wdata;
    logic [`AXI_STRB_W-1:0] wstrb;
    logic wlast, wvalid, wready;

    logic [`AXI_ID_W-1:0] bid;
    logic [1:0] bresp;
    logic bvalid, bready;

    logic [`AXI_ID_W-1:0] rid;
    logic [`AXI_DATA_W-1:0] rdata;
    logic [1:0] rresp;
    logic rlast, rvalid, rready;

    logic HwStart, HwAbort, HwIrqEn, Irq;
    logic HwBusy = 1'b0, HwDone = 1'b0, HwError = 1'b0;
    logic [3:0] HwErrcode = 4'h0;
    logic [`AXI_DATA_W-1:0] HwCapability = {`AXI_DATA_W{1'b0}};
    logic [`AXI_DATA_W-1:0] HwPerfCycles = {`AXI_DATA_W{1'b0}};
    logic [`AXI_DATA_W-1:0] HwPerfStalls = {`AXI_DATA_W{1'b0}};

    meds_s1_axi4_slave_wrapper #(
        .ID_VAL(64'hDEAD_BEEF)
    ) dut (
        .clk(clk),.rst_n(rst_n),
        .awid(awid),.awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),
        .awvalid(awvalid),.awready(awready),
        .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
        .bid(bid),.bresp(bresp),.bvalid(bvalid),.bready(bready),
        .arid(arid),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
        .arvalid(arvalid),.arready(arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
        .HwStart(HwStart),.HwAbort(HwAbort),.HwIrqEn(HwIrqEn),
        .HwBusy(HwBusy),.HwDone(HwDone),.HwError(HwError),.HwErrcode(HwErrcode),
        .HwCapability(HwCapability),.HwPerfCycles(HwPerfCycles),.HwPerfStalls(HwPerfStalls),
        .Irq(Irq)
    );

    task automatic axi_write_burst(input logic [`AXI_ADDR_W-1:0] base_addr,
                                    input int beats,
                                    input logic [`AXI_DATA_W-1:0] data0);
        awvalid = 1'b1; awaddr = base_addr; awlen = beats - 1; awsize = 3'd2; awburst = 2'b01; awid = '0;
        @(posedge clk);
        while (!awready) @(posedge clk);
        awvalid = 1'b0;

        for (int i = 0; i < beats; i++) begin
            wvalid = 1'b1;
            wdata = data0 + i;
            wstrb = {`AXI_STRB_W{1'b1}};
            wlast = (i == beats - 1);
            @(posedge clk);
            while (!wready) @(posedge clk);
        end
        wvalid = 1'b0;

        bready = 1'b1;
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        $display("[%0t] B: bresp=%0d (expect DECERR if burst touched RO/unmapped offsets)", $time, bresp);
        @(posedge clk);
        bready = 1'b0;
    endtask

    logic [`AXI_DATA_W-1:0] rdata_beat [0:3];
    logic [1:0] rresp_beat [0:3];
    logic rlast_beat [0:3];

    task automatic axi_read_burst(input logic [`AXI_ADDR_W-1:0] base_addr,
                                   input int beats);
        arvalid = 1'b1; araddr = base_addr; arlen = beats - 1; arsize = 3'd2; arburst = 2'b01; arid = '0;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid = 1'b0;

        rready = 1'b1;
        for (int i = 0; i < beats; i++) begin
            @(posedge clk);
            while (!rvalid) @(posedge clk);
            $display("[%0t] R: beat=%0d data=%h resp=%0d last=%0d", $time, i, rdata, rresp, rlast);
            if (i == beats - 1 && !rlast) $display("*** ERROR: RLAST missing on final beat ***");
            if (i != beats - 1 && rlast) $display("*** ERROR: early RLAST ***");
            if (i < 4) begin
                rdata_beat[i] = rdata;
                rresp_beat[i] = rresp;
                rlast_beat[i] = rlast;
            end
        end
        rready = 1'b0;
    endtask

    localparam [1:0] RESP_OKAY = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;
    integer errors = 0;

    task check_eq(input [255:0] name, input [`AXI_DATA_W-1:0] got, input [`AXI_DATA_W-1:0] exp);
        begin
            if (got !== exp) begin
                $display("[FAIL] %0s: got=0x%h expected=0x%h", name, got, exp);
                errors = errors + 1;
            end else
                $display("[PASS] %0s: 0x%h", name, got);
        end
    endtask

    task check_eq1(input [255:0] name, input got, input exp);
        begin
            if (got !== exp) begin
                $display("[FAIL] %0s: got=%0b expected=%0b", name, got, exp);
                errors = errors + 1;
            end else
                $display("[PASS] %0s: %0b", name, got);
        end
    endtask

    initial begin
        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        rst_n = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("");
        $display("### SCENARIO 1: 4-beat INCR write, only beat 2 (OFF_CTRL=0x08) legal ###");
        // beat0->OFF_ID(RO) beat1->OFF_VERSION(RO) beat2->OFF_CTRL(RW, data=3
        // i.e. HwStart|HwAbort pulsed, IrqEn=0) beat3->OFF_STATUS(RO).
        // 3 of 4 beats miss -> AXI4 has one BRESP per burst -> DECERR.
        axi_write_burst('h00, 4, {`AXI_DATA_W{1'b0}} + 1);
        check_eq("BRESP==DECERR(3/4 illegal)", {30'b0, bresp}, {30'b0, RESP_DECERR});

        $display("");
        $display("### SCENARIO 2: 4-beat INCR read over the same 4 registers ###");
        // ID_VAL=0xDEAD_BEEF (tb param) / VERSION_VAL=0x0001_0000 (default) /
        // CTRL readback is 0 (start/abort self-clear, irq_en never set by
        // the write above) / STATUS is 0 (Hw* status inputs tied low in tb).
        axi_read_burst('h00, 4);
        check_eq("beat0 ID readback", rdata_beat[0], {`AXI_DATA_W{1'b0}} | 64'hDEAD_BEEF);
        check_eq1("beat0 RRESP==OKAY", rresp_beat[0] == RESP_OKAY, 1'b1);
        check_eq1("beat0 RLAST==0", rlast_beat[0], 1'b0);
        check_eq("beat1 VERSION readback", rdata_beat[1], {`AXI_DATA_W{1'b0}} | 32'h0001_0000);
        check_eq1("beat1 RLAST==0", rlast_beat[1], 1'b0);
        check_eq("beat2 CTRL readback (self-clr)", rdata_beat[2], {`AXI_DATA_W{1'b0}});
        check_eq1("beat2 RLAST==0", rlast_beat[2], 1'b0);
        check_eq("beat3 STATUS readback", rdata_beat[3], {`AXI_DATA_W{1'b0}});
        check_eq1("beat3 RLAST==1 (final)", rlast_beat[3], 1'b1);

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

        $display("[%0t] tb_axi4_simple done", $time);
        $finish;
    end

    integer cycle_num = 0;
    initial begin
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            #1;
            cycle_num = cycle_num + 1;
            $display("-------------------------------------------------------------");
            $display("[cycle %0d] t=%0t", cycle_num, $time);
            $display(" AW: awid=%0d awaddr=%h awlen=%0d awsize=%0d awburst=%0b awvalid=%b awready=%b",
                      awid, awaddr, awlen, awsize, awburst, awvalid, awready);
            $display(" W : wdata=%h wstrb=%h wlast=%b wvalid=%b wready=%b",
                      wdata, wstrb, wlast, wvalid, wready);
            $display(" B : bid=%0d bresp=%0d bvalid=%b bready=%b",
                      bid, bresp, bvalid, bready);
            $display(" AR: arid=%0d araddr=%h arlen=%0d arsize=%0d arburst=%0b arvalid=%b arready=%b",
                      arid, araddr, arlen, arsize, arburst, arvalid, arready);
            $display(" R : rid=%0d rdata=%h rresp=%0d rlast=%b rvalid=%b rready=%b",
                      rid, rdata, rresp, rlast, rvalid, rready);
        end
    end

endmodule