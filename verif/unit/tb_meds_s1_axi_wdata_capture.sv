
// What this checks:
//   T1 - IDLE: ready=1 while empty; a valid data+strobe beat is latched on
//        the accepting edge, ready drops, captured_data/captured_strb hold
//        the exact bit pattern offered (checked with a distinctive,
//        non-symmetric 256-bit pattern so a byte-swap or lane-mixup bug
//        would actually show up, not just an all-1s/all-0s pass-by-luck).
//   T2 - backpressure: a different data/strobe offered while CAPTURED must
//        not be accepted or corrupt the held beat.
//   T3 - consume clears CAPTURED -> IDLE.
//   T4 - partial-strobe beat: strb != all-ones (a narrow/unaligned write)
//        is captured and held exactly as offered, not widened or masked
//        by the capture buffer itself (masking is the peripheral's job).
//   T5 - back-to-back capture/consume rounds with distinct data each time.
//   T6 - reset while CAPTURED clears captured_data/captured_strb/captured.



module tb_axi_wdata_capture;

    localparam int DATA_W = 256;
    localparam int STRB_W = DATA_W/8; // 32

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic [DATA_W-1:0] data;
    logic [STRB_W-1:0] strb;
    logic               valid;
    logic               ready;

    logic [DATA_W-1:0] captured_data;
    logic [STRB_W-1:0] captured_strb;
    logic               captured;
    logic               consume;

    meds_s1_axi_wdata_capture #(.DATA_W(DATA_W), .STRB_W(STRB_W)) dut (
        .clk_i(clk), .rst_ni(rst_n),
        .data(data), .strb(strb), .valid(valid), .ready(ready),
        .captured_data(captured_data), .captured_strb(captured_strb),
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


    task automatic check_wide(input string name, input logic [DATA_W-1:0] got, input logic [DATA_W-1:0] exp);
        if (got === exp) begin
            pass_cnt++;
            $display("[%0t] PASS  %-58s (256b match)", $time, name);
        end else begin
            fail_cnt++;
            $display("[%0t] FAIL  %-58s got[63:0]=0x%0h exp[63:0]=0x%0h  <<<<<<", $time, name, got[63:0], exp[63:0]);
        end
    endtask

    task automatic check_strb(input string name, input logic [STRB_W-1:0] got, input logic [STRB_W-1:0] exp);
        if (got === exp) begin
            pass_cnt++;
            $display("[%0t] PASS  %-58s got=0x%0h exp=0x%0h", $time, name, got, exp);
        end else begin
            fail_cnt++;
            $display("[%0t] FAIL  %-58s got=0x%0h exp=0x%0h  <<<<<<", $time, name, got, exp);
        end
    endtask

    //  per-clock-cycle transcript
    longint cycle_num = 0;
    function automatic string st(logic v); return v ? "1" : "0"; endfunction

    always @(posedge clk) begin
        if (rst_n) begin
            $display("CYC=%0d T=%0t | data[63:0]=0x%0h strb=0x%0h valid=%s ready=%s || cap_data[63:0]=0x%0h cap_strb=0x%0h captured=%s consume=%s",
                cycle_num, $time, data[63:0], strb, st(valid), st(ready),
                captured_data[63:0], captured_strb, st(captured), st(consume));
            cycle_num++;
        end
    end

    
    function automatic logic [DATA_W-1:0] pattern(input logic [7:0] seed);
        logic [DATA_W-1:0] p;
        for (int i = 0; i < DATA_W/8; i++) begin
            p[i*8 +: 8] = seed + i[7:0];
        end
        return p;
    endfunction

    
    initial begin
        data = '0; strb = '0; valid = 1'b0; consume = 1'b0;

        $display("========================================================================");
        $display(" tb_axi_wdata_capture : starting (DATA_W=%0d STRB_W=%0d)", DATA_W, STRB_W);
        $display("========================================================================");

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- T1: basic capture, full strobe, distinctive pattern ----
        $display("\n---- T1: basic capture, full strobe, distinctive byte-ramp pattern ----");
        check("T1 pre: ready high while IDLE", ready, 1'b1);
        check("T1 pre: captured low while IDLE", captured, 1'b0);

        @(negedge clk);
        data = pattern(8'hA0); strb = {STRB_W{1'b1}}; valid = 1'b1;
        @(posedge clk);
        #1;
        check("T1: ready already low -- accept happened on this edge", ready, 1'b0);
        @(negedge clk);
        valid = 1'b0;
        @(posedge clk);
        #1;
        check("T1: captured high", captured, 1'b1);
        check_wide("T1: captured_data matches offered pattern exactly", captured_data, pattern(8'hA0));
        check_strb("T1: captured_strb == full strobe", captured_strb, {STRB_W{1'b1}});

        // ---- T2: backpressure -- different data/strb offered while
        // CAPTURED must not leak in ----
        $display("\n---- T2: backpressure while CAPTURED ----");
        @(negedge clk);
        data = pattern(8'hFF); strb = {STRB_W{1'b0}}; valid = 1'b1; // deliberately different
        @(posedge clk);
        #1;
        check("T2: ready stays low despite valid while CAPTURED", ready, 1'b0);
        check_wide("T2: captured_data unchanged (still original pattern)", captured_data, pattern(8'hA0));
        check_strb("T2: captured_strb unchanged", captured_strb, {STRB_W{1'b1}});
        @(negedge clk);
        valid = 1'b0;

        // ---- T3: consume clears the buffer ----
        $display("\n---- T3: consume clears CAPTURED -> IDLE ----");
        @(negedge clk);
        consume = 1'b1;
        @(posedge clk);
        #1;
        check("T3: captured drops after consume", captured, 1'b0);
        check("T3: ready reasserts once back in IDLE", ready, 1'b1);
        @(negedge clk);
        consume = 1'b0;

        // ---- T4: partial-strobe beat held exactly, not masked ----
        $display("\n---- T4: partial-strobe (narrow write) beat captured as-is ----");
        @(negedge clk);
        data = pattern(8'h10); strb = 32'h0000_00F0; valid = 1'b1; // only lane 1 (bits 15:8 of strobe -- byte lane pattern) active
        @(posedge clk);
        @(negedge clk);
        valid = 1'b0;
        @(posedge clk);
        #1;
        check("T4: captured high", captured, 1'b1);
        check_wide("T4: captured_data holds full offered pattern (unmasked)", captured_data, pattern(8'h10));
        check_strb("T4: captured_strb == the exact partial strobe offered", captured_strb, 32'h0000_00F0);
        @(negedge clk);
        consume = 1'b1;
        @(posedge clk);
        @(negedge clk);
        consume = 1'b0;

        // ---- T5: back-to-back capture/consume rounds ----
        $display("\n---- T5: back-to-back capture/consume rounds, distinct pattern each time ----");
        for (int r = 0; r < 4; r++) begin
            logic [DATA_W-1:0] p;
            logic [STRB_W-1:0] s;
            p = pattern(8'(r * 16 + 1));
            s = {STRB_W{1'b1}} >> r; // different strobe shape each round
            @(negedge clk);
            data = p; strb = s; valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            valid = 1'b0;
            @(posedge clk);
            #1;
            check($sformatf("T5 round %0d: captured asserted", r), captured, 1'b1);
            check_wide($sformatf("T5 round %0d: captured_data correct", r), captured_data, p);
            check_strb($sformatf("T5 round %0d: captured_strb correct", r), captured_strb, s);
            @(negedge clk);
            consume = 1'b1;
            @(posedge clk);
            #1;
            check($sformatf("T5 round %0d: captured cleared after consume", r), captured, 1'b0);
            @(negedge clk);
            consume = 1'b0;
        end

        // ---- T6: reset while CAPTURED clears everything ----
        $display("\n---- T6: async reset while CAPTURED clears captured/data/strb ----");
        @(negedge clk);
        data = pattern(8'h77); strb = {STRB_W{1'b1}}; valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        valid = 1'b0;
        @(posedge clk);
        #1;
        check("T6 setup: captured before reset", captured, 1'b1);

        rst_n = 0;
        @(negedge clk);
        check("T6: captured clears under reset", captured, 1'b0);
        check_wide("T6: captured_data clears under reset", captured_data, {DATA_W{1'b0}});
        check_strb("T6: captured_strb clears under reset", captured_strb, {STRB_W{1'b0}});
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        #1;
        check("T6: ready high again after reset release", ready, 1'b1);

        repeat (3) @(posedge clk);

        $display("\n========================================================================");
        $display(" tb_axi_wdata_capture : DONE   PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
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
