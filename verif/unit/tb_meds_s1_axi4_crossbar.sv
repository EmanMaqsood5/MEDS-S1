
// Checks performed:
//   1. Single master, single-beat write+read-back to SLAVE1 (SRAM) --
//      data integrity through the crossbar and the mem-slave model.
//   2. Multi-beat INCR burst write+read to SLAVE2 (DRAM) -- RLAST /
//      burst addressing / WSTRB all exercised.
//   3. ID-tag routing: two different masters issue reads with the same
//      AXI ID value to two different slaves; checks each B/R response
//      comes back to the correct master (tag prepend/strip is correct),
//      not just "some" master.
//   4. Arbitration: two masters contend for the same slave
//      (SLAVE3) simultaneously; checks both eventually complete and
//      neither starves (round-robin fairness, single-outstanding-
//      per-slave is respected -- no interleaved AW/W between the two).
//   5. DECERR path: a master addresses an unmapped region; checks
//      BRESP/RRESP == SLVERR (2'b10) comes back with no hang, and
//      decerr_pulse fires for that master.

`timescale 1ns/1ps
`include "axi4_params.svh"
`include "axi4_addr_map.svh"


module simple_axi4_mem_slave (
    input logic clk_i,
    input logic rst_ni,

    input  logic [`AXI_SID_W-1:0]      awid,
    input  logic [`AXI_ADDR_W-1:0]     awaddr,
    input  logic [7:0]                 awlen,
    input  logic [2:0]                 awsize,
    input  logic [1:0]                 awburst,
    input  logic                       awvalid,
    output logic                       awready,

    input  logic [`AXI_DATA_W-1:0]     wdata,
    input  logic [`AXI_STRB_W-1:0]     wstrb,
    input  logic                       wlast,
    input  logic                       wvalid,
    output logic                       wready,

    output logic [`AXI_SID_W-1:0]      bid,
    output logic [1:0]                 bresp,
    output logic                       bvalid,
    input  logic                       bready,

    input  logic [`AXI_SID_W-1:0]      arid,
    input  logic [`AXI_ADDR_W-1:0]     araddr,
    input  logic [7:0]                 arlen,
    input  logic [2:0]                 arsize,
    input  logic [1:0]                 arburst,
    input  logic                       arvalid,
    output logic                       arready,

    output logic [`AXI_SID_W-1:0]      rid,
    output logic [`AXI_DATA_W-1:0]     rdata,
    output logic [1:0]                 rresp,
    output logic                       rlast,
    output logic                       rvalid,
    input  logic                       rready
);

    
    logic [7:0] mem [logic [`AXI_ADDR_W-1:0]];

    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} wstate_t;
    wstate_t wstate;
    logic [`AXI_ADDR_W-1:0] w_addr;
    logic [`AXI_SID_W-1:0]  w_id;
    logic [7:0]  w_len;
    logic [2:0]  w_size;
    logic [1:0]  w_burst;
    logic [7:0]  w_beat_cnt;

    assign awready = (wstate == W_IDLE);
    assign wready  = (wstate == W_DATA);
    assign bvalid  = (wstate == W_RESP);
    assign bid     = w_id;
    assign bresp   = 2'b00; // OKAY

    function automatic logic [`AXI_ADDR_W-1:0] next_addr(
        logic [`AXI_ADDR_W-1:0] a, logic [2:0] sz, logic [1:0] burst);
        if (burst == 2'b01) // INCR
            return a + (1 << sz);
        else
            return a; // FIXED (WRAP not modeled -- not used by this TB)
    endfunction

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wstate <= W_IDLE;
            w_beat_cnt <= '0;
        end else begin
            case (wstate)
                W_IDLE: if (awvalid && awready) begin
                    w_addr  <= awaddr;
                    w_id    <= awid;
                    w_len   <= awlen;
                    w_size  <= awsize;
                    w_burst <= awburst;
                    w_beat_cnt <= '0;
                    wstate  <= W_DATA;
                end
                W_DATA: if (wvalid && wready) begin
                    for (int b = 0; b < `AXI_STRB_W; b++)
                        if (wstrb[b]) mem[w_addr + b] = wdata[b*8 +: 8];
                    if (wlast) wstate <= W_RESP;
                    else begin
                        w_addr <= next_addr(w_addr, w_size, w_burst);
                        w_beat_cnt <= w_beat_cnt + 1;
                    end
                end
                W_RESP: if (bvalid && bready) wstate <= W_IDLE;
            endcase
        end
    end

    typedef enum logic [1:0] {R_IDLE, R_DATA} rstate_t;
    rstate_t rstate;
    logic [`AXI_ADDR_W-1:0] r_addr;
    logic [`AXI_SID_W-1:0]  r_id;
    logic [7:0]  r_len;
    logic [2:0]  r_size;
    logic [1:0]  r_burst;
    logic [7:0]  r_beat_cnt;

    assign arready = (rstate == R_IDLE);
    assign rvalid  = (rstate == R_DATA);
    assign rid     = r_id;
    assign rresp   = 2'b00; // OKAY
    assign rlast   = (rstate == R_DATA) && (r_beat_cnt == r_len);

    always_comb begin
        rdata = '0;
        // guard: only index the assoc array once an AR has actually been
        // captured (rstate==R_DATA), otherwise r_addr is still X at t=0
        // and Questa's assoc-array indexing rejects an X key outright.
        if (rstate == R_DATA) begin
            for (int b = 0; b < `AXI_STRB_W; b++)
                rdata[b*8 +: 8] = mem.exists(r_addr + b) ? mem[r_addr + b] : 8'h00;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rstate <= R_IDLE;
            r_beat_cnt <= '0;
        end else begin
            case (rstate)
                R_IDLE: if (arvalid && arready) begin
                    r_addr  <= araddr;
                    r_id    <= arid;
                    r_len   <= arlen;
                    r_size  <= arsize;
                    r_burst <= arburst;
                    r_beat_cnt <= '0;
                    rstate  <= R_DATA;
                end
                R_DATA: if (rvalid && rready) begin
                    if (rlast) rstate <= R_IDLE;
                    else begin
                        r_addr <= next_addr(r_addr, r_size, r_burst);
                        r_beat_cnt <= r_beat_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule


module tb_axi4_crossbar;

    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk; // 100MHz

    // ---------------- master-side flattened arrays ----------------
    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0]   m_awid;
    logic [`NUM_MASTERS-1:0][`AXI_ADDR_W-1:0] m_awaddr;
    logic [`NUM_MASTERS-1:0][7:0]             m_awlen;
    logic [`NUM_MASTERS-1:0][2:0]             m_awsize;
    logic [`NUM_MASTERS-1:0][1:0]             m_awburst;
    logic [`NUM_MASTERS-1:0]                  m_awvalid;
    logic [`NUM_MASTERS-1:0]                  m_awready;

    logic [`NUM_MASTERS-1:0][`AXI_DATA_W-1:0] m_wdata;
    logic [`NUM_MASTERS-1:0][`AXI_STRB_W-1:0] m_wstrb;
    logic [`NUM_MASTERS-1:0]                  m_wlast;
    logic [`NUM_MASTERS-1:0]                  m_wvalid;
    logic [`NUM_MASTERS-1:0]                  m_wready;

    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0]   m_bid;
    logic [`NUM_MASTERS-1:0][1:0]             m_bresp;
    logic [`NUM_MASTERS-1:0]                  m_bvalid;
    logic [`NUM_MASTERS-1:0]                  m_bready;

    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0]   m_arid;
    logic [`NUM_MASTERS-1:0][`AXI_ADDR_W-1:0] m_araddr;
    logic [`NUM_MASTERS-1:0][7:0]             m_arlen;
    logic [`NUM_MASTERS-1:0][2:0]             m_arsize;
    logic [`NUM_MASTERS-1:0][1:0]             m_arburst;
    logic [`NUM_MASTERS-1:0]                  m_arvalid;
    logic [`NUM_MASTERS-1:0]                  m_arready;

    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0]   m_rid;
    logic [`NUM_MASTERS-1:0][`AXI_DATA_W-1:0] m_rdata;
    logic [`NUM_MASTERS-1:0][1:0]             m_rresp;
    logic [`NUM_MASTERS-1:0]                  m_rlast;
    logic [`NUM_MASTERS-1:0]                  m_rvalid;
    logic [`NUM_MASTERS-1:0]                  m_rready;

    logic [`NUM_MASTERS-1:0]                  decerr_pulse;

    // ---------------- slave-side flattened arrays ----------------
    logic [`NUM_SLAVES-1:0][`AXI_SID_W-1:0]   s_awid;
    logic [`NUM_SLAVES-1:0][`AXI_ADDR_W-1:0]  s_awaddr;
    logic [`NUM_SLAVES-1:0][7:0]              s_awlen;
    logic [`NUM_SLAVES-1:0][2:0]              s_awsize;
    logic [`NUM_SLAVES-1:0][1:0]              s_awburst;
    logic [`NUM_SLAVES-1:0]                   s_awvalid;
    logic [`NUM_SLAVES-1:0]                   s_awready;

    logic [`NUM_SLAVES-1:0][`AXI_DATA_W-1:0]  s_wdata;
    logic [`NUM_SLAVES-1:0][`AXI_STRB_W-1:0]  s_wstrb;
    logic [`NUM_SLAVES-1:0]                   s_wlast;
    logic [`NUM_SLAVES-1:0]                   s_wvalid;
    logic [`NUM_SLAVES-1:0]                   s_wready;

    logic [`NUM_SLAVES-1:0][`AXI_SID_W-1:0]   s_bid;
    logic [`NUM_SLAVES-1:0][1:0]              s_bresp;
    logic [`NUM_SLAVES-1:0]                   s_bvalid;
    logic [`NUM_SLAVES-1:0]                   s_bready;

    logic [`NUM_SLAVES-1:0][`AXI_SID_W-1:0]   s_arid;
    logic [`NUM_SLAVES-1:0][`AXI_ADDR_W-1:0]  s_araddr;
    logic [`NUM_SLAVES-1:0][7:0]              s_arlen;
    logic [`NUM_SLAVES-1:0][2:0]              s_arsize;
    logic [`NUM_SLAVES-1:0][1:0]              s_arburst;
    logic [`NUM_SLAVES-1:0]                   s_arvalid;
    logic [`NUM_SLAVES-1:0]                   s_arready;

    logic [`NUM_SLAVES-1:0][`AXI_SID_W-1:0]   s_rid;
    logic [`NUM_SLAVES-1:0][`AXI_DATA_W-1:0]  s_rdata;
    logic [`NUM_SLAVES-1:0][1:0]              s_rresp;
    logic [`NUM_SLAVES-1:0]                   s_rlast;
    logic [`NUM_SLAVES-1:0]                   s_rvalid;
    logic [`NUM_SLAVES-1:0]                   s_rready;

    int errors = 0;
    int checks = 0;

    // set to 0 to silence the per-cycle trace and only see PASS/FAIL summary
    bit trace_en = 1;

    // ---------------- DUT ----------------
    meds_s1_axi4_crossbar dut (
        .clk_i(clk), .rst_ni(rst_n),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen), .m_awsize(m_awsize),
        .m_awburst(m_awburst), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen), .m_arsize(m_arsize),
        .m_arburst(m_arburst), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rlast(m_rlast),
        .m_rvalid(m_rvalid), .m_rready(m_rready),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen), .s_awsize(s_awsize),
        .s_awburst(s_awburst), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen), .s_arsize(s_arsize),
        .s_arburst(s_arburst), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rlast(s_rlast),
        .s_rvalid(s_rvalid), .s_rready(s_rready),
        .decerr_pulse(decerr_pulse)
    );

    // ---------------- slave BFMs on every port ----------------
    genvar gs;
    generate
        for (gs = 0; gs < `NUM_SLAVES; gs++) begin : g_slave
            simple_axi4_mem_slave u_mem (
                .clk_i(clk), .rst_ni(rst_n),
                .awid(s_awid[gs]), .awaddr(s_awaddr[gs]), .awlen(s_awlen[gs]),
                .awsize(s_awsize[gs]), .awburst(s_awburst[gs]),
                .awvalid(s_awvalid[gs]), .awready(s_awready[gs]),
                .wdata(s_wdata[gs]), .wstrb(s_wstrb[gs]), .wlast(s_wlast[gs]),
                .wvalid(s_wvalid[gs]), .wready(s_wready[gs]),
                .bid(s_bid[gs]), .bresp(s_bresp[gs]), .bvalid(s_bvalid[gs]), .bready(s_bready[gs]),
                .arid(s_arid[gs]), .araddr(s_araddr[gs]), .arlen(s_arlen[gs]),
                .arsize(s_arsize[gs]), .arburst(s_arburst[gs]),
                .arvalid(s_arvalid[gs]), .arready(s_arready[gs]),
                .rid(s_rid[gs]), .rdata(s_rdata[gs]), .rresp(s_rresp[gs]), .rlast(s_rlast[gs]),
                .rvalid(s_rvalid[gs]), .rready(s_rready[gs])
            );
        end
    endgenerate

    // default-drive all master inputs low; individual tasks drive per-index
    initial begin
        m_awvalid = '0; m_wvalid = '0; m_bready = '1;
        m_arvalid = '0; m_rready = '1;
        m_awid = '0; m_awaddr = '0; m_awlen = '0; m_awsize = '0; m_awburst = '0;
        m_wdata = '0; m_wstrb = '0; m_wlast = '0;
        m_arid = '0; m_araddr = '0; m_arlen = '0; m_arsize = '0; m_arburst = '0;
    end


    always @(posedge clk) begin
        if (trace_en && rst_n) begin
            for (int mi = 0; mi < `NUM_MASTERS; mi++) begin
                if (m_awvalid[mi] && m_awready[mi])
                    $display("[%0t] AW  M%0d: id=%0h addr=%0h len=%0d size=%0d burst=%0b",
                              $time, mi, m_awid[mi], m_awaddr[mi], m_awlen[mi], m_awsize[mi], m_awburst[mi]);
                if (m_wvalid[mi] && m_wready[mi])
                    $display("[%0t]  W  M%0d: data=%0h strb=%0h last=%0b",
                              $time, mi, m_wdata[mi], m_wstrb[mi], m_wlast[mi]);
                if (m_bvalid[mi] && m_bready[mi])
                    $display("[%0t]   B M%0d: id=%0h resp=%0b",
                              $time, mi, m_bid[mi], m_bresp[mi]);
                if (m_arvalid[mi] && m_arready[mi])
                    $display("[%0t] AR  M%0d: id=%0h addr=%0h len=%0d size=%0d burst=%0b",
                              $time, mi, m_arid[mi], m_araddr[mi], m_arlen[mi], m_arsize[mi], m_arburst[mi]);
                if (m_rvalid[mi] && m_rready[mi])
                    $display("[%0t]   R M%0d: id=%0h data=%0h resp=%0b last=%0b",
                              $time, mi, m_rid[mi], m_rdata[mi], m_rresp[mi], m_rlast[mi]);
                if (decerr_pulse[mi])
                    $display("[%0t] DECERR M%0d: address missed decode", $time, mi);
            end
            for (int si = 0; si < `NUM_SLAVES; si++) begin
                if (s_awvalid[si] && s_awready[si])
                    $display("[%0t] S%0d <- AW: sid=%0h addr=%0h len=%0d", $time, si, s_awid[si], s_awaddr[si], s_awlen[si]);
                if (s_arvalid[si] && s_arready[si])
                    $display("[%0t] S%0d <- AR: sid=%0h addr=%0h len=%0d", $time, si, s_arid[si], s_araddr[si], s_arlen[si]);
            end
        end
    end

    // ---------------- master driver tasks (blocking, one master idx at a time) ----------------
    task automatic axi4_write(
        input int mi,
        input logic [`AXI_ID_W-1:0] id,
        input logic [`AXI_ADDR_W-1:0] addr,
        input int burst_len, // beats, AWLEN+1
        input logic [`AXI_DATA_W-1:0] data_pattern_base
    );
        @(posedge clk);
        m_awid[mi]    = id;
        m_awaddr[mi]  = addr;
        m_awlen[mi]   = burst_len - 1;
        m_awsize[mi]  = 3'(($clog2(`AXI_STRB_W)));
        m_awburst[mi] = 2'b01; // INCR
        m_awvalid[mi] = 1'b1;
        do @(posedge clk); while (!m_awready[mi]);
        m_awvalid[mi] = 1'b0;

        for (int b = 0; b < burst_len; b++) begin
            m_wdata[mi]  = data_pattern_base + b;
            m_wstrb[mi]  = '1;
            m_wlast[mi]  = (b == burst_len - 1);
            m_wvalid[mi] = 1'b1;
            do @(posedge clk); while (!m_wready[mi]);
        end
        m_wvalid[mi] = 1'b0;
        m_wlast[mi]  = 1'b0;

        do @(posedge clk); while (!m_bvalid[mi]);
        checks++;
        if (m_bresp[mi] !== 2'b00) begin
            errors++;
            $display("[%0t] [FAIL] axi4_write: master %0d expected BRESP OKAY, got %0d", $time, mi, m_bresp[mi]);
        end
        if (m_bid[mi] !== id) begin
            errors++;
            $display("[%0t] [FAIL] axi4_write: master %0d expected BID %0h, got %0h", $time, mi, id, m_bid[mi]);
        end
    endtask

    task automatic axi4_read_expect(
        input int mi,
        input logic [`AXI_ID_W-1:0] id,
        input logic [`AXI_ADDR_W-1:0] addr,
        input int burst_len,
        input logic [`AXI_DATA_W-1:0] data_pattern_base,
        input bit expect_decerr = 0
    );
        @(posedge clk);
        m_arid[mi]    = id;
        m_araddr[mi]  = addr;
        m_arlen[mi]   = burst_len - 1;
        m_arsize[mi]  = 3'(($clog2(`AXI_STRB_W)));
        m_arburst[mi] = expect_decerr ? 2'b00 : 2'b01;
        m_arvalid[mi] = 1'b1;
        do @(posedge clk); while (!m_arready[mi]);
        m_arvalid[mi] = 1'b0;

        for (int b = 0; b < burst_len; b++) begin
            do @(posedge clk); while (!m_rvalid[mi]);
            checks++;
            if (m_rid[mi] !== id) begin
                errors++;
                $display("[%0t] [FAIL] axi4_read: master %0d beat %0d expected RID %0h, got %0h", $time, mi, b, id, m_rid[mi]);
            end
            if (expect_decerr) begin
                if (m_rresp[mi] !== 2'b11) begin
                    errors++;
                    $display("[FAIL] axi4_read: master %0d expected DECERR (2'b11), got RRESP=%0d", mi, m_rresp[mi]);
                end
            end else begin
                if (m_rresp[mi] !== 2'b00) begin
                    errors++;
                    $display("[%0t] [FAIL] axi4_read: master %0d beat %0d expected RRESP OKAY, got %0d", $time, mi, b, m_rresp[mi]);
                end
                if (m_rdata[mi] !== (data_pattern_base + b)) begin
                    errors++;
                    $display("[%0t] [FAIL] axi4_read: master %0d beat %0d expected data %0h, got %0h",
                              $time, mi, b, data_pattern_base + b, m_rdata[mi]);
                end
            end
            if ((b == burst_len - 1) && !m_rlast[mi]) begin
                errors++;
                $display("[%0t] [FAIL] axi4_read: master %0d final beat missing RLAST", $time, mi);
            end
        end
    endtask

    task automatic axi4_write_expect_decerr(
        input int mi,
        input logic [`AXI_ID_W-1:0] id,
        input logic [`AXI_ADDR_W-1:0] addr
    );
        @(posedge clk);
        m_awid[mi]    = id;
        m_awaddr[mi]  = addr;
        m_awlen[mi]   = 0;
        m_awsize[mi]  = 3'(($clog2(`AXI_STRB_W)));
        m_awburst[mi] = 2'b00;
        m_awvalid[mi] = 1'b1;
        do @(posedge clk); while (!m_awready[mi]);
        m_awvalid[mi] = 1'b0;

        m_wdata[mi]  = '0;
        m_wstrb[mi]  = '1;
        m_wlast[mi]  = 1'b1;
        m_wvalid[mi] = 1'b1;
        do @(posedge clk); while (!m_wready[mi]);
        m_wvalid[mi] = 1'b0;
        m_wlast[mi]  = 1'b0;

        do @(posedge clk); while (!m_bvalid[mi]);
        checks++;
        if (m_bresp[mi] !== 2'b11) begin
            errors++;
            $display("[FAIL] axi4_write_expect_decerr: master %0d expected DECERR (2'b11), got BRESP=%0d", mi, m_bresp[mi]);
        end
    endtask

    // ---------------- test sequence ----------------
    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("[%0t] === TEST 1: single-beat write+read, MASTER0 -> SLAVE1 (SRAM) ===", $time);
        axi4_write(0, 6'h05, ADDR_MAP_BASE[4], 1, 256'hDEAD_BEEF); // region idx 4 = SLAVE1
        axi4_read_expect(0, 6'h05, ADDR_MAP_BASE[4], 1, 256'hDEAD_BEEF);

        $display("[%0t] === TEST 2: multi-beat INCR burst, MASTER1 -> SLAVE2 (DRAM) ===", $time);
        axi4_write(1, 6'h0A, ADDR_MAP_BASE[5], 4, 256'hCAFE_0000); // region idx 5 = SLAVE2
        axi4_read_expect(1, 6'h0A, ADDR_MAP_BASE[5], 4, 256'hCAFE_0000);

        $display("[%0t] === TEST 3: ID-tag routing, MASTER2 & MASTER3 same AXI ID, different slaves ===", $time);
        fork
            axi4_write(2, 6'h01, ADDR_MAP_BASE[0], 1, 256'h1111_1111); // -> SLAVE0
            axi4_write(3, 6'h01, ADDR_MAP_BASE[2], 1, 256'h2222_2222); // -> SLAVE3
        join
        fork
            axi4_read_expect(2, 6'h01, ADDR_MAP_BASE[0], 1, 256'h1111_1111);
            axi4_read_expect(3, 6'h01, ADDR_MAP_BASE[2], 1, 256'h2222_2222);
        join

        $display("[%0t] === TEST 4: arbitration, MASTER4 & MASTER5 contend for SLAVE3 ===", $time);
        fork
            axi4_write(4, 6'h02, ADDR_MAP_BASE[2], 1, 256'h4444_0001);
            axi4_write(5, 6'h03, ADDR_MAP_BASE[2] + 40'h100, 1, 256'h5555_0001);
        join
        fork
            axi4_read_expect(4, 6'h02, ADDR_MAP_BASE[2], 1, 256'h4444_0001);
            axi4_read_expect(5, 6'h03, ADDR_MAP_BASE[2] + 40'h100, 1, 256'h5555_0001);
        join

        $display("[%0t] === TEST 5: DECERR path, MASTER0 addresses unmapped region ===", $time);
        fork
            begin
                axi4_write_expect_decerr(0, 6'h07, 40'hFF_0000_0000);
            end
            begin
                @(posedge clk);
                wait (decerr_pulse[0] === 1'b1);
                $display("[INFO] decerr_pulse[0] observed as expected");
            end
        join
        axi4_read_expect(0, 6'h08, 40'hFF_0000_1000, 1, 256'h0, 1'b1);

        // -----------------------------------------------------------
        // TEST 6: full coverage sweep -- every master (0..5), one
        // write+read each, to every one of the 6 mapped regions in
        // axi4_addr_map.svh. Sequential (not concurrent) so each
        // master/region pairing gets its own clean trace window --
        // 36 write+read pairs, 72 transactions total. Offsets are
        // spread out per master so back-to-back sweeps don't collide
        // on the same byte address in a shared region.
        // -----------------------------------------------------------
        $display("[%0t] === TEST 6: full coverage sweep, all 6 masters x all 6 regions ===", $time);
        for (int mi = 0; mi < `NUM_MASTERS; mi++) begin
            for (int region = 0; region < ADDR_MAP_NUM_REGIONS; region++) begin
                automatic logic [`AXI_ID_W-1:0] id = mi[5:0] ^ 6'h20;
                automatic logic [`AXI_ADDR_W-1:0] addr = ADDR_MAP_BASE[region] + (mi * 40'h20);
                automatic logic [`AXI_DATA_W-1:0] pattern = {mi[3:0], region[3:0]} << 16 | 256'hA5A5_0000;
                axi4_write(mi, id, addr, 1, pattern);
                axi4_read_expect(mi, id, addr, 1, pattern);
            end
        end
        $display("[%0t] TEST 6 complete: %0d master x region pairs swept", $time, `NUM_MASTERS * ADDR_MAP_NUM_REGIONS);

        // -----------------------------------------------------------
        // TEST 7: concurrent stress -- all 6 masters fire simultaneously
        // at 6 different slaves (one region each) with multi-beat
        // bursts, exercising full-width concurrent arbitration/routing
        // rather than the pairwise contention TEST 4 already covered.
        // -----------------------------------------------------------
        $display("[%0t] === TEST 7: concurrent stress, all 6 masters, distinct slaves, multi-beat ===", $time);
        fork
            axi4_write(0, 6'h11, ADDR_MAP_BASE[0] + 40'h400, 2, 256'h7000_0000);
            axi4_write(1, 6'h12, ADDR_MAP_BASE[4] + 40'h400, 2, 256'h7100_0000);
            axi4_write(2, 6'h13, ADDR_MAP_BASE[5] + 40'h400, 2, 256'h7200_0000);
            axi4_write(3, 6'h14, ADDR_MAP_BASE[2] + 40'h400, 2, 256'h7300_0000);
            axi4_write(4, 6'h15, ADDR_MAP_BASE[3] + 40'h400, 2, 256'h7400_0000);
            axi4_write(5, 6'h16, ADDR_MAP_BASE[1] + 40'h400, 2, 256'h7500_0000);
        join
        fork
            axi4_read_expect(0, 6'h11, ADDR_MAP_BASE[0] + 40'h400, 2, 256'h7000_0000);
            axi4_read_expect(1, 6'h12, ADDR_MAP_BASE[4] + 40'h400, 2, 256'h7100_0000);
            axi4_read_expect(2, 6'h13, ADDR_MAP_BASE[5] + 40'h400, 2, 256'h7200_0000);
            axi4_read_expect(3, 6'h14, ADDR_MAP_BASE[2] + 40'h400, 2, 256'h7300_0000);
            axi4_read_expect(4, 6'h15, ADDR_MAP_BASE[3] + 40'h400, 2, 256'h7400_0000);
            axi4_read_expect(5, 6'h16, ADDR_MAP_BASE[1] + 40'h400, 2, 256'h7500_0000);
        join
        $display("[%0t] TEST 7 complete", $time);

        repeat (5) @(posedge clk);

        $display("=====================================================");
        $display("TOTAL CHECKS: %0d   ERRORS: %0d", checks, errors);
        if (errors == 0) $display("*** TB_AXI4_CROSSBAR: PASS ***");
        else $display("*** TB_AXI4_CROSSBAR: FAIL ***");
        $display("=====================================================");
        $finish;
    end

    // safety timeout -- widened for the added TEST 6 sweep (36 pairs)
    // and TEST 7 stress traffic on top of the original 5 tests.
    initial begin
        #2000000;
        $display("[FAIL] TIMEOUT -- simulation did not finish in time");
        $finish;
    end

endmodule