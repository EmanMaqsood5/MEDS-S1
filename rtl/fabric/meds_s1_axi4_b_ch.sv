
`include "axi4_params.svh"

module meds_s1_axi4_b_ch #(
    parameter int ID_W = `AXI_ID_W 
) (
    input logic clk_i,
    input logic rst_ni,

    // From meds_s1_axi4_aw_ch
    input logic [ID_W-1:0] AwCapturedId,
    input logic [`AXI_ADDR_W-1:0] AwCapturedAddr,
    input logic [7:0] AwCapturedLen,
    input logic [2:0] AwCapturedSize,
    input logic [1:0] AwCapturedBurst,
    input logic AwCaptured,
    output logic AwConsume,

    // From meds_s1_axi4_w_ch
    input logic [`AXI_DATA_W-1:0] WCapturedData,
    input logic [`AXI_STRB_W-1:0] WCapturedStrb,
    input logic WCapturedLast,
    input logic WCaptured,
    output logic WConsume,

    // B channel
    output logic [ID_W-1:0] bid,
    output logic [1:0] bresp,
    output logic bvalid,
    input logic bready,

    
    output logic [`AXI_ADDR_W-1:0] WrAddr,
    output logic [`AXI_DATA_W-1:0] WrData,
    output logic [`AXI_STRB_W-1:0] WrStrb,
    output logic WrEn, // one-cycle commit pulse
    input logic WrAddrValid // 1 = in range -> OKAY, else DECERR
);

    localparam [1:0] RESP_OKAY = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;

    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_WRAP = 2'b10;

    localparam [1:0] IDLE = 2'd0,
                      BEAT = 2'd1,
                      RESP = 2'd2;

    logic [1:0] state, state_n;
    logic [`AXI_BEAT_CNT_W-1:0] beat_cnt, beat_cnt_n;
    logic [`AXI_ADDR_W-1:0] beat_addr, beat_addr_n;
    logic resp_bad, resp_bad_n;
    logic [ID_W-1:0] id_reg, id_reg_n;

    wire [`AXI_ADDR_W-1:0] incr_step = {{(`AXI_ADDR_W-8){1'b0}}, 8'd1} << AwCapturedSize;

    // WRAP burst arithmetic
   
  
    wire [`AXI_ADDR_W-1:0] wrap_burst_bytes =
        incr_step * ({{(`AXI_ADDR_W-8){1'b0}}, AwCapturedLen} + 1'b1);
    wire [`AXI_ADDR_W-1:0] wrap_mask = wrap_burst_bytes - 1'b1;
    wire [`AXI_ADDR_W-1:0] wrap_base = AwCapturedAddr & ~wrap_mask;
    wire [`AXI_ADDR_W-1:0] wrap_top = wrap_base + wrap_burst_bytes;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            beat_cnt <= '0;
            beat_addr <= '0;
            resp_bad <= 1'b0;
            id_reg <= '0;
        end else begin
            state <= state_n;
            beat_cnt <= beat_cnt_n;
            beat_addr <= beat_addr_n;
            resp_bad <= resp_bad_n;
            id_reg <= id_reg_n;
        end
    end

    always_comb begin
        state_n = state;
        beat_cnt_n = beat_cnt;
        beat_addr_n = beat_addr;
        resp_bad_n = resp_bad;
        id_reg_n = id_reg;

        AwConsume = 1'b0;
        WConsume = 1'b0;
        WrEn = 1'b0;
        bvalid = 1'b0;

        WrAddr = beat_addr;
        WrData = WCapturedData;
        WrStrb = WCapturedStrb;

        case (state)

            IDLE: begin
                if (AwCaptured) begin
                    beat_addr_n = AwCapturedAddr;
                    beat_cnt_n = '0;
                    resp_bad_n = 1'b0;
                    id_reg_n = AwCapturedId;
                    state_n = BEAT;
                end
            end

            BEAT: begin
                WrAddr = beat_addr;
                if (WCaptured) begin
                    WrEn = 1'b1;
                    resp_bad_n = resp_bad | ~WrAddrValid;
                    WConsume = 1'b1;

                    if (beat_cnt == AwCapturedLen[`AXI_BEAT_CNT_W-1:0]) begin
                        // last beat of this burst committed
                        AwConsume = 1'b1;
                        state_n = RESP;
                    end else begin
                        beat_cnt_n = beat_cnt + 1'b1;
                        if (AwCapturedBurst == BURST_FIXED)
                            beat_addr_n = beat_addr;
                        else if (AwCapturedBurst == BURST_WRAP)
                            beat_addr_n = ((beat_addr + incr_step) == wrap_top)
                                            ? wrap_base
                                            : (beat_addr + incr_step);
                        else // INCR (and reserved, treated as INCR)
                            beat_addr_n = beat_addr + incr_step;
                    end
                end
            end

            RESP: begin
                bvalid = 1'b1;
                if (bready) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign bid = id_reg;
    assign bresp = resp_bad ? RESP_DECERR : RESP_OKAY;

endmodule
