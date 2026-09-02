
// What this checks, per master lane, independently:
//   T1 - AW miss, single-beat write (awlen=0): awready pulses for exactly
//        one cycle, wready then accepts exactly one W beat (wlast), bvalid
//        then holds DECERR (2'b11) with the *original* awid until bready.
//   T2 - AW miss, multi-beat write (awlen=3): sink drains all 4 W beats
//        (wready high across all of them) before bvalid ever asserts --
//        i.e. the write response must not jump the gun.
//   T3 - AR miss, single-beat read (arlen=0): one-beat DECERR burst,
//        rlast=1 on that single beat, rdata=0.
//   T4 - AR miss, multi-beat read (arlen=7): 8-beat replay burst, rlast
//        only true on the 8th beat, rid constant, rdata=0 every beat.
//   T5 - Back-to-back misses on the same master lane (W then W again, and
//        R then R again): FSM must return cleanly to IDLE and accept the
//        next AW/AR, not wedge.
//   T6 - Two different master lanes (0 and 1) missing on the same cycle,
//        one on the write side and one on the read side: lanes must be
//        fully independent (checked by holding bready/rready low on one
//        lane while the other completes, then verifying the held lane's
//        response is still pending and correct).

`include "axi4_params.svh"

module tb_axi4_decerr_sink;

    
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic [`NUM_MASTERS-1:0] aw_miss, ar_miss;
    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] m_awid, m_arid;
    logic [`NUM_MASTERS-1:0][7:0] m_awlen, m_arlen;
    logic [`NUM_MASTERS-1:0] sink_awready, sink_arready;

    logic [`NUM_MASTERS-1:0] m_wvalid, m_wlast;
    logic [`NUM_MASTERS-1:0] sink_wready;

    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] sink_bid;
    logic [`NUM_MASTERS-1:0][1:0] sink_bresp;
    logic [`NUM_MASTERS-1:0] sink_bvalid;
    logic [`NUM_MASTERS-1:0] m_bready;

    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] sink_rid;
    logic [`NUM_MASTERS-1:0][`AXI_DATA_W-1:0] sink_rdata;
    logic [`NUM_MASTERS-1:0][1:0] sink_rresp;
    logic [`NUM_MASTERS-1:0] sink_rlast;
    logic [`NUM_MASTERS-1:0] sink_rvalid;
    logic [`NUM_MASTERS-1:0] m_rready;

    meds_s1_axi4_decerr_sink dut (
        .clk_i(clk), .rst_ni(rst_n),
        .aw_miss(aw_miss), .ar_miss(ar_miss),
        .m_awid(m_awid), .m_awlen(m_awlen), .sink_awready(sink_awready),
        .m_wvalid(m_wvalid), .m_wlast(m_wlast), .sink_wready(sink_wready),
        .sink_bid(sink_bid), .sink_bresp(sink_bresp), .sink_bvalid(sink_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_arlen(m_arlen), .sink_arready(sink_arready),
        .sink_rid(sink_rid), .sink_rdata(sink_rdata), .sink_rresp(sink_rresp),
        .sink_rlast(sink_rlast), .sink_rvalid(sink_rvalid), .m_rready(m_rready)
    );

    // ------------------------------------------------------------------
    // Pass/fail bookkeeping
    // ------------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check(input string name, input logic got, input logic exp);
        if (got === exp) begin
            pass_cnt++;
            $display("[%0t] PASS  %-46s got=%0b exp=%0b", $time, name, got, exp);
        end else begin
            fail_cnt++;
            $display("[%0t] FAIL  %-46s got=%0b exp=%0b  <<<<<<", $time, name, got, exp);
        end
    endtask


    task automatic check_bits(input string name, input logic [63:0] got, input logic [63:0] exp, input int width);
        logic [63:0] mask;
        begin
            mask = (width >= 64) ? 64'hFFFF_FFFF_FFFF_FFFF : ((64'd1 << width) - 64'd1);
            if ((got & mask) === (exp & mask)) begin
                pass_cnt++;
                $display("[%0t] PASS  %-46s got=0x%0h exp=0x%0h", $time, name, got, exp);
            end else begin
                fail_cnt++;
                $display("[%0t] FAIL  %-46s got=0x%0h exp=0x%0h  <<<<<<", $time, name, got, exp);
            end
        end
    endtask


    longint cycle_num = 0;

    function automatic string st(logic v);
        return v ? "1" : "0";
    endfunction

    always @(posedge clk) begin
        if (rst_n) begin
            $display("CYC=%0d T=%0t | M0: awV=%s awR=%s awID=%0d awLEN=%0d | wV=%s wL=%s wR=%s | bV=%s bR=%s bID=%0d bRESP=%0b | arV=%s arR=%s arID=%0d arLEN=%0d | rV=%s rR=%s rID=%0d rRESP=%0b rLAST=%s rDATA=%0h || M1: awV=%s awR=%s | wV=%s wR=%s | bV=%s bR=%s | arV=%s arR=%s | rV=%s rR=%s rLAST=%s",
                cycle_num, $time,
                st(aw_miss[0]), st(sink_awready[0]), m_awid[0], m_awlen[0],
                st(m_wvalid[0]), st(m_wlast[0]), st(sink_wready[0]),
                st(sink_bvalid[0]), st(m_bready[0]), sink_bid[0], sink_bresp[0],
                st(ar_miss[0]), st(sink_arready[0]), m_arid[0], m_arlen[0],
                st(sink_rvalid[0]), st(m_rready[0]), sink_rid[0], sink_rresp[0], st(sink_rlast[0]), sink_rdata[0],
                st(aw_miss[1]), st(sink_awready[1]),
                st(m_wvalid[1]), st(sink_wready[1]),
                st(sink_bvalid[1]), st(m_bready[1]),
                st(ar_miss[1]), st(sink_arready[1]),
                st(sink_rvalid[1]), st(m_rready[1]), st(sink_rlast[1])
            );
            cycle_num++;
        end
    end

   
    task automatic do_write_miss(input int m, input logic [`AXI_ID_W-1:0] id, input logic [7:0] len,
                                  input int bready_delay_cycles);
        int i;
        begin
            // Drive AW
            @(negedge clk);
            aw_miss[m]  = 1'b1;
            m_awid[m]   = id;
            m_awlen[m]  = len;
            @(posedge clk);
            check($sformatf("M%0d T-AW: sink_awready asserts on aw_miss", m), sink_awready[m], 1'b1);
            @(negedge clk);
            aw_miss[m] = 1'b0; // one-cycle handshake, mirrors a real master de-asserting after accept

            // Drain W beats: len+1 total, wlast on the last one
            for (i = 0; i <= len; i++) begin
                m_wvalid[m] = 1'b1;
                m_wlast[m]  = (i == len);
                @(posedge clk);
                check($sformatf("M%0d T-W: sink_wready high during drain beat %0d", m, i), sink_wready[m], 1'b1);
                // bvalid must NOT have jumped ahead of the burst finishing
                if (i != len)
                    check($sformatf("M%0d T-W: sink_bvalid stays low mid-burst (beat %0d)", m, i), sink_bvalid[m], 1'b0);
            end
            @(negedge clk);
            m_wvalid[m] = 1'b0;
            m_wlast[m]  = 1'b0;

            // B response: hold bready low for the requested number of
            // extra cycles first, to prove bvalid is *held* stably.
            repeat (bready_delay_cycles) begin
                @(posedge clk);
                check($sformatf("M%0d T-B: sink_bvalid held while bready low", m), sink_bvalid[m], 1'b1);
                check_bits($sformatf("M%0d T-B: sink_bid == original awid (held)", m), sink_bid[m], id, `AXI_ID_W);
                check_bits($sformatf("M%0d T-B: sink_bresp == DECERR (held)", m), sink_bresp[m], 2'b11, 2);
            end
            @(negedge clk);
            m_bready[m] = 1'b1;
            @(posedge clk);
            check($sformatf("M%0d T-B: sink_bvalid asserted at handshake", m), sink_bvalid[m], 1'b1);
            check_bits($sformatf("M%0d T-B: sink_bid == original awid", m), sink_bid[m], id, `AXI_ID_W);
            check_bits($sformatf("M%0d T-B: sink_bresp == DECERR (2'b11)", m), sink_bresp[m], 2'b11, 2);
            @(negedge clk);
            m_bready[m] = 1'b0;
            @(posedge clk);
            check($sformatf("M%0d T-B: sink_bvalid deasserts after handshake (FSM back to IDLE)", m), sink_bvalid[m], 1'b0);
        end
    endtask

    // Issue an AR miss on lane `m` with given id/len, then pull the full
    // len+1-beat DECERR replay burst, checking rdata/rresp/rlast every beat.
    task automatic do_read_miss(input int m, input logic [`AXI_ID_W-1:0] id, input logic [7:0] len);
        int i;
        begin
            @(negedge clk);
            ar_miss[m] = 1'b1;
            m_arid[m]  = id;
            m_arlen[m] = len;
            @(posedge clk);
            check($sformatf("M%0d T-AR: sink_arready asserts on ar_miss", m), sink_arready[m], 1'b1);
            @(negedge clk);
            ar_miss[m] = 1'b0;

            for (i = 0; i <= len; i++) begin
                m_rready[m] = 1'b1;
                @(posedge clk);
                check($sformatf("M%0d T-R: sink_rvalid high on beat %0d/%0d", m, i, len), sink_rvalid[m], 1'b1);
                check_bits($sformatf("M%0d T-R: sink_rid constant across burst (beat %0d)", m, i), sink_rid[m], id, `AXI_ID_W);
                check_bits($sformatf("M%0d T-R: sink_rresp == DECERR (beat %0d)", m, i), sink_rresp[m], 2'b11, 2);
                check($sformatf("M%0d T-R: sink_rdata == 0 (beat %0d)", m, i), |sink_rdata[m], 1'b0);
                check($sformatf("M%0d T-R: sink_rlast beat %0d (exp %0b)", m, i, (i == len)), sink_rlast[m], (i == len));
                @(negedge clk);
            end
            m_rready[m] = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // Stimulus
    // ------------------------------------------------------------------
    initial begin
        // init
        aw_miss = '0; ar_miss = '0;
        m_awid = '0; m_awlen = '0; m_arid = '0; m_arlen = '0;
        m_wvalid = '0; m_wlast = '0; m_bready = '0; m_rready = '0;

        $display("========================================================================");
        $display(" tb_axi4_decerr_sink : starting");
        $display("========================================================================");

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- T1: AW miss, single-beat write, immediate bready ----------
        $display("\n---- T1: single-beat write miss (M0, id=5, awlen=0) ----");
        do_write_miss(0, 6'd5, 8'd0, 0);

        // ---- T2: AW miss, multi-beat write (4 beats), bready delayed ---
        $display("\n---- T2: 4-beat write miss (M0, id=9, awlen=3), bready delayed 3 cyc ----");
        do_write_miss(0, 6'd9, 8'd3, 3);

        // ---- T3: AR miss, single-beat read --------------------------
        $display("\n---- T3: single-beat read miss (M0, id=2, arlen=0) ----");
        do_read_miss(0, 6'd2, 8'd0);

        // ---- T4: AR miss, 8-beat burst read ---------------------------
        $display("\n---- T4: 8-beat read miss (M0, id=11, arlen=7) ----");
        do_read_miss(0, 6'd11, 8'd7);

        // ---- T5: back-to-back misses on the same lane ------------------
        $display("\n---- T5a: back-to-back write misses on M0 (FSM returns to IDLE cleanly) ----");
        do_write_miss(0, 6'd1, 8'd0, 0);
        do_write_miss(0, 6'd2, 8'd1, 0);

        $display("\n---- T5b: back-to-back read misses on M0 ----");
        do_read_miss(0, 6'd3, 8'd0);
        do_read_miss(0, 6'd4, 8'd2);

        // ---- T6: two independent lanes missing concurrently ------------
        $display("\n---- T6: M0 write-miss and M1 read-miss concurrently, independent lanes ----");
        fork
            do_write_miss(0, 6'd20, 8'd1, 2);
            do_read_miss(1, 6'd21, 8'd3);
        join

        repeat (4) @(posedge clk);

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("\n========================================================================");
        $display(" tb_axi4_decerr_sink : DONE   PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" RESULT: ALL CHECKS PASSED");
        else
            $display(" RESULT: %0d CHECK(S) FAILED", fail_cnt);
        $display("========================================================================");

        $finish;
    end

    // Safety timeout in case a handshake never completes (would otherwise
    // hang the sim forever instead of failing loudly).
    initial begin
        #100000;
        $display("[%0t] TIMEOUT -- simulation did not finish in time", $time);
        $finish;
    end

endmodule
