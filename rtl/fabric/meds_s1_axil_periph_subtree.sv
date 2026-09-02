
`include "axi4_params.svh"
`include "parameters.svh"

module meds_s1_axil_periph_subtree #(
    parameter int NUM_PERIPH = 6,
    parameter int PIDX_W = 3 // ceil(log2(NUM_PERIPH))
) (
    input logic clk_i,
    input logic rst_ni,

    //  AXI4 slave-side (from meds_s1_axi4_crossbar slave port 5) 
    input logic [`AXI_SID_W-1:0] axi_awid,
    input logic [`AXI_ADDR_W-1:0] axi_awaddr,
    input logic axi_awvalid,
    output logic axi_awready,

    input logic [`AXI_DATA_W-1:0] axi_wdata,
    input logic [`AXI_STRB_W-1:0] axi_wstrb,
    input logic axi_wvalid,
    output logic axi_wready,

    output logic [`AXI_SID_W-1:0] axi_bid,
    output logic [1:0] axi_bresp,
    output logic axi_bvalid,
    input logic axi_bready,

    input logic [`AXI_SID_W-1:0] axi_arid,
    input logic [`AXI_ADDR_W-1:0] axi_araddr,
    input logic axi_arvalid,
    output logic axi_arready,

    output logic [`AXI_SID_W-1:0] axi_rid,
    output logic [`AXI_DATA_W-1:0] axi_rdata,
    output logic [1:0] axi_rresp,
    output logic axi_rlast,
    output logic axi_rvalid,
    input logic axi_rready,

    // Per-peripheral AXI4-Lite master-side ports
    // Index order: 0..5 = PERIPH0..PERIPH5 (generic AXI4-Lite peripheral slots). 
 
    output logic [NUM_PERIPH-1:0][`ADDR_WIDTH-1:0] p_awaddr,
    output logic [NUM_PERIPH-1:0] p_awvalid,
    input logic [NUM_PERIPH-1:0] p_awready,

    output logic [NUM_PERIPH-1:0][`DATA_WIDTH-1:0] p_wdata,
    output logic [NUM_PERIPH-1:0][`STRB_WIDTH-1:0] p_wstrb,
    output logic [NUM_PERIPH-1:0] p_wvalid,
    input logic [NUM_PERIPH-1:0] p_wready,

    input logic [NUM_PERIPH-1:0][1:0] p_bresp,
    input logic [NUM_PERIPH-1:0] p_bvalid,
    output logic [NUM_PERIPH-1:0] p_bready,

    output logic [NUM_PERIPH-1:0][`ADDR_WIDTH-1:0] p_araddr,
    output logic [NUM_PERIPH-1:0] p_arvalid,
    input logic [NUM_PERIPH-1:0] p_arready,

    input logic [NUM_PERIPH-1:0][`DATA_WIDTH-1:0] p_rdata,
    input logic [NUM_PERIPH-1:0][1:0] p_rresp,
    input logic [NUM_PERIPH-1:0] p_rvalid,
    output logic [NUM_PERIPH-1:0] p_rready
);

    localparam logic [`AXI_ADDR_W-1:0]
        PERIPH_BASE_0 = 40'h0200_0000, // PERIPH0
        PERIPH_BASE_1 = 40'h0C00_0000, // PERIPH1
        PERIPH_BASE_2 = 40'h1000_0000, // PERIPH2
        PERIPH_BASE_3 = 40'h1000_1000, // PERIPH3
        PERIPH_BASE_4 = 40'h1000_2000, // PERIPH4
        PERIPH_BASE_5 = 40'h1000_3000; // PERIPH5

    localparam logic [`AXI_ADDR_W-1:0]
        PERIPH_WIN_0 = 40'h0001_0000, // PERIPH0 -- 64K
        PERIPH_WIN_1 = 40'h0040_0000, // PERIPH1 -- 4M (example: a wide peripheral like an interrupt controller)
        PERIPH_WIN_2 = 40'h0000_1000, // PERIPH2 -- 4K
        PERIPH_WIN_3 = 40'h0000_1000, // PERIPH3 -- 4K
        PERIPH_WIN_4 = 40'h0000_1000, // PERIPH4 -- 4K
        PERIPH_WIN_5 = 40'h0000_1000; // PERIPH5 -- 4K

    logic [`AXI_ADDR_W-1:0] periph_base [NUM_PERIPH];
    logic [`AXI_ADDR_W-1:0] periph_win [NUM_PERIPH];
    assign periph_base[0] = PERIPH_BASE_0; assign periph_win[0] = PERIPH_WIN_0;
    assign periph_base[1] = PERIPH_BASE_1; assign periph_win[1] = PERIPH_WIN_1;
    assign periph_base[2] = PERIPH_BASE_2; assign periph_win[2] = PERIPH_WIN_2;
    assign periph_base[3] = PERIPH_BASE_3; assign periph_win[3] = PERIPH_WIN_3;
    assign periph_base[4] = PERIPH_BASE_4; assign periph_win[4] = PERIPH_WIN_4;
    assign periph_base[5] = PERIPH_BASE_5; assign periph_win[5] = PERIPH_WIN_5;


    // Peripheral select, priority-encoded, plain for-loop 
    
    logic [NUM_PERIPH-1:0] aw_hit_vec, ar_hit_vec;

    
    logic [`AXI_ADDR_W-1:0] aw_captured_addr;
    logic [`AXI_ADDR_W-1:0] ar_captured_addr;

    genvar gh;
    generate
        for (gh = 0; gh < NUM_PERIPH; gh++) begin : g_hit_vec
            assign aw_hit_vec[gh] = (aw_captured_addr >= periph_base[gh]) &&
                                     (aw_captured_addr < periph_base[gh] + periph_win[gh]);
            assign ar_hit_vec[gh] = (ar_captured_addr >= periph_base[gh]) &&
                                     (ar_captured_addr < periph_base[gh] + periph_win[gh]);
        end
    endgenerate

    logic [PIDX_W-1:0] aw_sel, ar_sel;
    logic aw_hit, ar_hit;

    always_comb begin
        aw_sel = '0;
        aw_hit = 1'b0;
        for (int i = 0; i < NUM_PERIPH; i++) begin
            if (aw_hit_vec[i] && !aw_hit) begin
                aw_sel = i[PIDX_W-1:0];
                aw_hit = 1'b1;
            end
        end
    end

    always_comb begin
        ar_sel = '0;
        ar_hit = 1'b0;
        for (int i = 0; i < NUM_PERIPH; i++) begin
            if (ar_hit_vec[i] && !ar_hit) begin
                ar_sel = i[PIDX_W-1:0];
                ar_hit = 1'b1;
            end
        end
    end

    
    // Write path
    
    logic [`AXI_SID_W-1:0] aw_captured_id;
    logic aw_captured;
    logic aw_consume;

    meds_s1_axi_addr_id_capture #(
        .ADDR_W (`AXI_ADDR_W),
        .ID_W (`AXI_SID_W)
    ) aw_cap_inst (
        .clk_i (clk_i),
        .rst_ni (rst_ni),
        .addr (axi_awaddr),
        .id (axi_awid),
        .valid (axi_awvalid),
        .ready (axi_awready),
        .captured_addr (aw_captured_addr),
        .captured_id (aw_captured_id),
        .captured (aw_captured),
        .consume (aw_consume)
    );

    logic [`AXI_DATA_W-1:0] w_captured_data;
    logic [`AXI_STRB_W-1:0] w_captured_strb;
    logic w_captured;
    logic w_consume;

    meds_s1_axi_wdata_capture #(
        .DATA_W (`AXI_DATA_W),
        .STRB_W (`AXI_STRB_W)
    ) w_cap_inst (
        .clk_i (clk_i),
        .rst_ni (rst_ni),
        .data (axi_wdata),
        .strb (axi_wstrb),
        .valid (axi_wvalid),
        .ready (axi_wready),
        .captured_data (w_captured_data),
        .captured_strb (w_captured_strb),
        .captured (w_captured),
        .consume (w_consume)
    );

    // ---- decode + 32-bit lane select on the way in ----
    logic [2:0] aw_lane;
    logic [`ADDR_WIDTH-1:0] aw_offset;
    logic [`DATA_WIDTH-1:0] w_data_lane;
    logic [`STRB_WIDTH-1:0] w_strb_lane;

    assign aw_lane = aw_captured_addr[4:2];
    // relative offset within the *selected* peripheral's window (item
    // 2.2) -- not a raw low-bit slice, since windows are no longer a
    // uniform, identically-aligned 4K (item 2.1's whole point).
    assign aw_offset = aw_hit ? (aw_captured_addr - periph_base[aw_sel]) : '0;

    always_comb begin
        case (aw_lane)
            3'd0: begin w_data_lane = w_captured_data[ 31: 0]; w_strb_lane = w_captured_strb[ 3: 0]; end
            3'd1: begin w_data_lane = w_captured_data[ 63: 32]; w_strb_lane = w_captured_strb[ 7: 4]; end
            3'd2: begin w_data_lane = w_captured_data[ 95: 64]; w_strb_lane = w_captured_strb[11: 8]; end
            3'd3: begin w_data_lane = w_captured_data[127: 96]; w_strb_lane = w_captured_strb[15:12]; end
            3'd4: begin w_data_lane = w_captured_data[159:128]; w_strb_lane = w_captured_strb[19:16]; end
            3'd5: begin w_data_lane = w_captured_data[191:160]; w_strb_lane = w_captured_strb[23:20]; end
            3'd6: begin w_data_lane = w_captured_data[223:192]; w_strb_lane = w_captured_strb[27:24]; end
            3'd7: begin w_data_lane = w_captured_data[255:224]; w_strb_lane = w_captured_strb[31:28]; end
            default: begin w_data_lane = w_captured_data[31:0]; w_strb_lane = w_captured_strb[3:0]; end
        endcase
    end

    // ---- sequencer: forward to the selected peripheral, wait for its ----
    // ---- response, drive it back out. ----
    typedef enum logic [1:0] { W_IDLE, W_DRIVE, W_BWAIT, W_BRESP } wstate_t;

    wstate_t wstate, wstate_n;
    logic [`AXI_SID_W-1:0] awid_hold, awid_hold_n;
    logic [PIDX_W-1:0] aw_sel_hold, aw_sel_hold_n;
    logic aw_hit_hold, aw_hit_hold_n;
    logic [`ADDR_WIDTH-1:0] aw_offset_hold, aw_offset_hold_n;
    logic [`DATA_WIDTH-1:0] w_data_hold, w_data_hold_n;
    logic [`STRB_WIDTH-1:0] w_strb_hold, w_strb_hold_n;
    logic [1:0] bresp_hold, bresp_hold_n;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wstate <= W_IDLE;
            awid_hold <= '0;
            aw_sel_hold <= '0;
            aw_hit_hold <= 1'b0;
            aw_offset_hold <= '0;
            w_data_hold <= '0;
            w_strb_hold <= '0;
            bresp_hold <= '0;
        end else begin
            wstate <= wstate_n;
            awid_hold <= awid_hold_n;
            aw_sel_hold <= aw_sel_hold_n;
            aw_hit_hold <= aw_hit_hold_n;
            aw_offset_hold <= aw_offset_hold_n;
            w_data_hold <= w_data_hold_n;
            w_strb_hold <= w_strb_hold_n;
            bresp_hold <= bresp_hold_n;
        end
    end

    always_comb begin
        wstate_n = wstate;
        awid_hold_n = awid_hold;
        aw_sel_hold_n = aw_sel_hold;
        aw_hit_hold_n = aw_hit_hold;
        aw_offset_hold_n = aw_offset_hold;
        w_data_hold_n = w_data_hold;
        w_strb_hold_n = w_strb_hold;
        bresp_hold_n = bresp_hold;

        aw_consume = 1'b0;
        w_consume = 1'b0;
        axi_bvalid = 1'b0;
        axi_bid = awid_hold;
        axi_bresp = bresp_hold;

        for (int i = 0; i < NUM_PERIPH; i++) begin
            p_awvalid[i] = 1'b0;
            p_awaddr[i] = aw_offset_hold;
            p_wvalid[i] = 1'b0;
            p_wdata[i] = '0;
            p_wstrb[i] = '0;
            p_bready[i] = 1'b0;
        end

        case (wstate)

            W_IDLE: begin
                if (aw_captured && w_captured) begin
                    awid_hold_n = aw_captured_id;
                    aw_sel_hold_n = aw_sel; // decoded off aw_captured_addr, still stable
                    aw_hit_hold_n = aw_hit;
                    aw_offset_hold_n = aw_offset;
                    w_data_hold_n = w_data_lane;
                    w_strb_hold_n = w_strb_lane;
                    aw_consume = 1'b1;
                    w_consume = 1'b1;
                    wstate_n = W_DRIVE;
                end
            end

            W_DRIVE: begin
                if (aw_hit_hold) begin
                    // present held AW+W to the selected peripheral
               
                    p_awvalid[aw_sel_hold] = 1'b1;
                    p_awaddr[aw_sel_hold] = aw_offset_hold;
                    p_wvalid[aw_sel_hold] = 1'b1;
                    p_wdata[aw_sel_hold] = w_data_hold;
                    p_wstrb[aw_sel_hold] = w_strb_hold;

                    if (p_awready[aw_sel_hold] && p_wready[aw_sel_hold]) wstate_n = W_BWAIT;
                end else begin
         
                    bresp_hold_n = 2'b11; // DECERR
                    wstate_n = W_BRESP;
                end
            end

            W_BWAIT: begin
                p_bready[aw_sel_hold] = 1'b1;
                if (p_bvalid[aw_sel_hold]) begin
                    bresp_hold_n = p_bresp[aw_sel_hold];
                    wstate_n = W_BRESP;
                end
            end

            W_BRESP: begin
                axi_bvalid = 1'b1;
                if (axi_bready) wstate_n = W_IDLE;
            end

            default: wstate_n = W_IDLE;
        endcase
    end

    // Read path
   

    logic [`AXI_SID_W-1:0] ar_captured_id;
    logic ar_captured;
    logic ar_consume;

    meds_s1_axi_addr_id_capture #(
        .ADDR_W (`AXI_ADDR_W),
        .ID_W (`AXI_SID_W)
    ) ar_cap_inst (
        .clk_i (clk_i),
        .rst_ni (rst_ni),
        .addr (axi_araddr),
        .id (axi_arid),
        .valid (axi_arvalid),
        .ready (axi_arready),
        .captured_addr (ar_captured_addr),
        .captured_id (ar_captured_id),
        .captured (ar_captured),
        .consume (ar_consume)
    );

    logic [2:0] ar_lane;
    logic [`ADDR_WIDTH-1:0] ar_offset;

    assign ar_lane = ar_captured_addr[4:2];
    assign ar_offset = ar_hit ? (ar_captured_addr - periph_base[ar_sel]) : '0;

    typedef enum logic [1:0] { R_IDLE, R_DRIVE, R_RWAIT, R_RRESP } rstate_t;

    rstate_t rstate, rstate_n;
    logic [`AXI_SID_W-1:0] arid_hold, arid_hold_n;
    logic [PIDX_W-1:0] ar_sel_hold, ar_sel_hold_n;
    logic ar_hit_hold, ar_hit_hold_n;
    logic [2:0] ar_lane_hold, ar_lane_hold_n;
    logic [`ADDR_WIDTH-1:0] ar_offset_hold, ar_offset_hold_n;
    logic [`DATA_WIDTH-1:0] r_data_hold, r_data_hold_n;
    logic [1:0] rresp_hold, rresp_hold_n;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rstate <= R_IDLE;
            arid_hold <= '0;
            ar_sel_hold <= '0;
            ar_hit_hold <= 1'b0;
            ar_lane_hold <= '0;
            ar_offset_hold <= '0;
            r_data_hold <= '0;
            rresp_hold <= '0;
        end else begin
            rstate <= rstate_n;
            arid_hold <= arid_hold_n;
            ar_sel_hold <= ar_sel_hold_n;
            ar_hit_hold <= ar_hit_hold_n;
            ar_lane_hold <= ar_lane_hold_n;
            ar_offset_hold <= ar_offset_hold_n;
            r_data_hold <= r_data_hold_n;
            rresp_hold <= rresp_hold_n;
        end
    end

    always_comb begin
        rstate_n = rstate;
        arid_hold_n = arid_hold;
        ar_sel_hold_n = ar_sel_hold;
        ar_hit_hold_n = ar_hit_hold;
        ar_lane_hold_n = ar_lane_hold;
        ar_offset_hold_n = ar_offset_hold;
        r_data_hold_n = r_data_hold;
        rresp_hold_n = rresp_hold;

        ar_consume = 1'b0;
        axi_rvalid = 1'b0;
        axi_rid = arid_hold;
        axi_rresp = rresp_hold;
        axi_rlast = 1'b1; // single beat only
        axi_rdata = '0;

        for (int i = 0; i < NUM_PERIPH; i++) begin
            p_arvalid[i] = 1'b0;
            p_araddr[i] = ar_offset_hold;
            p_rready[i] = 1'b0;
        end

        case (ar_lane_hold)
            3'd0: axi_rdata[ 31: 0] = r_data_hold;
            3'd1: axi_rdata[ 63: 32] = r_data_hold;
            3'd2: axi_rdata[ 95: 64] = r_data_hold;
            3'd3: axi_rdata[127: 96] = r_data_hold;
            3'd4: axi_rdata[159:128] = r_data_hold;
            3'd5: axi_rdata[191:160] = r_data_hold;
            3'd6: axi_rdata[223:192] = r_data_hold;
            3'd7: axi_rdata[255:224] = r_data_hold;
            default: axi_rdata[31:0] = r_data_hold;
        endcase

        case (rstate)

            R_IDLE: begin
                if (ar_captured) begin
                    arid_hold_n = ar_captured_id;
                    ar_sel_hold_n = ar_sel; // decoded off ar_captured_addr, still stable
                    ar_hit_hold_n = ar_hit;
                    ar_lane_hold_n = ar_lane;
                    ar_offset_hold_n = ar_offset;
                    ar_consume = 1'b1;
                    rstate_n = R_DRIVE;
                end
            end

            R_DRIVE: begin
                if (ar_hit_hold) begin
                    p_arvalid[ar_sel_hold] = 1'b1;
                    p_araddr[ar_sel_hold] = ar_offset_hold;
                    if (p_arready[ar_sel_hold]) rstate_n = R_RWAIT;
                end else begin
                    // no peripheral matched -- local DECERR, no data
                    rresp_hold_n = 2'b11; // DECERR
                    r_data_hold_n = 32'hDEAD_BEEF;
                    rstate_n = R_RRESP;
                end
            end

            R_RWAIT: begin
                p_rready[ar_sel_hold] = 1'b1;
                if (p_rvalid[ar_sel_hold]) begin
                    r_data_hold_n = p_rdata[ar_sel_hold];
                    rresp_hold_n = p_rresp[ar_sel_hold];
                    rstate_n = R_RRESP;
                end
            end

            R_RRESP: begin
                axi_rvalid = 1'b1;
                if (axi_rready) rstate_n = R_IDLE;
            end

            default: rstate_n = R_IDLE;
        endcase
    end

    

endmodule