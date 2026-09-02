
`include "axi4_params.svh"

module meds_s1_axi4_decerr_sink (
    input logic clk_i,
    input logic rst_ni,

    // per-master miss flags from meds_s1_axi4_addr_decode, latched by the crossbar
    input logic [`NUM_MASTERS-1:0] aw_miss, // = m_awvalid & ~aw_hit
    input logic [`NUM_MASTERS-1:0] ar_miss,

    input logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] m_awid,
    input logic [`NUM_MASTERS-1:0][7:0] m_awlen,
    output logic [`NUM_MASTERS-1:0] sink_awready,

    input logic [`NUM_MASTERS-1:0] m_wvalid,
    input logic [`NUM_MASTERS-1:0] m_wlast,
    output logic [`NUM_MASTERS-1:0] sink_wready,

    output logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] sink_bid,
    output logic [`NUM_MASTERS-1:0][1:0] sink_bresp,
    output logic [`NUM_MASTERS-1:0] sink_bvalid,
    input logic [`NUM_MASTERS-1:0] m_bready,

    input logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] m_arid,
    input logic [`NUM_MASTERS-1:0][7:0] m_arlen,
    output logic [`NUM_MASTERS-1:0] sink_arready,

    output logic [`NUM_MASTERS-1:0][`AXI_ID_W-1:0] sink_rid,
    output logic [`NUM_MASTERS-1:0][`AXI_DATA_W-1:0] sink_rdata,
    output logic [`NUM_MASTERS-1:0][1:0] sink_rresp,
    output logic [`NUM_MASTERS-1:0] sink_rlast,
    output logic [`NUM_MASTERS-1:0] sink_rvalid,
    input logic [`NUM_MASTERS-1:0] m_rready
);

    localparam logic [1:0] DECERR = 2'b11;

    // Write side: AW accept -> drain W -> hold B 
    typedef enum logic [1:0] {W_IDLE, W_DRAIN, W_RESP} w_state_e;

    genvar gm;
    generate
        for (gm = 0; gm < `NUM_MASTERS; gm++) begin : g_wsink
            w_state_e wstate, wstate_n;
            logic [`AXI_ID_W-1:0] bid_reg, bid_reg_n;

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    wstate <= W_IDLE;
                    bid_reg <= '0;
                end else begin
                    wstate <= wstate_n;
                    bid_reg <= bid_reg_n;
                end
            end

            always_comb begin
                wstate_n = wstate;
                bid_reg_n = bid_reg;
                sink_awready[gm] = 1'b0;
                sink_wready[gm] = 1'b0;
                sink_bvalid[gm] = 1'b0;

                case (wstate)
                  .
                    W_IDLE: begin
                        sink_awready[gm] = aw_miss[gm];
                        if (aw_miss[gm]) begin
                            bid_reg_n = m_awid[gm];
                            wstate_n = W_DRAIN;
                        end
                    end

                  
                    W_DRAIN: begin
                        sink_wready[gm] = 1'b1;
                        if (m_wvalid[gm] && m_wlast[gm]) wstate_n = W_RESP;
                    end

                    W_RESP: begin
                        sink_bvalid[gm] = 1'b1;
                        if (m_bready[gm]) wstate_n = W_IDLE;
                    end

                    default: wstate_n = W_IDLE;
                endcase
            end

            assign sink_bid[gm] = bid_reg;
            assign sink_bresp[gm] = DECERR;
        end
    endgenerate

    // Read side: AR accept -> replay DECERR burst 
    typedef enum logic [1:0] {R_IDLE, R_RESP} r_state_e;

    generate
        for (gm = 0; gm < `NUM_MASTERS; gm++) begin : g_rsink
            r_state_e rstate, rstate_n;
            logic [`AXI_ID_W-1:0] rid_reg, rid_reg_n;
            logic [7:0] beats_left, beats_left_n;

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    rstate <= R_IDLE;
                    rid_reg <= '0;
                    beats_left <= '0;
                end else begin
                    rstate <= rstate_n;
                    rid_reg <= rid_reg_n;
                    beats_left <= beats_left_n;
                end
            end

            always_comb begin
                rstate_n = rstate;
                rid_reg_n = rid_reg;
                beats_left_n = beats_left;
                sink_arready[gm] = 1'b0;
                sink_rvalid[gm] = 1'b0;

                case (rstate)
                    R_IDLE: begin
                        sink_arready[gm] = ar_miss[gm];
                        if (ar_miss[gm]) begin
                            rid_reg_n = m_arid[gm];
                            beats_left_n = m_arlen[gm]; // arlen = beats-1
                            rstate_n = R_RESP;
                        end
                    end

                    
                    R_RESP: begin
                        sink_rvalid[gm] = 1'b1;
                        if (m_rready[gm]) begin
                            if (beats_left == '0) rstate_n = R_IDLE;
                            else beats_left_n = beats_left - 8'd1;
                        end
                    end

                    default: rstate_n = R_IDLE;
                endcase
            end

            assign sink_rid[gm] = rid_reg;
            assign sink_rdata[gm] = '0;
            assign sink_rresp[gm] = DECERR;
            assign sink_rlast[gm] = (beats_left == '0);
        end
    endgenerate

endmodule
