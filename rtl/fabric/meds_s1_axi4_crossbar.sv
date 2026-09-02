
`include "axi4_params.svh"

module meds_s1_axi4_crossbar (
    input logic clk_i,
    input logic rst_ni,

    // Master (slave-port-facing-in) interfaces 
    // Flattened arrays, index 0..NUM_MASTERS-1
    input logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] m_awid,
    input logic [`NUM_MASTERS-1:0][`AXI_ADDR_W-1:0] m_awaddr,
    input logic [`NUM_MASTERS-1:0][7:0] m_awlen,
    input logic [`NUM_MASTERS-1:0][2:0] m_awsize,
    input logic [`NUM_MASTERS-1:0][1:0] m_awburst,
    input logic [`NUM_MASTERS-1:0] m_awvalid,
    output logic [`NUM_MASTERS-1:0] m_awready,

    input logic [`NUM_MASTERS-1:0][`AXI_DATA_W-1:0] m_wdata,
    input logic [`NUM_MASTERS-1:0][`AXI_STRB_W-1:0] m_wstrb,
    input logic [`NUM_MASTERS-1:0] m_wlast,
    input logic [`NUM_MASTERS-1:0] m_wvalid,
    output logic [`NUM_MASTERS-1:0] m_wready,

    output logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] m_bid,
    output logic [`NUM_MASTERS-1:0][1:0] m_bresp,
    output logic [`NUM_MASTERS-1:0] m_bvalid,
    input logic [`NUM_MASTERS-1:0] m_bready,

    input logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] m_arid,
    input logic [`NUM_MASTERS-1:0][`AXI_ADDR_W-1:0] m_araddr,
    input logic [`NUM_MASTERS-1:0][7:0] m_arlen,
    input logic [`NUM_MASTERS-1:0][2:0] m_arsize,
    input logic [`NUM_MASTERS-1:0][1:0] m_arburst,
    input logic [`NUM_MASTERS-1:0] m_arvalid,
    output logic [`NUM_MASTERS-1:0] m_arready,

    output logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] m_rid,
    output logic [`NUM_MASTERS-1:0][`AXI_DATA_W-1:0] m_rdata,
    output logic [`NUM_MASTERS-1:0][1:0] m_rresp,
    output logic [`NUM_MASTERS-1:0] m_rlast,
    output logic [`NUM_MASTERS-1:0] m_rvalid,
    input logic [`NUM_MASTERS-1:0] m_rready,

    // ---------------- Slave (master-port-facing-out) interfaces ----------------
    // ID fields on the slave side are AXI_SID_W (= AXI_ID_W + MIDX_W)
    // wide, not AXI_ID_W: the xbar prepends the MIDX_W-bit master tag
    // onto the FULL original ID rather than truncating it down to fit
    // (spec item 1.4 -- a truncated tag+ID silently drops the master's
    // upper ID bits and breaks AXI ID propagation for any master that
    // uses the full ID width).
    output logic [`NUM_SLAVES-1:0][`AXI_SID_W-1:0] s_awid,
    output logic [`NUM_SLAVES-1:0][`AXI_ADDR_W-1:0] s_awaddr,
    output logic [`NUM_SLAVES-1:0][7:0] s_awlen,
    output logic [`NUM_SLAVES-1:0][2:0] s_awsize,
    output logic [`NUM_SLAVES-1:0][1:0] s_awburst,
    output logic [`NUM_SLAVES-1:0] s_awvalid,
    input logic [`NUM_SLAVES-1:0] s_awready,

    output logic [`NUM_SLAVES-1:0][`AXI_DATA_W-1:0] s_wdata,
    output logic [`NUM_SLAVES-1:0][`AXI_STRB_W-1:0] s_wstrb,
    output logic [`NUM_SLAVES-1:0] s_wlast,
    output logic [`NUM_SLAVES-1:0] s_wvalid,
    input logic [`NUM_SLAVES-1:0] s_wready,

    input logic [`NUM_SLAVES-1:0][`AXI_SID_W-1:0] s_bid,
    input logic [`NUM_SLAVES-1:0][1:0] s_bresp,
    input logic [`NUM_SLAVES-1:0] s_bvalid,
    output logic [`NUM_SLAVES-1:0] s_bready,

    output logic [`NUM_SLAVES-1:0][`AXI_SID_W-1:0] s_arid,
    output logic [`NUM_SLAVES-1:0][`AXI_ADDR_W-1:0] s_araddr,
    output logic [`NUM_SLAVES-1:0][7:0] s_arlen,
    output logic [`NUM_SLAVES-1:0][2:0] s_arsize,
    output logic [`NUM_SLAVES-1:0][1:0] s_arburst,
    output logic [`NUM_SLAVES-1:0] s_arvalid,
    input logic [`NUM_SLAVES-1:0] s_arready,

    input logic [`NUM_SLAVES-1:0][`AXI_SID_W-1:0] s_rid,
    input logic [`NUM_SLAVES-1:0][`AXI_DATA_W-1:0] s_rdata,
    input logic [`NUM_SLAVES-1:0][1:0] s_rresp,
    input logic [`NUM_SLAVES-1:0] s_rlast,
    input logic [`NUM_SLAVES-1:0] s_rvalid,
    output logic [`NUM_SLAVES-1:0] s_rready,
    output logic [`NUM_MASTERS-1:0] decerr_pulse
);

   
    // Per-master address decode
 
    logic [`NUM_MASTERS-1:0][`SIDX_W-1:0] aw_slv, ar_slv;
    logic [`NUM_MASTERS-1:0] aw_hit, ar_hit;

    genvar gm;
    generate
        for (gm = 0; gm < `NUM_MASTERS; gm++) begin : g_decode
            meds_s1_axi4_addr_decode aw_dec (
                .addr (m_awaddr[gm]),
                .slv_sel (aw_slv[gm]),
                .hit (aw_hit[gm])
            );
            meds_s1_axi4_addr_decode ar_dec (
                .addr (m_araddr[gm]),
                .slv_sel (ar_slv[gm]),
                .hit (ar_hit[gm])
            );
        end
    endgenerate

    
    logic [`NUM_MASTERS-1:0] sink_awready, sink_wready, sink_bvalid;
    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] sink_bid;
    logic [`NUM_MASTERS-1:0][1:0] sink_bresp;
    logic [`NUM_MASTERS-1:0] sink_arready, sink_rvalid, sink_rlast;
    logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] sink_rid;
    logic [`NUM_MASTERS-1:0][`AXI_DATA_W-1:0] sink_rdata;
    logic [`NUM_MASTERS-1:0][1:0] sink_rresp;

    meds_s1_axi4_decerr_sink u_decerr_sink (
        .clk_i (clk_i),
        .rst_ni (rst_ni),
        .aw_miss (m_awvalid & ~aw_hit),
        .ar_miss (m_arvalid & ~ar_hit),
        .m_awid (m_awid),
        .m_awlen (m_awlen),
        .sink_awready (sink_awready),
        .m_wvalid (m_wvalid),
        .m_wlast (m_wlast),
        .sink_wready (sink_wready),
        .sink_bid (sink_bid),
        .sink_bresp (sink_bresp),
        .sink_bvalid (sink_bvalid),
        .m_bready (m_bready),
        .m_arid (m_arid),
        .m_arlen (m_arlen),
        .sink_arready (sink_arready),
        .sink_rid (sink_rid),
        .sink_rdata (sink_rdata),
        .sink_rresp (sink_rresp),
        .sink_rlast (sink_rlast),
        .sink_rvalid (sink_rvalid),
        .m_rready (m_rready)
    );

  
    // Per-slave AW arbitration
    
    logic [`NUM_SLAVES-1:0][`NUM_MASTERS-1:0] aw_req_per_slv;
    logic [`NUM_SLAVES-1:0][`NUM_MASTERS-1:0] aw_grant_per_slv;
    logic [`NUM_SLAVES-1:0][`MIDX_W-1:0] aw_grant_idx;
    logic [`NUM_SLAVES-1:0] aw_grant_valid;
    logic [`NUM_SLAVES-1:0] aw_advance;

   
    logic [`NUM_SLAVES-1:0][`MIDX_W-1:0] w_owner;
    logic [`NUM_SLAVES-1:0] w_owner_valid;

    genvar gs;
    generate
        for (gs = 0; gs < `NUM_SLAVES; gs++) begin : g_aw_arb

            for (gm = 0; gm < `NUM_MASTERS; gm++) begin : g_req
                assign aw_req_per_slv[gs][gm] =
                    m_awvalid[gm] && aw_hit[gm] && (aw_slv[gm] == gs) && !w_owner_valid[gs];
            end

            meds_s1_rr_arbiter #(.N(`NUM_MASTERS)) u_aw_rr (
                .clk_i (clk_i),
                .rst_ni (rst_ni),
                .req (aw_req_per_slv[gs]),
                .advance (aw_advance[gs]),
                .grant (aw_grant_per_slv[gs]),
                .grant_idx (aw_grant_idx[gs]),
                .grant_valid(aw_grant_valid[gs])
            );

           
            assign s_awvalid[gs] = aw_grant_valid[gs];
            assign s_awid[gs] = {aw_grant_idx[gs], m_awid[aw_grant_idx[gs]]};
            assign s_awaddr[gs] = m_awaddr[aw_grant_idx[gs]];
            assign s_awlen[gs] = m_awlen[aw_grant_idx[gs]];
            assign s_awsize[gs] = m_awsize[aw_grant_idx[gs]];
            assign s_awburst[gs] = m_awburst[aw_grant_idx[gs]];
            assign aw_advance[gs] = aw_grant_valid[gs] && s_awready[gs];

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    w_owner_valid[gs] <= 1'b0;
                    w_owner[gs] <= '0;
                end else begin
                    if (aw_grant_valid[gs] && s_awready[gs]) begin
                        w_owner_valid[gs] <= 1'b1;
                        w_owner[gs] <= aw_grant_idx[gs];
                    end else if (s_wvalid[gs] && s_wready[gs] && s_wlast[gs]) begin
                        w_owner_valid[gs] <= 1'b0; // burst done, slave free for next AW
                    end
                end
            end

            // W channel: steer the owning master's W stream to this slave
            assign s_wdata[gs] = m_wdata[w_owner[gs]];
            assign s_wstrb[gs] = m_wstrb[w_owner[gs]];
            assign s_wlast[gs] = m_wlast[w_owner[gs]];
            assign s_wvalid[gs] = w_owner_valid[gs] && m_wvalid[w_owner[gs]];
        end
    endgenerate

    
    always_comb begin
        for (int mi = 0; mi < `NUM_MASTERS; mi++) begin
            m_awready[mi] = 1'b0;
            m_wready[mi] = 1'b0;
            for (int si = 0; si < `NUM_SLAVES; si++) begin
                if (aw_hit[mi] && aw_slv[mi] == si &&
                    aw_grant_valid[si] && aw_grant_idx[si] == mi)
                    m_awready[mi] = s_awready[si];
                if (w_owner_valid[si] && w_owner[si] == mi)
                    m_wready[mi] = s_wready[si];
            end
            // decode miss: no slave was ever a candidate, so route to the
            // DECERR sink instead of leaving these stuck at 0.
            if (!aw_hit[mi]) begin
                m_awready[mi] = sink_awready[mi];
                m_wready[mi] = sink_wready[mi];
            end
        end
    end

  
    // B channel
    
    logic [`NUM_SLAVES-1:0][`MIDX_W-1:0] b_tag;
    generate
        for (gs = 0; gs < `NUM_SLAVES; gs++) begin : g_b_tag
            assign b_tag[gs] = s_bid[gs][`AXI_SID_W-1 -: `MIDX_W];
        end
    endgenerate

    always_comb begin
        for (int mi = 0; mi < `NUM_MASTERS; mi++) begin
            m_bvalid[mi] = 1'b0;
            m_bid[mi] = '0;
            m_bresp[mi] = 2'b00;
        end
        for (int si = 0; si < `NUM_SLAVES; si++) begin
            if (s_bvalid[si]) begin
                m_bvalid[b_tag[si]] = 1'b1;
                m_bid[b_tag[si]] = s_bid[si][`AXI_ID_W-1:0];
                m_bresp[b_tag[si]] = s_bresp[si];
            end
        end
        for (int mi = 0; mi < `NUM_MASTERS; mi++) begin
            if (!aw_hit[mi] && sink_bvalid[mi]) begin
                m_bvalid[mi] = 1'b1;
                m_bid[mi] = sink_bid[mi];
                m_bresp[mi] = sink_bresp[mi];
            end
        end
    end

    always_comb begin
        for (int si = 0; si < `NUM_SLAVES; si++)
            s_bready[si] = s_bvalid[si] ? m_bready[b_tag[si]] : 1'b0;
    end

    
    // Per-slave AR arbitration -- identical structure to AW.
   
    logic [`NUM_SLAVES-1:0][`NUM_MASTERS-1:0] ar_req_per_slv;
    logic [`NUM_SLAVES-1:0][`NUM_MASTERS-1:0] ar_grant_per_slv;
    logic [`NUM_SLAVES-1:0][`MIDX_W-1:0] ar_grant_idx;
    logic [`NUM_SLAVES-1:0] ar_grant_valid;
    logic [`NUM_SLAVES-1:0] ar_advance;
    logic [`NUM_SLAVES-1:0] r_inflight; // one read burst draining at a time

    generate
        for (gs = 0; gs < `NUM_SLAVES; gs++) begin : g_ar_arb
            for (gm = 0; gm < `NUM_MASTERS; gm++) begin : g_req
                assign ar_req_per_slv[gs][gm] =
                    m_arvalid[gm] && ar_hit[gm] && (ar_slv[gm] == gs) && !r_inflight[gs];
            end

            meds_s1_rr_arbiter #(.N(`NUM_MASTERS)) u_ar_rr (
                .clk_i (clk_i),
                .rst_ni (rst_ni),
                .req (ar_req_per_slv[gs]),
                .advance (ar_advance[gs]),
                .grant (ar_grant_per_slv[gs]),
                .grant_idx (ar_grant_idx[gs]),
                .grant_valid(ar_grant_valid[gs])
            );

            assign s_arvalid[gs] = ar_grant_valid[gs];
            assign s_arid[gs] = {ar_grant_idx[gs], m_arid[ar_grant_idx[gs]]};
            assign s_araddr[gs] = m_araddr[ar_grant_idx[gs]];
            assign s_arlen[gs] = m_arlen[ar_grant_idx[gs]];
            assign s_arsize[gs] = m_arsize[ar_grant_idx[gs]];
            assign s_arburst[gs] = m_arburst[ar_grant_idx[gs]];
            assign ar_advance[gs] = ar_grant_valid[gs] && s_arready[gs];

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) r_inflight[gs] <= 1'b0;
                else if (ar_grant_valid[gs] && s_arready[gs]) r_inflight[gs] <= 1'b1;
                else if (s_rvalid[gs] && s_rready[gs] && s_rlast[gs]) r_inflight[gs] <= 1'b0;
            end
        end
    endgenerate

    always_comb begin
        for (int mi = 0; mi < `NUM_MASTERS; mi++) m_arready[mi] = 1'b0;
        for (int mi = 0; mi < `NUM_MASTERS; mi++)
            for (int si = 0; si < `NUM_SLAVES; si++)
                if (ar_hit[mi] && ar_slv[mi] == si &&
                    ar_grant_valid[si] && ar_grant_idx[si] == mi)
                    m_arready[mi] = s_arready[si];
        // decode miss: route to the DECERR sink instead of hanging.
        for (int mi = 0; mi < `NUM_MASTERS; mi++)
            if (!ar_hit[mi]) m_arready[mi] = sink_arready[mi];
    end

    // R channel
    logic [`NUM_SLAVES-1:0][`MIDX_W-1:0] r_tag;
    generate
        for (gs = 0; gs < `NUM_SLAVES; gs++) begin : g_r_tag
            assign r_tag[gs] = s_rid[gs][`AXI_SID_W-1 -: `MIDX_W];
        end
    endgenerate

    always_comb begin
        for (int mi = 0; mi < `NUM_MASTERS; mi++) begin
            m_rvalid[mi] = 1'b0;
            m_rid[mi] = '0;
            m_rdata[mi] = '0;
            m_rresp[mi] = 2'b00;
            m_rlast[mi] = 1'b0;
        end
        for (int si = 0; si < `NUM_SLAVES; si++) begin
            if (s_rvalid[si]) begin
                m_rvalid[r_tag[si]] = 1'b1;
                m_rid[r_tag[si]] = s_rid[si][`AXI_ID_W-1:0];
                m_rdata[r_tag[si]] = s_rdata[si];
                m_rresp[r_tag[si]] = s_rresp[si];
                m_rlast[r_tag[si]] = s_rlast[si];
            end
        end
        for (int mi = 0; mi < `NUM_MASTERS; mi++) begin
            if (!ar_hit[mi] && sink_rvalid[mi]) begin
                m_rvalid[mi] = 1'b1;
                m_rid[mi] = sink_rid[mi];
                m_rdata[mi] = sink_rdata[mi];
                m_rresp[mi] = sink_rresp[mi];
                m_rlast[mi] = sink_rlast[mi];
            end
        end
    end

    always_comb begin
        for (int si = 0; si < `NUM_SLAVES; si++)
            s_rready[si] = s_rvalid[si] ? m_rready[r_tag[si]] : 1'b0;
    end

    // decode-miss reporting
    assign decerr_pulse = (m_awvalid & ~aw_hit) | (m_arvalid & ~ar_hit);

endmodule
