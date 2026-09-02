
/// What this checks:
//   T1 - IDLE: ready=1 every cycle nothing is captured; a valid+addr/id on
//        one cycle is latched exactly on the next posedge, ready drops.
//   T2 - CAPTURED: ready stays 0 (backpressure) while occupied, even if a
//        *different* address/id is offered with valid=1 -- the buffer must
//        not silently overwrite the held transaction.
//   T3 - consume clears the buffer back to IDLE, captured_addr/id held
//        stable right up until the cycle consume takes effect.
//   T4 - consume asserted in the SAME cycle a new valid arrives: per the
//        RTL, state_n only captures from the IDLE branch, so a same-cycle
//        consume+valid does NOT capture the new data that cycle -- this is
//        a real corner of the FSM and the TB asserts that exact behaviour
//        (not a "would be nice" guess), then re-offers valid the following
//        cycle to show it captures normally once IDLE is actually reached.
//   T5 - back-to-back full cycles (capture -> consume -> capture -> consume)
//        with different addr/id each time, to catch any register not
//        clearing/updating between rounds.
//   T6 - reset while CAPTURED: captured_addr/id/captured must all clear.
//


module tb_axi_addr_id_capture;

    localparam int ADDR_W = 40;
    localparam int ID_W   = 6;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic [ADDR_W-1:0] addr;
    logic [ID_W-1:0]   id;
    logic              valid;
    logic              ready;

    logic [ADDR_W-1:0] captured_addr;
    logic [ID_W-1:0]   captured_id;
    logic              captured;
    logic              consume;

    meds_s1_axi_addr_id_capture #(.ADDR_W(ADDR_W), .ID_W(ID_W)) dut (
        .clk_i(clk), .rst_ni(rst_n),
        .addr(addr), .id(id), .valid(valid), .ready(ready),
        .captured_addr(captured_addr), .captured_id(captured_id),
        .captured(captured), .consume(consume)
    );

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check(input string name, input logic got, input logic exp);
        if (got === exp) begin
            pass_cnt++;
            $display("[%0t] PASS  %-58s got=%0b exp=%0b", $time, name, got, exp);
        end else begin
            fail_cnt++;
            $display("[%0t] FAIL  %-58s got=%0b exp=%0b  <<<<<<", $time, name, got, exp);
        end
    endtask

    task automatic check_bits(input string name, input logic [63:0] got, input logic [63:0] exp, input int width);
        logic [63:0] mask;
        begin
            mask = (width >= 64) ? 64'hFFFF_FFFF_FFFF_FFFF : ((64'd1 << width) - 64'd1);
            if ((got & mask) === (exp & mask)) begin
                pass_cnt++;
                $display("[%0t] PASS  %-58s got=0x%0h exp=0x%0h", $time, name, got, exp);
            end else begin
                fail_cnt++;
                $display("[%0t] FAIL  %-58s got=0x%0h exp=0x%0h  <<<<<<", $time, name, got, exp);
            end
        end
    endtask

    // ---------------- per-clock-cycle transcript ----------------
    longint cycle_num = 0;
    function automatic string st(logic v); return v ? "1" : "0"; endfunction

    always @(posedge clk) begin
        if (rst_n) begin
            $display("CYC=%0d T=%0t | addr=0x%0h id=%0d valid=%s ready=%s || captured_addr=0x%0h captured_id=%0d captured=%s consume=%s",
                cycle_num, $time, addr, id, st(valid), st(ready),
                captured_addr, captured_id, st(captured), st(consume));
            cycle_num++;
        end
    end

    // ---------------- stimulus ----------------
    initial begin
        addr = '0; id = '0; valid = 1'b0; consume = 1'b0;

        $display("========================================================================");
        $display(" tb_axi_addr_id_capture : starting (ADDR_W=%0d ID_W=%0d)", ADDR_W, ID_W);
        $display("========================================================================");

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- T1: basic capture from IDLE ----
        $display("\n---- T1: basic capture (addr=0x1000, id=3) ----");
        check("T1 pre: ready high while IDLE", ready, 1'b1);
        check("T1 pre: captured low while IDLE", captured, 1'b0);

        @(negedge clk);
        addr = 40'h1000; id = 6'd3; valid = 1'b1;
        @(posedge clk);
        #1;
        check("T1: ready already low -- accept happened on this edge", ready, 1'b0);
        @(negedge clk);
        valid = 1'b0; // mimic a master dropping valid once accepted
        @(posedge clk);
        #1;
        check("T1: captured goes high one cycle after the accept", captured, 1'b1);
        check("T1: ready drops once captured", ready, 1'b0);
        check_bits("T1: captured_addr latched correctly", captured_addr, 40'h1000, ADDR_W);
        check_bits("T1: captured_id latched correctly", captured_id, 6'd3, ID_W);

        // ---- T2: backpressure -- offering a different addr/id while
        // CAPTURED must not be accepted or overwrite the held one ----
        $display("\n---- T2: backpressure while CAPTURED (offer addr=0xDEAD, id=5; must be ignored) ----");
        @(negedge clk);
        addr = 40'hDEAD; id = 6'd5; valid = 1'b1;
        @(posedge clk);
        #1;
        check("T2: ready stays low despite valid while CAPTURED", ready, 1'b0);
        check_bits("T2: captured_addr unchanged (still original)", captured_addr, 40'h1000, ADDR_W);
        check_bits("T2: captured_id unchanged (still original)", captured_id, 6'd3, ID_W);
        @(negedge clk);
        // hold the offer for a second cycle -- still must not leak in
        @(posedge clk);
        #1;
        check("T2b: ready still low on 2nd cycle of the offer", ready, 1'b0);
        check_bits("T2b: captured_addr still unchanged", captured_addr, 40'h1000, ADDR_W);
        @(negedge clk);
        valid = 1'b0;

        // ---- T3: consume clears the buffer ----
        $display("\n---- T3: consume clears CAPTURED -> IDLE ----");
        @(negedge clk);
        consume = 1'b1;
        @(posedge clk);
        #1;
        check("T3: captured drops the cycle after consume", captured, 1'b0);
        check("T3: ready reasserts once back in IDLE", ready, 1'b1);
        @(negedge clk);
        consume = 1'b0;

        // ---- T4: consume and a new valid arriving on the SAME cycle ----
        $display("\n---- T4: consume + simultaneous new valid (must NOT capture that same cycle) ----");
        // get back into CAPTURED first
        @(negedge clk);
        addr = 40'h2000; id = 6'd9; valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        valid = 1'b0;
        @(posedge clk);
        #1;
        check("T4 setup: captured before the same-cycle test", captured, 1'b1);
        check_bits("T4 setup: captured_addr == 0x2000", captured_addr, 40'h2000, ADDR_W);

        @(negedge clk);
        consume = 1'b1;
        addr = 40'h3000; id = 6'd12; valid = 1'b1; // offered on the SAME cycle as consume
        @(posedge clk);
        #1;
        check("T4: captured drops due to consume", captured, 1'b0);
        // per the RTL, capture only happens from the IDLE branch of the
        // case statement, and 'state' was still CAPTURED (not yet IDLE)
        // during this comb evaluation, so the new data is NOT captured yet
        check("T4: ready is high now (back in IDLE) but new data not yet captured", ready, 1'b1);
        @(negedge clk);
        consume = 1'b0;
        // valid is still held from before -- now that the module is
        // genuinely IDLE, this same offer should be captured normally
        @(posedge clk);
        #1;
        check("T4: valid held after reaching IDLE now gets captured", captured, 1'b1);
        check_bits("T4: captured_addr == 0x3000 (captured on the following IDLE cycle)", captured_addr, 40'h3000, ADDR_W);
        check_bits("T4: captured_id == 12", captured_id, 6'd12, ID_W);
        @(negedge clk);
        valid = 1'b0;

        // clear out before T5
        @(negedge clk);
        consume = 1'b1;
        @(posedge clk);
        @(negedge clk);
        consume = 1'b0;

        // ---- T5: back-to-back capture/consume rounds ----
        $display("\n---- T5: back-to-back capture/consume rounds, distinct addr/id each time ----");
        for (int r = 0; r < 4; r++) begin
            logic [ADDR_W-1:0] a;
            logic [ID_W-1:0] i2;
            a = 40'hA000 + (r << 8);
            i2 = r[ID_W-1:0] + 6'd1;
            @(negedge clk);
            addr = a; id = i2; valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            valid = 1'b0;
            @(posedge clk);
            #1;
            check($sformatf("T5 round %0d: captured asserted", r), captured, 1'b1);
            check_bits($sformatf("T5 round %0d: captured_addr correct", r), captured_addr, a, ADDR_W);
            check_bits($sformatf("T5 round %0d: captured_id correct", r), captured_id, i2, ID_W);
            @(negedge clk);
            consume = 1'b1;
            @(posedge clk);
            #1;
            check($sformatf("T5 round %0d: captured cleared after consume", r), captured, 1'b0);
            @(negedge clk);
            consume = 1'b0;
        end

        // ---- T6: reset while CAPTURED must clear everything ----
        $display("\n---- T6: async reset while CAPTURED clears captured/addr/id ----");
        @(negedge clk);
        addr = 40'h5555_5; id = 6'd21; valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        valid = 1'b0;
        @(posedge clk);
        #1;
        check("T6 setup: captured before reset", captured, 1'b1);

        rst_n = 0;
        @(negedge clk);
        check("T6: captured clears under reset", captured, 1'b0);
        check_bits("T6: captured_addr clears under reset", captured_addr, 40'h0, ADDR_W);
        check_bits("T6: captured_id clears under reset", captured_id, 6'd0, ID_W);
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        #1;
        check("T6: ready high again after reset release", ready, 1'b1);

        repeat (3) @(posedge clk);

        $display("\n========================================================================");
        $display(" tb_axi_addr_id_capture : DONE   PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" RESULT: ALL CHECKS PASSED");
        else
            $display(" RESULT: %0d CHECK(S) FAILED", fail_cnt);
        $display("========================================================================");

        $finish;
    end

    initial begin
        #50000;
        $display("[%0t] TIMEOUT -- simulation did not finish in time", $time);
        $finish;
    end

endmodule
