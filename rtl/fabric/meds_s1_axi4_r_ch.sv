
`include "axi4_params.svh"

module meds_s1_axi4_r_ch #(
    parameter int ID_W = `AXI_ID_W 
) (
    input logic clk_i,
    input logic rst_ni,

    // From meds_s1_axi4_ar_ch
    input logic [ID_W-1:0] ArCapturedId,
    input logic [`AXI_ADDR_W-1:0] ArCapturedAddr,
    input logic [7:0] ArCapturedLen,
    input logic [2:0] ArCapturedSize,
    input logic [1:0] ArCapturedBurst,
    input logic ArCaptured,
    output logic ArConsume,

    // Read data channel
    output logic [ID_W-1:0] rid,
    output logic [`AXI_DATA_W-1:0] rdata,
    output logic [1:0] rresp,
    output logic rlast,
    output logic rvalid,
    input logic rready,

    
    output logic [`AXI_ADDR_W-1:0] RdAddr, // address presented to storage
    input logic [`AXI_DATA_W-1:0] RdData, // data for RdAddr (combinational)
    input logic RdAddrValid // 1 = in range -> OKAY, else DECERR
);

    localparam [1:0] RESP_OKAY = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;

    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_WRAP = 2'b10;

    localparam [1:0] IDLE = 2'd0,
                      LOOKUP = 2'd1,
                      RESP = 2'd2;

    logic [1:0] state, state_n;
    logic [`AXI_BEAT_CNT_W-1:0] beat_cnt, beat_cnt_n;
    logic [`AXI_ADDR_W-1:0] beat_addr, beat_addr_n;
    logic [ID_W-1:0] id_reg, id_reg_n;
    logic [7:0] len_reg, len_reg_n;
    logic [1:0] burst_reg, burst_reg_n;
    logic [2:0] size_reg, size_reg_n;

    logic [`AXI_DATA_W-1:0] data_reg, data_reg_n;
    logic [1:0] resp_reg, resp_reg_n;
    logic last_reg, last_reg_n;

    wire [`AXI_ADDR_W-1:0] incr_step = {{(`AXI_ADDR_W-8){1'b0}}, 8'd1} << size_reg;

    wire [`AXI_ADDR_W-1:0] wrap_burst_bytes =
        incr_step * ({{(`AXI_ADDR_W-8){1'b0}}, len_reg} + 1'b1);
    wire [`AXI_ADDR_W-1:0] wrap_mask = wrap_burst_bytes - 1'b1;
    wire [`AXI_ADDR_W-1:0] wrap_base = ArCapturedAddr & ~wrap_mask;
    wire [`AXI_ADDR_W-1:0] wrap_top = wrap_base + wrap_burst_bytes;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            beat_cnt <= '0;
            beat_addr <= '0;
            id_reg <= '0;
            len_reg <= '0;
            burst_reg <= '0;
            size_reg <= '0;
            data_reg <= '0;
            resp_reg <= RESP_OKAY;
            last_reg <= 1'b0;
        end else begin
            state <= state_n;
            beat_cnt <= beat_cnt_n;
            beat_addr <= beat_addr_n;
            id_reg <= id_reg_n;
            len_reg <= len_reg_n;
            burst_reg <= burst_reg_n;
            size_reg <= size_reg_n;
            data_reg <= data_reg_n;
            resp_reg <= resp_reg_n;
            last_reg <= last_reg_n;
        end
    end

    always_comb begin
        state_n = state;
        beat_cnt_n = beat_cnt;
        beat_addr_n = beat_addr;
        id_reg_n = id_reg;
        len_reg_n = len_reg;
        burst_reg_n = burst_reg;
        size_reg_n = size_reg;
        data_reg_n = data_reg;
        resp_reg_n = resp_reg;
        last_reg_n = last_reg;

        ArConsume = 1'b0;
        rvalid = 1'b0;
        RdAddr = beat_addr;

        case (state)

            IDLE: begin
                if (ArCaptured) begin
                    beat_addr_n = ArCapturedAddr;
                    beat_cnt_n = '0;
                    id_reg_n = ArCapturedId;
                    len_reg_n = ArCapturedLen;
                    burst_reg_n = ArCapturedBurst;
                    size_reg_n = ArCapturedSize;
                    state_n = LOOKUP;
                end
            end

            LOOKUP: begin
                RdAddr = beat_addr;
                data_reg_n = RdData;
                resp_reg_n = RdAddrValid ? RESP_OKAY : RESP_DECERR;
                last_reg_n = (beat_cnt == len_reg[`AXI_BEAT_CNT_W-1:0]);
                state_n = RESP;
            end

            RESP: begin
                rvalid = 1'b1;
                if (rready) begin
                    if (last_reg) begin
                        ArConsume = 1'b1;
                        state_n = IDLE;
                    end else begin
                        beat_cnt_n = beat_cnt + 1'b1;
                        if (burst_reg == BURST_FIXED)
                            beat_addr_n = beat_addr;
                        else if (burst_reg == BURST_WRAP)
                            beat_addr_n = ((beat_addr + incr_step) == wrap_top)
                                            ? wrap_base
                                            : (beat_addr + incr_step);
                        else // INCR (and reserved, treated as INCR)
                            beat_addr_n = beat_addr + incr_step;
                        state_n = LOOKUP;
                    end
                end
            end

            default: state_n = IDLE;
        endcase
    end

    assign rid = id_reg;
    assign rdata = data_reg;
    assign rresp = resp_reg;
    assign rlast = last_reg;

endmodule
